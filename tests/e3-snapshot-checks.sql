do $$
declare b uuid; k text := repeat('a',64); result jsonb;
begin
  b := public.etl_start_snapshot_batch('e3-matchning-utbildning-kommun','SCB',3654,k,18014220);
  result := public.etl_snapshot_progress(b,k);
  if (result->>'next_chunk_index')::int <> 0 then raise exception 'Empty resume'; end if;
  begin
    perform public.etl_snapshot_progress(b,repeat('b',64));
    raise exception 'Wrong key accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.etl_start_snapshot_batch('e3-matchning-utbildning-kommun','SCB',3654,k,18014220);
    raise exception 'Duplicate snapshot accepted';
  exception when invalid_parameter_value then null; end;
  insert into etl_batch_chunks values(b,0,5000),(b,1,5000);
  update etl_batches set received_chunks=2,received_rows=10000 where id=b;
  result := public.etl_snapshot_progress(b,k);
  if (result->>'next_chunk_index')::int <> 2 then raise exception 'Resume index'; end if;
  update etl_batch_chunks set chunk_index=2 where batch_id=b and chunk_index=1;
  begin
    perform public.etl_snapshot_progress(b,k);
    raise exception 'Gap accepted';
  exception when invalid_parameter_value then null; end;
  update etl_batch_chunks set chunk_index=1 where batch_id=b and chunk_index=2;
  update etl_batches set received_rows=9999 where id=b;
  begin
    perform public.etl_snapshot_progress(b,k);
    raise exception 'Bad row counter accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.etl_start_snapshot_batch('e3-matchning-utbildning-kommun','SCB',10001,repeat('c',64),1);
    raise exception 'Chunk bound accepted';
  exception when check_violation then null; end;
  if has_function_privilege('anon','public.etl_snapshot_progress(uuid,text)','execute') then
    raise exception 'Anonymous execute granted';
  end if;
  if not has_function_privilege('service_role','public.etl_snapshot_progress(uuid,text)','execute') then
    raise exception 'Service role lacks execute';
  end if;
end $$;
