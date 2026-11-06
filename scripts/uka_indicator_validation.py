"""Bounded national JSON graph validation for the nine non-HST indicators."""
import argparse
import json
from pathlib import Path
import time
from urllib.parse import urlencode

from uka_json_probe import BASE, Probe
from uka_json_queue import Queue
from uka_source_audit import write_json


def run(cache, snapshot, inventory, budget=1000, seconds=600):
    root = Path(cache); started = time.monotonic(); requests = 0
    report = {'snapshot': snapshot, 'publish_allowed': False, 'full_source_coverage_verified': False,
              'planned_indicators': 9, 'indicators': [], 'new_requests': 0, 'completed_indicators': 0}
    write_json(root / 'indicator-validation.json', report)
    for item in inventory['indicators']:
        indicator = item['id']
        if indicator == 33:
            continue
        if time.monotonic() - started >= seconds:
            break
        period = item['periods'][0]
        url = BASE + f'/{indicator}?' + urlencode({'university': '1', 'year': period})
        probe = Probe(root, snapshot, budget=max(0, budget - requests))
        with Queue(root / 'indicator-validation' / f'{indicator}.sqlite', url, snapshot, indicator=indicator) as queue:
            result = queue.run(probe, max_nodes=300, seconds=max(0.1, seconds - (time.monotonic() - started)))
        requests += probe.requests
        report['indicators'].append({'indicator': indicator, 'period': period, 'gender': 'Total', 'age': 'Total', **result})
        report.update(new_requests=requests, completed_indicators=sum(i['graph_closed'] for i in report['indicators']))
        write_json(root / 'indicator-validation.json', report)
        print(json.dumps(report['indicators'][-1], ensure_ascii=False), flush=True)
        if result['stop_reason'] in ('request_budget', 'time_budget'):
            break
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', required=True)
    parser.add_argument('--snapshot', required=True)
    parser.add_argument('--inventory', default='docs/uka-source-inventory-2026-11-06.json')
    parser.add_argument('--max-new-requests', type=int, default=1000)
    parser.add_argument('--seconds', type=float, default=600)
    args = parser.parse_args()
    if args.max_new_requests < 0 or args.seconds <= 0:
        parser.error('Invalid work budget')
    result = run(args.cache, args.snapshot, json.loads(Path(args.inventory).read_text()), args.max_new_requests, args.seconds)
    raise SystemExit(1 if any(i['states'].get('error') for i in result['indicators']) else
                     75 if any(i['states'].get('retry_wait') for i in result['indicators']) else 0)
