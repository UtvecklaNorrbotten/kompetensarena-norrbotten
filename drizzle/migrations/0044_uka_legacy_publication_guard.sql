-- Skydd för verifierad UKÄ-publicering mot den äldre ETL-vägen.
-- Äldre ETL (uka_store_chunk/uka_finalize_batch via /api/public/jobs/uka/*) får inte
-- aktivera en ny batch eller radera föregående batch för en indikator som har, eller
-- håller på att få, en verifierad import. Spärren gäller även redan startade äldre
-- batchar: den kontrolleras vid varje chunk och vid finalisering, före aktivering och
-- radering. Verifierade vägar (uka_verified_*, uka99_verified_*) påverkas inte.
-- Ingen data ändras av denna migration.

CREATE OR REPLACE FUNCTION public.uka_legacy_publication_block(p_indicator_id text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM uka_active_batches a
      JOIN uka_verified_imports v ON v.batch_id = a.active_batch_id
      WHERE a.indicator_id = p_indicator_id)
      THEN 'aktiv version är publicerad via verifierad import (' || (
        SELECT v.import_key FROM uka_active_batches a
        JOIN uka_verified_imports v ON v.batch_id = a.active_batch_id
        WHERE a.indicator_id = p_indicator_id) || ')'
    WHEN EXISTS (
      SELECT 1 FROM uka_verified_imports v
      LEFT JOIN uka_batches b ON b.id = v.batch_id
      WHERE (b.indicator_id = p_indicator_id OR v.manifest->>'indicator' = p_indicator_id)
        AND v.published_at IS NULL)
      THEN 'en verifierad import pågår för indikatorn'
    WHEN EXISTS (
      SELECT 1 FROM uka_verified_imports v
      LEFT JOIN uka_batches b ON b.id = v.batch_id
      WHERE b.indicator_id = p_indicator_id OR v.manifest->>'indicator' = p_indicator_id)
      THEN 'indikatorn har publicerats via verifierad import; revisioner och rollback går via den verifierade vägen'
  END
$fn$;

REVOKE ALL ON FUNCTION public.uka_legacy_publication_block(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.uka_legacy_publication_block(text) TO service_role;

CREATE OR REPLACE FUNCTION public.uka_store_chunk(p_batch_id uuid, p_indicator_id text, p_chunk_index integer, p_observations jsonb, p_checksum text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET statement_timeout TO '180s'
AS $function$
declare
  v_batch public.uka_batches%rowtype;
  v_existing public.uka_batch_chunks%rowtype;
  v_rows integer;
  v_block text;
begin
  select * into v_batch
  from public.uka_batches
  where id = p_batch_id
  for update;

  if not found then
    raise exception 'UKÄ-batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;
  -- Äldre batchar (utan verifierad import) stoppas för skyddade indikatorer.
  if not exists (select 1 from public.uka_verified_imports where batch_id = p_batch_id) then
    v_block := public.uka_legacy_publication_block(v_batch.indicator_id);
    if v_block is not null then
      raise exception 'Äldre UKÄ-import stoppad för %: %. Inga rader har sparats.', v_batch.indicator_id, v_block
        using errcode = '55000',
              hint = 'Publicera via den verifierade importvägen. Aktiv och tidigare version lämnas orörda.';
    end if;
  end if;
  if v_batch.status not in ('receiving','ready') then
    raise exception 'UKÄ-batch har status %', v_batch.status using errcode = 'invalid_parameter_value';
  end if;
  if v_batch.indicator_id is distinct from p_indicator_id then
    raise exception 'Fel indikator för UKÄ-batch' using errcode = 'invalid_parameter_value';
  end if;
  if p_chunk_index < 0 or p_chunk_index >= v_batch.expected_chunks then
    raise exception 'UKÄ chunk_index utanför intervallet' using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_observations) o
    where not (o ? 'period' and o ? 'university')
       or coalesce(o->>'period','') = ''
       or coalesce(o->>'university','') = ''
       or o ? 'geo_code'
  ) then
    raise exception 'Ogiltig UKÄ-observation' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_existing
  from public.uka_batch_chunks
  where batch_id = p_batch_id and chunk_index = p_chunk_index;

  if found then
    if v_existing.checksum = p_checksum then
      return jsonb_build_object('duplicate', true, 'chunk_index', p_chunk_index);
    end if;
    raise exception 'UKÄ-chunk finns redan med annat innehåll' using errcode = 'unique_violation';
  end if;

  v_rows := jsonb_array_length(p_observations);

  insert into public.uka_observations (
    batch_id, indicator_id, period, university, gender, value, dimensions
  )
  select
    p_batch_id,
    p_indicator_id,
    o->>'period',
    o->>'university',
    nullif(o->>'gender',''),
    (o->>'value')::double precision,
    coalesce(o->'dimensions','{}'::jsonb)
  from jsonb_array_elements(p_observations) o;

  insert into public.uka_batch_chunks (batch_id, chunk_index, row_count, checksum)
  values (p_batch_id, p_chunk_index, v_rows, p_checksum);

  update public.uka_batches
  set received_chunks = received_chunks + 1,
      received_rows = received_rows + v_rows,
      status = case
        when received_chunks + 1 >= expected_chunks then 'ready'
        else 'receiving'
      end,
      last_activity_at = now()
  where id = p_batch_id;

  return jsonb_build_object('duplicate', false, 'chunk_index', p_chunk_index, 'rows', v_rows);
end;
$function$;

CREATE OR REPLACE FUNCTION public.uka_finalize_batch(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_batch public.uka_batches%rowtype;
  v_old uuid;
  v_block text;
begin
  select * into v_batch
  from public.uka_batches
  where id = p_batch_id
  for update;

  if not found then
    raise exception 'UKÄ-batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;
  if v_batch.status = 'succeeded' then
    return jsonb_build_object('batch_id', p_batch_id, 'rows', v_batch.received_rows, 'already_finalized', true);
  end if;
  if exists (select 1 from public.uka_verified_imports where batch_id = p_batch_id) then
    raise exception 'UKÄ-batch % hör till en verifierad import och kan inte finaliseras via äldre ETL', p_batch_id
      using errcode = '55000', hint = 'Använd den verifierade importens egen finalisering.';
  end if;
  if v_batch.status <> 'ready'
     or v_batch.received_chunks <> v_batch.expected_chunks
     or v_batch.received_rows <> v_batch.expected_rows then
    raise exception 'UKÄ-batch är inte komplett' using errcode = 'invalid_parameter_value';
  end if;

  perform pg_advisory_xact_lock(hashtext(v_batch.indicator_id));

  -- Kontrollera under indikatorlåset, före aktivering och radering.
  v_block := public.uka_legacy_publication_block(v_batch.indicator_id);
  if v_block is not null then
    raise exception 'Äldre UKÄ-finalisering stoppad för %: %. Ingen aktivering eller radering har gjorts.', v_batch.indicator_id, v_block
      using errcode = '55000',
            hint = 'Publicera via den verifierade importvägen. Aktiv och tidigare version lämnas orörda.';
  end if;

  select active_batch_id into v_old
  from public.uka_active_batches
  where indicator_id = v_batch.indicator_id;

  insert into public.uka_active_batches (indicator_id, active_batch_id, activated_at)
  values (v_batch.indicator_id, p_batch_id, now())
  on conflict (indicator_id) do update
  set active_batch_id = excluded.active_batch_id,
      activated_at = excluded.activated_at;

  insert into public.indicator_metadata (
    indicator_id, kalla, styrande_kalla,
    kalla_uppdaterad_datum, hamtad_datum, updated_at
  )
  select
    i.id, i.styrande_kalla, i.styrande_kalla,
    v_batch.kalla_uppdaterad_datum, current_date, now()
  from public.indicators i
  where i.id = v_batch.indicator_id
  on conflict (indicator_id) do update set
    kalla_uppdaterad_datum = coalesce(excluded.kalla_uppdaterad_datum, public.indicator_metadata.kalla_uppdaterad_datum),
    hamtad_datum = current_date,
    updated_at = now();

  update public.uka_batches
  set status = 'succeeded', finalized_at = now(), last_activity_at = now()
  where id = p_batch_id;

  if v_batch.run_id is not null then
    update public.data_source_runs
    set status = 'succeeded', finished_at = now(),
        rows_affected = v_batch.received_rows, error_message = null
    where id = v_batch.run_id;
  end if;

  if v_old is not null and v_old <> p_batch_id then
    delete from public.uka_batches where id = v_old;
  end if;

  return jsonb_build_object(
    'batch_id', p_batch_id,
    'indicator_id', v_batch.indicator_id,
    'rows', v_batch.received_rows,
    'already_finalized', false
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.uka_abort_batch(p_batch_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_batch public.uka_batches%rowtype;
begin
  select * into v_batch
  from public.uka_batches
  where id = p_batch_id
  for update;

  if not found then
    raise exception 'UKÄ-batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;
  if v_batch.status = 'succeeded' then
    raise exception 'UKÄ-batch är redan publicerad' using errcode = 'invalid_parameter_value';
  end if;
  -- Verifierade importer (även ofullständiga) har egen livscykel och raderas inte här.
  if exists (select 1 from public.uka_verified_imports where batch_id = p_batch_id) then
    raise exception 'UKÄ-batch % hör till en verifierad import och kan inte avbrytas via äldre ETL', p_batch_id
      using errcode = '55000';
  end if;

  if v_batch.run_id is not null then
    update public.data_source_runs
    set status = 'failed', finished_at = now(),
        error_message = coalesce(p_reason, 'UKÄ-batch avbruten')
    where id = v_batch.run_id;
  end if;

  delete from public.uka_batches where id = p_batch_id;

  return jsonb_build_object('batch_id', p_batch_id, 'status', 'failed');
end;
$function$;

REVOKE ALL ON FUNCTION public.uka_store_chunk(uuid, text, integer, jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_finalize_batch(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.uka_abort_batch(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.uka_store_chunk(uuid, text, integer, jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_finalize_batch(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.uka_abort_batch(uuid, text) TO service_role;
