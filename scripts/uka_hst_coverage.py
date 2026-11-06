"""Audit HST queue observations against ordered source filter paths; never publishes."""
import argparse
from collections import Counter
import json
from pathlib import Path
import sqlite3

from uka_json_probe import SUBJECT_LEVELS
from uka_source_audit import write_json


def source_paths(options):
    """Keep the active UI parent path: a reused code never joins two branches."""
    stack, paths = [], []
    for option in options:
        token = option['value'].removeprefix('dynamic:')
        if token == 'TOTAL':
            continue
        node, parent = token.split('_', 1)
        if parent:
            positions = [i for i, item in enumerate(stack) if item['code'] == parent]
            if len(positions) != 1:
                raise ValueError('Source filter order does not identify an active parent')
            stack = stack[:positions[0] + 1]
        else:
            stack = []
        if len(stack) >= len(SUBJECT_LEVELS):
            raise ValueError('Unexpected subject hierarchy depth')
        stack.append({'code': node, 'label': option['label']})
        paths.append({'codes': [x['code'] for x in stack],
                      'dimensions': dict(zip(SUBJECT_LEVELS, [x['label'] for x in stack]))})
    keys = [json.dumps(p['dimensions'], sort_keys=True, ensure_ascii=False) for p in paths]
    if len(keys) != len(set(keys)):
        raise ValueError('Source filter labels do not uniquely identify a subject path')
    return paths


def audit(database, metadata):
    allowed = {json.dumps(p['dimensions'], sort_keys=True, ensure_ascii=False) for p in metadata['paths']}
    db = sqlite3.connect(f'file:{Path(database).resolve()}?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    try:
        binding = json.loads(db.execute('SELECT binding FROM meta').fetchone()[0])
        counts = dict(Counter(r[0] for r in db.execute('SELECT status FROM nodes')))
        keys, invalid, represented = set(), [], set()
        duplicates = 0; university_counts = Counter(); study_counts = Counter()
        for row in db.execute("SELECT dimensions,observations FROM nodes WHERE status='done'"):
            dims = json.loads(row['dimensions'])
            subject = {k: v for k, v in dims.items() if k in SUBJECT_LEVELS}
            key = json.dumps(subject, sort_keys=True, ensure_ascii=False)
            if subject and key not in allowed:
                invalid.append(dims)
            if subject:
                represented.add(key)
            study_counts[dims.get('Studieform', 'Total')] += 1
            for observation in json.loads(row['observations']):
                okey = json.dumps([observation['university'], observation['dimensions']],
                                 sort_keys=True, ensure_ascii=False)
                duplicates += okey in keys
                keys.add(okey); university_counts[observation['university']] += 1
        return {'binding': binding, 'states': counts, 'observations': len(keys),
                'duplicates': duplicates, 'invalid_source_subject_paths': invalid,
                'metadata_subject_paths': len(allowed), 'represented_subject_paths': len(represented),
                'unobserved_subject_paths': [json.loads(k) for k in sorted(allowed - represented)],
                'nodes_by_study': dict(study_counts), 'observations_by_university': dict(university_counts),
                'graph_closed': bool(counts) and set(counts) == {'done'},
                'full_source_coverage_verified': False, 'publish_allowed': False,
                'coverage_limit': 'Unadvertised selections are unresolved, not inferred as zero or legitimate empty. Metadata options can span periods and population groups.'}
    finally:
        db.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database', required=True)
    parser.add_argument('--metadata', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    result = audit(args.database, json.loads(Path(args.metadata).read_text()))
    write_json(Path(args.output), result)
    print(json.dumps({k: v for k, v in result.items() if k not in
                      ('unobserved_subject_paths', 'observations_by_university')}, ensure_ascii=False, indent=2))
    raise SystemExit(1 if result['duplicates'] or result['invalid_source_subject_paths'] else 0)
