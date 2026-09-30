-- Fingerprints per AF-källa och period för kvartalsvis revisionskontroll.
-- Tabellen är intern och endast service_role får läsa/skriva.

create table if not exists public.af_revision_fingerprints (
  target text not null,
  period text not null,
  checksum text not null,
  row_count integer not null,
  source_release_period text,
  source_manifest jsonb not null default '{}'::jsonb,
  checked_at timestamptz not null default now(),
  primary key (target, period),
  constraint af_revision_fingerprints_target_check
    check (target in ('sok', 'tid', 'svag', 'yrke', 'bas')),
  constraint af_revision_fingerprints_row_count_check
    check (row_count >= 0)
);

create index if not exists af_revision_fingerprints_checked_at_idx
  on public.af_revision_fingerprints (checked_at desc);

alter table public.af_revision_fingerprints enable row level security;

revoke all on public.af_revision_fingerprints from public, anon, authenticated;
grant select, insert, update, delete on public.af_revision_fingerprints to service_role;

comment on table public.af_revision_fingerprints is
  'Källfingerprints per AF-target och period. Används för att upptäcka historiska revisioner utan att ladda om hela historiken.';

notify pgrst, 'reload schema';