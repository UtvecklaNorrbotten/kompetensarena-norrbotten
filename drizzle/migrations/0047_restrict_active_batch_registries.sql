CREATE OR REPLACE FUNCTION public.is_active_obs_batch(p_indicator_id text, p_batch_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN p_batch_id IS NULL THEN NOT EXISTS (SELECT 1 FROM public.indicator_active_batches a WHERE a.indicator_id = p_indicator_id)
    ELSE EXISTS (SELECT 1 FROM public.indicator_active_batches a WHERE a.indicator_id = p_indicator_id AND a.active_batch_id = p_batch_id)
  END
$$;
CREATE OR REPLACE FUNCTION public.is_active_uka_batch(p_indicator_id text, p_batch_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.uka_active_batches a WHERE a.indicator_id = p_indicator_id AND a.active_batch_id = p_batch_id)
$$;
REVOKE ALL ON FUNCTION public.is_active_obs_batch(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_active_uka_batch(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_active_obs_batch(text, uuid) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_active_uka_batch(text, uuid) TO anon, authenticated, service_role;

DROP POLICY IF EXISTS "Inloggade ser aktiva observationer enligt nivå" ON public.observations;
CREATE POLICY "Inloggade ser aktiva observationer enligt nivå" ON public.observations FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.indicators i WHERE i.id = observations.indicator_id AND (i.visibility = ANY (ARRAY['publik'::visibility_level,'inloggad'::visibility_level]) OR public.has_role(auth.uid(),'admin'::app_role)))
  AND public.is_active_obs_batch(observations.indicator_id, observations.batch_id));
DROP POLICY IF EXISTS "Publika aktiva observationer läsbara av alla" ON public.observations;
CREATE POLICY "Publika aktiva observationer läsbara av alla" ON public.observations FOR SELECT TO anon
USING (EXISTS (SELECT 1 FROM public.indicators i WHERE i.id = observations.indicator_id AND i.visibility = 'publik'::visibility_level)
  AND public.is_active_obs_batch(observations.indicator_id, observations.batch_id));

DROP POLICY IF EXISTS "Inloggade UKÄ-observationer" ON public.uka_observations;
CREATE POLICY "Inloggade UKÄ-observationer" ON public.uka_observations FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.indicators i WHERE i.id = uka_observations.indicator_id AND (i.visibility = ANY (ARRAY['publik'::visibility_level,'inloggad'::visibility_level]) OR public.has_role(auth.uid(),'admin'::app_role)))
  AND public.is_active_uka_batch(uka_observations.indicator_id, uka_observations.batch_id));
DROP POLICY IF EXISTS "Publika UKÄ-observationer" ON public.uka_observations;
CREATE POLICY "Publika UKÄ-observationer" ON public.uka_observations FOR SELECT TO anon
USING (EXISTS (SELECT 1 FROM public.indicators i WHERE i.id = uka_observations.indicator_id AND i.visibility = 'publik'::visibility_level)
  AND public.is_active_uka_batch(uka_observations.indicator_id, uka_observations.batch_id));

DROP POLICY IF EXISTS "Aktiva batchar är publika" ON public.indicator_active_batches;
CREATE POLICY "Admins läser aktiva batchar" ON public.indicator_active_batches FOR SELECT TO authenticated
USING (public.has_role(auth.uid(),'admin'::app_role));
DROP POLICY IF EXISTS "UKÄ aktiva batchar är publika" ON public.uka_active_batches;
CREATE POLICY "Admins läser UKÄ aktiva batchar" ON public.uka_active_batches FOR SELECT TO authenticated
USING (public.has_role(auth.uid(),'admin'::app_role));
REVOKE SELECT ON public.indicator_active_batches FROM anon;
REVOKE SELECT ON public.uka_active_batches FROM anon;