-- UKÄ verified snapshot import, shared by the eight CSV-staged indicators
-- (API 13, 31, 97, 108, 136, 77, 134, 135). HST (33) and 99 keep their own
-- functions. All write functions are SECURITY DEFINER and service_role only.
--
-- Two modes, both bound to an immutable manifest in uka_verified_imports:
--   copy   : the frozen manifest's per-period fingerprints must equal the
--            currently active batch exactly; rows are then copied inside the
--            database into a new staging batch in <=5000-row chunks.
--   upload : canonical lines are sent in chunks whose SHA-256 are listed in
--            the manifest.
-- Finalization re-verifies every stored value through the same fingerprint,
-- coverage (period, gender, age), identity uniqueness and, in copy mode, the
-- source batch again, then activates atomically. Nothing is overwritten or
-- deleted; the previous batch is retained for rollback.

-- Canonical numeric text: fixed decimal, trailing decimal zeros removed.
CREATE OR REPLACE FUNCTION public.uka_snapshot_value_text(p_value double precision)
RETURNS text LANGUAGE sql IMMUTABLE STRICT SET search_path = public AS $$
  SELECT CASE WHEN position('.' in p_value::numeric::text) > 0
              THEN rtrim(rtrim(p_value::numeric::text, '0'), '.')
              ELSE p_value::numeric::text END
$$;

-- Canonical line: jsonb_build_array(period, university, gender, dimensions, value-text)::text
CREATE OR REPLACE FUNCTION public.uka_snapshot_line(p_period text, p_university text, p_gender text,
  p_dimensions jsonb, p_value double precision)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT jsonb_build_array(p_period, p_university, p_gender, p_dimensions,
                           public.uka_snapshot_value_text(p_value))::text
$$;

CREATE OR REPLACE FUNCTION public.uka_snapshot_indicator(p_api_id int)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE p_api_id
    WHEN 13 THEN 'uka-forstahandssokande-yrkesprogram'
    WHEN 31 THEN 'uka-nyborjare-yrkesprogram'
    WHEN 97 THEN 'uka-antagna-yrkesprogram'
    WHEN 108 THEN 'uka-examinerade'
    WHEN 136 THEN 'uka-etablering'
    WHEN 77 THEN 'uka-kvarvaro-hogskolenyborjare'
    WHEN 134 THEN 'uka-kvarvaro-program'
    WHEN 135 THEN 'uka-examensfrekvens'
  END
$$;

-- Server-computed chunk plan for copy mode; written once at start.
CREATE TABLE public.uka_snapshot_copy_plan (
  import_key text NOT NULL REFERENCES public.uka_verified_imports(import_key),
  chunk_index integer NOT NULL CHECK (chunk_index >= 0),
  first_id bigint NOT NULL,
  last_id bigint NOT NULL,
  row_count integer NOT NULL CHECK (row_count BETWEEN 1 AND 5000),
  checksum text NOT NULL CHECK (checksum ~ '^[a-f0-9]{64}$'),
  PRIMARY KEY (import_key, chunk_index)
);
GRANT ALL ON public.uka_snapshot_copy_plan TO service_role;
ALTER TABLE public.uka_snapshot_copy_plan ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.uka_snapshot_copy_plan IS
  'Immutable server-computed copy plan (source id range, rows, canonical SHA-256) per verified UKÄ snapshot import.';

CREATE OR REPLACE FUNCTION public.uka_snapshot_immutable_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_TABLE_NAME = 'uka_snapshot_copy_plan' THEN
    RAISE EXCEPTION 'UKÄ-kopieringsplanen är oföränderlig' USING errcode = '55000';
  END IF;
  -- uka_verified_imports: only published_at may go from NULL to a timestamp.
  IF TG_OP = 'DELETE' THEN
    IF OLD.published_at IS NOT NULL THEN
      RAISE EXCEPTION 'Publicerad verifierad UKÄ-import kan inte raderas' USING errcode = '55000';
    END IF;
    RETURN OLD;
  END IF;
  IF NEW.import_key IS DISTINCT FROM OLD.import_key OR NEW.batch_id IS DISTINCT FROM OLD.batch_id
     OR NEW.manifest IS DISTINCT FROM OLD.manifest OR NEW.manifest_hash IS DISTINCT FROM OLD.manifest_hash
     OR NEW.previous_batch_id IS DISTINCT FROM OLD.previous_batch_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR (OLD.published_at IS NOT NULL AND NEW.published_at IS DISTINCT FROM OLD.published_at) THEN
    RAISE EXCEPTION 'Verifierat UKÄ-manifest är oföränderligt' USING errcode = '55000';
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER uka_snapshot_copy_plan_immutable
  BEFORE UPDATE OR DELETE ON public.uka_snapshot_copy_plan
  FOR EACH ROW EXECUTE FUNCTION public.uka_snapshot_immutable_guard();
CREATE TRIGGER uka_verified_imports_immutable
  BEFORE UPDATE OR DELETE ON public.uka_verified_imports
  FOR EACH ROW EXECUTE FUNCTION public.uka_snapshot_immutable_guard();

-- Pure manifest validation; returns NULL when valid, otherwise the first reason.
CREATE OR REPLACE FUNCTION public.uka_snapshot_manifest_error(m jsonb)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
DECLARE mode text; keys text[]; n int;
BEGIN
  IF jsonb_typeof(m) IS DISTINCT FROM 'object' THEN RETURN 'manifestet är inte ett objekt'; END IF;
  mode := m->>'mode';
  IF mode NOT IN ('copy', 'upload') OR mode IS NULL THEN RETURN 'mode måste vara copy eller upload'; END IF;
  SELECT array_agg(k ORDER BY k) INTO keys FROM jsonb_object_keys(m) k;
  IF keys IS DISTINCT FROM (SELECT array_agg(k ORDER BY k) FROM unnest(ARRAY['version','mode','policy','snapshot',
      'archive_sha256','canonicalization','api_id','indicator','rows','periods','coverage',
      'source_release_verified','full_source_coverage_verified','publication_basis',
      CASE mode WHEN 'copy' THEN 'source_batch_id' ELSE 'chunks' END]) k) THEN
    RETURN 'okända eller saknade manifestfält';
  END IF;
  IF m->>'version' IS DISTINCT FROM '1' THEN RETURN 'version måste vara 1'; END IF;
  IF m->>'policy' IS DISTINCT FROM 'csv-all-universities-partitions-every-root-v1' THEN RETURN 'okänd policy'; END IF;
  IF m->>'canonicalization' IS DISTINCT FROM
     'jsonb-array(period,university,gender,dimensions,numeric-text-fixed); bytewise order; newline separator without final newline'
    THEN RETURN 'okänd kanonisering'; END IF;
  IF coalesce(m->>'snapshot', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}(-[a-z0-9]+)*$' THEN RETURN 'ogiltig snapshot'; END IF;
  IF coalesce(m->>'archive_sha256', '') !~ '^[a-f0-9]{64}$' THEN RETURN 'ogiltig archive_sha256'; END IF;
  IF jsonb_typeof(m->'api_id') IS DISTINCT FROM 'number' OR (m->>'api_id') !~ '^[0-9]{1,4}$'
     OR public.uka_snapshot_indicator((m->>'api_id')::int) IS DISTINCT FROM m->>'indicator' THEN
    RETURN 'api_id och indikator hör inte till de åtta tillåtna indikatorerna';
  END IF;
  IF m->'source_release_verified' IS DISTINCT FROM 'false'::jsonb
     OR m->'full_source_coverage_verified' IS DISTINCT FROM 'false'::jsonb THEN
    RETURN 'source_release_verified och full_source_coverage_verified måste vara false';
  END IF;
  IF jsonb_typeof(m->'publication_basis') IS DISTINCT FROM 'string' OR length(m->>'publication_basis') NOT BETWEEN 20 AND 2000 THEN
    RETURN 'publication_basis saknas';
  END IF;
  IF jsonb_typeof(m->'rows') IS DISTINCT FROM 'number' OR (m->>'rows') !~ '^[1-9][0-9]{0,8}$' THEN RETURN 'ogiltigt radantal'; END IF;

  IF jsonb_typeof(m->'periods') IS DISTINCT FROM 'array' OR jsonb_array_length(m->'periods') = 0 THEN RETURN 'perioder saknas'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(m->'periods') p
             WHERE jsonb_typeof(p) <> 'object'
                OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(p) k) IS DISTINCT FROM ARRAY['period','rows','sha256']
                OR coalesce(p->>'period', '') !~ '^((HT|VT)[0-9]{4}|[0-9]{4}(/[0-9]{2})?)$'
                OR jsonb_typeof(p->'rows') <> 'number' OR (p->>'rows') !~ '^[1-9][0-9]{0,8}$'
                OR coalesce(p->>'sha256', '') !~ '^[a-f0-9]{64}$') THEN RETURN 'ogiltig periodpost'; END IF;
  IF (SELECT count(DISTINCT p->>'period') FROM jsonb_array_elements(m->'periods') p) <> jsonb_array_length(m->'periods') THEN
    RETURN 'dubblerad period';
  END IF;
  IF (SELECT sum((p->>'rows')::bigint) FROM jsonb_array_elements(m->'periods') p) <> (m->>'rows')::bigint THEN
    RETURN 'periodernas radantal summerar inte till rows';
  END IF;

  IF jsonb_typeof(m->'coverage') IS DISTINCT FROM 'array' OR jsonb_array_length(m->'coverage') = 0 THEN RETURN 'täckning saknas'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(m->'coverage') c
             WHERE jsonb_typeof(c) <> 'object'
                OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(c) k) IS DISTINCT FROM ARRAY['age','gender','period','rows']
                OR coalesce(c->>'gender', '') NOT IN ('Kvinnor', 'Män', 'Total') OR coalesce(c->>'age', '') NOT IN ('-24', '25-34', '35-', 'Total')
                OR jsonb_typeof(c->'rows') <> 'number' OR coalesce(c->>'rows', '') !~ '^[1-9][0-9]{0,8}$'
                OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(m->'periods') p WHERE p->>'period' = c->>'period'))
    THEN RETURN 'ogiltig täckningspost'; END IF;
  IF (SELECT count(DISTINCT (c->>'period', c->>'gender', c->>'age')) FROM jsonb_array_elements(m->'coverage') c)
     <> jsonb_array_length(m->'coverage') THEN RETURN 'dubblerad täckningspost'; END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(m->'periods') p
             WHERE (p->>'rows')::bigint IS DISTINCT FROM (SELECT sum((c->>'rows')::bigint) FROM jsonb_array_elements(m->'coverage') c
                                                         WHERE c->>'period' = p->>'period')) THEN
    RETURN 'täckningen summerar inte till periodens radantal';
  END IF;

  IF mode = 'copy' THEN
    IF coalesce(m->>'source_batch_id', '') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      RETURN 'ogiltigt source_batch_id';
    END IF;
  ELSE
    IF jsonb_typeof(m->'chunks') IS DISTINCT FROM 'array' THEN RETURN 'chunks saknas'; END IF;
    n := jsonb_array_length(m->'chunks');
    IF n < 1 OR n > 10000
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(m->'chunks') WITH ORDINALITY t(x, i)
                  WHERE jsonb_typeof(x) <> 'object'
                     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x) k) IS DISTINCT FROM ARRAY['index','rows','sha256']
                     OR coalesce(x->>'index', '') !~ '^[0-9]+$' OR (x->>'index')::int <> i - 1
                     OR coalesce(x->>'rows', '') !~ '^[0-9]+$' OR (x->>'rows')::int NOT BETWEEN 1 AND 5000
                     OR coalesce(x->>'sha256', '') !~ '^[a-f0-9]{64}$')
       OR (SELECT sum((x->>'rows')::bigint) FROM jsonb_array_elements(m->'chunks') x) <> (m->>'rows')::bigint THEN
      RETURN 'ogiltigt chunkmanifest';
    END IF;
  END IF;
  RETURN NULL;
END $$;

-- Per-period canonical fingerprints of one batch.
CREATE OR REPLACE FUNCTION public.uka_snapshot_period_hashes(p_batch_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET statement_timeout = '300s' AS $$
  SELECT coalesce(jsonb_agg(jsonb_build_object('period', period, 'rows', n, 'sha256', h) ORDER BY period COLLATE "C"), '[]'::jsonb)
  FROM (SELECT period, count(*) n,
               encode(extensions.digest(convert_to(string_agg(line, E'\n' ORDER BY line COLLATE "C"), 'UTF8'), 'sha256'), 'hex') h
        FROM (SELECT period, public.uka_snapshot_line(period, university, gender, dimensions, value) line
              FROM uka_observations WHERE batch_id = p_batch_id) l
        GROUP BY period) s
$$;

-- Full verification of a batch against a manifest; reports counts and periods only, never observations.
CREATE OR REPLACE FUNCTION public.uka_snapshot_verify_batch(p_batch_id uuid, p_manifest jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public SET statement_timeout = '300s' AS $$
DECLARE ind text := p_manifest->>'indicator'; hashes jsonb; period_bad jsonb; coverage_bad jsonb; integrity jsonb; ok boolean;
BEGIN
  hashes := public.uka_snapshot_period_hashes(p_batch_id);
  SELECT coalesce(jsonb_agg(jsonb_build_object('period', coalesce(e.period, a.period), 'expected_rows', e.rows,
           'actual_rows', a.rows, 'sha256_match', e.sha256 IS NOT DISTINCT FROM a.sha256) ORDER BY coalesce(e.period, a.period)), '[]'::jsonb)
    INTO period_bad
    FROM jsonb_to_recordset(p_manifest->'periods') e(period text, rows bigint, sha256 text)
    FULL JOIN jsonb_to_recordset(hashes) a(period text, rows bigint, sha256 text) ON a.period = e.period
   WHERE e.rows IS DISTINCT FROM a.rows OR e.sha256 IS DISTINCT FROM a.sha256;
  WITH actual AS (SELECT period, gender, coalesce(dimensions->>'aldersgrupp', 'Total') age, count(*) n
                    FROM uka_observations WHERE batch_id = p_batch_id GROUP BY 1, 2, 3),
       expected AS (SELECT * FROM jsonb_to_recordset(p_manifest->'coverage') x(period text, gender text, age text, rows bigint))
  SELECT coalesce(jsonb_agg(jsonb_build_object('period', coalesce(e.period, a.period), 'gender', coalesce(e.gender, a.gender),
           'age', coalesce(e.age, a.age), 'expected_rows', e.rows, 'actual_rows', a.n)), '[]'::jsonb)
    INTO coverage_bad
    FROM expected e FULL JOIN actual a ON a.period = e.period AND a.gender = e.gender AND a.age = e.age
   WHERE e.rows IS DISTINCT FROM a.n;
  SELECT jsonb_build_object(
    'wrong_indicator', count(*) FILTER (WHERE indicator_id IS DISTINCT FROM ind),
    'invalid_gender', count(*) FILTER (WHERE gender IS NULL OR gender NOT IN ('Kvinnor', 'Män', 'Total')),
    'invalid_age_key', count(*) FILTER (WHERE dimensions ? 'aldersgrupp' AND dimensions->>'aldersgrupp' NOT IN ('-24', '25-34', '35-')),
    'non_string_dimension', count(*) FILTER (WHERE jsonb_typeof(dimensions) <> 'object'
        OR EXISTS (SELECT 1 FROM jsonb_each(dimensions) d WHERE jsonb_typeof(d.value) <> 'string')),
    'inexact_value_text', count(*) FILTER (WHERE value IS NOT NULL
        AND (value::text IN ('NaN', 'Infinity', '-Infinity') OR public.uka_snapshot_value_text(value)::double precision <> value)),
    'duplicate_identity', (SELECT count(*) FROM (SELECT 1 FROM uka_observations WHERE batch_id = p_batch_id
        GROUP BY period, university, gender, dimensions HAVING count(*) > 1) d),
    -- agg_refresh_uka groups by (university, period, gender, key list, value list) and uses sum();
    -- with no collisions every aggregate row is exactly one observation, so nothing is summed.
    'aggregate_collision', (SELECT count(*) FROM (SELECT 1 FROM uka_observations o WHERE batch_id = p_batch_id
        GROUP BY o.university, o.period, coalesce(o.gender, 'Total'),
          coalesce((SELECT string_agg(k, '|' ORDER BY k) FROM jsonb_object_keys(o.dimensions) k), ''),
          coalesce((SELECT string_agg(o.dimensions->>k, '|' ORDER BY k) FROM jsonb_object_keys(o.dimensions) k), '')
        HAVING count(*) > 1) c))
    INTO integrity FROM uka_observations WHERE batch_id = p_batch_id;
  ok := period_bad = '[]'::jsonb AND coverage_bad = '[]'::jsonb
        AND NOT EXISTS (SELECT 1 FROM jsonb_each_text(integrity) WHERE value::bigint <> 0);
  RETURN jsonb_build_object('ok', ok, 'batch_id', p_batch_id, 'periods_checked', jsonb_array_length(hashes),
    'rows_checked', (SELECT coalesce(sum((x->>'rows')::bigint), 0) FROM jsonb_array_elements(hashes) x),
    'period_mismatches', period_bad, 'coverage_mismatches', coverage_bad, 'integrity', integrity);
END $$;

CREATE OR REPLACE FUNCTION public.uka_snapshot_status(p_import_key text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.uka_verified_status(p_import_key) || jsonb_build_object(
    'indicator', v.manifest->>'indicator', 'api_id', v.manifest->'api_id', 'mode', v.manifest->>'mode',
    'manifest_hash', v.manifest_hash, 'previous_batch_id', v.previous_batch_id,
    'planned_chunks', (SELECT count(*) FROM uka_snapshot_copy_plan c WHERE c.import_key = v.import_key))
  FROM uka_verified_imports v WHERE v.import_key = p_import_key AND v.manifest ? 'api_id'
$$;

CREATE OR REPLACE FUNCTION public.uka_snapshot_start(p_import_key text, p_manifest jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public SET statement_timeout = '300s' AS $$
DECLARE err text; ind text; v uka_verified_imports%rowtype; old uuid; src uuid; run uuid; b uuid; n int;
        other text; mhash text; chk jsonb;
BEGIN
  err := public.uka_snapshot_manifest_error(p_manifest);
  IF err IS NOT NULL THEN RAISE EXCEPTION 'Ogiltigt UKÄ-manifest: %', err USING errcode = '22023'; END IF;
  ind := p_manifest->>'indicator';
  IF p_import_key IS NULL OR p_import_key !~ ('^uka-' || (p_manifest->>'api_id') || '-[a-z0-9][a-z0-9-]{7,120}$') THEN
    RAISE EXCEPTION 'Importnyckeln måste ha formen uka-%-<stabil-del>', p_manifest->>'api_id' USING errcode = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('uka-snapshot:' || ind));
  SELECT * INTO v FROM uka_verified_imports WHERE import_key = p_import_key;
  IF FOUND THEN
    IF v.manifest IS DISTINCT FROM p_manifest THEN
      RAISE EXCEPTION 'Importnyckeln % är redan bunden till ett annat manifest', p_import_key USING errcode = '55000';
    END IF;
    RETURN public.uka_snapshot_status(p_import_key) || jsonb_build_object('resumed', true);
  END IF;
  mhash := encode(extensions.digest(p_manifest::text, 'sha256'), 'hex');
  SELECT import_key INTO other FROM uka_verified_imports WHERE manifest_hash = mhash LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Samma manifest är redan bundet till import %', other USING errcode = '55000';
  END IF;
  SELECT v2.import_key INTO other FROM uka_verified_imports v2 LEFT JOIN uka_batches b2 ON b2.id = v2.batch_id
   WHERE (b2.indicator_id = ind OR v2.manifest->>'indicator' = ind) AND v2.published_at IS NULL LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'En annan verifierad import (%) pågår för %', other, ind USING errcode = '55000';
  END IF;
  SELECT active_batch_id INTO old FROM uka_active_batches WHERE indicator_id = ind;
  IF p_manifest->>'mode' = 'copy' THEN
    src := (p_manifest->>'source_batch_id')::uuid;
    IF old IS DISTINCT FROM src THEN
      RAISE EXCEPTION 'Källbatchen % är inte aktiv för %', src, ind USING errcode = '55000';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM uka_batches WHERE id = src AND indicator_id = ind AND status = 'succeeded') THEN
      RAISE EXCEPTION 'Källbatchen är inte en publicerad batch för %', ind USING errcode = '55000';
    END IF;
    chk := public.uka_snapshot_verify_batch(src, p_manifest);
    IF NOT (chk->>'ok')::boolean THEN
      RAISE EXCEPTION 'Källbatchen matchar inte det frysta manifestet; inget har skrivits' USING errcode = '22000', detail = chk::text;
    END IF;
    n := ceil((p_manifest->>'rows')::numeric / 5000)::int;
  ELSE
    n := jsonb_array_length(p_manifest->'chunks');
  END IF;
  INSERT INTO data_source_runs(source, source_id, indicator_id, status, started_at, details)
  VALUES ('UKÄ verified CSV snapshot', 'uka-hogskolan-i-siffror', ind, 'started', now(),
          jsonb_build_object('import_key', p_import_key, 'mode', p_manifest->>'mode', 'manifest_hash', mhash,
                             'source_release_verified', false, 'full_source_coverage_verified', false))
  RETURNING id INTO run;
  b := public.uka_start_batch(ind, 'UKÄ verified CSV snapshot', n, (p_manifest->>'rows')::int, NULL, run);
  INSERT INTO uka_verified_imports(import_key, batch_id, manifest, manifest_hash, previous_batch_id)
  VALUES (p_import_key, b, p_manifest, mhash, old);
  IF p_manifest->>'mode' = 'copy' THEN
    INSERT INTO uka_snapshot_copy_plan(import_key, chunk_index, first_id, last_id, row_count, checksum)
    SELECT p_import_key, ci, min(id), max(id), count(*),
           encode(extensions.digest(convert_to(string_agg(line, E'\n' ORDER BY line COLLATE "C"), 'UTF8'), 'sha256'), 'hex')
      FROM (SELECT id, ((row_number() OVER (ORDER BY id)) - 1) / 5000 AS ci,
                   public.uka_snapshot_line(period, university, gender, dimensions, value) line
              FROM uka_observations WHERE batch_id = src) s
     GROUP BY ci;
    IF (SELECT count(*) FROM uka_snapshot_copy_plan WHERE import_key = p_import_key) <> n THEN
      RAISE EXCEPTION 'Kopieringsplanen fick fel antal chunkar';
    END IF;
  END IF;
  RETURN public.uka_snapshot_status(p_import_key) || jsonb_build_object('resumed', false, 'source_check', chk);
END $$;

-- Internal copy of one planned chunk from the verified source batch.
CREATE OR REPLACE FUNCTION public.uka_snapshot_copy_chunk(p_import_key text, p_index int)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public SET statement_timeout = '180s' AS $$
DECLARE v uka_verified_imports%rowtype; p uka_snapshot_copy_plan%rowtype; b uka_batches%rowtype;
        ind text; src uuid; prior text; n int; sha text;
BEGIN
  SELECT * INTO v FROM uka_verified_imports WHERE import_key = p_import_key FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Okänd importnyckel' USING errcode = 'no_data_found'; END IF;
  ind := v.manifest->>'indicator';
  IF v.manifest->>'mode' IS DISTINCT FROM 'copy' OR public.uka_snapshot_manifest_error(v.manifest) IS NOT NULL THEN
    RAISE EXCEPTION 'Importen är inte en verifierad kopieringsimport' USING errcode = '55000';
  END IF;
  SELECT * INTO p FROM uka_snapshot_copy_plan WHERE import_key = p_import_key AND chunk_index = p_index;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chunk % ligger utanför planen', p_index USING errcode = '22023'; END IF;
  SELECT checksum INTO prior FROM uka_batch_chunks WHERE batch_id = v.batch_id AND chunk_index = p_index;
  IF FOUND THEN
    IF prior <> p.checksum THEN RAISE EXCEPTION 'Mottagen chunk avviker från planen' USING errcode = '55000'; END IF;
    RETURN jsonb_build_object('duplicate', true, 'index', p_index);
  END IF;
  IF v.published_at IS NOT NULL THEN RAISE EXCEPTION 'Publicerad import är oföränderlig' USING errcode = '55000'; END IF;
  SELECT * INTO b FROM uka_batches WHERE id = v.batch_id FOR UPDATE;
  IF b.indicator_id IS DISTINCT FROM ind OR b.status NOT IN ('receiving', 'ready') THEN
    RAISE EXCEPTION 'Stagingbatchen kan inte ta emot chunkar' USING errcode = '55000';
  END IF;
  src := (v.manifest->>'source_batch_id')::uuid;
  SELECT count(*), encode(extensions.digest(convert_to(string_agg(line, E'\n' ORDER BY line COLLATE "C"), 'UTF8'), 'sha256'), 'hex')
    INTO n, sha
    FROM (SELECT public.uka_snapshot_line(period, university, gender, dimensions, value) line
            FROM uka_observations WHERE batch_id = src AND id BETWEEN p.first_id AND p.last_id) l;
  IF n <> p.row_count OR sha IS DISTINCT FROM p.checksum THEN
    RAISE EXCEPTION 'Källbatchen har ändrats sedan planen skapades; inget kopierat' USING errcode = '55000';
  END IF;
  INSERT INTO uka_observations(batch_id, indicator_id, period, university, gender, value, dimensions)
  SELECT v.batch_id, ind, period, university, gender, value, dimensions
    FROM uka_observations WHERE batch_id = src AND id BETWEEN p.first_id AND p.last_id ORDER BY id;
  INSERT INTO uka_batch_chunks(batch_id, chunk_index, row_count, checksum) VALUES (v.batch_id, p_index, n, sha);
  UPDATE uka_batches SET received_chunks = received_chunks + 1, received_rows = received_rows + n,
         status = CASE WHEN received_chunks + 1 >= expected_chunks THEN 'ready' ELSE 'receiving' END,
         last_activity_at = now()
   WHERE id = v.batch_id;
  RETURN jsonb_build_object('duplicate', false, 'index', p_index, 'rows', n);
END $$;

-- Upload of one chunk of canonical lines (newline separated, no final newline).
CREATE OR REPLACE FUNCTION public.uka_snapshot_chunk(p_import_key text, p_index int, p_payload text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public SET statement_timeout = '180s' AS $$
DECLARE v uka_verified_imports%rowtype; b uka_batches%rowtype; expected jsonb; ind text; prior text; sha text;
        lines text[]; parsed jsonb[]; bad int;
BEGIN
  SELECT * INTO v FROM uka_verified_imports WHERE import_key = p_import_key FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Okänd importnyckel' USING errcode = 'no_data_found'; END IF;
  ind := v.manifest->>'indicator';
  IF v.manifest->>'mode' IS DISTINCT FROM 'upload' OR public.uka_snapshot_manifest_error(v.manifest) IS NOT NULL THEN
    RAISE EXCEPTION 'Importen är inte en verifierad uppladdningsimport' USING errcode = '55000';
  END IF;
  expected := v.manifest->'chunks'->p_index;
  IF p_index < 0 OR expected IS NULL THEN RAISE EXCEPTION 'Chunk % ligger utanför manifestet', p_index USING errcode = '22023'; END IF;
  sha := encode(extensions.digest(convert_to(p_payload, 'UTF8'), 'sha256'), 'hex');
  IF sha <> expected->>'sha256' THEN RAISE EXCEPTION 'Chunkens kontrollsumma avviker från manifestet' USING errcode = '22000'; END IF;
  SELECT checksum INTO prior FROM uka_batch_chunks WHERE batch_id = v.batch_id AND chunk_index = p_index;
  IF FOUND THEN
    IF prior <> sha THEN RAISE EXCEPTION 'Mottagen chunk avviker' USING errcode = '55000'; END IF;
    RETURN jsonb_build_object('duplicate', true, 'index', p_index);
  END IF;
  IF v.published_at IS NOT NULL THEN RAISE EXCEPTION 'Publicerad import är oföränderlig' USING errcode = '55000'; END IF;
  SELECT * INTO b FROM uka_batches WHERE id = v.batch_id FOR UPDATE;
  IF b.indicator_id IS DISTINCT FROM ind OR b.status NOT IN ('receiving', 'ready') THEN
    RAISE EXCEPTION 'Stagingbatchen kan inte ta emot chunkar' USING errcode = '55000';
  END IF;
  lines := string_to_array(p_payload, E'\n');
  IF coalesce(cardinality(lines), 0) <> (expected->>'rows')::int THEN
    RAISE EXCEPTION 'Chunkens radantal avviker från manifestet' USING errcode = '22000';
  END IF;
  BEGIN
    SELECT array_agg(l::jsonb ORDER BY i) INTO parsed FROM unnest(lines) WITH ORDINALITY t(l, i);
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'Chunken innehåller en rad som inte är JSON' USING errcode = '22000';
  END;
  SELECT count(*) INTO bad FROM unnest(lines, parsed) t(l, x)
   WHERE jsonb_typeof(x) <> 'array' OR jsonb_array_length(x) <> 5
      OR x::text <> l
      OR jsonb_typeof(x->0) <> 'string' OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v.manifest->'periods') p WHERE p->>'period' = x->>0)
      OR jsonb_typeof(x->1) <> 'string' OR x->>1 = ''
      OR jsonb_typeof(x->2) <> 'string' OR x->>2 NOT IN ('Kvinnor', 'Män', 'Total')
      OR jsonb_typeof(x->3) <> 'object'
      OR EXISTS (SELECT 1 FROM jsonb_each(x->3) d WHERE jsonb_typeof(d.value) <> 'string' OR d.key = '')
      OR (x->3 ? 'aldersgrupp' AND x->3->>'aldersgrupp' NOT IN ('-24', '25-34', '35-'))
      OR jsonb_typeof(x->4) NOT IN ('string', 'null')
      OR (jsonb_typeof(x->4) = 'string' AND (x->>4 !~ '^-?(0|[1-9][0-9]*)([.][0-9]*[1-9])?$'
          OR public.uka_snapshot_value_text((x->>4)::double precision) <> x->>4));
  IF bad > 0 THEN
    RAISE EXCEPTION '% rader är inte kanoniska eller ligger utanför manifestet; inget sparat', bad USING errcode = '22000';
  END IF;
  INSERT INTO uka_observations(batch_id, indicator_id, period, university, gender, value, dimensions)
  SELECT v.batch_id, ind, x->>0, x->>1, x->>2, (x->>4)::double precision, x->3 FROM unnest(parsed) x;
  INSERT INTO uka_batch_chunks(batch_id, chunk_index, row_count, checksum) VALUES (v.batch_id, p_index, cardinality(lines), sha);
  UPDATE uka_batches SET received_chunks = received_chunks + 1, received_rows = received_rows + cardinality(lines),
         status = CASE WHEN received_chunks + 1 >= expected_chunks THEN 'ready' ELSE 'receiving' END,
         last_activity_at = now()
   WHERE id = v.batch_id;
  RETURN jsonb_build_object('duplicate', false, 'index', p_index, 'rows', cardinality(lines));
END $$;

CREATE OR REPLACE FUNCTION public.uka_snapshot_finalize(p_import_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public SET statement_timeout = '900s' AS $$
DECLARE v uka_verified_imports%rowtype; b uka_batches%rowtype; ind text; current_id uuid; refresh jsonb;
        new_chk jsonb; src_chk jsonb; chunk_bad int;
BEGIN
  SELECT * INTO v FROM uka_verified_imports WHERE import_key = p_import_key FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Okänd importnyckel' USING errcode = 'no_data_found'; END IF;
  IF public.uka_snapshot_manifest_error(v.manifest) IS NOT NULL THEN
    RAISE EXCEPTION 'Importen hör inte till den gemensamma verifierade vägen' USING errcode = '55000';
  END IF;
  ind := v.manifest->>'indicator';
  IF v.published_at IS NOT NULL THEN
    RETURN public.uka_snapshot_status(p_import_key) || jsonb_build_object('already_published', true);
  END IF;
  SELECT * INTO b FROM uka_batches WHERE id = v.batch_id FOR UPDATE;
  IF b.indicator_id IS DISTINCT FROM ind THEN RAISE EXCEPTION 'Batchen hör till en annan indikator' USING errcode = '55000'; END IF;
  IF b.status <> 'ready' OR b.received_rows <> b.expected_rows OR b.received_chunks <> b.expected_chunks
     OR (SELECT count(*) FROM uka_observations WHERE batch_id = b.id) <> b.expected_rows THEN
    RAISE EXCEPTION 'Ofullständig verifierad import: %/% chunkar, %/% rader', b.received_chunks, b.expected_chunks,
      b.received_rows, b.expected_rows USING errcode = '55000';
  END IF;
  IF v.manifest->>'mode' = 'copy' THEN
    SELECT count(*) INTO chunk_bad
      FROM (SELECT chunk_index, row_count, checksum FROM uka_snapshot_copy_plan WHERE import_key = p_import_key) p
      FULL JOIN (SELECT chunk_index, row_count, checksum FROM uka_batch_chunks WHERE batch_id = b.id) c USING (chunk_index)
     WHERE c.checksum IS DISTINCT FROM p.checksum OR c.row_count IS DISTINCT FROM p.row_count;
  ELSE
    SELECT count(*) INTO chunk_bad
      FROM (SELECT (x->>'index')::int chunk_index, (x->>'rows')::int row_count, x->>'sha256' checksum
              FROM jsonb_array_elements(v.manifest->'chunks') x) p
      FULL JOIN (SELECT chunk_index, row_count, checksum FROM uka_batch_chunks WHERE batch_id = b.id) c USING (chunk_index)
     WHERE c.checksum IS DISTINCT FROM p.checksum OR c.row_count IS DISTINCT FROM p.row_count;
  END IF;
  IF chunk_bad <> 0 THEN RAISE EXCEPTION 'Serverns chunkar avviker från manifestet/planen (%)', chunk_bad USING errcode = '55000'; END IF;
  new_chk := public.uka_snapshot_verify_batch(b.id, v.manifest);
  IF NOT (new_chk->>'ok')::boolean THEN
    RAISE EXCEPTION 'Stagingbatchen matchar inte manifestet; ingen aktivering' USING errcode = '22000', detail = new_chk::text;
  END IF;
  IF v.manifest->>'mode' = 'copy' THEN
    src_chk := public.uka_snapshot_verify_batch((v.manifest->>'source_batch_id')::uuid, v.manifest);
    IF NOT (src_chk->>'ok')::boolean THEN
      RAISE EXCEPTION 'Källbatchen matchar inte längre manifestet; ingen aktivering' USING errcode = '22000', detail = src_chk::text;
    END IF;
  END IF;
  -- Same lock as the legacy finalizer and the per-indicator verified paths.
  PERFORM pg_advisory_xact_lock(hashtext(ind));
  SELECT active_batch_id INTO current_id FROM uka_active_batches WHERE indicator_id = ind;
  IF current_id IS DISTINCT FROM v.previous_batch_id THEN
    RAISE EXCEPTION 'Aktiv batch för % har ändrats sedan importen startade', ind USING errcode = '55000';
  END IF;
  INSERT INTO uka_active_batches(indicator_id, active_batch_id, activated_at) VALUES (ind, b.id, now())
  ON CONFLICT (indicator_id) DO UPDATE SET active_batch_id = excluded.active_batch_id, activated_at = excluded.activated_at;
  INSERT INTO indicator_metadata(indicator_id, kalla, styrande_kalla, kalla_uppdaterad_datum, hamtad_datum, updated_at)
  SELECT id, styrande_kalla, styrande_kalla, NULL, left(v.manifest->>'snapshot', 10)::date, now() FROM indicators WHERE id = ind
  ON CONFLICT (indicator_id) DO UPDATE SET kalla_uppdaterad_datum = NULL, hamtad_datum = excluded.hamtad_datum, updated_at = now();
  UPDATE uka_batches SET status = 'succeeded', finalized_at = now(), last_activity_at = now() WHERE id = b.id;
  UPDATE data_source_runs SET status = 'succeeded', finished_at = now(), rows_affected = b.received_rows, error_message = NULL,
         details = coalesce(details, '{}'::jsonb) || jsonb_build_object('previous_batch_retained', v.previous_batch_id,
           'periods_verified', new_chk->'periods_checked', 'rows_verified', new_chk->'rows_checked')
   WHERE id = b.run_id;
  -- Activation and aggregate refresh commit together; the previous batch is kept.
  refresh := public.agg_refresh_uka();
  UPDATE uka_verified_imports SET published_at = now() WHERE import_key = p_import_key;
  RETURN public.uka_snapshot_status(p_import_key) || jsonb_build_object('aggregate_refresh', refresh,
    'previous_batch_retained', v.previous_batch_id, 'staging_check', new_chk, 'source_check', src_chk);
END $$;

-- HST functions: unchanged except that they now refuse imports of other indicators.
CREATE OR REPLACE FUNCTION public.uka_verified_chunk(p_import_key text, p_index integer, p_payload text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '180s'
AS $function$
DECLARE v public.uka_verified_imports%rowtype; expected jsonb; data jsonb; full_rows jsonb; sha text; prior text;
BEGIN
 SELECT * INTO v FROM uka_verified_imports WHERE import_key=p_import_key FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown import key'; END IF;
 IF v.manifest->>'indicator' IS DISTINCT FROM 'uka-hst' THEN RAISE EXCEPTION 'Not an HST import' USING errcode = '55000'; END IF;
 expected:=v.manifest->'chunks'->p_index;
 IF p_index<0 OR expected IS NULL THEN RAISE EXCEPTION 'Chunk outside manifest'; END IF;
 sha:=encode(extensions.digest(p_payload,'sha256'),'hex');
 IF sha<>expected->>'sha256' THEN RAISE EXCEPTION 'Chunk checksum differs from manifest'; END IF;
 SELECT checksum INTO prior FROM uka_batch_chunks WHERE batch_id=v.batch_id AND chunk_index=p_index;
 IF FOUND THEN
  IF prior<>sha THEN RAISE EXCEPTION 'Existing chunk differs'; END IF;
  RETURN jsonb_build_object('duplicate',true,'index',p_index);
 END IF;
 IF v.published_at IS NOT NULL THEN RAISE EXCEPTION 'Published import is immutable'; END IF;
 data:=p_payload::jsonb;
 IF jsonb_typeof(data)<>'array' OR jsonb_array_length(data)<>(expected->>'rows')::int THEN RAISE EXCEPTION 'Chunk row count differs'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(data) x WHERE jsonb_array_length(x)<>5
 OR (x->>0)::int<0 OR v.manifest->'periods'->((x->>0)::int) IS NULL
 OR (x->>1)::int<0 OR v.manifest->'universities'->((x->>1)::int) IS NULL
 OR (x->>2)::int NOT BETWEEN 0 AND 2
 OR (x->>3)::int<0 OR v.manifest->'dimensions'->((x->>3)::int) IS NULL
 OR x->>4 !~ '^[0-9]+([.][0-9]+)?([Ee][+-]?[0-9]+)?$') THEN RAISE EXCEPTION 'Invalid HST row or dictionary index'; END IF;
 SELECT jsonb_agg(jsonb_build_object('period',v.manifest->'periods'->>((x->>0)::int),
  'university',v.manifest->'universities'->>((x->>1)::int),
  'gender',v.manifest->'genders'->>((x->>2)::int),
  'dimensions',v.manifest->'dimensions'->((x->>3)::int),'value',x->>4)) INTO full_rows FROM jsonb_array_elements(data) x;
 RETURN uka_store_chunk(v.batch_id,'uka-hst',p_index,full_rows,sha);
END $function$;

CREATE OR REPLACE FUNCTION public.uka_verified_finalize(p_import_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '900s'
AS $function$
DECLARE v public.uka_verified_imports%rowtype; b public.uka_batches%rowtype; current_id uuid; refresh jsonb;
BEGIN
 SELECT * INTO v FROM uka_verified_imports WHERE import_key=p_import_key FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown import key'; END IF;
 IF v.manifest->>'indicator' IS DISTINCT FROM 'uka-hst' THEN RAISE EXCEPTION 'Not an HST import' USING errcode = '55000'; END IF;
 IF v.published_at IS NOT NULL THEN RETURN uka_verified_status(p_import_key); END IF;
 SELECT * INTO b FROM uka_batches WHERE id=v.batch_id FOR UPDATE;
 IF b.indicator_id IS DISTINCT FROM 'uka-hst' THEN RAISE EXCEPTION 'Batch belongs to another indicator' USING errcode = '55000'; END IF;
 IF b.status<>'ready' OR b.received_rows<>b.expected_rows OR b.received_chunks<>b.expected_chunks
 OR (SELECT count(*) FROM uka_observations WHERE batch_id=b.id)<>b.expected_rows THEN RAISE EXCEPTION 'Incomplete verified upload'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v.manifest->'chunks') x LEFT JOIN uka_batch_chunks c ON c.batch_id=b.id AND c.chunk_index=(x->>'index')::int
 WHERE c.checksum IS DISTINCT FROM x->>'sha256' OR c.row_count IS DISTINCT FROM (x->>'rows')::int) THEN RAISE EXCEPTION 'Server chunk manifest mismatch'; END IF;
 IF EXISTS(WITH actual AS (SELECT period,gender,coalesce(dimensions->>'aldersgrupp','Total') age,count(*) n FROM uka_observations WHERE batch_id=b.id GROUP BY 1,2,3),
 expected AS (SELECT x->>'period' period,x->>'gender' gender,x->>'age' age,(x->>'rows')::bigint n FROM jsonb_array_elements(v.manifest->'coverage') x)
 SELECT 1 FROM actual FULL JOIN expected USING(period,gender,age) WHERE actual.n IS DISTINCT FROM expected.n) THEN RAISE EXCEPTION 'Server HST coverage differs from manifest'; END IF;
 PERFORM pg_advisory_xact_lock(hashtext('uka-hst'));
 SELECT active_batch_id INTO current_id FROM uka_active_batches WHERE indicator_id='uka-hst';
 IF current_id IS DISTINCT FROM v.previous_batch_id THEN RAISE EXCEPTION 'Active HST changed since upload began'; END IF;
 INSERT INTO uka_active_batches(indicator_id,active_batch_id,activated_at) VALUES('uka-hst',b.id,now())
 ON CONFLICT(indicator_id) DO UPDATE SET active_batch_id=excluded.active_batch_id,activated_at=excluded.activated_at;
 INSERT INTO indicator_metadata(indicator_id,kalla,styrande_kalla,kalla_uppdaterad_datum,hamtad_datum,updated_at)
 SELECT id,styrande_kalla,styrande_kalla,NULL,(v.manifest->>'snapshot')::date,now() FROM indicators WHERE id='uka-hst'
 ON CONFLICT(indicator_id) DO UPDATE SET kalla_uppdaterad_datum=NULL,hamtad_datum=excluded.hamtad_datum,updated_at=now();
 UPDATE uka_batches SET status='succeeded',finalized_at=now(),last_activity_at=now() WHERE id=b.id;
 UPDATE data_source_runs SET status='succeeded',finished_at=now(),rows_affected=b.received_rows,error_message=NULL WHERE id=b.run_id;
 -- Refresh and activation commit together. Unlike the legacy finalizer, retain
 -- the previous batch for rollback instead of deleting its observations.
 refresh:=agg_refresh_uka();
 UPDATE uka_verified_imports SET published_at=now() WHERE import_key=p_import_key;
 RETURN uka_verified_status(p_import_key)||jsonb_build_object('aggregate_refresh',refresh,'previous_batch_retained',v.previous_batch_id);
END $function$;

REVOKE ALL ON FUNCTION public.uka_snapshot_value_text(double precision) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_snapshot_line(text, text, text, jsonb, double precision) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_snapshot_indicator(int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_snapshot_manifest_error(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_snapshot_period_hashes(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_snapshot_verify_batch(uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_snapshot_status(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_snapshot_start(text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_snapshot_copy_chunk(text, int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_snapshot_chunk(text, int, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_snapshot_finalize(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_snapshot_immutable_guard() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_verified_chunk(text, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_verified_finalize(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.uka_snapshot_value_text(double precision) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_snapshot_line(text, text, text, jsonb, double precision) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_snapshot_indicator(int) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_snapshot_manifest_error(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_snapshot_period_hashes(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_snapshot_verify_batch(uuid, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_snapshot_status(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_snapshot_start(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_snapshot_copy_chunk(text, int) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_snapshot_chunk(text, int, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_snapshot_finalize(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_verified_chunk(text, integer, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_verified_finalize(text) TO service_role;
