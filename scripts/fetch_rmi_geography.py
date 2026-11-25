"""Publish bounded, source-verified U3 snapshots. No inferred totals or missing-value imputation."""
import datetime
import itertools
import hashlib
import json
import pathlib
import os
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
API = 'https://statistikdatabasen.scb.se/api/v2/'
MEASURES = ['000008Q' + c for c in 'GHIJKLMNO']


def get(path, payload=None):
    for attempt in range(5):
        try:
            request = urllib.request.Request(API + path, data=json.dumps(payload).encode() if payload else None,
                                            headers={'Content-Type': 'application/json', 'User-Agent': 'KompetensarenaNorrbotten/1.0'})
            with urllib.request.urlopen(request, timeout=120) as response:
                return json.load(response)
        except Exception:
            if attempt == 4:
                raise
            time.sleep(3 * (attempt + 1))


def main():
    meta = get('tables/TAB6928/metadata?lang=sv')
    previous = ROOT / 'src/data/rmi/catalog.json'
    if previous.exists() and os.environ.get('FORCE_REFRESH') != 'true':
        if json.loads(previous.read_text())['updated'] == meta['updated']:
            print('SCB:s uppdateringstid är oförändrad; befintlig verifierad version behålls.')
            return
    groups = get('codeLists/vs_Utbildningsgrupp19N?lang=sv')['values']
    labels = meta['dimension']['Region']['category']['label']
    regions = {k: v for k, v in labels.items() if k.startswith('25')}
    assert len(regions) == 15 and '25' in regions
    periods = list(meta['dimension']['Tid']['category']['index'])
    catalog = {'table': 'TAB6928', 'updated': meta['updated'], 'fetched': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'regions': regions, 'groups': {g['code']: g['label'] for g in groups}, 'periods': periods,
               'measures': MEASURES, 'notes': meta.get('note', [])}
    pending = {}
    # One geography per response: bounded to < 20 000 cells; county and municipalities use distinct codelists.
    for region in regions:
        selection = [
            {'variableCode': 'Region', 'valueCodes': [region], 'codelist': 'vs_CKM02Län' if region == '25' else 'vs_CKM03Kommun'},
            {'variableCode': 'Utbildngrupp', 'valueCodes': [g['code'] for g in groups], 'codelist': 'vs_Utbildningsgrupp19N'},
            {'variableCode': 'KonAlderFodelseland', 'valueCodes': ['totalt', '2', '1'], 'codelist': 'vs_KonCKMRMI'},
            {'variableCode': 'ContentsCode', 'valueCodes': MEASURES},
            {'variableCode': 'Tid', 'valueCodes': periods}]
        result = get('tables/TAB6928/data?lang=sv&outputFormat=json-stat2', {'selection': selection})
        dimensions = result['id']
        codes = [sorted(result['dimension'][key]['category']['index'], key=result['dimension'][key]['category']['index'].get) for key in dimensions]
        expected = 1
        for axis in codes:
            expected *= len(axis)
        assert expected == len(groups) * 3 * 9 * len(periods)
        values = result['value']
        assert not isinstance(values, list) or len(values) == expected
        records = {}
        for i, cell in enumerate(itertools.product(*codes)):
            d = dict(zip(dimensions, cell))
            key = (d['Utbildngrupp'], d['KonAlderFodelseland'], d['Tid'])
            row = records.setdefault(key, [None] * 9)
            value = values[i] if isinstance(values, list) else values.get(str(i))
            assert value is None or isinstance(value, (int, float))
            row[MEASURES.index(d['ContentsCode'])] = value
        pending[region] = [[*key, *value] for key, value in records.items()]
        print(region, len(records), flush=True)
    # Write only after all fifteen responses pass validation.
    out = ROOT / 'src/data/rmi'
    out.mkdir(parents=True, exist_ok=True)
    catalog['snapshots'] = {}
    for region, rows in pending.items():
        content = json.dumps(rows, ensure_ascii=False, separators=(',', ':')) + '\n'
        catalog['snapshots'][region] = hashlib.sha256(content.encode()).hexdigest()
        (out / f'{region}.json').write_text(content)
    (out / 'catalog.json').write_text(json.dumps(catalog, ensure_ascii=False, separators=(',', ':')) + '\n')


if __name__ == '__main__':
    main()
