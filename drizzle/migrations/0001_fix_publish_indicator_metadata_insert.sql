-- Korrigerar publish_indicator: metadata-insert saknade indikator-id i select-listan
create or replace function public.publish_indicator(
  p_indicator_id text,
  p_observations jsonb,
  p_kalla_uppdaterad_datum date default null,
  p_rows_affected integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer := 0;
begin
  if not exists (select 1 from public.indicators where id = p_indicator_id) then
    raise exception 'Indikator % finns inte', p_indicator_id;
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_observations) o
    where not (o ? 'geo_code' and o ? 'period')
  ) then
    raise exception 'Varje observation måste ha geo_code och period';
  end if;

  perform pg_advisory_xact_lock(hashtext(p_indicator_id));

  delete from public.observations where indicator_id = p_indicator_id;

  insert into public.observations (indicator_id, geo_code, period, value, dimensions)
  select
    p_indicator_id,
    o->>'geo_code',
    o->>'period',
    (o->>'value')::double precision,
    coalesce(o->'dimensions', '{}'::jsonb)
  from jsonb_array_elements(p_observations) o;
  get diagnostics v_count = row_count;

  insert into public.indicator_metadata (indicator_id, kalla, styrande_kalla, kalla_uppdaterad_datum, hamtad_datum, updated_at)
  select i.id, i.styrande_kalla, i.styrande_kalla, p_kalla_uppdaterad_datum, current_date, now()
  from public.indicators i where i.id = p_indicator_id
  on conflict (indicator_id) do update set
    kalla_uppdaterad_datum = coalesce(excluded.kalla_uppdaterad_datum, public.indicator_metadata.kalla_uppdaterad_datum),
    hamtad_datum = current_date,
    updated_at = now();

  return jsonb_build_object('indicator_id', p_indicator_id, 'rows', v_count);
end;
$$;

revoke execute on function public.publish_indicator(text, jsonb, date, integer) from public, anon, authenticated;
grant execute on function public.publish_indicator(text, jsonb, date, integer) to service_role;
