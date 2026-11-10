-- Rollback-only tests of the shared verified UKÄ snapshot import
-- (migration 0046_uka_snapshot_verified_import). Each block below is run as ONE
-- statement and ALWAYS ends with an exception, so every write is rolled back;
-- the exception message is the test report. No data is changed.
-- Real active data is used: indicator 13 (73 268 rows) for validation, start, sparse
-- chunks and guards (A, B1); indicator 136 (9 899 rows, technical age Total only) for
-- the full finalize/upload blocks (B2, C, D) so each block stays within the SQL
-- runner's request time (a 13 finalize incl. aggregate refresh takes ~3 min).
-- Test manifests are built from the active batch with the same functions; the
-- frozen pilot manifest itself is compared by scripts/uka_snapshot_publish_verified.py.

-- ===== BLOCK A: manifest validation, changed hash/value, wrong indicator =====
do $$
declare
  ind constant text := 'uka-forstahandssokande-yrkesprogram';
  src uuid; m jsonb; bad jsonb; r jsonb; report text := ''; before_imports int; before_batches int;
begin
  select active_batch_id into src from uka_active_batches where indicator_id = ind;
  m := jsonb_build_object('version','1','mode','copy','policy','csv-all-universities-partitions-every-root-v1',
    'snapshot','2026-11-10-all','archive_sha256','1be12b057d06285fa97b9eaa314d31e0898de57130f7c4d99c3a4093e2eb4170',
    'canonicalization','jsonb-array(period,university,gender,dimensions,numeric-text-fixed); bytewise order; newline separator without final newline',
    'api_id',13,'indicator',ind,'rows',(select count(*) from uka_observations where batch_id = src),
    'periods', uka_snapshot_period_hashes(src),
    'coverage', (select jsonb_agg(jsonb_build_object('period',period,'gender',gender,'age',age,'rows',cnt)
                   order by period collate "C", gender collate "C", age collate "C")
                 from (select period, gender, coalesce(dimensions->>'aldersgrupp','Total') age, count(*) cnt
                       from uka_observations where batch_id = src group by 1,2,3) c),
    'source_batch_id', src::text, 'source_release_verified', false, 'full_source_coverage_verified', false,
    'publication_basis', 'TEST rollback-only manifest built from the active batch');
  select count(*) into before_imports from uka_verified_imports;
  select count(*) into before_batches from uka_batches;
  report := report || format('A0 valid=%s; ', uka_snapshot_manifest_error(m) is null);

  -- A1 incomplete manifests
  report := report || format('A1 no_coverage=%s; ', uka_snapshot_manifest_error(m - 'coverage'));
  report := report || format('A1 period_missing=%s; ', uka_snapshot_manifest_error(jsonb_set(m, '{periods}', (m->'periods') - 0)));
  report := report || format('A1 flag_true=%s; ', uka_snapshot_manifest_error(jsonb_set(m, '{source_release_verified}', 'true')));
  report := report || format('A1 cov_sum=%s; ', uka_snapshot_manifest_error(jsonb_set(m, '{coverage,0,rows}', to_jsonb((m#>>'{coverage,0,rows}')::int + 1))));
  begin
    r := uka_snapshot_start('uka-13-test-incomplete', m - 'coverage');
    report := report || 'A1 FAIL start accepted; ';
  exception when sqlstate '22023' then report := report || 'A1 PASS start refused; ';
  end;

  -- A2 changed hash: one period fingerprint differs -> nothing written
  bad := jsonb_set(m, '{periods,3,sha256}', to_jsonb(repeat('0', 64)));
  begin
    r := uka_snapshot_start('uka-13-test-badhash', bad);
    report := report || 'A2 FAIL accepted; ';
  exception when sqlstate '22000' then
    report := report || format('A2 PASS hash refused (%s); ', left(sqlerrm, 50));
  end;
  -- A2b changed row count in one period
  bad := jsonb_set(m, '{periods,0,rows}', to_jsonb((m#>>'{periods,0,rows}')::int - 1));
  report := report || format('A2b rowcount=%s; ', uka_snapshot_manifest_error(bad));

  -- A3 changed value in the source batch (sub-transaction, rolled back): start refuses
  begin
    update uka_observations set value = value + 1
     where id = (select id from uka_observations where batch_id = src order by id limit 1 offset 4321);
    r := uka_snapshot_start('uka-13-test-changedvalue', m);
    report := report || 'A3 FAIL accepted; ';
  exception when sqlstate '22000' then
    report := report || 'A3 PASS changed value refused; ';
  end;

  -- A4 wrong indicator / pairing
  report := report || format('A4 api33=%s; ', uka_snapshot_manifest_error(jsonb_set(jsonb_set(m, '{api_id}', '33'), '{indicator}', '"uka-hst"')));
  report := report || format('A4 pair=%s; ', uka_snapshot_manifest_error(jsonb_set(m, '{indicator}', '"uka-antagna-yrkesprogram"')));
  begin
    r := uka_snapshot_start('uka-97-test-wrongkey', m);
    report := report || 'A4 FAIL key accepted; ';
  exception when sqlstate '22023' then report := report || 'A4 PASS key/api mismatch refused; ';
  end;
  -- A4b copy from a batch that is not active for the indicator (HST active batch)
  begin
    r := uka_snapshot_start('uka-13-test-wrongsource', jsonb_set(m, '{source_batch_id}',
           to_jsonb((select active_batch_id::text from uka_active_batches where indicator_id = 'uka-hst'))));
    report := report || 'A4b FAIL accepted; ';
  exception when sqlstate '55000' then report := report || 'A4b PASS foreign source refused; ';
  end;

  report := report || format('A9 imports_unchanged=%s batches_unchanged=%s active_unchanged=%s',
    (select count(*) from uka_verified_imports) = before_imports, (select count(*) from uka_batches) = before_batches,
    (select active_batch_id from uka_active_batches where indicator_id = ind) = src);
  raise exception 'ROLLBACK-ONLY SNAPSHOT TEST A: %', report;
end $$;

-- ===== BLOCK B1: copy flow start, sparse/duplicate chunks, resume, binding, legacy guards =====
do $$
declare
  ind constant text := 'uka-forstahandssokande-yrkesprogram';
  k constant text := 'uka-13-test-copy-flow';
  src uuid; m jsonb; r jsonb; s jsonb; report text := ''; nb uuid; n int; i int; lb uuid; agg_before bigint;
begin
  select active_batch_id into src from uka_active_batches where indicator_id = ind;
  m := jsonb_build_object('version','1','mode','copy','policy','csv-all-universities-partitions-every-root-v1',
    'snapshot','2026-11-10-all','archive_sha256','1be12b057d06285fa97b9eaa314d31e0898de57130f7c4d99c3a4093e2eb4170',
    'canonicalization','jsonb-array(period,university,gender,dimensions,numeric-text-fixed); bytewise order; newline separator without final newline',
    'api_id',13,'indicator',ind,'rows',(select count(*) from uka_observations where batch_id = src),
    'periods', uka_snapshot_period_hashes(src),
    'coverage', (select jsonb_agg(jsonb_build_object('period',period,'gender',gender,'age',age,'rows',cnt)
                   order by period collate "C", gender collate "C", age collate "C")
                 from (select period, gender, coalesce(dimensions->>'aldersgrupp','Total') age, count(*) cnt
                       from uka_observations where batch_id = src group by 1,2,3) c),
    'source_batch_id', src::text, 'source_release_verified', false, 'full_source_coverage_verified', false,
    'publication_basis', 'TEST rollback-only manifest built from the active batch');
  select count(*) into agg_before from agg_uka_university where indicator_id = ind;

  r := uka_snapshot_start(k, m);
  nb := (r->>'batch_id')::uuid; n := (r->>'planned_chunks')::int;
  report := report || format('B1 started resumed=%s chunks=%s source_ok=%s; ', r->>'resumed', n, r#>>'{source_check,ok}');

  -- sparse chunks
  perform uka_snapshot_copy_chunk(k, 0); perform uka_snapshot_copy_chunk(k, 2); perform uka_snapshot_copy_chunk(k, n - 1);
  r := uka_snapshot_copy_chunk(k, 2);
  report := report || format('B2 duplicate=%s received=%s; ', r->>'duplicate', uka_snapshot_status(k)->'received_indices');
  begin r := uka_snapshot_copy_chunk(k, n); report := report || 'B2 FAIL outside plan; ';
  exception when sqlstate '22023' then report := report || 'B2 PASS outside plan refused; '; end;
  begin r := uka_snapshot_finalize(k); report := report || 'B3 FAIL incomplete finalize; ';
  exception when sqlstate '55000' then report := report || format('B3 PASS incomplete refused (%s); ', left(sqlerrm, 60)); end;

  -- resume / binding
  r := uka_snapshot_start(k, m);
  report := report || format('B4 resumed=%s same_batch=%s; ', r->>'resumed', (r->>'batch_id')::uuid = nb);
  begin r := uka_snapshot_start(k, jsonb_set(m, '{publication_basis}', '"TEST another basis for the same key"'));
    report := report || 'B4 FAIL rebind; ';
  exception when sqlstate '55000' then report := report || 'B4 PASS other manifest refused; '; end;
  begin r := uka_snapshot_start('uka-13-test-second-import', jsonb_set(m, '{publication_basis}', '"TEST parallel import for indicator"'));
    report := report || 'B4 FAIL parallel; ';
  exception when sqlstate '55000' then report := report || 'B4 PASS parallel import refused; '; end;
  begin r := uka_snapshot_start('uka-13-test-same-manifest', m);
    report := report || 'B4 FAIL same manifest; ';
  exception when sqlstate '55000' then report := report || 'B4 PASS same manifest other key refused; '; end;

  -- legacy and foreign paths are refused
  begin r := uka_finalize_batch(nb); report := report || 'B5 FAIL legacy finalize; ';
  exception when sqlstate '55000' then report := report || 'B5 PASS legacy finalize refused; '; end;
  begin r := uka_abort_batch(nb, 'test'); report := report || 'B5 FAIL legacy abort; ';
  exception when sqlstate '55000' then report := report || 'B5 PASS legacy abort refused; '; end;
  lb := uka_start_batch(ind, 'GUARDTEST', 1, 1, null, null);
  begin perform uka_store_chunk(lb, ind, 0, '[{"period":"HT2026","university":"Riket","gender":"Total","value":"1","dimensions":{}}]'::jsonb, 'g');
    report := report || 'B5 FAIL legacy chunk; ';
  exception when sqlstate '55000' then report := report || 'B5 PASS legacy chunk refused; '; end;
  begin r := uka_verified_finalize(k); report := report || 'B5 FAIL HST finalize; ';
  exception when sqlstate '55000' then report := report || 'B5 PASS HST path refused; '; end;
  begin r := uka99_verified_finalize(k); report := report || 'B5 FAIL 99 finalize; ';
  exception when others then report := report || format('B5 PASS 99 path refused (%s); ', left(sqlerrm, 30)); end;
  begin r := uka_snapshot_chunk(k, 1, 'x'); report := report || 'B5 FAIL upload into copy; ';
  exception when sqlstate '55000' then report := report || 'B5 PASS upload into copy import refused; '; end;

  raise exception 'ROLLBACK-ONLY SNAPSHOT TEST B1: %', report;
end $$;

-- ===== BLOCK B2: full copy, finalize, read-back, idempotent publication, immutability =====
do $$
declare
  ind constant text := 'uka-etablering';
  k constant text := 'uka-136-test-copy-flow';
  src uuid; m jsonb; r jsonb; s jsonb; report text := ''; nb uuid; n int; i int; lb uuid; agg_before bigint;
begin
  select active_batch_id into src from uka_active_batches where indicator_id = ind;
  m := jsonb_build_object('version','1','mode','copy','policy','csv-all-universities-partitions-every-root-v1',
    'snapshot','2026-11-10-all','archive_sha256','1be12b057d06285fa97b9eaa314d31e0898de57130f7c4d99c3a4093e2eb4170',
    'canonicalization','jsonb-array(period,university,gender,dimensions,numeric-text-fixed); bytewise order; newline separator without final newline',
    'api_id',136,'indicator',ind,'rows',(select count(*) from uka_observations where batch_id = src),
    'periods', uka_snapshot_period_hashes(src),
    'coverage', (select jsonb_agg(jsonb_build_object('period',period,'gender',gender,'age',age,'rows',cnt)
                   order by period collate "C", gender collate "C", age collate "C")
                 from (select period, gender, coalesce(dimensions->>'aldersgrupp','Total') age, count(*) cnt
                       from uka_observations where batch_id = src group by 1,2,3) c),
    'source_batch_id', src::text, 'source_release_verified', false, 'full_source_coverage_verified', false,
    'publication_basis', 'TEST rollback-only manifest built from the active batch');
  select count(*) into agg_before from agg_uka_university where indicator_id = ind;

  r := uka_snapshot_start(k, m);
  nb := (r->>'batch_id')::uuid; n := (r->>'planned_chunks')::int;
  -- complete and finalize
  for i in 0 .. n - 1 loop perform uka_snapshot_copy_chunk(k, i); end loop;
  r := uka_snapshot_finalize(k);
  report := report || format('B6 finalize status=%s staging_ok=%s source_ok=%s rows_checked=%s prev=%s; ',
    r->>'status', r#>>'{staging_check,ok}', r#>>'{source_check,ok}', r#>>'{staging_check,rows_checked}', r->>'previous_batch_retained');
  report := report || format('B7 active_new=%s prev_rows=%s new_rows=%s agg_rows=%s(before %s) agg_eq_obs=%s; ',
    (select active_batch_id from uka_active_batches where indicator_id = ind) = nb,
    (select count(*) from uka_observations where batch_id = src), (select count(*) from uka_observations where batch_id = nb),
    (select count(*) from agg_uka_university where indicator_id = ind), agg_before,
    not exists (select o.university, o.period, o.gender,
        coalesce((select string_agg(x, '|' order by x) from jsonb_object_keys(o.dimensions) x), ''),
        coalesce((select string_agg(o.dimensions->>x, '|' order by x) from jsonb_object_keys(o.dimensions) x), ''), o.value
      from uka_observations o where o.batch_id = nb
      except select g.university, g.period, g.gender, g.breakdown, g.category, g.value
      from agg_uka_university g where g.indicator_id = ind));
  report := report || format('B7 hashes_equal=%s; ', uka_snapshot_period_hashes(nb) = uka_snapshot_period_hashes(src));

  -- idempotent publication and immutability
  r := uka_snapshot_finalize(k);
  report := report || format('B8 refinalize already_published=%s; ', r->>'already_published');
  r := uka_snapshot_start(k, m);
  report := report || format('B8 restart resumed=%s published=%s; ', r->>'resumed', r->>'published_at' is not null);
  r := uka_snapshot_copy_chunk(k, 0);
  report := report || format('B8 recopy duplicate=%s; ', r->>'duplicate');
  begin update uka_verified_imports set manifest = manifest || '{"x":1}' where import_key = k; report := report || 'B9 FAIL manifest update; ';
  exception when sqlstate '55000' then report := report || 'B9 PASS manifest immutable; '; end;
  begin delete from uka_verified_imports where import_key = k; report := report || 'B9 FAIL delete; ';
  exception when sqlstate '55000' then report := report || 'B9 PASS published import undeletable; '; end;
  begin delete from uka_snapshot_copy_plan where import_key = k; report := report || 'B9 FAIL plan delete; ';
  exception when sqlstate '55000' then report := report || 'B9 PASS plan immutable; '; end;

  raise exception 'ROLLBACK-ONLY SNAPSHOT TEST B2: %', report;
end $$;

-- ===== BLOCK C: source batch changes after start (copy and finalize re-check) =====
do $$
declare
  ind constant text := 'uka-etablering';
  src uuid; m jsonb; r jsonb; report text := ''; n int; i int; victim bigint; nb uuid;
begin
  select active_batch_id into src from uka_active_batches where indicator_id = ind;
  m := jsonb_build_object('version','1','mode','copy','policy','csv-all-universities-partitions-every-root-v1',
    'snapshot','2026-11-10-all','archive_sha256','1be12b057d06285fa97b9eaa314d31e0898de57130f7c4d99c3a4093e2eb4170',
    'canonicalization','jsonb-array(period,university,gender,dimensions,numeric-text-fixed); bytewise order; newline separator without final newline',
    'api_id',136,'indicator',ind,'rows',(select count(*) from uka_observations where batch_id = src),
    'periods', uka_snapshot_period_hashes(src),
    'coverage', (select jsonb_agg(jsonb_build_object('period',period,'gender',gender,'age',age,'rows',cnt)
                   order by period collate "C", gender collate "C", age collate "C")
                 from (select period, gender, coalesce(dimensions->>'aldersgrupp','Total') age, count(*) cnt
                       from uka_observations where batch_id = src group by 1,2,3) c),
    'source_batch_id', src::text, 'source_release_verified', false, 'full_source_coverage_verified', false,
    'publication_basis', 'TEST rollback-only manifest built from the active batch');
  -- C1 change inside a not yet copied chunk -> copy refuses
  r := uka_snapshot_start('uka-136-test-source-change', m); n := (r->>'planned_chunks')::int; nb := (r->>'batch_id')::uuid;
  select first_id + 7 into victim from uka_snapshot_copy_plan where import_key = 'uka-136-test-source-change' and chunk_index = 1;
  begin
    update uka_observations set value = value + 1 where id = victim;
    perform uka_snapshot_copy_chunk('uka-136-test-source-change', 1);
    report := report || 'C1 FAIL copied changed source; ';
  exception when sqlstate '55000' then
    report := report || format('C1 PASS changed source chunk refused (%s); ', left(sqlerrm, 50));
  end;
  -- C2 copy everything, then change an already copied source row -> finalize refuses, nothing activated
  for i in 0 .. n - 1 loop perform uka_snapshot_copy_chunk('uka-136-test-source-change', i); end loop;
  begin
    update uka_observations set value = value + 1 where id = victim;
    r := uka_snapshot_finalize('uka-136-test-source-change');
    report := report || 'C2 FAIL finalize after source change; ';
  exception when sqlstate '22000' then
    report := report || format('C2 PASS finalize refused (%s) active_unchanged=%s; ', left(sqlerrm, 50),
      (select active_batch_id from uka_active_batches where indicator_id = ind) = src);
  end;
  -- C3 change in the staging copy -> finalize refuses
  begin
    update uka_observations set value = value + 1
     where id = (select id from uka_observations where batch_id = nb order by id limit 1 offset 999);
    r := uka_snapshot_finalize('uka-136-test-source-change');
    report := report || 'C3 FAIL finalize after staging change; ';
  exception when sqlstate '22000' then
    report := report || format('C3 PASS staging change refused (%s); ', left(sqlerrm, 50));
  end;
  -- C4 active batch changed after start -> finalize refuses
  begin
    update uka_active_batches set active_batch_id = nb where indicator_id = ind;
    r := uka_snapshot_finalize('uka-136-test-source-change');
    report := report || 'C4 FAIL; ';
  exception when sqlstate '55000' then report := report || format('C4 PASS active change refused (%s); ', left(sqlerrm, 50));
  end;
  raise exception 'ROLLBACK-ONLY SNAPSHOT TEST C: %', report;
end $$;

-- ===== BLOCK D: upload mode (canonical lines), invalid lines, full upload + finalize =====
do $$
declare
  ind constant text := 'uka-etablering';
  k constant text := 'uka-136-test-upload-flow';
  src uuid; m jsonb; chunks jsonb; payloads text[]; r jsonb; report text := ''; i int; nb uuid;
  p0 text := '["VT2017", "Testlärosäte", "Total", {}, "5.0"]';
  p1 text := '["VT2017", "Testlärosäte", "Total", {"aldersgrupp": "Total"}, "5"]';
  p2 text := '["VT2017", "Testlärosäte", "Total", {}, "5"]';
  fake jsonb;
begin
  -- D1 invalid canonical lines are refused even when their hash is in the manifest (indicator 31, no activation)
  fake := jsonb_build_object('version','1','mode','upload','policy','csv-all-universities-partitions-every-root-v1',
    'snapshot','2026-11-10-all','archive_sha256',repeat('a',64),
    'canonicalization','jsonb-array(period,university,gender,dimensions,numeric-text-fixed); bytewise order; newline separator without final newline',
    'api_id',31,'indicator','uka-nyborjare-yrkesprogram','rows',3,
    'periods',jsonb_build_array(jsonb_build_object('period','VT2017','rows',3,'sha256',repeat('b',64))),
    'coverage',jsonb_build_array(jsonb_build_object('period','VT2017','gender','Total','age','Total','rows',3)),
    'chunks',jsonb_build_array(
      jsonb_build_object('index',0,'rows',1,'sha256',encode(extensions.digest(convert_to(p0,'UTF8'),'sha256'),'hex')),
      jsonb_build_object('index',1,'rows',1,'sha256',encode(extensions.digest(convert_to(p1,'UTF8'),'sha256'),'hex')),
      jsonb_build_object('index',2,'rows',1,'sha256',encode(extensions.digest(convert_to(p2,'UTF8'),'sha256'),'hex'))),
    'source_release_verified',false,'full_source_coverage_verified',false,'publication_basis','TEST rollback-only upload manifest');
  r := uka_snapshot_start('uka-31-test-invalid-lines', fake);
  begin perform uka_snapshot_chunk('uka-31-test-invalid-lines', 0, p0); report := report || 'D1 FAIL 5.0 accepted; ';
  exception when sqlstate '22000' then report := report || 'D1 PASS non-canonical value refused; '; end;
  begin perform uka_snapshot_chunk('uka-31-test-invalid-lines', 1, p1); report := report || 'D1 FAIL age Total key accepted; ';
  exception when sqlstate '22000' then report := report || 'D1 PASS technical age key refused; '; end;
  begin perform uka_snapshot_chunk('uka-31-test-invalid-lines', 2, p2 || ' '); report := report || 'D1 FAIL changed payload; ';
  exception when sqlstate '22000' then report := report || 'D1 PASS changed payload hash refused; '; end;
  r := uka_snapshot_chunk('uka-31-test-invalid-lines', 2, p2);
  report := report || format('D1 valid line stored=%s; ', r->>'rows');
  begin r := uka_snapshot_finalize('uka-31-test-invalid-lines'); report := report || 'D1 FAIL finalize; ';
  exception when sqlstate '55000' then report := report || 'D1 PASS incomplete upload refused; '; end;

  -- D2 full upload of indicator 13 from canonical lines (same text the local manifest hashes)
  select active_batch_id into src from uka_active_batches where indicator_id = ind;
  select array_agg(t order by ci), jsonb_agg(jsonb_build_object('index', ci, 'rows', n,
           'sha256', encode(extensions.digest(convert_to(t, 'UTF8'), 'sha256'), 'hex')) order by ci)
    into payloads, chunks
    from (select ci, count(*) n, string_agg(line, E'\n' order by line collate "C") t
            from (select line, ((row_number() over (order by line collate "C")) - 1) / 5000 ci
                    from (select uka_snapshot_line(period, university, gender, dimensions, value) line
                            from uka_observations where batch_id = src) a) b
           group by ci) c;
  m := jsonb_build_object('version','1','mode','upload','policy','csv-all-universities-partitions-every-root-v1',
    'snapshot','2026-11-10-all','archive_sha256','1be12b057d06285fa97b9eaa314d31e0898de57130f7c4d99c3a4093e2eb4170',
    'canonicalization','jsonb-array(period,university,gender,dimensions,numeric-text-fixed); bytewise order; newline separator without final newline',
    'api_id',136,'indicator',ind,'rows',(select count(*) from uka_observations where batch_id = src),
    'periods', uka_snapshot_period_hashes(src),
    'coverage', (select jsonb_agg(jsonb_build_object('period',period,'gender',gender,'age',age,'rows',cnt)
                   order by period collate "C", gender collate "C", age collate "C")
                 from (select period, gender, coalesce(dimensions->>'aldersgrupp','Total') age, count(*) cnt
                       from uka_observations where batch_id = src group by 1,2,3) c),
    'chunks', chunks, 'source_release_verified', false, 'full_source_coverage_verified', false,
    'publication_basis', 'TEST rollback-only upload manifest built from the active batch');
  r := uka_snapshot_start(k, m); nb := (r->>'batch_id')::uuid;
  for i in reverse cardinality(payloads) .. 1 loop perform uka_snapshot_chunk(k, i - 1, payloads[i]); end loop;
  r := uka_snapshot_chunk(k, 0, payloads[1]);
  report := report || format('D2 chunks=%s duplicate=%s; ', cardinality(payloads), r->>'duplicate');
  r := uka_snapshot_finalize(k);
  report := report || format('D2 finalize status=%s staging_ok=%s active_new=%s prev_rows=%s hashes_equal=%s; ',
    r->>'status', r#>>'{staging_check,ok}', (select active_batch_id from uka_active_batches where indicator_id = ind) = nb,
    (select count(*) from uka_observations where batch_id = src), uka_snapshot_period_hashes(nb) = uka_snapshot_period_hashes(src));
  raise exception 'ROLLBACK-ONLY SNAPSHOT TEST D: %', report;
end $$;
