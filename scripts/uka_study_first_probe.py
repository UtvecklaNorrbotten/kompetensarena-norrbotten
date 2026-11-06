"""Compare study-first HST discovery with cached references. Never publishes."""
import argparse
import json
from pathlib import Path
import tempfile
from urllib.parse import urlencode

from uka_hst_complete_probe import traverse
from uka_json_probe import BASE, Probe, yearly
from uka_json_queue import Queue
from uka_source_audit import write_json


def unique(body, column, name):
    matches = [row for group in body.get('groups', []) if group['column'] == column
               for row in group['totals'] if row['name'] == name]
    if len(matches) != 1:
        raise ValueError(f'Expected one {column}/{name}, got {len(matches)}')
    return matches[0]


def verify(probe, output):
    report = {'publish_allowed': False, 'full_coverage_verified': False,
              'small_graph_comparisons': [], 'parent_context_checks': []}
    with tempfile.TemporaryDirectory() as tmp:
        for age in (None, '8', '9', '10'):
            query = {'university': '171', 'year': '2025/26', 'gender': 'Kvinnor'}
            if age:
                query['age_group'] = age
            url = BASE + '/33?' + urlencode(query)
            reference, _ = traverse(probe, url)
            with Queue(Path(tmp) / (str(age) + '.sqlite'), url, probe.snapshot, 'study-first') as queue:
                result = queue.run(probe, max_nodes=100)
                actual = {row['dimensions']: json.loads(row['value']) for row in
                          queue.db.execute("SELECT dimensions,value FROM nodes WHERE status='done'")}
                if not result['graph_closed'] or actual != reference:
                    raise ValueError('Study-first differs from complete reference observations')
                report['small_graph_comparisons'].append({'age': age or 'Total',
                    'observations': len(actual), 'exact_keys_and_values_equal': True,
                    'source_total': actual['{}']})
    # These are source-advertised routes, not guessed or rewritten group slugs.
    url = BASE + '/33?' + urlencode({'university': '1', 'year': '2025/26',
                                     'gender': 'Kvinnor', 'age_group': '8'})
    root = probe.get(url, 33)
    study = unique(root, 'Studieform', 'Fristående kurser')
    study_body = probe.get(study['url'], 33)
    expected = {'Medicin och odontologi': ('38.1', {'Biomedicinsk laboratorievetenskap',
                'Medicinska tekniker', 'Övrigt inom medicin'}),
                'Naturvetenskap': ('56.2', {'Husdjursvetenskap', 'Livsmedelsvetenskap',
                'Övrigt inom naturvetenskap'})}
    for area, (value, names) in expected.items():
        area_row = unique(study_body, 'Ämnesområde', area)
        area_body = probe.get(area_row['url'], 33)
        other = unique(area_body, 'Ämnesdelområde', 'Övrigt')
        child = probe.get(other['url'], 33)
        actual_names = {row['name'] for group in child.get('groups', [])
                        if group['column'] == 'Ämnesgrupp' for row in group['totals']}
        actual_value = yearly(child)['2025/26']
        if actual_names != names or actual_value != value:
            raise ValueError('Source parent context or reference value changed')
        report['parent_context_checks'].append({'area': area, 'study': study['name'],
            'subarea': 'Övrigt', 'value': actual_value, 'url': other['url'],
            'subject_groups': sorted(actual_names)})
    report['new_requests'] = probe.requests
    write_json(Path(output), report)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache', required=True)
    parser.add_argument('--snapshot', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--max-new-requests', type=int, default=0)
    args = parser.parse_args()
    report = verify(Probe(args.cache, args.snapshot, budget=args.max_new_requests), args.output)
    print(json.dumps(report, ensure_ascii=False, indent=2))
