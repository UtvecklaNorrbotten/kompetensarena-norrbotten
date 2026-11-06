"""Read-only gate between an explicit HST CSV package and completed staging.

A verified university subset never completes a national campaign selection.
No staging rows, job states, production data or publication flags are changed.
"""
import argparse
import json
from pathlib import Path
import sqlite3

from uka_campaign import rows_digest
from uka_csv_bulk_probe import observations, compare
from uka_source_audit import Source, digest, write_json


def audit(actual, database, snapshot, period):
    db = sqlite3.connect(f'file:{Path(database).resolve()}?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    try:
        binding = json.loads(db.execute('SELECT binding FROM meta').fetchone()[0])
        if binding['indicator'] != 33 or binding['snapshot'] != snapshot:
            raise ValueError('CSV and staging indicator/snapshot differ')
        for key in actual:
            if json.loads(key)[0] != period:
                raise ValueError('CSV contains another period')
        comparisons = []
        for job in db.execute("SELECT * FROM jobs WHERE status='done' ORDER BY ordinal"):
            spec = json.loads(job['spec'])
            if spec['period'] != period:
                continue
            summary = json.loads(job['summary'])
            rows = db.execute('SELECT key,payload,source_hash FROM observations WHERE job_id=? ORDER BY key', (job['id'],)).fetchall()
            if rows_digest(rows) != summary['staging_sha256']:
                raise ValueError('Previously staged observations changed')
            reference = {}
            for row in rows:
                p = json.loads(row['payload'])
                context = [p['period'], p['gender'], p['age']]
                if (context != [period, spec['gender'], spec['age']] or p['indicator'] != 33 or
                        row['key'] != digest([33, *context, p['university'], p['dimensions']])):
                    raise ValueError('Staged observation key or selection changed')
                key = json.dumps([period, p['university'], p['gender'], p['age'], p['dimensions']], ensure_ascii=False, sort_keys=True)
                if key in reference:
                    raise ValueError('Duplicate staged observation identity')
                reference[key] = p['value']
            selected = {k:v for k,v in actual.items() if json.loads(k)[2:4] == [spec['gender'], spec['age']]}
            shared = reference.keys() & selected.keys()
            matched = sum(reference[k] == selected[k] for k in shared)
            comparisons.append({'job_id': job['id'], 'period': period, 'gender': spec['gender'], 'age': spec['age'],
                **compare(reference, selected), 'shared_observations': len(shared), 'identical_shared_values': matched,
                'national_selection_equivalent': reference == selected,
                'csv_university_codes': sorted({json.loads(k)[1] for k in selected}),
                'reference_university_codes': sorted({json.loads(k)[1] for k in reference})})
        if not comparisons:
            raise ValueError('No completed staging reference for this CSV period')
        return {'indicator': 33, 'snapshot': snapshot, 'period': period, 'plan_id': binding['plan_id'],
                'comparisons': comparisons, 'publish_allowed': False, 'staging_written': False,
                'all_national_references_equivalent': all(c['national_selection_equivalent'] for c in comparisons),
                'meaning': 'University-subset agreement cannot complete a national campaign job. No import performed.'}
    finally:
        db.close()


def run(root, metadata, database, snapshot, period, universities, output):
    source = Source(root, snapshot); source.export_budget = 0
    filters = ['from:' + period, 'to:' + period] + ['uni:' + u for u in universities]
    filters += [v['value'] for v in metadata['genders']] + [v['value'] for v in metadata['ages']]
    filters += [g['index'] + v['value'] for g in metadata['groups'] for v in g['values']]
    exported = source.export(33, filters, metadata['metadata_hash'])
    if exported['status'] != 'data':
        raise ValueError('CSV source package is not valid data')
    paths = json.loads(Path('docs/uka-hst-subject-paths-2026-11-06.json').read_text())['paths']
    actual = observations(exported['rows'], metadata, period, universities, paths)
    report = audit(actual, database, snapshot, period)
    report.update(csv_sha256=exported['sha256'], csv_observations=len(actual), new_exports=source.network_exports)
    write_json(Path(output), report)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('root', 'metadata', 'database', 'snapshot', 'period', 'output'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--universities', nargs='+', required=True)
    args = parser.parse_args()
    print(json.dumps(run(args.root, json.loads(Path(args.metadata).read_text()), args.database,
                         args.snapshot, args.period, args.universities, args.output), ensure_ascii=False, indent=2))
