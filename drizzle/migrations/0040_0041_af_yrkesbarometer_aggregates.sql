-- Analysis-ready Yrkesbarometern summary sourced only from the active batch.
-- Apply in Lovable. The raw snapshot and publication history are untouched.
create table if not exists public.agg_af_yrkesbarometer (
  period text not null,
  geo_code text not null references public.geographies(code),
  yb_concept_id text not null,
  jobbmojligheter text,
  rekryteringssituation text,
  prognos text,
  hogsta_bedomningsniva text,
  delvis_helt text,
  yrke text,
  ssyk jsonb,
  original jsonb not null,
  source_batch_id uuid not null,
  refreshed_at timestamptz not null default now(),
  primary key (period, geo_code, yb_concept_id)
);
create index if not exists agg_af_yb_geo_period_idx
  on public.agg_af_yrkesbarometer (geo_code, period);
create index if not exists agg_af_yb_occupation_idx
  on public.agg_af_yrkesbarometer (yb_concept_id, period);

alter table public.agg_af_yrkesbarometer enable row level security;
grant select on public.agg_af_yrkesbarometer to authenticated;
grant all on public.agg_af_yrkesbarometer to service_role;
drop policy if exists "Yrkesbarometern endast admin tills granskad" on public.agg_af_yrkesbarometer;
create policy "Yrkesbarometern endast admin tills granskad"
  on public.agg_af_yrkesbarometer for select to authenticated
  using (public.has_role(auth.uid(), 'admin'));

create or replace function public.refresh_agg_af_yrkesbarometer()
returns void language plpgsql security definer set search_path = public as $$
declare v_batch uuid;
begin
  select active_batch_id into v_batch from public.indicator_active_batches
    where indicator_id = 'af-yrkesbarometern';
  if v_batch is null then return; end if;
  delete from public.agg_af_yrkesbarometer;
  insert into public.agg_af_yrkesbarometer (
    period, geo_code, yb_concept_id, jobbmojligheter,
    rekryteringssituation, prognos, hogsta_bedomningsniva,
    delvis_helt, yrke, ssyk, original, source_batch_id)
  select o.period, o.geo_code, o.dimensions->>'yb_concept_id',
    r.raw->>'jobbmojligheter', r.raw->>'rekryteringssituation',
    r.raw->>'prognos', r.raw->>'hogsta_bedomningsniva',
    r.raw->>'delvis_helt', coalesce(r.raw->>'yb_yrke', r.raw->>'yrke'),
    r.raw->'ssyk', r.raw, v_batch
  from public.observations o
  cross join lateral (select (o.dimensions->>'row_json')::jsonb as raw) r
  where o.indicator_id = 'af-yrkesbarometern' and o.batch_id = v_batch;
end;
$$;
revoke all on function public.refresh_agg_af_yrkesbarometer() from public, anon, authenticated;
grant execute on function public.refresh_agg_af_yrkesbarometer() to service_role;

create or replace function public.refresh_agg_af_yb_on_activation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.indicator_id = 'af-yrkesbarometern' and
    (tg_op = 'INSERT' or new.active_batch_id is distinct from old.active_batch_id)
  then perform public.refresh_agg_af_yrkesbarometer(); end if;
  return new;
end;
$$;
drop trigger if exists refresh_agg_af_yb_activation on public.indicator_active_batches;
create trigger refresh_agg_af_yb_activation
after insert or update of active_batch_id on public.indicator_active_batches
for each row execute function public.refresh_agg_af_yb_on_activation();

-- Backfill immediately from the already successfully imported October batch.
select public.refresh_agg_af_yrkesbarometer();
notify pgrst, 'reload schema';