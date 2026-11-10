"""Offline verification of a complete indicator-99 restart package."""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3
from unittest.mock import patch

from uka_99_full_csv import Collection
from uka_99_values import observations
from uka_csv_bulk_probe import compare, queue_reference
from uka_source_audit import parse_csv


def verify(root):
    root = Path(root).resolve()
    inventory = json.loads((root / 'checksums.json').read_text())
    for relative, expected in inventory.items():
        path = (root / relative).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            raise ValueError('Missing or unsafe package file: ' + relative)
        with path.open('rb') as stream:
            actual = hashlib.file_digest(stream, 'sha256').hexdigest()
        if actual != expected:
            raise ValueError('Package checksum changed: ' + relative)
    metadata = json.loads((root / 'collection-99/metadata/99.json').read_text())
    # A hard network prohibition proves that zero budgets did not hide requests.
    with patch('requests.sessions.Session.request', side_effect=AssertionError('Network prohibited')):
        with Collection(root / 'collection-99', metadata, '2026-11-10') as c:
            before = {r[0]: json.loads(r[1])['staging_sha256'] for r in c.db.execute('SELECT period,summary FROM years')}
            if set(before) != set(c.periods):
                raise ValueError('Incomplete ten-year collection')
            for period in c.periods:
                result = c.collect_year(period)
                if result['written_this_run'] or result['staging_sha256'] != before[period]:
                    raise ValueError('Zero-budget resume changed staging')
            report = c.report()
            if report['new_exports_this_run'] or report['new_json_requests_this_run'] or report['publish_allowed']:
                raise ValueError('Unexpected source activity or publication')
    source = parse_csv((root / 'reference-99/original.csv').read_bytes())
    old_csv = observations(source['rows'], metadata, 'HT2026', ['1', '32'])
    old_csv = {k: v for k, v in old_csv.items() if json.loads(k)[2] == 'Total'}
    old_json = {k: v for k, v in queue_reference(root / 'reference-99/99.sqlite').items() if json.loads(k)[1] in ('1', '32')}
    reference = compare(old_csv, old_json)
    if len(old_csv) != 66 or not reference['exact']:
        raise ValueError('Frozen 66-observation reference differs')
    def staged(path):
        db = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
        try:
            if db.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
                raise ValueError('SQLite integrity failure')
            result = {}
            for row in db.execute('SELECT payload FROM observations'):
                x = json.loads(row[0])
                if x['period'] != 'HT2026':
                    continue
                key = json.dumps([x['period'], x['university'], x['gender'], x['age'], x['dimensions']], ensure_ascii=False, sort_keys=True)
                result[key] = x['value']
            return result
        finally:
            db.close()
    revision = compare(staged(root / 'reference-99/old-staging/campaign.sqlite'), staged(root / 'collection-99/99-full.sqlite'))
    if not revision['exact'] or revision['actual_observations'] != 1337:
        raise ValueError('Old full staging differs from new campaign')
    return {'verified_files': len(inventory), 'periods': len(before), 'observations': report['observations'],
            'new_requests': 0, 'new_exports': 0, 'new_insertions': 0,
            'staging_checksums_unchanged': True, 'reference_66': reference, 'revision_1337': revision,
            'publish_allowed': False}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', required=True)
    args = p.parse_args()
    print(json.dumps(verify(args.root), ensure_ascii=False, indent=2))
