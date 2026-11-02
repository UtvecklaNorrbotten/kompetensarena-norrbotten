-- lovable-cron-fallback-reviewed: bounded drain job that unschedules itself when nothing obsolete remains
CREATE INDEX IF NOT EXISTS observations_batch_id_idx ON public.observations (batch_id);
SELECT cron.schedule('etl-purge-obsolete-batches', '*/2 * * * *', $$select public.etl_purge_obsolete_batches(25000)$$);