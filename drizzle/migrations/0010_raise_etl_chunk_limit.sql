-- Höj endast antalet tillåtna chunkar per batch. Storleken per chunk är
-- oförändrad, liksom timeout, rättigheter och publiceringslogik.
alter table public.etl_batches
  drop constraint if exists etl_batches_expected_chunks_check;

alter table public.etl_batches
  add constraint etl_batches_expected_chunks_check
  check (expected_chunks > 0 and expected_chunks <= 2000);

comment on constraint etl_batches_expected_chunks_check on public.etl_batches is
  'En ETL-batch får innehålla 1–2000 chunkar.';
