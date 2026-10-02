alter table public.afr_je_current add column if not exists primary_sni text;
alter table public.afr_ae_current add column if not exists primary_sni text;
alter table public.afr_je_history add column if not exists sni jsonb;
alter table public.afr_ae_history add column if not exists sni jsonb;
comment on column public.afr_je_history.sni is 'Kanoniskt SNI-snapshot för versionen: [{r,kod,andel,avd}] sorterat på r, kod (C).';
comment on column public.afr_ae_history.sni is 'Kanoniskt SNI-snapshot för versionen: [{r,kod,andel,avd}] sorterat på r, kod (C).';

create or replace function public.afr_sni_snapshot(p jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('r', (e->>'r')::int, 'kod', e->>'kod',
      'andel', (e->>'andel')::int, 'avd', e->>'avd') order by (e->>'r')::int, (e->>'kod') collate "C"), '[]'::jsonb)
  from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) e
$$;
create or replace function public.afr_sni_primary(snap jsonb) returns text
language sql immutable set search_path = public as $$
  select case when (snap->0->>'r') = '1' then snap->0->>'kod' end
$$;

comment on table public.afr_je_sni_history is 'DEPRECATED: ersatt av afr_je_history.sni (JSONB-snapshot)';
comment on table public.afr_ae_sni_history is 'DEPRECATED: ersatt av afr_ae_history.sni (JSONB-snapshot)';

create or replace view public.afr_ae_analysis with (security_invoker = true) as
SELECT a.cfar_nr, a.lan, a.kommun, a.anst_kl, a.ae_stat, a.ae_typ, a.hj_verks_je, a.tat_sma_typ_kod, a.tat_ort_sma_ort_kod,
    a.primary_sni AS primar_sni, a.je_id, j.ag_kat, g.grupp AS agarkontroll_grupp, j.sektor, j.jurform, j.lan_sate, j.kommun_sate,
    ((j.lan_sate IS NOT NULL) AND (a.lan IS NOT NULL) AND (j.lan_sate <> a.lan)) AS sate_utanfor_lan
   FROM afr_ae_current a
     LEFT JOIN afr_je_current j ON j.je_id = a.je_id
     LEFT JOIN afr_agkat_group g ON g.ag_kat = j.ag_kat
  WHERE a.in_source AND EXISTS (SELECT 1 FROM afr_syncs s WHERE s.mode = 'initial' AND s.status = 'succeeded');