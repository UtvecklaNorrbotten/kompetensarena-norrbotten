-- Rollback-only test of the legacy UKÄ publication guard (migration 0044_uka_legacy_publication_guard).
-- Run as one statement. It ALWAYS ends with an exception so every write is rolled back;
-- the exception message is the test report. No data is changed.
do $$
declare
  ind constant text := 'uka-soktryck-yrkesprogram';
  cur constant uuid := 'be0322b3-7016-4d03-9619-9bac577b381b';
  prev constant uuid := '4892c284-c21a-4ec5-b9c8-2b78b5ce61db';
  hst_active uuid; hst_verified uuid; small_old uuid;
  b uuid; r jsonb; msg text; report text := '';
  ok boolean;
  periods jsonb; unis jsonb; dims jsonb; cov jsonb; chunks jsonb := '[]'::jsonb; payloads text[] := '{}';
  manifest jsonb; total int; i int; payload text;
begin
  -- T1: rollback scenario (active = previous legacy batch); a new legacy chunk is refused.
  update uka_active_batches set active_batch_id = prev where indicator_id = ind;
  b := uka_start_batch(ind, 'GUARDTEST', 1, 1, null, null);
  begin
    perform uka_store_chunk(b, ind, 0, '[{"period":"HT2026","university":"Riket","gender":"Total","value":"1","dimensions":{}}]'::jsonb, 'g');
    report := report || 'T1 FAIL chunk accepted; ';
  exception when sqlstate '55000' then
    report := report || format('T1 PASS chunk blocked (%s) rows_in_test_batch=%s; ', left(sqlerrm, 60),
      (select count(*) from uka_observations where batch_id = b));
  end;
  -- T2: an already started legacy batch (ready) is refused at finalize before activation/deletion.
  insert into uka_observations (batch_id, indicator_id, period, university, gender, value, dimensions)
    values (b, ind, 'HT2026', 'Riket', 'Total', 1, '{}');
  update uka_batches set status = 'ready', received_chunks = 1, received_rows = 1 where id = b;
  begin
    r := uka_finalize_batch(b);
    report := report || 'T2 FAIL finalize accepted; ';
  exception when sqlstate '55000' then
    report := report || format('T2 PASS finalize blocked; active_is_prev=%s prev_rows=%s cur_rows=%s; ',
      (select active_batch_id = prev from uka_active_batches where indicator_id = ind),
      (select count(*) from uka_observations where batch_id = prev),
      (select count(*) from uka_observations where batch_id = cur));
  end;
  update uka_active_batches set active_batch_id = cur where indicator_id = ind;

  -- T3: HST has a verified import in progress; legacy finalize is refused without deleting the active HST batch.
  select active_batch_id into hst_active from uka_active_batches where indicator_id = 'uka-hst';
  b := uka_start_batch('uka-hst', 'GUARDTEST', 1, 1, null, null);
  insert into uka_observations (batch_id, indicator_id, period, university, gender, value, dimensions)
    values (b, 'uka-hst', '2025', 'Riket', 'Total', 1, '{}');
  update uka_batches set status = 'ready', received_chunks = 1, received_rows = 1 where id = b;
  begin
    r := uka_finalize_batch(b);
    report := report || 'T3 FAIL HST finalize accepted; ';
  exception when sqlstate '55000' then
    report := report || format('T3 PASS HST blocked; hst_active_unchanged=%s; ',
      (select active_batch_id = hst_active from uka_active_batches where indicator_id = 'uka-hst'));
  end;
  -- T4: the in-progress verified HST batch cannot be aborted through the legacy path.
  select v.batch_id into hst_verified from uka_verified_imports v join uka_batches x on x.id = v.batch_id
   where x.indicator_id = 'uka-hst' and v.published_at is null limit 1;
  if hst_verified is not null then
    begin
      perform uka_abort_batch(hst_verified, 'GUARDTEST');
      report := report || 'T4 FAIL verified abort accepted; ';
    exception when sqlstate '55000' then
      report := report || format('T4 PASS verified abort blocked; hst_staging_rows=%s; ',
        (select received_rows from uka_batches where id = hst_verified));
    end;
  else
    report := report || 'T4 SKIP no in-progress HST import; ';
  end if;

  -- T5: an unprotected indicator still publishes through the legacy path.
  select active_batch_id into small_old from uka_active_batches where indicator_id = 'uka-regional-examinerade';
  b := uka_start_batch('uka-regional-examinerade', 'GUARDTEST', 1, 1, null, null);
  perform uka_store_chunk(b, 'uka-regional-examinerade', 0, '[{"period":"2024/25","university":"Riket","gender":"Total","value":"1","dimensions":{}}]'::jsonb, 'g');
  r := uka_finalize_batch(b);
  report := report || format('T5 %s legacy unprotected; ',
    case when (select active_batch_id = b from uka_active_batches where indicator_id = 'uka-regional-examinerade')
         then 'PASS' else 'FAIL' end);

  -- T6: a verified indicator-99 revision still works and retains the previous batch.
  select jsonb_agg(p order by p) into periods from (select distinct period p from uka_observations where batch_id = cur) s;
  select jsonb_agg(u order by u) into unis from (select distinct university u from uka_observations where batch_id = cur) s;
  select jsonb_agg(d order by d::text) into dims from (select distinct dimensions d from uka_observations where batch_id = cur) s;
  select jsonb_agg(jsonb_build_object('period', period, 'gender', gender, 'rows', n)), sum(n)
    into cov, total from (select period, gender, count(*) n from uka_observations where batch_id = cur group by 1, 2) s;
  for i in 0..((total - 1) / 5000) loop
    select jsonb_agg(jsonb_build_array(
             (select (x.ord - 1)::int from jsonb_array_elements_text(periods) with ordinality x(v, ord) where x.v = o.period),
             (select (x.ord - 1)::int from jsonb_array_elements_text(unis) with ordinality x(v, ord) where x.v = o.university),
             (select (x.ord - 1)::int from jsonb_array_elements_text('["Kvinnor","Män","Total"]') with ordinality x(v, ord) where x.v = o.gender),
             (select (x.ord - 1)::int from jsonb_array_elements(dims) with ordinality x(v, ord) where x.v = o.dimensions),
             o.value::text) order by o.rn)::text
      into payload
      from (select *, row_number() over (order by period, university, gender, dimensions::text) rn
              from uka_observations where batch_id = cur) o
     where o.rn > i * 5000 and o.rn <= (i + 1) * 5000;
    payloads := payloads || payload;
    chunks := chunks || jsonb_build_object('index', i, 'rows', jsonb_array_length(payload::jsonb),
      'sha256', encode(extensions.digest(payload, 'sha256'), 'hex'));
  end loop;
  manifest := jsonb_build_object('indicator', ind, 'version', '1',
    'policy', '99-csv-term-university-program-root-controls-v1',
    'archive_sha256', repeat('a', 64), 'staging_sha256', repeat('b', 64), 'snapshot', '2026-11-10',
    'rows', total, 'periods', periods, 'universities', unis, 'dimensions', dims, 'coverage', cov,
    'chunks', chunks, 'genders', '["Kvinnor","Män","Total"]'::jsonb, 'ages', '["Total"]'::jsonb,
    'review', jsonb_build_object('full_source_coverage_verified', false, 'source_release_verified', false),
    'publication_basis', 'GUARDTEST rollback-only');
  r := uka99_verified_start('uka-99-guardtest-rollback', manifest);
  for i in 1..array_length(payloads, 1) loop
    perform uka99_verified_chunk('uka-99-guardtest-rollback', i - 1, payloads[i]);
  end loop;
  r := uka99_verified_finalize('uka-99-guardtest-rollback');
  report := report || format('T6 verified: new_active=%s prev_retained=%s(rows %s) older_retained=%s(rows %s) agg_rows_99=%s; ',
    (select active_batch_id <> cur from uka_active_batches where indicator_id = ind),
    exists(select 1 from uka_batches where id = cur), (select count(*) from uka_observations where batch_id = cur),
    exists(select 1 from uka_batches where id = prev), (select count(*) from uka_observations where batch_id = prev),
    (select count(*) from agg_uka_university where indicator_id = ind));

  raise exception 'ROLLBACK-ONLY GUARD TEST: %', report;
end $$;
