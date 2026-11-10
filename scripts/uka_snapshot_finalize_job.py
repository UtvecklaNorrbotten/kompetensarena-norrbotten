"""Generate SQL for one bounded, self-removing snapshot finalization job.

Run the generated SQL through the existing privileged database connection when
an HTTP client's time limit is shorter than finalization. It sends no raw data.
The job is only created for a ready, unpublished import; finalizations remain
serial. Success and handled failures remove the job. Failures leave the old active batch in
place and are recorded on the existing source run for diagnosis and resumption.
"""
import argparse
import re


def finalize_job_sql(import_key):
    match=re.fullmatch(r'uka-(13|31|97|108|136|77|134|135)-snapshot-[0-9]{4}-[0-9]{2}-[0-9]{2}(?:-[a-z0-9]+)*-([a-f0-9]{12})',import_key)
    if not match:
        raise ValueError('Expected a snapshot publisher import key; arbitrary SQL is refused')
    name=f'uka-finalize-{match[1]}-{match[2]}'
    command=("SET statement_timeout='20min'; DO $finish$ BEGIN BEGIN "
        f"PERFORM public.uka_snapshot_finalize('{import_key}'); "
        "EXCEPTION WHEN query_canceled OR assert_failure OR OTHERS THEN UPDATE data_source_runs "
        "SET error_message=SQLSTATE||': '||SQLERRM, "
        "details=coalesce(details,'{}'::jsonb)||jsonb_build_object("
        "'finalization_error',SQLSTATE||': '||SQLERRM,'finalization_failed_at',now()) "
        "WHERE id=(SELECT b.run_id FROM uka_verified_imports v JOIN uka_batches b ON b.id=v.batch_id "
        f"WHERE v.import_key='{import_key}'); END; "
        f"PERFORM cron.unschedule('{name}'); END $finish$;")
    return (f"SELECT cron.schedule('{name}','* * * * *',$command${command}$command$) job_id "
        "WHERE NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname LIKE 'uka-finalize-%') "
        "AND EXISTS(SELECT 1 FROM uka_verified_imports v JOIN uka_batches b ON b.id=v.batch_id "
        f"WHERE v.import_key='{import_key}' AND v.published_at IS NULL AND b.status='ready' "
        "AND b.received_rows=b.expected_rows AND b.received_chunks=b.expected_chunks);")


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--import-key',required=True)
    args=parser.parse_args()
    print(finalize_job_sql(args.import_key))
