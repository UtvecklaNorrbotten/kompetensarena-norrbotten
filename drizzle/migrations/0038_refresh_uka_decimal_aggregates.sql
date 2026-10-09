-- Decimalerna finns i den aktiva UKÄ-importen men äldre aggregat måste räknas om.
-- Framtida UKÄ-publiceringar uppdaterar aggregaten i finaliseringsendpointen.
select public.agg_refresh_uka();
