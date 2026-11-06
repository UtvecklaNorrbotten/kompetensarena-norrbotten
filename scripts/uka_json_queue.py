"""Single-writer, transactional UKÄ discovery queue. No publication capability."""
import argparse
from collections import Counter
from datetime import date
import fcntl
import json
from pathlib import Path
import sqlite3
import time
import requests

from uka_json_probe import Probe, SUBJECT_LEVELS, validate_follow, validate_url, yearly
from uka_source_audit import canonical_value, digest, write_json


def transient_error(error):
    if isinstance(error, requests.exceptions.SSLError):
        return False
    if isinstance(error, (requests.Timeout, requests.ConnectionError)):
        return True
    return (isinstance(error, requests.HTTPError) and error.response is not None and
            error.response.status_code in (408, 425, 429, 500, 502, 503, 504))


SOURCE_DIMENSIONS = {
    13: ('Program',), 31: ('Studieform',),
    33: (*SUBJECT_LEVELS, 'Studieform'), 97: ('Program',), 99: ('Program',),
    108: ('Examenskategori', 'Examen', 'Inriktning'), 136: ('Examen',),
    77: ('Utbildningsnivå', 'Studieform'), 134: ('Program',), 135: ('Program',),
}


class Queue:
    def __init__(self, path, root_url, snapshot, strategy="all-routes", indicator=33):
        if indicator not in SOURCE_DIMENSIONS:
            raise ValueError("Unsupported source indicator")
        if indicator != 33 and strategy != "all-routes":
            raise ValueError("Study-first strategy is verified only for HST")
        self.indicator = indicator
        self.source_dimensions = SOURCE_DIMENSIONS[indicator]
        if strategy not in ("all-routes", "study-first"):
            raise ValueError("Unknown discovery strategy")
        self.strategy = strategy
        root = validate_url(root_url, indicator)
        period = root['year']
        path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = open(str(path) + '.lock', 'a')
        try:
            fcntl.flock(self.lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.lock.close()
            raise ValueError('Another worker owns this queue')
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.root = root
        self.period = period
        binding = {'version': 1, 'root': self.root, 'snapshot': snapshot, 'indicator': self.indicator}
        if strategy != 'all-routes':
            binding['strategy'] = strategy
        if indicator != 33:
            binding['source_dimensions'] = list(self.source_dimensions)
        self.db.executescript('''
          CREATE TABLE IF NOT EXISTS meta (binding TEXT NOT NULL);
          CREATE TABLE IF NOT EXISTS nodes (
            id TEXT PRIMARY KEY, url TEXT NOT NULL, dimensions TEXT NOT NULL UNIQUE,
            status TEXT NOT NULL DEFAULT 'pending', value TEXT, source_hash TEXT,
            observations TEXT, error TEXT);
          CREATE TABLE IF NOT EXISTS edges (
            parent TEXT NOT NULL, child TEXT NOT NULL, expected TEXT NOT NULL,
            PRIMARY KEY(parent, child));
        ''')
        columns = {r['name'] for r in self.db.execute('PRAGMA table_info(nodes)')}
        for name, declaration in (('attempts', 'INTEGER NOT NULL DEFAULT 0'),
                                  ('retry_after', 'REAL'), ('error_kind', 'TEXT')):
            if name not in columns:
                self.db.execute(f'ALTER TABLE nodes ADD COLUMN {name} {declaration}')
        saved = self.db.execute('SELECT binding FROM meta').fetchone()
        if saved and json.loads(saved['binding']) != binding:
            self.close()
            raise ValueError('Queue selection or snapshot mismatch')
        with self.db:
            if not saved:
                self.db.execute('INSERT INTO meta VALUES (?)', (json.dumps(binding, sort_keys=True),))
            self.db.execute('INSERT OR IGNORE INTO nodes(id,url,dimensions) VALUES (?,?,?)',
                            (digest(self.root), root_url, '{}'))

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def close(self):
        self.db.close(); self.lock.close()

    def checkpoint(self, node, body):
        dims = json.loads(node['dimensions'])
        groups = body.get('groups')
        # Observed HST convention: institution-level terminal nodes omit groups.
        # Do not generalise this to missing root structure or national coverage.
        if ('groups' not in body and self.indicator == 33 and self.root['university'] != '1' and
                all(k in dims for k in self.source_dimensions)):
            groups = []
        if str(body.get('indicator', {}).get('id')) != str(self.indicator) or not isinstance(groups, list):
            raise ValueError('Incomplete or wrong source response')
        if any('value' not in row for row in body.get('yearly_totals', {}).get('totals', [])):
            raise ValueError('Missing source value field')
        series = yearly(body)
        if self.period not in series:
            raise ValueError('Requested period absent from source')
        value = series[self.period]
        observations = [{'university': self.root['university'], 'value': value, 'dimensions': dims}]
        children = []
        universities = set()
        for group in groups:
            column = group['column']
            if column == 'Lärosäten':
                for row in group.get('totals', []):
                    query = validate_url(row['url'], self.indicator)
                    university = query.get('university')
                    if not university or university == self.root['university'] or university in universities:
                        raise ValueError('Duplicate or invalid university observation')
                    if any(query.get(k) != validate_url(node['url'], self.indicator).get(k)
                           for k in ('year', 'gender', 'age_group', 'group_slug')):
                        raise ValueError('University link changed another context filter')
                    universities.add(university)
                    observations.append({'university': university, 'name': row['name'],
                                         'value': None if row['value'] is None else canonical_value(str(row['value'])),
                                         'dimensions': dims})
            elif column in self.source_dimensions:
                # Enumerate Study x Subject using Study selections at the root only.
                # Subject -> Study links are ambiguous for reused subject code 1051.
                # The original all-routes strategy and its blocked queue stay intact.
                if self.strategy == 'study-first' and column == 'Studieform' and dims:
                    continue
                if column in dims:
                    raise ValueError('Source reoffers selected dimension')
                for row in group.get('totals', []):
                    validate_follow(node['url'], row['url'], self.indicator)
                    expected = None if row['value'] is None else canonical_value(str(row['value']))
                    children.append((digest(validate_url(row['url'], self.indicator)), row['url'],
                                     json.dumps({**dims, column: row['name']}, ensure_ascii=False, sort_keys=True), expected))
            elif column not in ('Kön', 'Åldersgrupper'):
                raise ValueError('Unknown source dimension: ' + column)
        # Child insertion, source value and frontier changes commit together.
        with self.db:
            for edge in self.db.execute('SELECT expected FROM edges WHERE child=?', (node['id'],)):
                if json.loads(edge['expected']) != value:
                    raise ValueError('Parent and child source observations disagree')
            for child_id, url, dimensions, expected in children:
                existing = self.db.execute('SELECT * FROM nodes WHERE id=?', (child_id,)).fetchone()
                if existing and existing['dimensions'] != dimensions:
                    raise ValueError('Conflicting dimensions for one source URL')
                same_dims = self.db.execute('SELECT id FROM nodes WHERE dimensions=?', (dimensions,)).fetchone()
                if same_dims and same_dims['id'] != child_id:
                    raise ValueError('Different source URLs duplicate an observation key')
                if existing and existing['status'] == 'done' and json.loads(existing['value']) != expected:
                    raise ValueError('New edge disagrees with already validated child')
                self.db.execute('INSERT OR IGNORE INTO nodes(id,url,dimensions) VALUES (?,?,?)',
                                (child_id, url, dimensions))
                edge = self.db.execute('SELECT expected FROM edges WHERE parent=? AND child=?',
                                       (node['id'], child_id)).fetchone()
                if edge and json.loads(edge['expected']) != expected:
                    raise ValueError('Conflicting repeated source edge')
                self.db.execute('INSERT OR IGNORE INTO edges VALUES (?,?,?)',
                                (node['id'], child_id, json.dumps(expected)))
            self.db.execute("UPDATE nodes SET status='done',value=?,source_hash=?,observations=?,error=NULL,error_kind=NULL,retry_after=NULL WHERE id=?",
                            (json.dumps(value), digest(body), json.dumps(observations, ensure_ascii=False), node['id']))

    def run(self, probe, max_nodes=20, seconds=30):
        started = time.monotonic(); processed = 0; reason = 'graph_exhausted'
        with self.db:
            self.db.execute("UPDATE nodes SET status='pending' WHERE status='retry_wait' AND retry_after<=?", (time.time(),))
        while processed < max_nodes:
            if self.db.execute("SELECT 1 FROM nodes WHERE status='error' LIMIT 1").fetchone():
                reason = 'blocked_source_error'; break
            if time.monotonic() - started >= seconds:
                reason = 'time_budget'; break
            node = self.db.execute("SELECT * FROM nodes WHERE status='pending' ORDER BY rowid LIMIT 1").fetchone()
            if node is None:
                break
            try:
                body = probe.get(node['url'], self.indicator)
                self.checkpoint(node, body)
            except RuntimeError as error:
                if 'request budget exhausted' in str(error):
                    reason = 'request_budget'; break
                raise
            except Exception as error:
                retryable = transient_error(error)
                attempts = node['attempts'] + 1
                waiting = retryable and attempts < 3
                status = 'retry_wait' if waiting else 'error'
                kind = 'transient' if waiting else 'transient_exhausted' if retryable else 'permanent'
                next_try = time.time() + min(300, 30 * 2 ** (attempts - 1)) if waiting else None
                with self.db:
                    self.db.execute("UPDATE nodes SET status=?,error=?,error_kind=?,attempts=?,retry_after=? WHERE id=?",
                                    (status, str(error), kind, attempts, next_try, node['id']))
                reason = 'temporary_source_error' if waiting else 'source_error'; break
            processed += 1
        else:
            reason = 'node_budget'
        states = dict(Counter(r['status'] for r in self.db.execute('SELECT status FROM nodes')))
        if reason == 'graph_exhausted' and states.get('retry_wait'):
            reason = 'retry_backoff'
        done = self.db.execute("SELECT observations FROM nodes WHERE status='done'").fetchall()
        return {'indicator': self.indicator, 'strategy': self.strategy, 'stop_reason': reason, 'processed_this_run': processed, 'states': states,
                'observations': sum(len(json.loads(r['observations'])) for r in done),
                'university_codes': sorted({o['university'] for r in done for o in json.loads(r['observations'])}),
                'errors': [dict(r) for r in self.db.execute("SELECT url,error,error_kind,attempts,retry_after FROM nodes WHERE status IN ('error','retry_wait') LIMIT 10")],
                'graph_closed': all(status == 'done' for status in states),
                'publish_allowed': False, 'source_release_verified': False,
                'network_requests_this_run': probe.requests}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root-url', required=True)
    parser.add_argument('--indicator', type=int, choices=sorted(SOURCE_DIMENSIONS), default=33)
    parser.add_argument('--snapshot', default=date.today().isoformat())
    parser.add_argument('--strategy', choices=('all-routes', 'study-first'), default='all-routes')
    parser.add_argument('--database', default='output/uka-json-probe/queue.sqlite')
    parser.add_argument('--cache', default='output/uka-json-probe')
    parser.add_argument('--max-new-requests', type=int, default=0)
    parser.add_argument('--max-nodes', type=int, default=20)
    parser.add_argument('--seconds', type=float, default=30)
    args = parser.parse_args()
    if args.max_new_requests < 0 or args.max_nodes < 1 or args.seconds <= 0:
        parser.error('Invalid work budget')
    probe = Probe(args.cache, args.snapshot, budget=args.max_new_requests)
    with Queue(args.database, args.root_url, args.snapshot, strategy=args.strategy, indicator=args.indicator) as queue:
        result = queue.run(probe, args.max_nodes, args.seconds)
    write_json(Path(args.database).with_suffix('.summary.json'), result)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(1 if result['states'].get('error') else 75 if result['states'].get('retry_wait') else 0)
