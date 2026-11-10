"""Bounded Indicator-99 ten-year CSV collection with independent layout controls.

Uses a NEW campaign; never changes historical manifests, queues or public data.
Each year must match two disjoint university exports and two program exports,
plus all three national gender JSON root controls, before a transactional staging write.
This verifies the declared checks, not every leaf against independent JSON.
"""
import argparse
from collections import Counter
import fcntl
import hashlib
import json
from pathlib import Path
import sqlite3
import time
import requests
from urllib.parse import urlencode

from uka_campaign import rows_digest
from uka_csv_bulk_probe import compare
from uka_99_values import observations
from uka_hst_coverage import source_paths
from uka_json_probe import BASE, Probe, validate_url, yearly
from uka_source_audit import Source, canonical_value, digest, write_json

POLICY = '99-csv-term-university-program-root-controls-v1'


class DeadlineSession(requests.Session):
    """Bound every request by the remaining per-term wall-clock budget."""
    def __init__(self, deadline):
        super().__init__()
        self.deadline = deadline

    def request(self, *args, **kwargs):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError('Term time budget exhausted; resume from saved sources')
        kwargs['timeout'] = min(kwargs.get('timeout', 60), remaining)
        return super().request(*args, **kwargs)


def observation_key(period, university, gender, age, dimensions):
    return json.dumps([period, university, gender, age, dimensions], ensure_ascii=False, sort_keys=True)


def union_exact(parts, reference):
    combined = {}
    for part in parts:
        if combined.keys() & part.keys():
            raise ValueError('Overlapping partition observations')
        combined.update(part)
    comparison = compare(reference, combined)
    if not comparison['exact']:
        raise ValueError('Partition coverage or values differ: ' + json.dumps(comparison, ensure_ascii=False))
    return comparison


def root_control(actual, body, period, gender, age, all_universities):
    """Require source-native totals and advertised first-level values, not sums."""
    if str(body.get('indicator', {}).get('id')) != '99' or not isinstance(body.get('groups'), list):
        raise ValueError('Invalid national indicator 99 root control')
    required = {observation_key(period, '1', gender, age, {}): yearly(body)[period]}
    advertised = {'1'}
    for group in body['groups']:
        column = group['column']
        if column not in ('Lärosäten', 'Program', 'Kön'):
            raise ValueError('Unknown national root dimension: ' + column)
        for row in group.get('totals', []):
            if 'value' not in row:
                raise ValueError('Missing source control value')
            if column == 'Lärosäten':
                q = validate_url(row['url'], 99); university = q.get('university')
                if (university not in all_universities or university in advertised or q.get('year') != period or
                        q.get('gender', 'Total') != gender or q.get('age_group') != {'-24': '8', '25-34': '9', '35-': '10', 'Total': None}[age] or 'group_slug' in q):
                    raise ValueError('Invalid advertised university control')
                advertised.add(university); dimensions = {}
            elif column == 'Program':
                university = '1'; dimensions = {column: row['name']}
            else:
                continue
            key = observation_key(period, university, gender, age, dimensions)
            if key in required:
                raise ValueError('Duplicate root control identity')
            required[key] = None if row['value'] is None else canonical_value(str(row['value']))
    for key, value in required.items():
        if key not in actual or actual[key] != value:
            raise ValueError('CSV missing or differing native JSON control: ' + key)
    selected = {k: v for k, v in actual.items() if json.loads(k)[2:4] == [gender, age]}
    observed = {json.loads(k)[1] for k in selected}
    if observed != advertised:
        raise ValueError('CSV university coverage differs from positive JSON root list')
    program_names = {r['name'] for g in body['groups'] if g['column'] == 'Program' for r in g.get('totals', [])}
    csv_programs = {json.loads(k)[4]['Program'] for k in selected if json.loads(k)[1] == '1' and 'Program' in json.loads(k)[4]}
    if program_names != csv_programs:
        raise ValueError('CSV national program coverage differs from positive JSON root list')
    missing = sorted(set(all_universities) - advertised)
    return {'gender': gender, 'age': age, 'native_controls': len(required),
            'observations': len(selected), 'advertised_programs': sorted(program_names), 'advertised_universities': sorted(advertised),
            'not_advertised_universities': missing,
            'absence_meaning': 'Absent in positive national root and controlled broad CSV; no zero values generated.'}


class Collection:
    def __init__(self, root, metadata, snapshot, max_exports=0, max_requests=0, max_seconds=240):
        self.root = Path(root); self.root.mkdir(parents=True, exist_ok=True)
        self.metadata, self.snapshot = metadata, snapshot
        if (metadata['indicator'] != 99 or metadata['snapshot'] != snapshot or
                metadata['metadata_hash'] != digest({k: v for k, v in metadata.items() if k != 'metadata_hash'})):
            raise ValueError('Changed or wrong source metadata')
        if {g['index'] for g in metadata['groups']} != {'6.'}:
            raise ValueError('Unknown indicator 99 dimension groups')
        self.studies = next(g for g in metadata['groups'] if g['index'] == '6.')['values']
        self.subjects = self.studies
        self.universities = [o['value'].removeprefix('uni:') for o in metadata['universities']]
        self.periods = [o['value'].removeprefix('from:') for o in metadata['retained_periods']]
        self.genders = [o['label'] for o in metadata['genders']]; self.ages = [o['label'] for o in metadata['ages']]
        if (len(self.periods) != 20 or len(set(self.periods)) != 20 or
                set(self.genders) != {'Kvinnor', 'Män', 'Total'} or set(self.ages) != {'Total'} or
                len(self.universities) != len(set(self.universities)) or '1' not in self.universities):
            raise ValueError('Unverified ten-year indicator 99 scope')
        self.binding = {'version': 1, 'indicator': 99, 'snapshot': snapshot, 'policy': POLICY,
                        'metadata_hash': metadata['metadata_hash'], 'subject_paths_hash': digest(self.subjects),
                        'periods': self.periods, 'universities': self.universities,
                        'genders': self.genders, 'ages': self.ages}
        self.lock = open(self.root / '99-full.sqlite.lock', 'a')
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close(); raise ValueError('Another worker owns indicator 99 collection')
        self.db = sqlite3.connect(self.root / '99-full.sqlite'); self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.executescript('''
          CREATE TABLE IF NOT EXISTS meta(binding TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS years(period TEXT PRIMARY KEY, summary TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS observations(key TEXT PRIMARY KEY, period TEXT NOT NULL REFERENCES years(period), payload TEXT NOT NULL, source_hash TEXT NOT NULL);
        ''')
        saved = self.db.execute('SELECT binding FROM meta').fetchone()
        if saved and json.loads(saved[0]) != self.binding:
            self.close(); raise ValueError('Collection manifest changed')
        with self.db:
            if not saved:
                self.db.execute('INSERT INTO meta VALUES (?)', (json.dumps(self.binding, sort_keys=True),))
        self.source = Source(self.root, snapshot); self.source.export_budget = max_exports
        self.probe = Probe(self.root, snapshot, max_requests)
        self.bookends = Probe(self.root / 'bookends', snapshot, max_requests)
        self.max_requests = max_requests
        self.max_seconds = max_seconds
        for client in (self.source, self.probe, self.bookends):
            client.session.close()
            client.session = DeadlineSession(time.monotonic() + max_seconds)
        try:
            self.validate_staged()
        except (ValueError, KeyError, OSError, sqlite3.Error):
            self.close(); raise
        write_json(self.root / 'collection-manifest.json', self.binding)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def close(self):
        self.db.close(); self.lock.close()

    def validate_staged(self, period=None):
        query = 'SELECT period,summary FROM years' + (' WHERE period=?' if period else '')
        for row in self.db.execute(query, (period,) if period else ()):
            summary = json.loads(row['summary'])
            rows = self.db.execute('SELECT key,payload,source_hash FROM observations WHERE period=? ORDER BY key', (row['period'],)).fetchall()
            if (summary['binding_hash'] != digest(self.binding) or summary['period'] != row['period'] or
                    len(rows) != summary['observations'] or rows_digest(rows) != summary['staging_sha256']):
                raise ValueError('Previously staged full-year rows or manifest changed')
            for receipt in summary['exports']:
                key = digest(receipt['spec'])
                saved = json.loads((self.root / 'selections' / (key + '.json')).read_text())
                path = self.root / 'selections' / (key + '.csv')
                with path.open('rb') as stream:
                    checksum = hashlib.file_digest(stream, 'sha256').hexdigest()
                if saved.get('spec') != receipt['spec'] or saved.get('sha256') != receipt['sha256'] or checksum != receipt['sha256']:
                    raise ValueError('Previously verified CSV source or receipt changed')
            for url, expected in summary['root_hashes'].items():
                key = digest([self.snapshot, 99, validate_url(url, 99)])
                saved = json.loads((self.root / 'responses' / (key + '.json')).read_text())
                if saved['sha256'] != expected or digest(saved['body']) != expected or saved['snapshot'] != self.snapshot or validate_url(saved['url'], 99) != validate_url(url, 99):
                    raise ValueError('Previously verified JSON root changed')
            total_url = BASE + '/99?' + urlencode({'university': '1', 'year': row['period']})
            key = digest([self.snapshot, 99, validate_url(total_url, 99)])
            end = json.loads((self.root / 'bookends' / 'responses' / (key + '.json')).read_text())
            if (end['sha256'] != summary['root_hashes'][total_url] or digest(end['body']) != end['sha256'] or
                    end['snapshot'] != self.snapshot or validate_url(end['url'], 99) != validate_url(total_url, 99)):
                raise ValueError('Previously verified source bookend changed')

    def export(self, period, universities, studies):
        m = self.metadata
        filters = ['from:' + period, 'to:' + period] + ['uni:' + u for u in universities]
        filters += [o['value'] for o in m['genders']] + [o['value'] for o in m['ages']]
        filters += ['6.' + o['value'] for o in studies]
        receipt = self.source.export(99, filters, m['metadata_hash'])
        if receipt['status'] != 'data':
            raise ValueError('Technical/unconfirmed CSV export: ' + receipt['status'])
        actual = observations(receipt['rows'], m, period, universities, studies)
        allowed_study = {o['label'] for o in studies}
        if any(json.loads(k)[4].get('Program', 'Total') not in allowed_study for k in actual):
            raise ValueError('CSV ignored study-form scope')
        return actual, {k: v for k, v in receipt.items() if k not in ('rows', 'headers', 'cached')}

    def roots(self, period, actual):
        result = []; hashes = {}
        for gender in self.genders:
            for age in self.ages:
                q = {'university': '1', 'year': period}
                if gender != 'Total': q['gender'] = gender
                if age != 'Total': q['age_group'] = {'-24': '8', '25-34': '9', '35-': '10'}[age]
                if self.probe.requests + self.bookends.requests >= self.max_requests:
                    self.probe.budget = self.probe.requests
                url = BASE + '/99?' + urlencode(q)
                body = self.probe.get(url, 99)
                result.append(root_control(actual, body, period, gender, age, self.universities))
                hashes[url] = digest(body)
        return result, hashes

    def collect_year(self, period):
        if period not in self.periods:
            raise ValueError('Year is outside frozen collection plan')
        saved = self.db.execute('SELECT summary FROM years WHERE period=?', (period,)).fetchone()
        if saved:
            self.validate_staged(period)
            return {**json.loads(saved[0]), 'written_this_run': False}
        for client in (self.source, self.probe, self.bookends):
            client.session.deadline = time.monotonic() + self.max_seconds
        checkpoint = self.root / 'checkpoints' / (period.replace('/', '-') + '.json')
        evidence = {'period': period, 'binding_hash': digest(self.binding), 'publish_allowed': False,
                    'state': 'fetching', 'exports': [], 'comparisons': []}
        write_json(checkpoint, evidence)
        try:
            actual, receipt = self.export(period, self.universities, self.studies)
            evidence['exports'].append(receipt); evidence['observations'] = len(actual)
            write_json(checkpoint, evidence)
            half = (len(self.universities) + 1) // 2
            university_parts = []
            for universities in (self.universities[:half], self.universities[half:]):
                part, receipt = self.export(period, universities, self.studies)
                university_parts.append(part); evidence['exports'].append(receipt)
                write_json(checkpoint, evidence)
            evidence['comparisons'].append({'layout': 'disjoint-universities', **union_exact(university_parts, actual)})
            del university_parts
            study_parts = []
            for studies in (self.studies[::2], self.studies[1::2]):
                part, receipt = self.export(period, self.universities, studies)
                study_parts.append(part); evidence['exports'].append(receipt)
                write_json(checkpoint, evidence)
            evidence['comparisons'].append({'layout': 'disjoint-programs', **union_exact(study_parts, actual)})
            del study_parts
            evidence['coverage'], evidence['root_hashes'] = self.roots(period, actual)
            # Separate captures bracket source stability within this acquisition.
            url = BASE + '/99?' + urlencode({'university': '1', 'year': period})
            self.bookends.budget = max(self.bookends.requests, self.max_requests - self.probe.requests)
            end = self.bookends.get(url, 99)
            if digest(end) != evidence['root_hashes'][url]:
                raise ValueError('National root changed during year acquisition; new campaign required')
            evidence['root_stability_checked'] = True
            evidence['source_release_verified'] = False
            evidence['full_source_coverage_verified'] = False
            evidence['coverage_limit'] = 'Exact CSV layouts and all root controls; independent JSON leaf and suppression semantics remain unverified.'
            evidence['state'] = 'checked'
            write_json(checkpoint, evidence)
            rows = []
            for identity, value in actual.items():
                p, u, g, a, dims = json.loads(identity)
                payload = {'indicator': 99, 'period': p, 'university': u, 'gender': g, 'age': a, 'dimensions': dims, 'value': value}
                rows.append((digest([99, p, g, a, u, dims]), json.dumps(payload, ensure_ascii=False, sort_keys=True), evidence['exports'][0]['sha256']))
            rows.sort(); evidence['staging_sha256'] = rows_digest(rows)
            evidence['observed_universities'] = sorted({json.loads(k)[1] for k in actual})
            evidence['not_observed_universities'] = sorted(set(self.universities) - set(evidence['observed_universities']))
            evidence['value_markers'] = dict(Counter(v for v in actual.values() if v in ('', '..', '.', '-', '…') or v is None))
            evidence['state'] = 'staged'
            with self.db:
                self.db.execute('INSERT INTO years VALUES (?,?)', (period, json.dumps(evidence, ensure_ascii=False, sort_keys=True)))
                self.db.executemany('INSERT INTO observations VALUES (?,?,?,?)', ((k, period, p, h) for k, p, h in rows))
            write_json(checkpoint, evidence)
            return {**evidence, 'written_this_run': True}
        except Exception as error:
            evidence.update(state='blocked', error=str(error))
            write_json(checkpoint, evidence)
            raise

    def report(self):
        self.validate_staged()
        summaries = [json.loads(r[0]) for r in self.db.execute('SELECT summary FROM years ORDER BY period DESC')]
        report = {'indicator': 99, 'snapshot': self.snapshot, 'policy': POLICY, 'binding_hash': digest(self.binding),
                  'planned_years': self.periods, 'staged_years': len(summaries),
                  'observations': sum(y['observations'] for y in summaries),
                  'requested_universities': len(self.universities),
                  'years': [{k: y[k] for k in ('period', 'observations', 'staging_sha256', 'observed_universities', 'not_observed_universities', 'value_markers', 'root_stability_checked')} for y in summaries],
                  'new_exports_this_run': self.source.network_exports,
                  'new_json_requests_this_run': self.probe.requests + self.bookends.requests,
                  'all_planned_years_staged': len(summaries) == len(self.periods),
                  'full_source_coverage_verified': False, 'source_release_verified': False, 'publish_allowed': False,
                  'limitations': ['Independent JSON leaf equivalence is not verified for every cell', 'Unadvertised cells are not zeros', 'Suppression semantics require source documentation', 'No official immutable source release identifier']}
        write_json(self.root / 'collection-report.json', report)
        return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True); parser.add_argument('--snapshot', required=True)
    parser.add_argument('--metadata', required=True); parser.add_argument('--period', action='append', default=[])
    parser.add_argument('--all-years', action='store_true')
    parser.add_argument('--seconds', type=float, default=240)
    parser.add_argument('--max-new-exports', type=int, default=0); parser.add_argument('--max-new-requests', type=int, default=0)
    args = parser.parse_args()
    if args.all_years == bool(args.period) or min(args.max_new_exports, args.max_new_requests) < 0:
        parser.error('Select either --all-years or bounded --period; budgets cannot be negative')
    with Collection(args.root, json.loads(Path(args.metadata).read_text()), args.snapshot, args.max_new_exports, args.max_new_requests, args.seconds) as collection:
        try:
            for period in (collection.periods if args.all_years else args.period):
                r = collection.collect_year(period)
                print(json.dumps({k: r[k] for k in ('period', 'observations', 'staging_sha256', 'written_this_run')}, ensure_ascii=False), flush=True)
                if r['written_this_run']:
                    collection.report()
        finally:
            result = collection.report()
            print(json.dumps({k: v for k, v in result.items() if k not in ('years', 'planned_years')}, ensure_ascii=False), flush=True)
