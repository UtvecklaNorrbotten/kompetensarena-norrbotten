"""Durable per-year MUCF snapshots, resumed from a dedicated Git data branch."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import gzip
import hashlib
import json
from pathlib import Path
import threading
import time

from .source import Source, URL, discover, options, parse_table, queries

COLUMNS = ['geo_code', 'age', 'gender', 'origin', 'category', 'count', 'count_status',
           'count_raw', 'share', 'share_status', 'share_raw']
NOTES = [
    'MUCF:s registerbaserade UVAS-mått är inte Eurostats NEET-mått. Arbetsmarknadsåtgärder kan ingå.',
    'Master: andel av befolkningen i samma ålder, kön och födelsekategori. Övriga kategorier: andel av UVAS i motsvarande grupp.',
    'Prickar och stjärnor bevaras som null med status suppressed och originalmarkering; tomma celler får status missing. Noll är ett observerat värde.',
    'CKM från 2023: summerade delar kan avvika från publicerad total. Inga totaler eller andelar räknas fram.',
    'Gränspendling till Finland räknas bort från 2015; före dess endast Norge och Danmark. Tidsserier i gränskommuner kräver försiktighet.',
    'Kategorier får inte summeras utan stöd i MUCF:s metod. Ursprung korsas bara med total UVAS, enligt MUCF:s tillgängliga urval.',
    'Senast ändrad/ETag för webbsidan är ingen verifierad uppdateringstid för statistikunderlaget.',
]
LOCAL = threading.local()


def now():
    return datetime.now(timezone.utc).isoformat()


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = encode(data) + b'\n'
    if path.suffix == '.gz':
        raw = gzip.compress(raw, mtime=0)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_bytes(raw)
    temp.replace(path)


def read_json(path, fallback=None):
    if not path.exists():
        return fallback
    raw = path.read_bytes()
    return json.loads(gzip.decompress(raw) if path.suffix == '.gz' else raw)


def fetch_query(args):
    year, query = args
    key, geo, category, label, gender, origin = query
    if not hasattr(LOCAL, 'source'):
        LOCAL.source = Source()
    page = LOCAL.source.query(year, geo['county'], geo['city'], category, gender, origin)
    rows = parse_table(page, year, geo['code'], geo['label'], category, label, gender, origin)
    table = str(page.select_one('#results-wrapper'))
    return key, {'rows': rows, 'fetched_at': now(), 'source_table_sha256': hashlib.sha256(table.encode()).hexdigest(),
                 'table_html': table}


def complete_year(root, year, plan, results, cycle):
    expected = {q[0] for q in queries(plan)}
    if set(results) != expected:
        raise ValueError('Ofullständig årgång får inte aktiveras')
    rows = [row for key in sorted(results) for row in results[key]['rows']]
    if len({tuple(row[:5]) for row in rows}) != len(rows):
        raise ValueError('Dubblerade celler i årgång')
    snapshot = {'schema': 1, 'year': str(year), 'cycle': cycle, 'source_url': URL,
                'columns': COLUMNS, 'geographies': plan, 'notes': NOTES, 'rows': rows,
                'first_fetched_at': min(r['fetched_at'] for r in results.values()),
                'last_fetched_at': max(r['fetched_at'] for r in results.values())}
    # Content hash excludes retrieval timestamps so unchanged data do not republish.
    snapshot['data_sha256'] = hashlib.sha256(encode([plan, rows, NOTES])).hexdigest()
    write_json(root / 'snapshots' / f'{year}.json.gz', snapshot)
    return {'rows': len(rows), 'queries': len(expected), 'data_sha256': snapshot['data_sha256'],
            'completed_at': now(), 'cycle': cycle}


def collect(root, budget_minutes=290, sample=False):
    deadline = time.monotonic() + budget_minutes * 60
    state_path = root / 'state.json'
    state = read_json(state_path, {})
    if state.get('complete') and datetime.now(timezone.utc) - datetime.fromisoformat(state['completed_at']) < timedelta(days=7):
        print('MUCF: senaste fullständiga kontrollen är yngre än sju dagar.', flush=True)
        return state
    source = Source()
    page = source.bootstrap()
    years = sorted(options(page, '[column_1][year]'), reverse=True)
    regions = source.geography()
    if any(not y.isdigit() for y in years) or not years:
        raise ValueError('Felaktig årskatalog')
    if state and not set(state['years']) <= set(years):
        raise ValueError('MUCF har tagit bort tidigare årgångar; befintlig data behålls')
    # Start another full revision pass only seven days after a complete pass.
    # An incomplete pass always resumes, even across a weekly boundary.
    if state.get('complete'):
        fresh = datetime.now(timezone.utc) - datetime.fromisoformat(state['completed_at']) < timedelta(days=7)
        if fresh and state['years'] == years:
            print('MUCF: senaste fullständiga kontrollen är yngre än sju dagar.', flush=True)
            return state
        state = {}
    if not state:
        state = {'schema': 1, 'cycle': now(), 'years': years, 'completed_years': {}, 'complete': False}
    state['years'] = years
    write_json(state_path, state)
    try:
        for year in years[:1] if sample else years:
            if year in state['completed_years']:
                continue
            plan_path = root / 'pending' / f'{year}-plan.json'
            saved = read_json(plan_path, {})
            if saved.get('cycle') == state['cycle']:
                plan = saved['geographies']
            else:
                plan = discover(source, year, regions)
                write_json(plan_path, {'cycle': state['cycle'], 'geographies': plan})
            result_path = root / 'pending' / f'{year}-results.json.gz'
            saved = read_json(result_path, {})
            results = saved.get('queries', {}) if saved.get('cycle') == state['cycle'] else {}
            todo = [q for q in queries(plan) if q[0] not in results]
            # Small batches bound checkpoint loss; at most two source requests in flight.
            with ThreadPoolExecutor(max_workers=2) as pool:
                for offset in range(0, min(len(todo), 8) if sample else len(todo), 8):
                    if time.monotonic() >= deadline:
                        break
                    futures = [pool.submit(fetch_query, (year, q)) for q in todo[offset:offset + 8]]
                    failure = None
                    for future in futures:
                        try:
                            key, result = future.result()
                            results[key] = result
                        except Exception as exc:
                            failure = exc
                    write_json(result_path, {'cycle': state['cycle'], 'queries': results})
                    state['progress'] = {'year': year, 'done': len(results), 'expected': len(list(queries(plan)))}
                    write_json(state_path, state)
                    print(f'MUCF {year}: {len(results)}/{state["progress"]["expected"]} urval verifierade', flush=True)
                    if failure:
                        raise failure
            if len(results) == len(list(queries(plan))):
                state['completed_years'][year] = complete_year(root, year, plan, results, state['cycle'])
                write_json(state_path, state)
            if sample or time.monotonic() >= deadline:
                break
        state['complete'] = set(state['completed_years']) == set(years)
        if state['complete']:
            state['completed_at'] = now()
        state.pop('error', None)
    except Exception as exc:
        state['error'] = type(exc).__name__ + ': ' + str(exc)[:300]
        raise
    finally:
        state['last_checked_at'] = now()
        write_json(state_path, state)
        catalog = {'source_url': URL, 'columns': COLUMNS, 'notes': NOTES, 'available_years': years,
                   'cycle': state['cycle'], 'complete': state['complete'], 'last_checked_at': state['last_checked_at'],
                   'snapshots': {p.stem.split('.')[0]: read_json(p)['data_sha256']
                                 for p in (root / 'snapshots').glob('*.json.gz')},
                   'progress': state.get('progress'), 'error': state.get('error')}
        write_json(root / 'catalog.json', catalog)
    return state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--budget-minutes', type=float, default=290)
    parser.add_argument('--sample', action='store_true')
    args = parser.parse_args()
    collect(args.root, args.budget_minutes, args.sample)


if __name__ == '__main__':
    main()
