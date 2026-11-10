"""Reject executable input before any privileged SQL is generated."""
import sys
from pathlib import Path
import unittest
sys.path.insert(0,str(Path(__file__).parents[1]/'scripts'))
from uka_snapshot_finalize_job import finalize_job_sql

class FinalizerSqlTest(unittest.TestCase):
    def test_rejects_sql_injection_and_unrelated_indicators(self):
        for key in ("uka-31-snapshot-2026-11-10-all-1be12b057d06'); DROP TABLE uka_batches; --",'uka-33-snapshot-2026-11-10-all-1be12b057d06','uka-99-snapshot-2026-11-10-all-1be12b057d06','',"uka-31-snapshot-2026-11-10-all-1be12b057d06\n"):
            with self.assertRaises(ValueError):finalize_job_sql(key)
    def test_accepts_real_snapshot_key_as_single_statement(self):
        sql=finalize_job_sql('uka-31-snapshot-2026-11-10-all-1be12b057d06')
        self.assertTrue(sql.startswith('SELECT cron.schedule('))
        self.assertIn('v.published_at IS NULL',sql)
        self.assertIn("cron.unschedule('uka-finalize-31-1be12b057d06')",sql)

if __name__=='__main__':unittest.main()
