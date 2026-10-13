-- AF Yrkesbarometern: versioned YB-to-SSYK4 bridge.
-- Assessments remain at (edition, geography, YB occupation), NEVER SSYK.
-- Only relation keys are repeated. All 18 original fields remain in
-- observations.dimensions.row_json. No synthetic SSYK assessments.
create table if not exists public.rel_af_yb_ssyk (
  period text not null,
  taxonomi_version text not null,
  yb_concept_id text not null,
  ssyk4 text not null check (ssyk4 ~ '^[0-9]{4}$'),
  del_av_ssyk integer,
  antal_ssyk integer,
  yb_beskrivning text,
  source_batch_id uuid not null,
  updated_at timestamptz not null default now(),
  primary key (period, taxonomi_version, yb_concept_id, ssyk4)
);
create index if not exists rel_af_yb_ssyk_reverse_idx
  on public.rel_af_yb_ssyk (ssyk4, period, taxonomi_version);
alter table public.rel_af_yb_ssyk enable row level security;
grant select on public.rel_af_yb_ssyk to authenticated;
grant all on public.rel_af_yb_ssyk to service_role;
drop policy if exists "YB SSYK endast admin" on public.rel_af_yb_ssyk;
create policy "YB SSYK endast admin" on public.rel_af_yb_ssyk
for select to authenticated using (public.has_role(auth.uid(), 'admin'));

create or replace function public.refresh_rel_af_yb_ssyk()
returns void language plpgsql security definer set search_path = public as $$
declare v_batch uuid;
begin
  select active_batch_id into v_batch from public.indicator_active_batches
  where indicator_id = 'af-yrkesbarometern';
  if v_batch is null then return; end if;

  -- Stop rather than fabricate incomplete mappings if source SSYK codes
  -- cannot be interpreted. Both scalar and array formats are supported.
  if exists (
    select 1 from public.observations o
    where o.indicator_id = 'af-yrkesbarometern' and o.batch_id = v_batch
      and (o.dimensions->>'row_json')::jsonb ? 'ssyk'
      and (o.dimensions->>'row_json')::jsonb ->> 'ssyk' is not null
      and not ((o.dimensions->>'row_json')::jsonb ->> 'ssyk' ~ '[0-9]{4}')
  ) then
    raise exception 'Yrkesbarometern has unparseable SSYK; relation update aborted';
  end if;

  delete from public.rel_af_yb_ssyk;
  insert into public.rel_af_yb_ssyk (
    period, taxonomi_version, yb_concept_id, ssyk4,
    del_av_ssyk, antal_ssyk, yb_beskrivning, source_batch_id)
  select distinct on (o.period, r.raw->>'taxonomi_version',
                      o.dimensions->>'yb_concept_id', code.ssyk4)
    o.period, r.raw->>'taxonomi_version', o.dimensions->>'yb_concept_id',
    code.ssyk4,
    case when r.raw->>'del_av_ssyk' ~ '^[0-9]+$' then
      (r.raw->>'del_av_ssyk')::integer else null end,
    case when r.raw->>'antal_ssyk' ~ '^[0-9]+$' then
      (r.raw->>'antal_ssyk')::integer else null end,
    r.raw->>'yb_beskrivning', v_batch
  from public.observations o
  cross join lateral (
    select (o.dimensions->>'row_json')::jsonb as raw
  ) r
  cross join lateral regexp_matches(r.raw->>'ssyk', '[0-9]{4}', 'g') as code_array(parts)
  cross join lateral (select code_array.parts[1] as ssyk4) code
  where o.indicator_id = 'af-yrkesbarometern' and o.batch_id = v_batch
    and nullif(r.raw->>'taxonomi_version', '') is not null
  order by o.period, r.raw->>'taxonomi_version',
    o.dimensions->>'yb_concept_id', code.ssyk4,
    (o.geo_code = '00') desc;
end;
$$;
revoke all on function public.refresh_rel_af_yb_ssyk() from public, anon, authenticated;
grant execute on function public.refresh_rel_af_yb_ssyk() to service_role;

create or replace function public.refresh_rel_af_yb_ssyk_on_activation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.indicator_id = 'af-yrkesbarometern' then
    perform public.refresh_rel_af_yb_ssyk();
  end if;
  return new;
end;
$$;
drop trigger if exists refresh_rel_af_yb_ssyk_activation
on public.indicator_active_batches;
create trigger refresh_rel_af_yb_ssyk_activation
after insert or update of active_batch_id on public.indicator_active_batches
for each row execute function public.refresh_rel_af_yb_ssyk_on_activation();

-- Immediately populate from the already active snapshot.
select public.refresh_rel_af_yb_ssyk();
notify pgrst, 'reload schema';
