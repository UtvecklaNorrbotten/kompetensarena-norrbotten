"""Verified public E3 read model. Source percentages and CKM totals are never recalculated."""
import base64
import datetime
import gzip
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import time
import urllib.request
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
import threading

ROOT = Path(__file__).resolve().parents[1]
API = 'https://statistikdatabasen.scb.se/api/v2/'
MEASURES = ['000008Q' + c for c in 'QPRSTUVW']
REQUEST_LOCK = threading.Lock()
NEXT_REQUEST = 0.0


def request(path, payload=None):
    global NEXT_REQUEST
    for attempt in range(6):
        try:
            with REQUEST_LOCK:
                time.sleep(max(0, NEXT_REQUEST - time.monotonic()))
                NEXT_REQUEST = time.monotonic() + 2.0
            req = urllib.request.Request(API + urllib.parse.quote(path, safe='/?=&'), data=json.dumps(payload).encode() if payload else None,
                                         headers={'Content-Type': 'application/json'})
            with urllib.request.urlopen(req, timeout=120) as response:
                result = json.load(response)
            time.sleep(1.1)
            return result
        except Exception as error:
            print(f'Retrying source request: {error}', flush=True)
            if attempt == 5:
                raise
            time.sleep(5 * (attempt + 1))


def decode(result):
    axes = [sorted(result['dimension'][k]['category']['index'],
                   key=result['dimension'][k]['category']['index'].get) for k in result['id']]
    size = math.prod(map(len, axes))
    assert size == math.prod(result['size'])
    values = result['value']
    assert not isinstance(values, list) or len(values) == size
    rows = {}
    for i, cell in enumerate(itertools.product(*axes)):
        d = dict(zip(result['id'], cell))
        key = (d['Region'], d['Utbildning'], d['KonAlderFodelseland'], d['Tid'], d['SNI2007'])
        value = values[i] if isinstance(values, list) else values.get(str(i))
        assert value is None or (isinstance(value, (int, float)) and math.isfinite(value))
        rows.setdefault(key, [None] * 8)[MEASURES.index(d['ContentsCode'])] = value
    return [[*k, *v] for k, v in rows.items()]


def main():
    meta = request('tables/TAB6929/metadata?lang=sv')
    catalog_path = ROOT / 'src/data/matching/catalog.json'
    if catalog_path.exists() and os.environ.get('FORCE_REFRESH') != 'true':
        previous = json.loads(catalog_path.read_text())
        files = [filename for group in ['summary', 'comparisons', 'flows'] for filename in previous.get(group, {}).values()]
        complete = len(previous.get('summary', {})) == 312 and files and all((ROOT / 'public/data/matching' / filename).is_file() for filename in files)
        if complete and previous['updated'] == meta['updated']:
            print('SCB metadata unchanged; retaining verified snapshot.')
            return
    dim = meta['dimension']
    regions = dim['Region']['category']['label']
    assert len(regions) == 312
    education = dim['Utbildning']['category']['label']
    periods = list(dim['Tid']['category']['index'])
    flow_geos = [g for g in regions if len(g) == 2 or g.startswith('25')]
    snapshots = {}
    # Checkpoints are outside the repository and tied to the full source metadata.
    cache = Path(os.environ.get('MATCHING_CACHE', '/tmp/kan-matching-cache')) / hashlib.sha256(json.dumps(meta, sort_keys=True).encode()).hexdigest()
    cache.mkdir(parents=True, exist_ok=True)

    def fetch_rows(geos, educations, branches, measures=MEASURES):
        selection = [
            {'variableCode': 'Region', 'valueCodes': geos},
            {'variableCode': 'Utbildning', 'valueCodes': educations},
            {'variableCode': 'SNI2007', 'valueCodes': branches},
            {'variableCode': 'KonAlderFodelseland', 'valueCodes': ['totalt', '1', '2'], 'codelist': 'vs_KonCKMRMI'},
            {'variableCode': 'ContentsCode', 'valueCodes': measures},
            {'variableCode': 'Tid', 'valueCodes': periods}]
        key = hashlib.sha256(json.dumps(selection).encode()).hexdigest()
        path = cache / (key + '.json')
        if not path.exists():
            result = request('tables/TAB6929/data?lang=sv&outputFormat=json-stat2', {'selection': selection})
            for item in selection:
                actual = result['dimension'][item['variableCode']]['category']['index']
                assert set(actual) == set(item['valueCodes'])
            rows = decode(result)
            assert len(rows) == len(geos) * len(educations) * len(branches) * 3 * len(periods)
            temporary = path.with_suffix('.tmp')
            temporary.write_text(json.dumps(rows, ensure_ascii=False, separators=(',', ':')))
            temporary.replace(path)
        return json.loads(path.read_text())

    def prepare(name, rows):
        raw = json.dumps(rows, ensure_ascii=False, separators=(',', ':')).encode()
        checksum = hashlib.sha256(raw).hexdigest()
        filename = f'{name}-{checksum[:16]}.json'
        snapshots[filename] = json.dumps({'gzip': base64.b64encode(gzip.compress(raw, mtime=0)).decode()}, separators=(',', ':'))
        return filename

    summary = {}
    period_rows = {p: [] for p in periods}
    geos = list(regions)
    batches = list(range(0, len(geos), 8))
    with ThreadPoolExecutor(max_workers=3) as pool:
        fetched = list(pool.map(lambda start: fetch_rows(geos[start:start + 8], list(education), ['A-U']), batches))
    for start, rows in zip(batches, fetched):
        for g in geos[start:start + 8]:
            own = [[r[1], r[2], r[3], *r[5:]] for r in rows if r[0] == g]
            summary[g] = prepare('geo-' + g, own)
        for r in rows:
            period_rows[r[3]].append([r[0], r[1], r[2], *r[5:]])
        print('Summary', start + len(geos[start:start + 8]), '/', len(geos), flush=True)
    comparisons = {p: prepare('period-' + p, rows) for p, rows in period_rows.items()}
    flows = {}
    branches = [b for b in dim['SNI2007']['category']['index'] if b != 'A-U']
    def fetch_flow(g):
        rows = fetch_rows([g], list(education), branches, MEASURES[:4])
        own = [r[1:] for r in rows]
        print('Flow', g, flush=True)
        return own
    with ThreadPoolExecutor(max_workers=3) as pool:
        fetched_flows = list(pool.map(fetch_flow, flow_geos))
    for g, own in zip(flow_geos, fetched_flows):
        flows[g] = prepare('flow-' + g, own)
    groups = {}
    for name, codelist in [('grupp', 'vs_UtbildningsgruppE2-3N1-2'), ('niva', 'vs_Utbildningsnivå19RMI'), ('inriktning', 'vs_Utbildningsinriktning19RMI')]:
        # Discover exact spelling from metadata rather than relying on a guessed code list.
        candidates = dim['Utbildning']['extension']['codelists']
        selected = next((c['id'] for c in candidates if c['id'] == codelist), None)
        if selected is None:
            selected = next(c['id'] for c in candidates if {'grupp': 'grupp', 'niva': 'nivå', 'inriktning': 'inriktning'}[name] in c['label'].lower())
        groups[name] = [v['code'] for v in request('codeLists/' + selected + '?lang=sv')['values']]
    catalog = {'table': 'TAB6929', 'source': 'https://www.statistikdatabasen.scb.se/pxweb/sv/ssd/START__AM__AM9906__AM9906B/RegionInd19E3CKM/',
               'updated': meta['updated'], 'fetched': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'regions': regions, 'education': education, 'groups': groups, 'periods': periods,
               'branches': dim['SNI2007']['category']['label'], 'measures': dim['ContentsCode']['category']['label'],
               'measureNotes': dim['ContentsCode']['category'].get('note', {}), 'notes': meta.get('note', []),
               'summary': summary, 'comparisons': comparisons, 'flows': flows}
    assert request('tables/TAB6929/metadata?lang=sv')['updated'] == meta['updated'], 'SCB changed during collection; retry before publishing.'
    # Only complete validated collections become visible to the app.
    out = ROOT / 'public/data/matching'
    out.mkdir(parents=True, exist_ok=True)
    for name, content in snapshots.items():
        (out / name).write_text(content)
    catalog_path.parent.mkdir(parents=True, exist_ok=True)
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, separators=(',', ':')) + '\n')
    for path in out.glob('*.json'):
        if path.name not in snapshots:
            path.unlink()


if __name__ == '__main__':
    main()
