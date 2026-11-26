"""Publish only complete, hash-verified years through the existing period-batch API."""
import argparse
import hashlib
import math
from pathlib import Path

from etl_scb_bas import Client
from .collect import encode, now, read_json, write_json

SOURCE = 'mucf-uvas'
INDICATORS = {'count': 'mucf-uvas-antal', 'share': 'mucf-uvas-andel'}


def observations(snapshot, measure):
    offset = 5 if measure == 'count' else 8
    for row in snapshot['rows']:
        geo, age, sex, origin, category = row[:5]
        dimensions = {
            'alder_code': age, 'alder_label': age + ' år',
            'kon_code': {'Kvinnor': '2', 'Män': '1', 'Totalt': '1+2'}[sex], 'kon_label': sex,
            'fodelseregion_code': {'Inrikesfödd': 'inrikes', 'Utrikesfödd': 'utrikes', 'Totalt': 'tot'}[origin],
            'fodelseregion_label': origin, 'kategori_code': category,
            'kategori_label': next(g['categories'][category] for g in snapshot['geographies'] if g['code'] == geo),
            'value_status': row[offset + 1], 'source_value': row[offset + 2],
            'denominator': 'befolkning' if category == 'Master' else 'uvas',
            'source_table': 'MUCF UVAS', 'rojandeskydd': 'CKM' if int(snapshot['year']) >= 2023 else 'sekretess',
        }
        yield {'geo_code': geo, 'period': snapshot['year'], 'value': row[offset], 'dimensions': dimensions}


def verified_snapshot(path, expected_year):
    snapshot = read_json(path)
    if snapshot['year'] != expected_year or snapshot['schema'] != 1:
        raise ValueError('Fel årgång eller snapshotformat')
    actual = hashlib.sha256(encode([snapshot['geographies'], snapshot['rows'], snapshot['notes']])).hexdigest()
    if actual != snapshot['data_sha256']:
        raise ValueError('MUCF-snapshotens kontrollsumma stämmer inte')
    return snapshot


def publish(root, client=None, before_collection=False):
    client = client or Client()
    # This verifies that the registration is deployed; never silently skip DB errors.
    client.etl('source-state?source_id=' + SOURCE)
    state = read_json(root / 'state.json', {})
    catalog = read_json(root / 'catalog.json', {})
    registry = read_json(root / 'published.json', {})
    details = {'collection_complete': state.get('complete', False), 'collection_progress': state.get('progress'),
               'available_years': state.get('years', []), 'published_years': sorted(registry),
               'data_branch': 'data/mucf-uvas', 'source_updated_at': None}
    initialized = {}
    try:
        for year in sorted(catalog.get('snapshots', {}), reverse=True):
            snapshot = verified_snapshot(root / 'snapshots' / f'{year}.json.gz', year)
            if snapshot['data_sha256'] != catalog['snapshots'][year]:
                raise ValueError('Katalogens kontrollsumma stämmer inte')
            year_state = registry.setdefault(year, {})
            for measure, indicator in INDICATORS.items():
                if year_state.get(measure) == snapshot['data_sha256']:
                    continue
                rows = list(observations(snapshot, measure))
                chunks = math.ceil(len(rows) / 5000)
                if not chunks:
                    raise ValueError('Tom MUCF-årgång')
                if indicator not in initialized:
                    remote = client.etl('etl-state?indicator_id=' + indicator)
                    initialized[indicator] = bool(remote.get('last_successful_at') or remote.get('hamtad_datum'))
                # A period batch requires an active base. Only the first ever
                # publication uses full; never infer this from a local checkpoint.
                mode = 'replace_period' if initialized[indicator] else 'full'
                batch = client.etl('etl-batch/start', {
                    'indicator_id': indicator, 'source': 'MUCF', 'mode': mode,
                    **({'replace_period': year} if mode == 'replace_period' else {}), 'expected_rows': len(rows), 'expected_chunks': chunks,
                }, retry_safe=False)
                batch_id = batch['batch_id']
                try:
                    for index in range(chunks):
                        client.etl('etl-batch/chunk', {'batch_id': batch_id, 'indicator_id': indicator,
                                   'chunk_index': index, 'observations': rows[index * 5000:(index + 1) * 5000]})
                    client.etl('etl-batch/finalize', {'batch_id': batch_id})
                    batch_id = None
                    initialized[indicator] = True
                    year_state[measure] = snapshot['data_sha256']
                    write_json(root / 'published.json', registry)
                    print(f'MUCF: {indicator}, {year}, {len(rows)} rader publicerade', flush=True)
                finally:
                    if batch_id:
                        client.etl('etl-batch/abort', {'batch_id': batch_id, 'reason': 'MUCF-publicering avbruten'})
        details['published_years'] = sorted(y for y, values in registry.items()
                                            if len(values) == len(INDICATORS))
        if state.get('error') and not before_collection:
            raise ValueError('Källhämtningen är ofullständig: ' + state['error'])
        complete = state.get('complete', False) and set(details['published_years']) == set(state.get('years', []))
        client.etl('source-state', {'source_id': SOURCE, 'status': 'succeeded' if complete else 'ready',
                   'latest_available_period': max(state.get('years', [''])),
                   **({'latest_successful_period': max(details['published_years'])} if complete else {}),
                   'details': details})
    except Exception as exc:
        client.etl('source-state', {'source_id': SOURCE, 'status': 'failed',
                   'error_message': str(exc)[:300], 'details': details})
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--before-collection', action='store_true')
    args = parser.parse_args()
    publish(args.root, before_collection=args.before_collection)


if __name__ == '__main__':
    main()
