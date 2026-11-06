"""Bounded HST CSV bulk/reference pilot. Read only; never publishes."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sqlite3

from uka_json_probe import BASE, Probe, validate_url, yearly
from uka_source_audit import Source, canonical_value, write_json

COLUMNS = {'Tidsperiod', 'Lärosäte', 'Kön', 'Åldersgrupp', 'Studieform',
           'Ämnesområde', 'Ämnesdelområde', 'Ämnesgrupp', 'Värde'}
DIMENSIONS = ('Studieform', 'Ämnesområde', 'Ämnesdelområde', 'Ämnesgrupp')


def observations(rows, metadata, period, universities, subject_paths=None):
    """Keep source hierarchy and source totals; value is never part of the key."""
    names = {}
    for option in metadata['universities']:
        code = option['value'].removeprefix('uni:')
        if code in universities:
            if option['label'] in names and names[option['label']] != code:
                raise ValueError('Ambiguous source university label')
            names[option['label']] = code
    allowed_paths = ({json.dumps(p['dimensions'], ensure_ascii=False, sort_keys=True) for p in subject_paths}
                     if subject_paths is not None else None)
    ages = {o['label'] for o in metadata['ages']}
    result = {}
    for raw in rows:
        row = {re.sub(r'\[\d+\]$', '', k): v for k, v in raw.items()}
        if set(row) != COLUMNS or len(row) != len(raw):
            raise ValueError('Unexpected or duplicate CSV dimension headers')
        university = names.get(row['Lärosäte']) if row['Lärosäte'] else '1'
        if row['Tidsperiod'] != period or university not in universities:
            raise ValueError('CSV returned an unrequested period or university')
        if row['Kön'] not in ('Kvinnor', 'Män', 'Total') or row['Åldersgrupp'] not in ages:
            raise ValueError('CSV returned an unknown gender or age')
        dims = {k: row[k] for k in DIMENSIONS if row[k]}
        subject = {k:v for k,v in dims.items() if k != 'Studieform'}
        if subject and allowed_paths is not None and json.dumps(subject, ensure_ascii=False, sort_keys=True) not in allowed_paths:
            raise ValueError('CSV subject hierarchy does not match source metadata')
        key = json.dumps([period, university, row['Kön'], row['Åldersgrupp'], dims], ensure_ascii=False, sort_keys=True)
        if key in result:
            raise ValueError('Duplicate CSV observation key, regardless of value')
        result[key] = canonical_value(row['Värde'])
    if not result:
        raise ValueError('Empty CSV needs separate positive reference evidence')
    return result


def compare(reference, actual):
    changes = [{'key': json.loads(k), 'reference': reference[k], 'actual': actual[k]}
               for k in reference.keys() & actual.keys() if reference[k] != actual[k]]
    return {'exact': reference == actual, 'reference_observations': len(reference),
            'actual_observations': len(actual), 'only_reference': len(reference.keys() - actual.keys()),
            'only_actual': len(actual.keys() - reference.keys()), 'different_values': changes[:20]}


def queue_reference(database, university=None):
    db = sqlite3.connect(f'file:{Path(database).resolve()}?mode=ro', uri=True); db.row_factory = sqlite3.Row
    try:
        binding = json.loads(db.execute('SELECT binding FROM meta').fetchone()[0]); q = binding['root']
        if {r[0] for r in db.execute('SELECT status FROM nodes')} != {'done'}:
            raise ValueError('Incomplete JSON reference graph')
        result = {}
        for row in db.execute('SELECT observations FROM nodes'):
            for observation in json.loads(row['observations']):
                if university and observation['university'] != university:
                    continue
                key = json.dumps([q['year'], observation['university'], q.get('gender', 'Total'),
                                  {'8': '-24', '9': '25-34', '10': '35-'}.get(q.get('age_group'), 'Total'),
                                  observation['dimensions']], ensure_ascii=False, sort_keys=True)
                if key in result:
                    raise ValueError('Duplicate JSON reference observation')
                result[key] = observation['value']
        return result
    finally:
        db.close()


def run(root, metadata, json_cache, snapshot, max_new_exports=0):
    root = Path(root); source = Source(root, snapshot); exports = {}; evidence = []
    source.export_budget = max_new_exports
    subject_paths = json.loads(Path('docs/uka-hst-subject-paths-2026-11-06.json').read_text())['paths']
    groups = [g['index'] + option['value'] for g in metadata['groups'] for option in g['values']]
    report = {'snapshot': snapshot, 'publish_allowed': False, 'full_coverage_verified': False,
              'exports': evidence, 'comparisons': [], 'empty_selection_evidence': []}
    specs = [('riket', '2025/26', ['1']), ('ltu', '2025/26', ['32']),
             ('small', '2025/26', ['171']), ('mixed', '2025/26', ['1', '32', '171']),
             ('old-riket', '2016/17', ['1']), ('old-ltu', '2016/17', ['32']),
             ('old-mixed', '2016/17', ['1', '32', '171'])]
    for name, period, universities in specs:
        filters = ['from:' + period, 'to:' + period] + ['uni:' + u for u in universities]
        filters += [o['value'] for o in metadata['genders']] + [o['value'] for o in metadata['ages']] + groups
        result = source.export(33, filters, metadata['metadata_hash'])
        evidence.append({'case': name, 'period': period, 'universities': universities,
                         **{k: result.get(k) for k in ('status', 'row_count', 'bytes', 'sha256', 'file_url')}})
        write_json(root / 'bulk-reference.json', report)
        if result['status'] != 'data':
            raise ValueError('Bulk source export failed: ' + name)
        exports[name] = observations(result['rows'], metadata, period, universities, subject_paths)
    for prefix, singles in (('', ('riket', 'ltu', 'small')), ('old-', ('old-riket', 'old-ltu'))):
        union = {}
        for name in singles:
            if union.keys() & exports[name].keys():
                raise ValueError('Duplicate observation between disjoint university chunks')
            union.update(exports[name])
        comparison = compare(exports[prefix + 'mixed'], union)
        report['comparisons'].append({'test': prefix + 'mixed-vs-university-chunks', **comparison})
        if not comparison['exact']:
            raise ValueError('Mixed and partitioned CSV observations differ')
    small_json = {}
    for database in (Path(json_cache) / 'validation').glob('*.sqlite'):
        part = queue_reference(database, '171')
        part = {k: v for k, v in part.items() if json.loads(k)[0] == '2025/26'}
        if small_json.keys() & part.keys():
            raise ValueError('Duplicate reference across age/gender cases')
        small_json.update(part)
    report['comparisons'].append({'test': 'small-all-genders-ages-vs-json', **compare(exports['small'], small_json)})
    national = Path(json_cache) / 'national-study-first.sqlite'
    for name, university in (('riket', '1'), ('ltu', '32')):
        reference = queue_reference(national, university)
        selected = {k: v for k, v in exports[name].items() if json.loads(k)[2:4] == ['Kvinnor', '-24']}
        report['comparisons'].append({'test': name + '-women-under25-vs-json', **compare(selected, reference)})
    controls = Probe(json_cache, snapshot, budget=0)
    for period, country_case in (('2025/26', 'riket'), ('2016/17', 'old-riket')):
        root_url = BASE + '/33?university=1&year=' + period.replace('/', '%2F')
        country = controls.get(root_url, 33)
        key = json.dumps([period, '1', 'Total', 'Total', {}], ensure_ascii=False, sort_keys=True)
        report['comparisons'].append({'test': country_case + '-native-grand-total',
            **compare({key: yearly(country)[period]}, {key: exports[country_case][key]})})
        if period == '2025/26':
            for code, name in (('32', 'ltu'), ('171', 'small')):
                row = next(r for g in country['groups'] if g['column'] == 'Lärosäten'
                           for r in g['totals'] if validate_url(r['url'], 33)['university'] == code)
                key = json.dumps([period, code, 'Total', 'Total', {}], ensure_ascii=False, sort_keys=True)
                report['comparisons'].append({'test': name + '-native-grand-total',
                    **compare({key: canonical_value(str(row['value']))}, {key: exports[name][key]})})
    parent = controls.get(BASE + '/33?university=1&year=2016%2F17', 33)
    university_codes = {validate_url(r['url'], 33)['university'] for g in parent.get('groups', [])
                        if g['column'] == 'Lärosäten' for r in g['totals']}
    old_codes = {json.loads(k)[1] for k in exports['old-mixed']}
    report['empty_selection_evidence'].append({'period': '2016/17', 'university': '171',
        'absent_from_successful_explicit_mixed_csv': '171' not in old_codes,
        'absent_from_broader_json_university_list': '171' not in university_codes,
        'meaning': 'Evidence of no advertised observations in this scope; no zero values generated. Direct empty/500 responses remain technical errors.'})
    report['empty_selection_evidence'][0]['verified_by_broader_positive_references'] = ('171' not in old_codes and '171' not in university_codes)
    report['all_comparisons_passed'] = all(c['exact'] for c in report['comparisons'])
    report['network_exports'] = source.network_exports
    write_json(root / 'bulk-reference.json', report)
    if not report['all_comparisons_passed']:
        raise ValueError('CSV/JSON reference mismatch')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True)
    parser.add_argument('--metadata', required=True)
    parser.add_argument('--json-cache', required=True)
    parser.add_argument('--snapshot', required=True)
    parser.add_argument('--max-new-exports', type=int, default=0)
    args = parser.parse_args()
    result = run(args.root, json.loads(Path(args.metadata).read_text()), args.json_cache, args.snapshot, args.max_new_exports)
    print(json.dumps(result, ensure_ascii=False, indent=2))
