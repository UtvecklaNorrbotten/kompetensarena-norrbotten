"""CSV-first source staging for the eight remaining UKÄ indicators.

No production connection. Missing rows are never generated. A period is committed
only after disjoint CSV partitions and every gender/age JSON root agree.
"""
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import threading
import fcntl
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import time
from urllib.parse import urlencode

from uka_99_full_csv import DeadlineSession, observation_key, union_exact
from uka_campaign import rows_digest
from uka_json_probe import BASE, Probe, validate_url, yearly
from uka_json_queue import SOURCE_DIMENSIONS
from uka_source_audit import Source, canonical_value, digest, write_json

# Ordered source levels, not inferred from the number of underscores in a token.
GROUP_LEVELS = {13: [('Program',)], 31: [('Studieform',)], 97: [('Program',)],
                108: [('Examenskategori', 'Examen', 'Inriktning')],
                136: [('Examen',)], 77: [('Studieform',), ('Utbildningsnivå',)],
                134: [('Program',)], 135: [('Program',)]}
POLICY = 'csv-all-universities-partitions-every-root-v1'


def paths(group, levels):
    options = group['values']; nodes = {}
    for o in options:
        token = o['value'].removeprefix('dynamic:')
        if token == 'TOTAL':
            continue
        code, parent = token.split('_', 1)
        nodes.setdefault(code, []).append((parent, o['label']))
    def ascend(code, parent, label, trail=()):
        if code in trail:
            raise ValueError('Cyclic source hierarchy')
        if not parent:
            return [[label]]
        if parent not in nodes:
            raise ValueError('Missing hierarchy parent')
        return [p + [label] for gp, name in nodes[parent]
                for p in ascend(parent, gp, name, trail + (code,))]
    result = [{}]
    for code, values in nodes.items():
        for parent, label in values:
            for names in ascend(code, parent, label):
                if len(names) > len(levels):
                    raise ValueError('Unrecognized hierarchy depth')
                result.append(dict(zip(levels, names)))
    return result


def validate_metadata(m, indicator, snapshot):
    if (indicator not in GROUP_LEVELS or m['indicator'] != indicator or m['snapshot'] != snapshot or
            m['metadata_hash'] != digest({k: v for k, v in m.items() if k != 'metadata_hash'})):
        raise ValueError('Wrong/changed metadata')
    if [g['index'] for g in m['groups']] != [f'{i+6}.' for i in range(len(GROUP_LEVELS[indicator]))]:
        raise ValueError('Unknown source dimension group')
    for key in ('universities', 'genders', 'ages', 'retained_periods'):
        if not m[key] or len({o['value'] for o in m[key]}) != len(m[key]):
            raise ValueError('Empty/ambiguous metadata scope')
    if {o['label'] for o in m['genders']} != {'Kvinnor', 'Män', 'Total'}:
        raise ValueError('Unexpected genders')
    if not {o['label'] for o in m['ages']} <= {'Total', '-24', '25-34', '35-'}:
        raise ValueError('Unknown source age')
    if 'uni:1' not in {o['value'] for o in m['universities']}:
        raise ValueError('Missing national scope')


def observations(rows, m, period, universities):
    indicator = m['indicator']; dims = SOURCE_DIMENSIONS[indicator]
    names = {o['label']: o['value'].removeprefix('uni:') for o in m['universities']}
    if len(names) != len(m['universities']):
        raise ValueError('Ambiguous university labels')
    allowed = [paths(g, levels) for g, levels in zip(m['groups'], GROUP_LEVELS[indicator])]
    genders = {o['label'] for o in m['genders']}; ages = {o['label'] for o in m['ages']}
    result = {}
    expected = {'Tidsperiod', 'Lärosäte', 'Kön', 'Åldersgrupp', 'Värde', *dims}
    for raw in rows:
        row = {re.sub(r'\[\d+\]$', '', k): v for k, v in raw.items()}
        if set(row) != expected or len(row) != len(raw):
            raise ValueError('Unexpected/duplicate CSV columns: ' + str(list(raw)))
        u = names.get(row['Lärosäte']) if row['Lärosäte'] else '1'
        if row['Tidsperiod'] != period or u not in universities or row['Kön'] not in genders or row['Åldersgrupp'] not in ages:
            raise ValueError('Unrequested CSV context')
        dimensions = {d: row[d] for d in dims if row[d]}
        for levels, valid in zip(GROUP_LEVELS[indicator], allowed):
            if {d: dimensions[d] for d in levels if d in dimensions} not in valid:
                raise ValueError('Invalid source hierarchy path')
        k = observation_key(period, u, row['Kön'], row['Åldersgrupp'], dimensions)
        if k in result:
            raise ValueError('Duplicate observation identity')
        result[k] = canonical_value(row['Värde'])
    if not result:
        raise ValueError('Empty CSV requires positive broader references')
    return result


def root_control(actual, body, indicator, period, gender, age, universities):
    if str(body.get('indicator', {}).get('id')) != str(indicator) or not isinstance(body.get('groups'), list):
        raise ValueError('Invalid root control')
    columns = [g['column'] for g in body['groups']]
    expected = {'Lärosäten', *(levels[0] for levels in GROUP_LEVELS[indicator])}
    if len(columns) != len(set(columns)) or not expected.issubset(columns):
        raise ValueError('Missing/duplicate root dimension lists')
    required = {observation_key(period, '1', gender, age, {}): yearly(body)[period]}
    advertised = {'1'}; dimension_lists = {}
    for group in body['groups']:
        col = group['column']
        if col not in (*SOURCE_DIMENSIONS[indicator], 'Lärosäten', 'Kön', 'Åldersgrupper'):
            raise ValueError('Unknown JSON dimension: ' + col)
        if col in ('Kön', 'Åldersgrupper'):
            continue
        seen = set()
        for r in group.get('totals', []):
            if 'value' not in r or r['name'] in seen:
                raise ValueError('Missing/duplicate root value')
            seen.add(r['name'])
            q = validate_url(r['url'], indicator)
            if col in ('Kön', 'Åldersgrupper'):
                continue
            if (q.get('year') != period or q.get('gender', 'Total') != gender or
                    q.get('age_group') != {'-24': '8', '25-34': '9', '35-': '10', 'Total': None}[age]):
                raise ValueError('JSON link changed context')
            if col == 'Lärosäten':
                u = q.get('university')
                if u not in universities or u in advertised or 'group_slug' in q:
                    raise ValueError('Invalid university control')
                advertised.add(u); dimensions = {}
            else:
                if q.get('university') != '1' or not q.get('group_slug'):
                    raise ValueError('Invalid dimension control')
                u = '1'; dimensions = {col: r['name']}
            key = observation_key(period, u, gender, age, dimensions)
            if key in required:
                raise ValueError('Duplicate root identity')
            required[key] = None if r['value'] is None else canonical_value(str(r['value']))
        if col in SOURCE_DIMENSIONS[indicator]:
            dimension_lists[col] = sorted(seen)
    for key, value in required.items():
        if key not in actual or actual[key] != value:
            raise ValueError('CSV missing/differing JSON control: ' + key + ' expected=' + str(value))
    selected = {k: v for k, v in actual.items() if json.loads(k)[2:4] == [gender, age]}
    if {json.loads(k)[1] for k in selected} != advertised:
        raise ValueError('University coverage differs from positive root list')
    for col, labels in dimension_lists.items():
        present = {json.loads(k)[4][col] for k in selected if json.loads(k)[1] == '1' and set(json.loads(k)[4]) == {col}}
        if present != set(labels):
            raise ValueError('National dimension coverage differs: ' + col)
    return {'gender': gender, 'age': age, 'native_controls': len(required),
            'advertised_universities': sorted(advertised), 'advertised_dimensions': dimension_lists,
            'not_advertised_universities': sorted(set(universities) - advertised),
            'absence_classification': 'verified_missing_combination_in_this_scope',
            'absence_meaning': 'Absent in both successful broad CSV and positive JSON root; no zero or causal explanation inferred.'}


class Collection:
    def __init__(self, root, metadata, snapshot, exports=0, requests=0, seconds=300):
        self.indicator = metadata['indicator']; validate_metadata(metadata, self.indicator, snapshot)
        if min(exports, requests) < 0 or seconds <= 0:
            raise ValueError('Invalid budget')
        self.root = Path(root); self.root.mkdir(parents=True, exist_ok=True)
        self.metadata = metadata; self.snapshot = snapshot; self.seconds = seconds
        self.periods = [o['value'].removeprefix('from:') for o in metadata['retained_periods']]
        self.universities = [o['value'].removeprefix('uni:') for o in metadata['universities']]
        self.binding = {'indicator': self.indicator, 'snapshot': snapshot, 'metadata_hash': metadata['metadata_hash'], 'policy': POLICY, 'periods': self.periods}
        self.lock = open(self.root / 'collection.lock', 'a')
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close(); raise ValueError('Another worker owns collection')
        self.db = sqlite3.connect(self.root / 'collection.sqlite'); self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.executescript('CREATE TABLE IF NOT EXISTS meta(binding TEXT NOT NULL); CREATE TABLE IF NOT EXISTS periods(period TEXT PRIMARY KEY, summary TEXT NOT NULL); CREATE TABLE IF NOT EXISTS observations(key TEXT PRIMARY KEY, period TEXT REFERENCES periods(period), payload TEXT NOT NULL, source_hash TEXT NOT NULL);')
        saved = self.db.execute('SELECT binding FROM meta').fetchone()
        if saved and json.loads(saved[0]) != self.binding:
            self.close(); raise ValueError('Collection manifest changed')
        if not saved:
            with self.db:
                self.db.execute('INSERT INTO meta VALUES (?)', (json.dumps(self.binding, sort_keys=True),))
        self.source = Source(self.root, snapshot); self.source.export_budget = exports
        self.probe = Probe(self.root, snapshot, requests)
        for client in (self.source, self.probe):
            client.session.close(); client.session = DeadlineSession(time.monotonic() + seconds)
        try:
            self.validate_staged()
        except Exception:
            self.close(); raise
        write_json(self.root / 'metadata.json', metadata); write_json(self.root / 'manifest.json', self.binding)

    def __enter__(self): return self
    def __exit__(self, *args): self.close()
    def close(self): self.db.close(); self.lock.close()

    def validate_staged(self):
        for row in self.db.execute('SELECT * FROM periods'):
            s = json.loads(row['summary'])
            staged = self.db.execute('SELECT key,payload,source_hash FROM observations WHERE period=? ORDER BY key', (row['period'],)).fetchall()
            if s['binding_hash'] != digest(self.binding) or s['period'] != row['period'] or len(staged) != s['observations'] or rows_digest(staged) != s['staging_sha256']:
                raise ValueError('Staged rows/manifest changed')
            for r in s['exports']:
                spec = r['spec']; key = digest(spec)
                if spec['indicator'] != self.indicator or spec['snapshot'] != self.snapshot or spec['metadata_hash'] != self.metadata['metadata_hash']:
                    raise ValueError('CSV source context changed')
                receipt = json.loads((self.root / 'selections' / (key + '.json')).read_text())
                raw = (self.root / 'selections' / (key + '.csv')).read_bytes()
                if spec != receipt['spec'] or receipt['sha256'] != r['sha256'] or hashlib.sha256(raw).hexdigest() != r['sha256']:
                    raise ValueError('CSV source evidence changed')
            for url, sha in s['root_hashes'].items():
                # budget=0 enforces proof from persisted sources, never refetches on corruption.
                p = Probe(self.root, self.snapshot, 0); body = p.get(url, self.indicator)
                if digest(body) != sha:
                    raise ValueError('JSON source evidence changed')
                p.session.close()

    def export(self, period, universities):
        m = self.metadata
        filters = ['from:' + period, 'to:' + period] + ['uni:' + u for u in universities]
        filters += [o['value'] for o in m['genders']] + [o['value'] for o in m['ages']]
        filters += [g['index'] + o['value'] for g in m['groups'] for o in g['values']]
        receipt = self.source.export(self.indicator, filters, m['metadata_hash'])
        if receipt['status'] != 'data':
            raise ValueError('Technical/unconfirmed CSV: ' + receipt['status'])
        return observations(receipt['rows'], m, period, universities), {k: v for k, v in receipt.items() if k not in ('rows', 'headers', 'cached')}

    def collect(self, period):
        if period not in self.periods: raise ValueError('Unplanned period')
        saved = self.db.execute('SELECT summary FROM periods WHERE period=?', (period,)).fetchone()
        if saved:
            self.validate_staged(); return {**json.loads(saved[0]), 'written_this_run': False}
        for c in (self.source, self.probe): c.session.deadline = time.monotonic() + self.seconds
        s = {'period': period, 'binding_hash': digest(self.binding), 'state': 'fetching', 'publish_allowed': False, 'exports': [], 'root_hashes': {}, 'coverage': []}
        checkpoint = self.root / 'checkpoints' / (period.replace('/', '-') + '.json')
        write_json(checkpoint, s)
        try:
            actual, receipt = self.export(period, self.universities); s['exports'].append(receipt)
            write_json(checkpoint, s)
            halves = (self.universities[::2], self.universities[1::2]); parts = []
            for codes in halves:
                part, receipt = self.export(period, codes); parts.append(part); s['exports'].append(receipt)
                write_json(checkpoint, s)
            s['partition_comparison'] = union_exact(parts, actual)
            controls = []
            for g in self.metadata['genders']:
                for a in self.metadata['ages']:
                    q = {'university': '1', 'year': period}
                    if g['label'] != 'Total': q['gender'] = g['label']
                    if a['label'] != 'Total': q['age_group'] = a['value'].removeprefix('age:')
                    controls.append((BASE + f'/{self.indicator}?' + urlencode(q), g['label'], a['label']))
            # Independent GETs use separate sessions. Reserve budget under a lock;
            # cached controls need no reservation. Every completed response is persisted.
            reservation = threading.Lock()
            def fetch_control(spec):
                url, gender, age = spec
                probe = Probe(self.root, self.snapshot, 0)
                probe.session.close()
                probe.session = DeadlineSession(self.probe.session.deadline)
                try:
                    try:
                        b = probe.get(url, self.indicator)
                    except RuntimeError as error:
                        if str(error) != 'JSON request budget exhausted': raise
                        with reservation:
                            if self.probe.requests >= self.probe.budget: raise
                            self.probe.requests += 1
                        probe.budget = 1
                        b = probe.get(url, self.indicator)
                    return url, b, root_control(actual, b, self.indicator, period, gender, age, self.universities)
                finally:
                    probe.session.close()
            with ThreadPoolExecutor(max_workers=3) as pool:
                for url, b, coverage in pool.map(fetch_control, controls):
                    s['root_hashes'][url] = digest(b); s['coverage'].append(coverage)
                    write_json(checkpoint, s)
            rows = []
            for key, value in actual.items():
                p,u,g,a,d = json.loads(key)
                payload = {'indicator': self.indicator, 'period': p, 'university': u, 'gender': g, 'age': a, 'dimensions': d, 'value': value}
                rows.append((digest([self.indicator,p,g,a,u,d]), json.dumps(payload, ensure_ascii=False, sort_keys=True), s['exports'][0]['sha256']))
            rows.sort(); s.update(state='staged', observations=len(rows), staging_sha256=rows_digest(rows),
                                 value_markers=dict(Counter(v for v in actual.values() if v in ('', '.', '..', '-', '…') or v is None)),
                                 observed_universities=sorted({json.loads(k)[1] for k in actual}),
                                 independent_leaf_coverage_verified=False, source_release_verified=False)
            with self.db:
                self.db.execute('INSERT INTO periods VALUES (?,?)', (period, json.dumps(s, ensure_ascii=False, sort_keys=True)))
                self.db.executemany('INSERT INTO observations VALUES (?,?,?,?)', ((k,period,p,h) for k,p,h in rows))
            write_json(checkpoint,s); return {**s,'written_this_run':True}
        except Exception as error:
            s.update(state='blocked', error=str(error), classification='technical_error' if isinstance(error, (OSError, RuntimeError)) else 'unresolved_validation_error')
            write_json(checkpoint,s); raise

    def report(self):
        self.validate_staged()
        summaries = [json.loads(r[0]) for r in self.db.execute('SELECT summary FROM periods ORDER BY period')]
        report = {'indicator':self.indicator,'snapshot':self.snapshot,'policy':POLICY,'binding':self.binding,
                  'planned_periods':self.periods,'staged_periods':len(summaries),'observations':sum(s['observations'] for s in summaries),
                  'periods':summaries,'new_exports':self.source.network_exports,'new_json_requests':self.probe.requests,
                  'all_planned_periods_staged':len(summaries)==len(self.periods),'publish_allowed':False,
                  'limitations':['CSV partitions may share source errors','Independent JSON detail equivalence is scoped separately','Missing rows are not zeros','Null/marker cause must be documented','No immutable source release ID verified']}
        write_json(self.root/'report.json',report); return report


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('--root',required=True); p.add_argument('--metadata',required=True); p.add_argument('--snapshot',required=True)
    p.add_argument('--period',action='append',default=[]); p.add_argument('--all-periods',action='store_true'); p.add_argument('--max-new-exports',type=int,default=0); p.add_argument('--max-new-requests',type=int,default=0); p.add_argument('--seconds',type=float,default=300)
    a=p.parse_args()
    if a.all_periods == bool(a.period): p.error('Choose explicit periods or all periods')
    with Collection(a.root,json.loads(Path(a.metadata).read_text()),a.snapshot,a.max_new_exports,a.max_new_requests,a.seconds) as c:
        try:
            for period in (c.periods if a.all_periods else a.period):
                s=c.collect(period); print(json.dumps({k:s[k] for k in ('period','observations','written_this_run')},ensure_ascii=False),flush=True)
                c.report()
        finally:
            r=c.report(); print(json.dumps({k:v for k,v in r.items() if k!='periods'},ensure_ascii=False),flush=True)
