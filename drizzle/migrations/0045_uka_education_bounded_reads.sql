-- Begränsade, behovsstyrda läsningar för Utbildningssidan.
-- Katalogen (perioder, uppdelningar och kategorikombinationer per lärosäte) hämtas
-- separat från värdena. Värden hämtas per indikator, uppdelning och urval i sidor
-- om högst 1000 rader. Funktionerna är SECURITY INVOKER: tabellens RLS gäller.
-- Inga data ändras.

CREATE INDEX IF NOT EXISTS agg_uka_university_slice_idx
  ON public.agg_uka_university (indicator_id, university, breakdown, period, gender, category);

CREATE OR REPLACE FUNCTION public.uka_education_catalog(p_university text, p_indicator_ids text[])
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO 'public' AS $fn$
  WITH base AS MATERIALIZED (
    SELECT DISTINCT indicator_id, period, breakdown, category
    FROM agg_uka_university
    WHERE university = p_university AND indicator_id = ANY (p_indicator_ids)
  )
  SELECT jsonb_build_object(
    'indicators', coalesce((
      SELECT jsonb_object_agg(indicator_id, jsonb_build_object('periods', periods, 'breakdowns', breakdowns))
      FROM (
        SELECT indicator_id,
               to_jsonb(array_agg(DISTINCT period ORDER BY period)) periods,
               to_jsonb(array_agg(DISTINCT breakdown ORDER BY breakdown)) breakdowns
        FROM base GROUP BY indicator_id
      ) i), '{}'::jsonb),
    'combos', coalesce((
      SELECT jsonb_agg(jsonb_build_array(breakdown, category) ORDER BY breakdown, category)
      FROM (SELECT DISTINCT breakdown, category FROM base) c), '[]'::jsonb)
  )
$fn$;

CREATE OR REPLACE FUNCTION public.uka_education_slice(
  p_university text, p_indicator_id text, p_breakdown text, p_selection jsonb,
  p_offset integer, p_limit integer)
RETURNS TABLE (period text, gender text, category text, value double precision)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO 'public' AS $fn$
  SELECT g.period, g.gender, g.category, g.value
  FROM agg_uka_university g
  WHERE g.indicator_id = p_indicator_id
    AND g.university = p_university
    AND g.breakdown = p_breakdown
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_each_text(coalesce(p_selection, '{}'::jsonb)) s
      WHERE coalesce(array_position(string_to_array(p_breakdown, '|'), s.key), 0) = 0
         OR split_part(g.category, '|', array_position(string_to_array(p_breakdown, '|'), s.key)) <> s.value)
  ORDER BY g.period, g.gender, g.category
  OFFSET greatest(coalesce(p_offset, 0), 0)
  LIMIT least(greatest(coalesce(p_limit, 1000), 1), 1000)
$fn$;

REVOKE ALL ON FUNCTION public.uka_education_catalog(text, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.uka_education_slice(text, text, text, jsonb, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.uka_education_catalog(text, text[]) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.uka_education_slice(text, text, text, jsonb, integer, integer) TO anon, authenticated, service_role;
