"""Bounded, resumable validation campaign for HST; no publishing."""
import argparse
import json
from pathlib import Path
import time
from urllib.parse import urlencode

from uka_hst_complete_probe import traverse
from uka_json_probe import BASE, Probe
from uka_json_queue import Queue
from uka_source_audit import digest, write_json


def cases():
    result = []
    for period in ('2024/25', '2025/26'):
        for gender in ('Total', 'Kvinnor', 'Män'):
            for age in ('Total', '8', '9', '10'):
                query = {'university': '171', 'year': period}
                if gender != 'Total':
                    query['gender'] = gender
                if age != 'Total':
                    query['age_group'] = age
                result.append({'period': period, 'gender': gender, 'age': age,
                               'root_url': BASE + '/33?' + urlencode(query)})
    return result


def run(root, snapshot, budget=400, seconds=480):
    root = Path(root); started = time.monotonic(); requests = 0
    report = {'snapshot': snapshot, 'university': '171', 'publish_allowed': False,
              'full_source_coverage_verified': False, 'cases': []}
    for case in cases():
        if time.monotonic() - started >= seconds:
            break
        probe = Probe(root, snapshot, budget=max(0, budget - requests))
        database = root / 'validation' / (digest(case) + '.sqlite')
        with Queue(database, case['root_url'], snapshot, 'study-first') as queue:
            result = queue.run(probe, max_nodes=100, seconds=max(0.1, seconds - (time.monotonic() - started)))
            observations = {row['dimensions']: json.loads(row['value']) for row in
                            queue.db.execute("SELECT dimensions,value FROM nodes WHERE status='done'")}
        requests += probe.requests
        comparison = False
        if result['graph_closed']:
            # A second traversal may only use saved source responses.
            reference, _ = traverse(Probe(root, snapshot, budget=0), case['root_url'])
            if reference != observations:
                raise ValueError('Campaign observations differ from all-routes reference')
            comparison = True
        report['cases'].append({**case, **result, 'exact_reference_comparison': comparison,
                                'source_total': observations.get('{}')})
        report.update(new_requests=requests, completed_cases=sum(c['exact_reference_comparison'] for c in report['cases']),
                      planned_cases=24)
        report['campaign_closed'] = report['completed_cases'] == 24
        write_json(root / 'hst-validation.json', report)
        print(json.dumps({**case, 'states': result['states'], 'observations': result['observations'],
                          'exact_reference_comparison': comparison}, ensure_ascii=False), flush=True)
        if result['states'].get('error') or result['states'].get('retry_wait'):
            break
        if not result['graph_closed']:
            break
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', required=True)
    parser.add_argument('--snapshot', required=True)
    parser.add_argument('--max-new-requests', type=int, default=400)
    parser.add_argument('--seconds', type=float, default=480)
    args = parser.parse_args()
    if args.max_new_requests < 0 or args.seconds <= 0:
        parser.error('Invalid validation budget')
    r = run(args.cache, args.snapshot, args.max_new_requests, args.seconds)
    raise SystemExit(1 if any(c['states'].get('error') for c in r['cases']) else
                     75 if any(c['states'].get('retry_wait') for c in r['cases']) else 0)
