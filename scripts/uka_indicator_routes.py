"""Read-only observations and dimension routes for the nine non-HST indicators."""
import argparse
import json
from pathlib import Path
from urllib.parse import urlencode

from uka_json_probe import BASE, Probe, CONTEXT, edge_value, validate_url, yearly
from uka_source_audit import canonical_value, write_json

SCALARS = {'Lärosäten', 'Kön', 'Åldersgrupper'}


def university_reference(probe, url, body, indicator):
    rows = [r for g in body.get('groups', []) if g['column'] == 'Lärosäten'
            for r in g.get('totals', [])]
    if not rows:
        return {'verified': False, 'reason': 'No advertised university observation'}
    row = next((r for r in rows if validate_url(r['url'], indicator).get('university') == '32'), rows[0])
    before, after = validate_url(url, indicator), validate_url(row['url'], indicator)
    if any(before.get(k) != after.get(k) for k in (*CONTEXT, 'group_slug') if k != 'university'):
        raise ValueError('University link changed another selection')
    if not after.get('university') or after['university'] == before['university']:
        raise ValueError('Invalid university transition')
    child = probe.get(row['url'], indicator)
    actual = yearly(child)[before['year']]
    expected = None if row['value'] is None else canonical_value(str(row['value']))
    if actual != expected:
        raise ValueError('University observation differs from direct source reference')
    return {'verified': True, 'university': after['university'], 'name': row['name'],
            'value': actual, 'url': row['url']}


def run(cache, snapshot, inventory, budget=80):
    probe = Probe(cache, snapshot, budget=budget)
    report = {'snapshot': snapshot, 'publish_allowed': False, 'full_coverage_verified': False,
              'scope': 'First advertised dimension path and direct university observation; not exhaustive', 'indicators': []}
    for item in inventory['indicators']:
        indicator = item['id']
        if indicator == 33:
            continue
        result = {'indicator': indicator, 'periods': []}
        for period in dict.fromkeys((item['periods'][0], item['periods'][-1])):
            url = BASE + f'/{indicator}?' + urlencode({'university': '1', 'year': period})
            body = probe.get(url, indicator)
            series = yearly(body)
            if period not in series:
                raise ValueError('Requested period missing')
            case = {'period': period, 'source_total': series[period], 'root_url': url,
                    'dimension_columns': [g['column'] for g in body.get('groups', []) if g['column'] not in SCALARS],
                    'university_reference': university_reference(probe, url, body, indicator), 'route': []}
            selected = set()
            for depth in range(3):
                groups = [g for g in body.get('groups', []) if g['column'] not in SCALARS and
                          g['column'] not in selected and g.get('totals')]
                if not groups:
                    break
                group = groups[0]; row = group['totals'][0]
                child = probe.get(row['url'], indicator)
                value = edge_value(url, row['url'], child, row['value'], indicator)
                case['route'].append({'column': group['column'], 'name': row['name'],
                                      'value': value, 'url': row['url']})
                selected.add(group['column']); url, body = row['url'], child
            case['group_university_reference'] = university_reference(probe, url, body, indicator)
            case['verified_sample'] = bool(case['route']) and case['university_reference']['verified'] and case['group_university_reference']['verified']
            result['periods'].append(case)
        report['indicators'].append(result)
        report['new_requests'] = probe.requests
        report['verified_period_samples'] = sum(p['verified_sample'] for i in report['indicators'] for p in i['periods'])
        write_json(Path(cache) / 'indicator-routes.json', report)
        print(json.dumps({'indicator': indicator, 'periods': [p['period'] for p in result['periods']],
                          'routes': [[r['column'] for r in p['route']] for p in result['periods']]}, ensure_ascii=False), flush=True)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', required=True)
    parser.add_argument('--snapshot', required=True)
    parser.add_argument('--inventory', default='docs/uka-source-inventory-2026-11-06.json')
    parser.add_argument('--max-new-requests', type=int, default=80)
    args = parser.parse_args()
    report = run(args.cache, args.snapshot, json.loads(Path(args.inventory).read_text()), args.max_new_requests)
    raise SystemExit(0 if report['verified_period_samples'] == 18 else 1)
