"""Independent SCB API readback against the published workforce snapshot."""
import base64
from concurrent.futures import ThreadPoolExecutor
import gzip
import json
from fetch_employment import ROOT, request, decode


def verify(item):
    key, info, catalog = item
    selection = {k: list(v) for k, v in info['selection'].items()}
    for k, values in selection.items():
        if k == 'Region':
            selection[k] = [g for g in ['00', '25', '2580'] if g in values]
        elif k not in ['ContentsCode', 'Kon', 'Fodelseregion', 'Yrkesstallning']:
            selection[k] = list(dict.fromkeys([values[0], values[-1]]))
    query = {'selection': [{'variableCode': k, 'valueCodes': v} for k, v in selection.items()]}
    source = request(info['table'] + '/data?lang=sv&outputFormat=json-stat2', query)
    if source['updated'] != info['updated']:
        raise ValueError('Källversion ändrad: ' + key)
    cached = {}
    count = 0
    for f, value, flag in decode(source, selection):
        geo = f.get('Region', '00')
        if geo not in cached:
            filename = catalog['files'][key + '/geo-' + geo + '.json']['path']
            payload = json.loads((ROOT / 'public/data/workforce' / filename).read_bytes())
            rows = json.loads(gzip.decompress(base64.b64decode(payload['gzip'])))
            cached[geo] = {tuple(r[:5]): r[5:] for r in rows}
        rowkey = (f['Tid'], f['Kon'], f[info['group']], f.get('Alder', ''), f['ContentsCode'])
        if cached[geo].get(rowkey) != [value, flag]:
            raise ValueError(f'Kontrollvärde avviker: {key} {geo} {rowkey}')
        count += 1
    print('SCB readback verified', key, count, flush=True)
    return count


if __name__ == '__main__':
    catalog = json.loads((ROOT / 'src/data/workforce/catalog.json').read_bytes())
    with ThreadPoolExecutor(max_workers=2) as pool:
        counts = list(pool.map(verify, [(key, info, catalog) for key, info in catalog['datasets'].items()]))
    print('Independent SCB cells verified:', sum(counts))
