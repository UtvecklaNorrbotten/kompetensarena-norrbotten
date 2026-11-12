DROP POLICY IF EXISTS "Publik läsning av aggregat" ON public.agg_refresh_state;
REVOKE ALL ON public.agg_refresh_state FROM anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.agg_refresh_state FROM authenticated;
GRANT SELECT ON public.agg_refresh_state TO authenticated;
GRANT ALL ON public.agg_refresh_state TO service_role;
CREATE POLICY "Admins läser aggregatstatus"
  ON public.agg_refresh_state
  FOR SELECT
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'::public.app_role));