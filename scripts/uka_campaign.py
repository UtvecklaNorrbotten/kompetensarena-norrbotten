"""Partitioned UKÄ discovery and transactional file staging. Cannot publish."""
import argparse
from collections import Counter
import fcntl
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import time

from uka_hst_coverage import audit as audit_subjects
from uka_json_plan import STRATEGY, build_plan
from uka_json_probe import Probe, validate_url, yearly
from uka_json_queue import Queue, SOURCE_DIMENSIONS
from uka_source_audit import canonical_value, digest, write_json


def strategy_for(indicator):
    return 'study-first' if indicator == 33 else 'all-routes'


def rows_digest(rows):
    checksum = hashlib.sha256()
    for row in rows:
        checksum.update((json.dumps(tuple(row), ensure_ascii=False, separators=(',', ':')) + '\n').encode())
    return checksum.hexdigest()


class CampaignProbe(Probe):
    """Read immutable shared baselines without copying them into each partition."""
    def __init__(self, root, snapshot, budget, bases=()):
        super().__init__(root, snapshot, budget)
        self.bases = [Path(p) for p in bases]

    def get(self, url, indicator):
        key = digest([self.snapshot, indicator, validate_url(url, indicator)])
        if not (self.root / 'responses' / (key + '.json')).exists():
            for base in self.bases:
                if (base / 'responses' / (key + '.json')).exists():
                    try:
                        return Probe(base, self.snapshot, budget=0).get(url, indicator)
                    except RuntimeError as error:
                        raise ValueError('Invalid shared source cache') from error
        return super().get(url, indicator)


def baseline_queues(bases, snapshot):
    result = {}
    for base in bases:
        for path in Path(base).rglob('*.sqlite'):
            db = sqlite3.connect(f'file:{path.resolve()}?mode=ro', uri=True)
            try:
                tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
                if not {'meta', 'nodes', 'edges'}.issubset(tables):
                    continue
                binding = json.loads(db.execute('SELECT binding FROM meta').fetchone()[0])
                if binding.get('snapshot') != snapshot:
                    continue
                states = dict(db.execute('SELECT status,count(*) FROM nodes GROUP BY status'))
                if states and set(states) == {'done'}:
                    result[digest(binding)] = path
            finally:
                db.close()
    return result


class Campaign:
    def __init__(self, root, plan, indicator, bases=()):
        if plan['strategy'] != STRATEGY or indicator not in SOURCE_DIMENSIONS:
            raise ValueError('Unsupported campaign policy')
        self.root = Path(root); self.root.mkdir(parents=True, exist_ok=True)
        self.plan, self.indicator, self.bases = plan, indicator, [Path(p) for p in bases]
        jobs = [j for j in plan['jobs'] if j['indicator'] == indicator]
        if not jobs or len({j['job_id'] for j in jobs}) != len(jobs):
            raise ValueError('Missing or duplicate campaign selections')
        specs = []
        for job in jobs:
            q = validate_url(job['url'], indicator)
            if (not re.fullmatch('[a-f0-9]{64}', job['job_id']) or q.get('university') != '1' or
                    q.get('year') != job['period'] or 'group_slug' in q or
                    q.get('gender') != (None if job['gender'] == 'Total' else job['gender']) or
                    q.get('age_group') != job['age_parameter'] or
                    (job['age'] == 'Total') != (job['age_parameter'] is None) or
                    job['gender'] not in ('Kvinnor', 'Män', 'Total')):
                raise ValueError('Campaign selection does not match source context')
            specs.append({k: job[k] for k in ('job_id', 'indicator', 'period', 'gender', 'age', 'age_parameter', 'url')})
        self.subject_metadata = (json.loads(Path('docs/uka-hst-subject-paths-2026-11-06.json').read_text())
                                 if indicator == 33 else None)
        binding = {'version': 1, 'plan_id': plan['plan_id'], 'snapshot': plan['snapshot'],
                   'indicator': indicator, 'selections_hash': digest(specs),
                   'source_dimensions': list(SOURCE_DIMENSIONS[indicator]), 'strategy': strategy_for(indicator)}
        if self.subject_metadata is not None:
            binding['subject_metadata_hash'] = digest(self.subject_metadata)
        self.manifest = {'binding': binding, 'inventory_hash': plan['inventory_hash'],
                         'global_planned_jobs': len(plan['jobs']), 'selections': specs}
        self.lock = open(self.root / 'campaign.sqlite.lock', 'a')
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close(); raise ValueError('Another worker owns campaign staging')
        self.db = sqlite3.connect(self.root / 'campaign.sqlite')
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.executescript('''
            CREATE TABLE IF NOT EXISTS meta(binding TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS jobs(
              id TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, spec TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending', summary TEXT);
            CREATE TABLE IF NOT EXISTS observations(
              key TEXT PRIMARY KEY, job_id TEXT NOT NULL REFERENCES jobs(id),
              payload TEXT NOT NULL, source_hash TEXT NOT NULL);
        ''')
        saved = self.db.execute('SELECT binding FROM meta').fetchone()
        if saved and json.loads(saved['binding']) != binding:
            self.close(); raise ValueError('Campaign manifest or policy changed')
        with self.db:
            if not saved:
                self.db.execute('INSERT INTO meta VALUES (?)', (json.dumps(binding, sort_keys=True),))
            for ordinal, spec in enumerate(specs):
                self.db.execute('INSERT OR IGNORE INTO jobs(id,ordinal,spec) VALUES (?,?,?)',
                                (spec['job_id'], ordinal, json.dumps(spec, ensure_ascii=False, sort_keys=True)))

        saved_jobs = {row['id']: json.loads(row['spec']) for row in self.db.execute('SELECT id,spec FROM jobs')}
        if saved_jobs != {s['job_id']: s for s in specs}:
            self.close(); raise ValueError('Stored campaign selections differ from manifest')
        for row in self.db.execute("SELECT id,summary FROM jobs WHERE status='done'"):
            summary = json.loads(row['summary'])
            actual = rows_digest(self.db.execute('SELECT key,payload,source_hash FROM observations WHERE job_id=? ORDER BY key', (row['id'],)))
            if actual != summary.get('staging_sha256'):
                self.close(); raise ValueError('Previously staged observations changed')
        write_json(self.root / 'campaign-manifest.json', self.manifest)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def close(self):
        self.db.close(); self.lock.close()

    def queue(self, spec):
        return Queue(self.root / 'queues' / (spec['job_id'] + '.sqlite'), spec['url'],
                     self.plan['snapshot'], strategy_for(self.indicator), self.indicator)

    def stage(self, spec, queue, summary):
        saved = self.db.execute('SELECT spec FROM jobs WHERE id=?', (spec['job_id'],)).fetchone()
        queue_binding = json.loads(queue.db.execute('SELECT binding FROM meta').fetchone()[0])
        saved_spec = json.loads(saved['spec']) if saved else {}
        if (not saved or saved_spec != {k: spec.get(k) for k in saved_spec} or queue.indicator != self.indicator or
                queue.root != validate_url(spec['url'], self.indicator) or
                queue_binding['snapshot'] != self.plan['snapshot'] or
                queue.strategy != strategy_for(self.indicator)):
            raise ValueError('Staging selection or provenance does not match manifest')
        states = {r[0] for r in queue.db.execute('SELECT status FROM nodes')}
        if states != {'done'} or not summary['graph_closed']:
            raise ValueError('Incomplete graph cannot enter staging')
        if self.subject_metadata is not None:
            queue_path = queue.db.execute('PRAGMA database_list').fetchone()[2]
            coverage = audit_subjects(queue_path, self.subject_metadata)
            if coverage['duplicates'] or coverage['invalid_source_subject_paths']:
                raise ValueError('HST source subject path coverage is inconsistent')
        # Read back immutable source responses without any network allowance.
        source = CampaignProbe(self.root, self.plan['snapshot'], budget=0, bases=self.bases)
        # Observations and completion marker commit or roll back together.
        with self.db:
            for node in queue.db.execute('SELECT url,dimensions,observations,source_hash FROM nodes ORDER BY id'):
                if not node['source_hash']:
                    raise ValueError('Missing staged source provenance')
                body = source.get(node['url'], self.indicator)
                if digest(body) != node['source_hash']:
                    raise ValueError('Staged node differs from immutable source response')
                dimensions = json.loads(node['dimensions'])
                expected = [{'university': '1', 'value': yearly(body)[spec['period']], 'dimensions': dimensions}]
                for group in body.get('groups', []):
                    if group['column'] == 'Lärosäten':
                        for row in group.get('totals', []):
                            expected.append({'university': validate_url(row['url'], self.indicator)['university'],
                                             'name': row['name'], 'dimensions': dimensions,
                                             'value': None if row['value'] is None else canonical_value(str(row['value']))})
                observations = json.loads(node['observations'])
                if expected != observations:
                    raise ValueError('Staged observation differs from source value or university')
                for observation in observations:
                    payload = {**observation, 'indicator': self.indicator, 'period': spec['period'],
                               'gender': spec['gender'], 'age': spec['age']}
                    key = digest([self.indicator, spec['period'], spec['gender'], spec['age'],
                                  observation['university'], observation['dimensions']])
                    self.db.execute('INSERT INTO observations VALUES (?,?,?,?)',
                                    (key, spec['job_id'], json.dumps(payload, ensure_ascii=False, sort_keys=True), node['source_hash']))
            staged = {**summary, 'staging_sha256': rows_digest(self.db.execute(
                'SELECT key,payload,source_hash FROM observations WHERE job_id=? ORDER BY key', (spec['job_id'],)))}
            self.db.execute("UPDATE jobs SET status='done',summary=? WHERE id=?",
                            (json.dumps(staged, ensure_ascii=False), spec['job_id']))

    def stage_or_block(self, spec, queue, summary):
        try:
            self.stage(spec, queue, summary)
            return True
        except (ValueError, RuntimeError, KeyError, sqlite3.IntegrityError) as error:
            failed = {**summary, 'errors': [*summary.get('errors', []),
                      {'error': str(error), 'error_kind': 'staging_validation'}]}
            with self.db:
                self.db.execute("UPDATE jobs SET status='blocked',summary=? WHERE id=?",
                                (json.dumps(failed, ensure_ascii=False), spec['job_id']))
            return False

    def report(self, requests=0, seeded=0):
        statuses = dict(Counter(r[0] for r in self.db.execute('SELECT status FROM jobs')))
        coverage = []
        for row in self.db.execute('SELECT * FROM jobs ORDER BY ordinal'):
            spec = json.loads(row['spec']); summary = json.loads(row['summary']) if row['summary'] else {}
            coverage.append({**{k: spec[k] for k in ('period', 'gender', 'age')}, 'status': row['status'],
                             'observations': summary.get('observations', 0) if row['status'] == 'done' else 0,
                             'university_codes': summary.get('university_codes', []) if row['status'] == 'done' else [],
                             'validated_queue_observations': summary.get('observations', 0),
                             'states': summary.get('states', {}),
                             'errors': summary.get('errors', [])})
        checksum = rows_digest(self.db.execute('SELECT key,payload,source_hash FROM observations ORDER BY key'))
        result = {'plan_id': self.plan['plan_id'], 'snapshot': self.plan['snapshot'],
                  'indicator': self.indicator, 'planned_jobs': len(coverage), 'job_states': statuses,
                  'completed_jobs': statuses.get('done', 0),
                  'staged_university_codes': sorted({u for c in coverage for u in c['university_codes']}),
                  'observations': self.db.execute('SELECT count(*) FROM observations').fetchone()[0],
                  'staging_sha256': checksum, 'manifest_sha256': digest(self.manifest),
                  'global_planned_jobs': len(self.plan['jobs']), 'new_requests': requests, 'seeded_jobs': seeded,
                  'discovery_complete': set(statuses) == {'done'}, 'coverage': coverage,
                  'source_release_verified': False, 'full_source_coverage_verified': False,
                  'publish_allowed': False,
                  'blockers': ['Full source coverage and empty semantics unresolved',
                               'Verified source release missing', 'Database publication unavailable']}
        write_json(self.root / 'campaign-report.json', result)
        return result

    def run(self, probe, max_jobs=20, seconds=150):
        started = time.monotonic(); processed = 0; seeded = 0
        baselines = baseline_queues(self.bases, self.plan['snapshot'])
        # Import already validated baseline graphs before spending a request budget.
        for row in self.db.execute("SELECT * FROM jobs WHERE status='pending' ORDER BY ordinal").fetchall():
            spec = json.loads(row['spec'])
            binding = {'version': 1, 'root': validate_url(spec['url'], self.indicator),
                       'snapshot': self.plan['snapshot'], 'indicator': self.indicator}
            if self.indicator == 33:
                binding['strategy'] = 'study-first'
            else:
                binding['source_dimensions'] = list(SOURCE_DIMENSIONS[self.indicator])
            source = baselines.get(digest(binding))
            if not source:
                continue
            with self.queue(spec) as queue:
                current = queue.db.execute('SELECT count(*) FROM nodes').fetchone()[0]
                if current == 1 and queue.db.execute("SELECT count(*) FROM nodes WHERE status='done'").fetchone()[0] == 0:
                    saved = sqlite3.connect(f'file:{source.resolve()}?mode=ro', uri=True)
                    try:
                        saved.backup(queue.db)
                    finally:
                        saved.close()
                cached_only = CampaignProbe(self.root, self.plan['snapshot'], budget=0, bases=self.bases)
                summary = queue.run(cached_only, max_nodes=2000, seconds=30)
                if summary['graph_closed']:
                    if self.stage_or_block(spec, queue, summary):
                        seeded += 1
        self.report(probe.requests, seeded)
        for row in self.db.execute("SELECT * FROM jobs WHERE status IN ('pending','waiting') ORDER BY ordinal").fetchall():
            if processed >= max_jobs or time.monotonic() - started >= seconds:
                break
            spec = json.loads(row['spec']); before = probe.requests
            with self.queue(spec) as queue:
                summary = queue.run(probe, max_nodes=2000, seconds=max(0.1, seconds - (time.monotonic() - started)))
                summary['network_requests_this_run'] = probe.requests - before
                if summary['graph_closed']:
                    self.stage_or_block(spec, queue, summary)
                else:
                    state = 'blocked' if summary['states'].get('error') else 'waiting' if summary['states'].get('retry_wait') else 'pending'
                    # A budget-only replay does not resolve an earlier source failure.
                    if row['status'] == 'waiting' and summary['stop_reason'] == 'request_budget' and probe.requests == before:
                        state = 'waiting'
                        previous = json.loads(row['summary'])
                        summary['errors'] = previous.get('errors', [])
                    with self.db:
                        self.db.execute('UPDATE jobs SET status=?,summary=? WHERE id=?',
                                        (state, json.dumps(summary, ensure_ascii=False), spec['job_id']))
            processed += 1
            self.report(probe.requests, seeded)
            if summary['stop_reason'] in ('request_budget', 'time_budget'):
                break
        return self.report(probe.requests, seeded)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--indicator', required=True, type=int, choices=sorted(SOURCE_DIMENSIONS))
    parser.add_argument('--snapshot', required=True)
    parser.add_argument('--root', required=True)
    parser.add_argument('--base', action='append', default=[])
    parser.add_argument('--inventory', default='docs/uka-source-inventory-2026-11-06.json')
    parser.add_argument('--max-new-requests', type=int, default=0)
    parser.add_argument('--max-jobs', type=int, default=20)
    parser.add_argument('--seconds', type=float, default=150)
    args = parser.parse_args()
    if args.max_new_requests < 0 or args.max_jobs < 1 or args.seconds <= 0:
        parser.error('Invalid staging budget')
    inventory = json.loads(Path(args.inventory).read_text())
    plan = build_plan(inventory, args.snapshot, args.base[0] if args.base else args.root)
    probe = CampaignProbe(args.root, args.snapshot, args.max_new_requests, args.base)
    with Campaign(args.root, plan, args.indicator, args.base) as campaign:
        result = campaign.run(probe, args.max_jobs, args.seconds)
    print(json.dumps({k: v for k, v in result.items() if k != 'coverage'}, ensure_ascii=False, indent=2))
    raise SystemExit(1 if result['job_states'].get('blocked') else 75 if result['job_states'].get('waiting') else 0)
