-- Funktionsspecifik timeout för PostgREST och idempotent sista chunk.
-- SET ligger i funktionsdeklarationen så PostgREST kan läsa inställningen
-- före anropet. SET inuti funktionskroppen förlänger inte en redan startad timer.
-- Inga rollinställningar, publicerade observationer eller aktiva batchar ändras.

create or replace function public.etl_store_chunk(
  p_batch_id uuid,
  p_indicator_id text,
  p_chunk_index integer,
  p_observations jsonb,
  p_checksum text
)
returns jsonb
language plpgsql
security definer
set search_path = public
set statement_timeout = '30s'
as $$
declare
  v_batch public.etl_batches%rowtype;
  v_existing public.etl_batch_chunks%rowtype;
  v_rows integer;
  v_bad_geo text;
begin
  select * into v_batch from public.etl_batches where id = p_batch_id for update;
  if not found then
    raise exception 'Batch % finns inte', p_batch_id using errcode = 'no_data_found';
  end if;

  if v_batch.status not in ('started', 'receiving', 'ready') then
    raise exception 'Batch % har status % och tar inte emot fler chunkar', p_batch_id, v_batch.status
      using errcode = 'invalid_parameter_value';
  end if;

  if v_batch.indicator_id is distinct from p_indicator_id then
    raise exception 'Chunk tillhör fel indikator (batch: %, chunk: %)', v_batch.indicator_id, p_indicator_id
      using errcode = 'invalid_parameter_value';
  end if;

  if p_chunk_index < 0 or p_chunk_index >= v_batch.expected_chunks then
    raise exception 'chunk_index % utanför intervallet 0..%', p_chunk_index, v_batch.expected_chunks - 1
      using errcode = 'invalid_parameter_value';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_observations) o
    where not (o ? 'geo_code' and o ? 'period')
  ) then
    raise exception 'Varje observation måste ha geo_code och period' using errcode = 'invalid_parameter_value';
  end if;

  select o->>'geo_code' into v_bad_geo
  from jsonb_array_elements(p_observations) o
  where not exists (select 1 from public.geographies g where g.code = o->>'geo_code')
  limit 1;
  if v_bad_geo is not null then
    raise exception 'Okänd geografi: %', v_bad_geo using errcode = 'foreign_key_violation';
  end if;

  v_rows := jsonb_array_length(p_observations);

  select * into v_existing from public.etl_batch_chunks
  where batch_id = p_batch_id and chunk_index = p_chunk_index;

  if found then
    if v_existing.checksum = p_checksum then
      update public.etl_batches set last_activity_at = now() where id = p_batch_id;
      return jsonb_build_object(
        'batch_id', p_batch_id, 'chunk_index', p_chunk_index, 'duplicate', true,
        'received_chunks', v_batch.received_chunks, 'received_rows', v_batch.received_rows,
        'status', v_batch.status
      );
    end if;
    raise exception 'Chunk % finns redan med annat innehåll', p_chunk_index
      using errcode = 'unique_violation';
  end if;

  -- Ett tappat svar för sista chunken får återförsökas även i status ready.
  -- Bara en redan registrerad chunk med samma checksumma accepteras då.
  if v_batch.status = 'ready' then
    raise exception 'Batch % är redan komplett', p_batch_id
      using errcode = 'invalid_parameter_value';
  end if;

  insert into public.observations (batch_id, indicator_id, geo_code, period, value, dimensions)
  select
    p_batch_id,
    v_batch.indicator_id,
    o->>'geo_code',
    o->>'period',
    (o->>'value')::double precision,
    coalesce(o->'dimensions', '{}'::jsonb)
  from jsonb_array_elements(p_observations) o;

  insert into public.etl_batch_chunks (batch_id, chunk_index, row_count, checksum)
  values (p_batch_id, p_chunk_index, v_rows, p_checksum);

  update public.etl_batches
  set received_chunks = received_chunks + 1,
      received_rows = received_rows + v_rows,
      status = case when received_chunks + 1 >= expected_chunks then 'ready'::public.etl_batch_status
                    else 'receiving'::public.etl_batch_status end,
      last_activity_at = now()
  where id = p_batch_id
  returning * into v_batch;

  return jsonb_build_object(
    'batch_id', p_batch_id, 'chunk_index', p_chunk_index, 'duplicate', false,
    'received_chunks', v_batch.received_chunks, 'received_rows', v_batch.received_rows,
    'status', v_batch.status
  );
end;
$$;

revoke execute on function public.etl_store_chunk(uuid, text, integer, jsonb, text)
  from public, anon, authenticated;
grant execute on function public.etl_store_chunk(uuid, text, integer, jsonb, text)
  to service_role;

notify pgrst, 'reload schema';
