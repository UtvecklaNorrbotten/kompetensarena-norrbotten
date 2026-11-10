-- Verifierad, återstartbar publicering av UKÄ indikator 99 (Söktryck) från
-- ett fryst filbaserat stagingpaket. Påverkar inga andra indikatorer och
-- ändrar inte HST:s uka_verified_*-funktioner. Föregående aktiv batch behålls.

CREATE OR REPLACE FUNCTION public.uka99_verified_start(p_import_key text, p_manifest jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  ind constant text := 'uka-soktryck-yrkesprogram';
  v public.uka_verified_imports%rowtype; b uuid; old uuid; run uuid; n int; total int;
BEGIN
  IF coalesce(p_import_key,'') !~ '^uka-99-[A-Za-z0-9._-]{1,180}$'
   OR p_manifest->>'indicator' IS DISTINCT FROM ind
   OR p_manifest->>'version' IS DISTINCT FROM '1'
   OR p_manifest->>'policy' IS DISTINCT FROM '99-csv-term-university-program-root-controls-v1'
   OR coalesce(p_manifest->>'archive_sha256','') !~ '^[a-f0-9]{64}$'
   OR coalesce(p_manifest->>'staging_sha256','') !~ '^[a-f0-9]{64}$'
   OR coalesce(p_manifest->>'snapshot','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
   OR jsonb_typeof(p_manifest->'rows') IS DISTINCT FROM 'number'
   OR jsonb_typeof(p_manifest->'periods') IS DISTINCT FROM 'array'
   OR jsonb_typeof(p_manifest->'universities') IS DISTINCT FROM 'array'
   OR jsonb_typeof(p_manifest->'dimensions') IS DISTINCT FROM 'array'
   OR jsonb_typeof(p_manifest->'coverage') IS DISTINCT FROM 'array'
   OR jsonb_typeof(p_manifest->'chunks') IS DISTINCT FROM 'array'
   OR jsonb_typeof(p_manifest->'review') IS DISTINCT FROM 'object'
   OR jsonb_typeof(p_manifest->'review'->'full_source_coverage_verified') IS DISTINCT FROM 'boolean'
   OR jsonb_typeof(p_manifest->'review'->'source_release_verified') IS DISTINCT FROM 'boolean'
   OR coalesce(p_manifest->>'publication_basis','') = ''
   OR p_manifest->'genders' IS DISTINCT FROM '["Kvinnor","Män","Total"]'::jsonb
   OR p_manifest->'ages' IS DISTINCT FROM '["Total"]'::jsonb
  THEN RAISE EXCEPTION 'Invalid indicator 99 manifest'; END IF;

  total := (p_manifest->>'rows')::int;
  IF total <= 0
   OR jsonb_array_length(p_manifest->'periods') <> 20
   OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_manifest->'periods') x
              WHERE jsonb_typeof(x) <> 'string' OR x #>> '{}' !~ '^(HT|VT)[0-9]{4}$')
   OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(p_manifest->'periods') x) <> 20
   OR NOT (p_manifest->'universities' ? 'Riket')
   OR NOT (p_manifest->'universities' ? 'Luleå tekniska universitet')
   OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_manifest->'universities') x
              WHERE jsonb_typeof(x) <> 'string' OR x #>> '{}' = '')
   OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(p_manifest->'universities') x)
      <> jsonb_array_length(p_manifest->'universities')
   -- Programdimension enligt normalize_uka: {"program": namn}; källans program-Total = {}.
   OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_manifest->'dimensions') d
              WHERE jsonb_typeof(d) <> 'object'
                 OR NOT (d = '{}'::jsonb OR ((d - 'program') = '{}'::jsonb
                         AND jsonb_typeof(d->'program') = 'string'
                         AND d->>'program' NOT IN ('', 'Total'))))
   OR (SELECT count(DISTINCT d) FROM jsonb_array_elements(p_manifest->'dimensions') d)
      <> jsonb_array_length(p_manifest->'dimensions')
   OR (SELECT count(*) FROM jsonb_array_elements(p_manifest->'dimensions') d WHERE d = '{}'::jsonb) <> 1
   OR jsonb_array_length(p_manifest->'coverage') <> 60
   OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_manifest->'coverage') x
              WHERE NOT (p_manifest->'periods' ? (x->>'period'))
                 OR NOT (p_manifest->'genders' ? (x->>'gender'))
                 OR jsonb_typeof(x->'rows') <> 'number' OR (x->>'rows')::int <= 0)
   OR (SELECT count(DISTINCT (x->>'period') || '|' || (x->>'gender'))
       FROM jsonb_array_elements(p_manifest->'coverage') x) <> 60
   OR (SELECT sum((x->>'rows')::int) FROM jsonb_array_elements(p_manifest->'coverage') x) <> total
  THEN RAISE EXCEPTION 'Invalid indicator 99 dictionaries or coverage'; END IF;

  n := jsonb_array_length(p_manifest->'chunks');
  IF n < 1 OR n > 10000
   OR (SELECT sum((x->>'rows')::int) FROM jsonb_array_elements(p_manifest->'chunks') x) <> total
   OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_manifest->'chunks') WITH ORDINALITY t(x, i)
              WHERE (x->>'index')::int <> i - 1 OR (x->>'rows')::int NOT BETWEEN 1 AND 5000
                 OR coalesce(x->>'sha256','') !~ '^[a-f0-9]{64}$')
  THEN RAISE EXCEPTION 'Invalid chunk manifest'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_import_key));
  SELECT * INTO v FROM uka_verified_imports WHERE import_key = p_import_key;
  IF FOUND THEN
    IF v.manifest IS DISTINCT FROM p_manifest THEN
      RAISE EXCEPTION 'Import key already bound to another manifest';
    END IF;
    RETURN jsonb_build_object('batch_id', v.batch_id, 'resumed', true, 'published', v.published_at IS NOT NULL);
  END IF;

  SELECT active_batch_id INTO old FROM uka_active_batches WHERE indicator_id = ind;
  INSERT INTO data_source_runs (source, source_id, indicator_id, status, started_at, source_period, details)
  VALUES ('UKÄ verified CSV snapshot', 'uka-hogskolan-i-siffror', ind, 'started', now(),
          p_manifest->>'snapshot',
          jsonb_build_object('import_key', p_import_key,
                             'archive_sha256', p_manifest->>'archive_sha256',
                             'staging_sha256', p_manifest->>'staging_sha256',
                             'policy', p_manifest->>'policy',
                             'review', p_manifest->'review',
                             'publication_basis', p_manifest->>'publication_basis',
                             'previous_batch_id', old))
  RETURNING id INTO run;
  b := uka_start_batch(ind, 'UKÄ verified CSV snapshot', n, total, NULL, run);
  INSERT INTO uka_verified_imports (import_key, batch_id, manifest, manifest_hash, previous_batch_id)
  VALUES (p_import_key, b, p_manifest, encode(extensions.digest(p_manifest::text, 'sha256'), 'hex'), old);
  RETURN jsonb_build_object('batch_id', b, 'resumed', false, 'published', false, 'previous_batch_id', old);
END $fn$;

CREATE OR REPLACE FUNCTION public.uka99_verified_chunk(p_import_key text, p_index integer, p_payload text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' SET statement_timeout TO '180s' AS $fn$
DECLARE
  ind constant text := 'uka-soktryck-yrkesprogram';
  v public.uka_verified_imports%rowtype; expected jsonb; data jsonb; full_rows jsonb; sha text; prior text;
BEGIN
  SELECT * INTO v FROM uka_verified_imports WHERE import_key = p_import_key FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown import key'; END IF;
  IF v.manifest->>'indicator' IS DISTINCT FROM ind THEN RAISE EXCEPTION 'Not an indicator 99 import'; END IF;
  expected := v.manifest->'chunks'->p_index;
  IF p_index < 0 OR expected IS NULL THEN RAISE EXCEPTION 'Chunk outside manifest'; END IF;
  sha := encode(extensions.digest(p_payload, 'sha256'), 'hex');
  IF sha <> expected->>'sha256' THEN RAISE EXCEPTION 'Chunk checksum differs from manifest'; END IF;
  SELECT checksum INTO prior FROM uka_batch_chunks WHERE batch_id = v.batch_id AND chunk_index = p_index;
  IF FOUND THEN
    IF prior <> sha THEN RAISE EXCEPTION 'Existing chunk differs'; END IF;
    RETURN jsonb_build_object('duplicate', true, 'index', p_index);
  END IF;
  IF v.published_at IS NOT NULL THEN RAISE EXCEPTION 'Published import is immutable'; END IF;
  data := p_payload::jsonb;
  IF jsonb_typeof(data) <> 'array' OR jsonb_array_length(data) <> (expected->>'rows')::int THEN
    RAISE EXCEPTION 'Chunk row count differs';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(data) x
             WHERE jsonb_typeof(x) <> 'array' OR jsonb_array_length(x) <> 5
                OR jsonb_typeof(x->0) <> 'number' OR jsonb_typeof(x->1) <> 'number'
                OR jsonb_typeof(x->2) <> 'number' OR jsonb_typeof(x->3) <> 'number'
                OR jsonb_typeof(x->4) <> 'string'
                OR (x->>0)::int < 0 OR v.manifest->'periods'->((x->>0)::int) IS NULL
                OR (x->>1)::int < 0 OR v.manifest->'universities'->((x->>1)::int) IS NULL
                OR (x->>2)::int NOT BETWEEN 0 AND 2
                OR (x->>3)::int < 0 OR v.manifest->'dimensions'->((x->>3)::int) IS NULL
                OR x->>4 !~ '^[0-9]+([.][0-9]+)?([Ee][+-]?[0-9]+)?$')
  THEN RAISE EXCEPTION 'Invalid indicator 99 row or dictionary index'; END IF;
  SELECT jsonb_agg(jsonb_build_object(
           'period', v.manifest->'periods'->>((x->>0)::int),
           'university', v.manifest->'universities'->>((x->>1)::int),
           'gender', v.manifest->'genders'->>((x->>2)::int),
           'dimensions', v.manifest->'dimensions'->((x->>3)::int),
           'value', x->>4))
    INTO full_rows FROM jsonb_array_elements(data) x;
  RETURN uka_store_chunk(v.batch_id, ind, p_index, full_rows, sha);
END $fn$;

CREATE OR REPLACE FUNCTION public.uka99_verified_finalize(p_import_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' SET statement_timeout TO '900s' AS $fn$
DECLARE
  ind constant text := 'uka-soktryck-yrkesprogram';
  v public.uka_verified_imports%rowtype; b public.uka_batches%rowtype; current_id uuid; refresh jsonb;
BEGIN
  SELECT * INTO v FROM uka_verified_imports WHERE import_key = p_import_key FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown import key'; END IF;
  IF v.manifest->>'indicator' IS DISTINCT FROM ind THEN RAISE EXCEPTION 'Not an indicator 99 import'; END IF;
  IF v.published_at IS NOT NULL THEN RETURN uka_verified_status(p_import_key); END IF;
  SELECT * INTO b FROM uka_batches WHERE id = v.batch_id FOR UPDATE;
  IF b.indicator_id IS DISTINCT FROM ind THEN RAISE EXCEPTION 'Batch belongs to another indicator'; END IF;
  IF b.status <> 'ready' OR b.received_rows <> b.expected_rows OR b.received_chunks <> b.expected_chunks
   OR b.expected_rows <> (v.manifest->>'rows')::int
   OR (SELECT count(*) FROM uka_observations WHERE batch_id = b.id) <> b.expected_rows
  THEN RAISE EXCEPTION 'Incomplete verified upload'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v.manifest->'chunks') x
             LEFT JOIN uka_batch_chunks c ON c.batch_id = b.id AND c.chunk_index = (x->>'index')::int
             WHERE c.checksum IS DISTINCT FROM x->>'sha256' OR c.row_count IS DISTINCT FROM (x->>'rows')::int)
   OR (SELECT count(*) FROM uka_batch_chunks WHERE batch_id = b.id) <> jsonb_array_length(v.manifest->'chunks')
  THEN RAISE EXCEPTION 'Server chunk manifest mismatch'; END IF;
  IF EXISTS (
    WITH actual AS (SELECT period, gender, count(*) n FROM uka_observations WHERE batch_id = b.id GROUP BY 1, 2),
         expected AS (SELECT x->>'period' period, x->>'gender' gender, (x->>'rows')::bigint n
                      FROM jsonb_array_elements(v.manifest->'coverage') x)
    SELECT 1 FROM actual FULL JOIN expected USING (period, gender) WHERE actual.n IS DISTINCT FROM expected.n)
  THEN RAISE EXCEPTION 'Server coverage differs from manifest'; END IF;
  IF EXISTS (SELECT 1 FROM uka_observations WHERE batch_id = b.id
             AND (gender IS NULL OR value IS NULL OR dimensions ? 'aldersgrupp'
                  OR NOT (dimensions = '{}'::jsonb OR (dimensions - 'program') = '{}'::jsonb)
                  OR NOT (v.manifest->'universities' ? university)))
  THEN RAISE EXCEPTION 'Unexpected value, age or dimension in upload'; END IF;
  IF (SELECT count(*) FROM (SELECT DISTINCT period, university, gender, dimensions
                            FROM uka_observations WHERE batch_id = b.id) s) <> b.expected_rows
  THEN RAISE EXCEPTION 'Duplicate identities in upload'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(v.manifest->'periods') p
             WHERE NOT EXISTS (SELECT 1 FROM uka_observations o
                               WHERE o.batch_id = b.id AND o.period = p AND o.university = 'Riket'))
   OR NOT EXISTS (SELECT 1 FROM uka_observations WHERE batch_id = b.id AND university = 'Luleå tekniska universitet')
  THEN RAISE EXCEPTION 'Riket or LTU missing'; END IF;

  PERFORM pg_advisory_xact_lock(hashtext(ind));
  SELECT active_batch_id INTO current_id FROM uka_active_batches WHERE indicator_id = ind;
  IF current_id IS DISTINCT FROM v.previous_batch_id THEN
    RAISE EXCEPTION 'Active indicator 99 batch changed since upload began';
  END IF;
  INSERT INTO uka_active_batches (indicator_id, active_batch_id, activated_at) VALUES (ind, b.id, now())
  ON CONFLICT (indicator_id) DO UPDATE SET active_batch_id = excluded.active_batch_id, activated_at = excluded.activated_at;
  -- Officiell källrevision är inte verifierad: inget källuppdateringsdatum anges.
  INSERT INTO indicator_metadata (indicator_id, kalla, styrande_kalla, kalla_uppdaterad_datum, hamtad_datum, updated_at)
  SELECT id, styrande_kalla, styrande_kalla, NULL, (v.manifest->>'snapshot')::date, now() FROM indicators WHERE id = ind
  ON CONFLICT (indicator_id) DO UPDATE SET kalla_uppdaterad_datum = NULL, hamtad_datum = excluded.hamtad_datum, updated_at = now();
  UPDATE uka_batches SET status = 'succeeded', finalized_at = now(), last_activity_at = now() WHERE id = b.id;
  UPDATE data_source_runs SET status = 'succeeded', finished_at = now(), rows_affected = b.received_rows, error_message = NULL
  WHERE id = b.run_id;
  -- Föregående batch behålls för rollback (raderas inte).
  refresh := agg_refresh_uka();
  UPDATE uka_verified_imports SET published_at = now() WHERE import_key = p_import_key;
  RETURN uka_verified_status(p_import_key)
    || jsonb_build_object('aggregate_refresh', refresh, 'previous_batch_retained', v.previous_batch_id);
END $fn$;

REVOKE ALL ON FUNCTION public.uka99_verified_start(text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka99_verified_chunk(text, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka99_verified_finalize(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.uka99_verified_start(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka99_verified_chunk(text, integer, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka99_verified_finalize(text) TO service_role;
