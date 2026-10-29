-- BAS-periodimporterna når etl-batch/finalize men avbryts efter cirka 8–10 s.
-- SCB-uttag och staging är validerade. Finalisering av en ny period räknar
-- staged rader, ersätter perioden och flyttar raderna till aktiv historik.
-- Ge just denna RPC en avgränsad tidsbudget, som för övriga stora ETL-RPC:er.
-- PostgREST läser funktionens inställning före anropet.
-- Ingen publicerad statistik, rättighet eller finaliseringslogik ändras.
alter function public.etl_finalize_batch(uuid)
  set statement_timeout = '180s';

notify pgrst, 'reload schema';
