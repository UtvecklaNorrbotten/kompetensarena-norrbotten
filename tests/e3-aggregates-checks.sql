-- Exempel: syntetiska data verifierar att kommuner inte räknas in i Riket.
insert into public.indicator_active_batches values
  ('e3-matchning-utbildning','11111111-1111-1111-1111-111111111111'),
  ('e3-matchning-utbildning-kommun','22222222-2222-2222-2222-222222222222');
insert into public.observations values
  ('11111111-1111-1111-1111-111111111111','e3-matchning-utbildning','25','2024',10,
   '{"contents_code":"000008QQ","utbildning_code":"00S","utbildning_indelning_code":"grupp","sni2007_code":"A-U","kon_alder_fodelseland_code":"totalt"}'),
  ('11111111-1111-1111-1111-111111111111','e3-matchning-utbildning','25','2024',100,
   '{"contents_code":"000008QQ","utbildning_code":"00S","utbildning_indelning_code":"niva","sni2007_code":"A-U","kon_alder_fodelseland_code":"totalt"}'),
  ('22222222-2222-2222-2222-222222222222','e3-matchning-utbildning-kommun','2580','2024',2,
   '{"contents_code":"000008QQ","utbildning_code":"00S","utbildning_indelning_code":"grupp","sni2007_code":"A-U","kon_alder_fodelseland_code":"totalt"}'),
  ('22222222-2222-2222-2222-222222222222','e3-matchning-utbildning-kommun','2580','2024',null,
   '{"contents_code":"000008QS","utbildning_code":"00S","utbildning_indelning_code":"grupp","sni2007_code":"A-U","kon_alder_fodelseland_code":"totalt"}'),
  ('22222222-2222-2222-2222-222222222222','e3-matchning-utbildning-kommun','2580','2024',33.4,
   '{"contents_code":"000008QV","utbildning_code":"00S","utbildning_indelning_code":"grupp","sni2007_code":"A-U","kon_alder_fodelseland_code":"totalt"}');
select public.agg_refresh_e3();
do $$
begin
  if (select count(*) from agg_e3_matchning) <> 3 then raise exception 'Wrong aggregate row count'; end if;
  if (select helt from agg_e3_matchning where geo_code='00') <> 10 then raise exception 'Municipality double-counted in national total'; end if;
  if (select helt from agg_e3_matchning where geo_code='25') <> 10 then raise exception 'Education partitions mixed'; end if;
  if (select helt from agg_e3_matchning where geo_code='2580') <> 2 then raise exception 'Municipality missing'; end if;
  if (select geo_level from agg_e3_matchning where geo_code='2580') <> 'kommun' then raise exception 'Wrong geography level'; end if;
  if (select saknas from agg_e3_matchning where geo_code='2580') is not null then raise exception 'Null replaced with zero'; end if;
  if (select matchad_forvarvsgrad from agg_e3_matchning where geo_code='2580') <> 33.4 then raise exception 'Source percentage changed'; end if;
end $$;
