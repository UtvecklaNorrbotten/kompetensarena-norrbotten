"""Read-only AGD/AGI source investigation. Python stdlib; no production access."""
import argparse
import collections
import csv
import datetime as dt
import hashlib
import json
import pathlib
import re
import shutil
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = 'https://skatteverket.entryscape.net'
API = BASE + '/rowstore/dataset/b72fcfe9-cacf-4859-8f57-38357f6306b0'
CSV_URL = BASE + '/store/26/resource/22'
FIELDS = {'period', 'uppdateringsdatum', 'gruppering', 'statistikterm', 'antal',
          'belopp', 'grupperingsvärde', 'inkomstar', 'ar_manad'}
KEY = ('ar_manad', 'inkomstar', 'period', 'statistikterm', 'gruppering', 'grupperingsvärde')
MUNICIPALITIES = ['ARJEPLOG', 'ARVIDSJAUR', 'BODEN', 'GÄLLIVARE', 'HAPARANDA',
                  'JOKKMOKK', 'KALIX', 'KIRUNA', 'LULEÅ', 'PAJALA', 'PITEÅ',
                  'ÄLVSBYN', 'ÖVERKALIX', 'ÖVERTORNEÅ']
TERMS = ['Bruttolön utom förmåner', 'Lönesumma', 'Summa avgifter att betala']


def open_url(url, accept='*/*'):
    for attempt in range(4):
        try:
            return urllib.request.urlopen(urllib.request.Request(
                url, headers={'User-Agent': 'Kompetensarena-source-probe/1.0', 'Accept': accept}), timeout=60)
        except urllib.error.HTTPError as exc:
            if exc.code not in (429, 500, 502, 503, 504) or attempt == 3:
                raise
        except (urllib.error.URLError, TimeoutError):
            if attempt == 3:
                raise
        time.sleep(2 ** attempt)


def get_json(url):
    accept = 'application/ld+json' if '/store/' in url else 'application/json'
    with open_url(url, accept) as response:
        return json.load(response)


def save_json(path, value):
    pathlib.Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def fetch_rows(filters, getter=get_json):
    """Fail on truncation, changed counts, wrong filters or duplicate observations."""
    if set(filters) - FIELDS:
        raise ValueError('Unknown filters: ' + str(set(filters) - FIELDS))
    rows, offset, expected, seen = [], 0, None, set()
    while True:
        url = API + '?' + urllib.parse.urlencode({**filters, '_limit': 500, '_offset': offset})
        page = getter(url)
        count = page['resultCount']
        if expected is None:
            expected = count
        if count != expected or page['offset'] != offset:
            raise ValueError('Dataset changed during pagination, or incorrect offset')
        batch = page['results']
        if len(batch) > 500 or (not batch and offset < count):
            raise ValueError('Truncated/invalid API page')
        for row in batch:
            if set(row) != FIELDS:
                raise ValueError('Source schema changed')
            for field, expression in filters.items():
                # Our probes use only exact alternatives, not partial-match syntax.
                if row[field] not in expression.split('|'):
                    raise ValueError('Server did not apply filter: ' + field)
            key = tuple(row[k] for k in KEY)
            if key in seen:
                raise ValueError('Duplicate observation across pages')
            seen.add(key)
        rows.extend(batch)
        offset += len(batch)
        if offset == count:
            return rows
        if offset > count or offset > 100000:
            raise ValueError('Invalid count or probe exceeds 100,000 rows')


def inventory(path):
    groups = collections.defaultdict(set)
    periods = collections.defaultdict(set)
    terms = collections.defaultdict(lambda: {'groups': set(), 'periods': set()})
    updates = collections.defaultdict(set)
    numeric_tokens = collections.Counter()
    n = 0
    with open(path, encoding='cp1252', newline='') as handle:
        reader = csv.DictReader(handle)
        if {k.lower() for k in reader.fieldnames} != FIELDS:
            raise ValueError('CSV schema changed')
        for raw in reader:
            row = {k.lower(): v for k, v in raw.items()}
            n += 1
            groups[row['gruppering']].add(row['grupperingsvärde'])
            periods[row['ar_manad']].add(row['period'] or row['inkomstar'])
            terms[row['statistikterm']]['groups'].add(row['gruppering'])
            if row['ar_manad'] == 'Månad':
                terms[row['statistikterm']]['periods'].add(row['period'])
            updates[row['inkomstar']].add(row['uppdateringsdatum'])
            for field in ('antal', 'belopp'):
                if not re.fullmatch(r'-?\d+', row[field]):
                    numeric_tokens[field + ':' + row[field]] += 1
    if n == 0:
        raise ValueError('Empty CSV')
    return {'rows': n, 'group_values': {k: sorted(v) for k, v in sorted(groups.items())},
            'period_ranges': {k: [min(v), max(v)] for k, v in periods.items()},
            'terms': {k: {'groups': sorted(v['groups']),
                          'monthly_range': [min(v['periods']), max(v['periods'])] if v['periods'] else None}
                      for k, v in sorted(terms.items())},
            'updates_by_year': {k: sorted(v) for k, v in updates.items()},
            'nonnumeric_tokens': dict(numeric_tokens)}


def default_period(today):
    # Two calendar months back is a candidate, never a completeness guarantee.
    index = today.year * 12 + today.month - 1 - 2
    return f'{index // 12:04d}{index % 12 + 1:02d}'


def period_status(period, updated):
    end = (dt.date(int(period[:4]) + (period[4:] == '12'),
                   int(period[4:]) % 12 + 1, 1) - dt.timedelta(days=1))
    days = (dt.date.fromisoformat(updated) - end).days
    return {'days_after_month_end_at_source_update': days,
            'status': 'immature' if days < 33 else 'candidate_not_verified_complete'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--period', default=default_period(dt.date.today()))
    parser.add_argument('--output', default='artifacts/agi-probe')
    parser.add_argument('--inventory-csv', help='Use already downloaded official CSV')
    args = parser.parse_args()
    if not re.fullmatch(r'20\d{2}(0[1-9]|1[0-2])', args.period):
        parser.error('period must be YYYYMM')
    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    before = get_json(BASE + '/store/26/resource/27')
    save_json(output / 'distribution-before.json', before)
    swagger = get_json(API + '/swagger')
    save_json(output / 'swagger.json', swagger)
    params = {p['name'] for p in next(iter(swagger['paths'].values()))['get']['parameters']}
    if not FIELDS <= params:
        raise ValueError('Swagger missing expected fields')
    with tempfile.TemporaryDirectory() as temp:
        csv_path = args.inventory_csv or str(pathlib.Path(temp) / 'source.csv')
        if not args.inventory_csv:
            with open_url(CSV_URL) as response, open(csv_path, 'wb') as handle:
                shutil.copyfileobj(response, handle)
        discovered = inventory(csv_path)
        save_json(output / 'inventory.json', discovered)
    common = {'period': args.period, 'ar_manad': 'Månad', 'statistikterm': '|'.join(TERMS)}
    queries = {
        'norrbotten': {**common, 'gruppering': 'Län', 'grupperingsvärde': 'NORRBOTTEN'},
        'municipalities-norrbotten': {**common, 'gruppering': 'Kommun', 'grupperingsvärde': '|'.join(MUNICIPALITIES)},
        'municipalities-national': {**common, 'gruppering': 'Kommun'},
        'branches': {**common, 'gruppering': 'Bransch'},
        'sizes': {**common, 'gruppering': 'Antal anställda'},
        'national-current-year': {'inkomstar': args.period[:4], 'ar_manad': 'Månad',
                                  'statistikterm': 'Lönesumma', 'gruppering': 'Total'},
        'annual-norrbotten': {'inkomstar': str(int(args.period[:4]) - 1), 'ar_manad': 'År',
                              'statistikterm': 'Lönesumma', 'gruppering': 'Län', 'grupperingsvärde': 'NORRBOTTEN'},
        # OR returns marginal rows; it cannot produce a geographical/industry cross-tab.
        'grouping-or': {**common, 'statistikterm': 'Lönesumma', 'gruppering': 'Län|Bransch'},
    }
    counts = {}
    extracts = {}
    for name, query in queries.items():
        rows = fetch_rows(query)
        if not rows:
            raise ValueError('Empty expected extraction: ' + name)
        counts[name] = len(rows)
        extracts[name] = rows
        save_json(output / (name + '.json'), {'filters': query, 'rows': rows})
        print(name + ': ' + str(len(rows)), flush=True)
    found = {r['grupperingsvärde'] for r in extracts['municipalities-norrbotten']}
    if found != set(MUNICIPALITIES):
        raise ValueError('Missing Norrbotten municipalities: ' + str(set(MUNICIPALITIES) - found))
    after = get_json(BASE + '/store/26/resource/27')
    save_json(output / 'distribution-after.json', after)
    if before != after:
        raise ValueError('Source distribution changed during investigation; rerun')
    national = extracts['national-current-year']
    summary = {'checked_at_utc': dt.datetime.now(dt.timezone.utc).isoformat(),
               'candidate_period': args.period, 'api': API, 'counts': counts,
               'csv_inventory_rows': discovered['rows'],
               'available_latest_month': max(r['period'] for r in national),
               'freshness': {r['period']: period_status(r['period'], r['uppdateringsdatum']) for r in national},
               'source_hash': hashlib.sha256(json.dumps(before, sort_keys=True).encode()).hexdigest(),
               'technical_probe': 'passed', 'ready_for_dashboard': False,
               'limitations': ['Geography is registered seat/address, not workplace.',
                               'API contains one grouping per row; no region x industry cube.',
                               'No source completeness flag; latest period must not drive trends.',
                               'SNI 2007 changes to SNI 2025 in 2026.',
                               'API monthly history before 2019 conflicts with portal definition.']}
    save_json(output / 'summary.json', summary)
    report = ('# Skatteverket AGD/AGI – tekniskt prov\n\n'
              f'Tekniskt prov godkänt. Kandidatmånad: {args.period}.\n\n'
              '**Inte godkänt för automatisk dashboard-publicering.** '\
              'Geografi avser säte/adress och månaders fullständighet måste kontrolleras.\n\n'
              '| Uttag | Rader |\n| --- | ---: |\n' +
              ''.join(f'| {name} | {count} |\n' for name, count in counts.items()))
    (output / 'summary.md').write_text(report, encoding='utf-8')
    print(report)


if __name__ == '__main__':
    main()
