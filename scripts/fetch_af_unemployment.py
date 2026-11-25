"""Build bounded public AF read models from the existing ETL's original XLSX sources.

No person records. Numerator and denominator always come from the same BAS row.
Snapshots are written only after source, coverage and reconciliation checks pass.
"""
from __future__ import annotations
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import tempfile
from urllib.parse import urljoin
import xml.etree.ElementTree as ET
import zipfile
import requests
import openpyxl

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'src/data/af'
SOURCE = 'https://arbetsformedlingen.se/statistik/sok-statistik/tidigare-statistik-tidsserier'
NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
# Exact source field pairs. Older age labels are not assumed to have a fixed upper bound.
PAIRS = [
 ('total', '', 'TOT'), ('total', 'K', 'KVI'), ('total', 'M', 'MAN'),
 ('young', '', 'UNG'), ('young', 'K', 'UNGK'), ('young', 'M', 'UNGM'),
 ('older', '', 'GAM'), ('older', 'K', 'GAMK'), ('older', 'M', 'GAMM'),
 ('domestic', '', 'INR'), ('domestic', 'K', 'INRK'), ('domestic', 'M', 'INRM'),
 ('foreign', '', 'UTR'), ('foreign', 'K', 'UTRK'), ('foreign', 'M', 'UTRM'),
 ('pre', '', 'FG'), ('pre', 'K', 'FGK'), ('pre', 'M', 'FGM'),
 ('upper', '', 'GY'), ('upper', 'K', 'GYK'), ('upper', 'M', 'GYM'),
 ('post', '', 'EG'), ('post', 'K', 'EGK'), ('post', 'M', 'EGM'),
]

def geography():
    text = (ROOT / 'drizzle/migrations/0014_apply_af_geographies_and_indicators.sql').read_text()
    records = re.findall(r"\('([0-9]+)','([^']+)','(riket|län|kommun)',(null|'[0-9]+')\)", text)
    result = {c: {'name': n, 'level': l, 'parent': p.strip("'") if p != 'null' else None} for c,n,l,p in records}
    county_text = (ROOT / 'drizzle/migrations/0003_seed_e3_indicator_and_counties.sql').read_text()
    for code,name in re.findall(r"\('([0-9]{2})', '([^']+)', 'län'\)", county_text):
        result[code] = {'name':name,'level':'län','parent':'00'}
    assert len(result) == 312, len(result)
    return result

def clean(name):
    return re.sub(r'\s+län$', '', str(name)).strip().casefold()

def numeric(value):
    if value is None or value == '': return None
    if str(value).strip() == '<5': return '<5'
    number = float(value)
    if not math.isfinite(number) or number < 0: raise ValueError(f'Invalid AF value: {value}')
    return int(number) if number.is_integer() else number

def complete(values):
    values = list(values)
    # Suppressed cells never become zeros or exact sums.
    if any(v == '<5' for v in values): return '<5'
    if any(v is None for v in values): return None
    return sum(values)

def cache_rows(path, required):
    """Discover by field names, never by cache number; stream records with bounded memory."""
    with zipfile.ZipFile(path) as archive:
        for definition in archive.namelist():
            if not re.fullmatch(r'xl/pivotCache/pivotCacheDefinition\d+\.xml', definition): continue
            root = ET.fromstring(archive.read(definition))
            fields = list(root.find(NS+'cacheFields'))
            names = [f.get('name') for f in fields]
            if not set(required) <= set(names): continue
            items = [[c.get('v') for c in f.find(NS+'sharedItems')] if f.find(NS+'sharedItems') is not None else [] for f in fields]
            indices = [(names.index(n), n) for n in required]
            records = definition.replace('Definition', 'Records')
            with archive.open(records) as stream:
                context = ET.iterparse(stream, events=('start','end'))
                _, document = next(context)
                for event, row in context:
                    if event != 'end' or row.tag != NS+'r': continue
                    result = {}
                    for i, name in indices:
                        cell = row[i]
                        result[name] = items[i][int(cell.get('v'))] if cell.tag == NS+'x' else cell.get('v')
                    yield result
                    document.clear()
            return
    raise ValueError(f'No pivot cache with fields {required}')

def discover():
    response = requests.get(SOURCE, timeout=60); response.raise_for_status()
    found = {}
    for href in re.findall(r'href=[\"\']([^\"\']+)', response.text):
        for key, prefix in [('sok','web-sok-lan-kom'), ('bas','web-inskrivna-arbetslosa-andel-av-bas')]:
            match = re.search(prefix+r'-(\d{4}-\d{2})\.xlsx', href, flags=re.I)
            if match and (key not in found or match[1] > found[key]['period']):
                found[key] = {'url': urljoin(SOURCE, href), 'period': match[1]}
    if len(found) != 2 or found['sok']['period'] != found['bas']['period']:
        raise ValueError('AF source periods are not synchronized')
    return found

def build(bas_path, sok_path, sources):
    geos = geography()
    municipalities = {clean(v['name']): c for c,v in geos.items() if v['level']=='kommun'}
    counties = {clean(v['name']): c for c,v in geos.items() if v['level']=='län'}
    county_aliases = (ROOT / 'R/etl/af_geography.R').read_text().split('.af_geo_cache')[0]
    counties.update({clean(name):code for name,code in re.findall(r'"([^"\n]+)" = "(\d{2})"', county_aliases)})
    # Aliases mirror existing af_geography.R (historical names retain stable codes).
    municipalities.update({'malung':'2023', 'falun':'2080'})
    bas = defaultdict(lambda: defaultdict(list))
    seen = set()
    national_residual = {}
    required = ['PERIOD','LAN','KOM'] + [p+s for _,_,p in PAIRS for s in ['SOK','AK']]
    for row in cache_rows(bas_path, required):
        period = row['PERIOD']; code = municipalities.get(clean(row['KOM'])); county = counties.get(clean(row['LAN']))
        if code is None and county is None and row['KOM'] is None and row['LAN'] is None:
            # AF includes the residual numerator in national totals; no workforce
            # is attached to this non-geographic category. Preserve it separately.
            for group,sex,prefix in PAIRS:
                n=numeric(row[prefix+'SOK'])
                if group in ('pre','upper','post') and period < '2024-04': n=None
                national_residual[(period,group,sex)]=n
            continue
        if code is None or county is None: raise ValueError(f"Unknown BAS geography {row['KOM']} / {row['LAN']}")
        seen.add((period,code))
        for group,sex,prefix in PAIRS:
            pair = [numeric(row[prefix+'SOK']),numeric(row[prefix+'AK'])]
            # AF notes explicitly say education is not available before 2024-04.
            if group in ('pre','upper','post') and period < '2024-04': pair = [None,None]
            for target in [code,county,'00']:
                bas[target][(period,group,sex)].append(pair)
    periods = sorted({p for p,c in seen})
    for earlier,later in zip(periods,periods[1:]):
        y,m=map(int,earlier.split('-')); next_period=f'{y+(m==12):04d}-{m%12+1:02d}'
        assert later==next_period, f'Missing BAS month between {earlier} and {later}'
    expected = sources['bas']['period']
    assert periods[-1] == expected
    for period in periods:
        assert len({c for p,c in seen if p==period}) == 290, f'Incomplete BAS coverage {period}'
    paired = {}
    for code, rows in bas.items():
        paired[code] = [[p,g,s,complete(x[0] for x in v),complete(x[1] for x in v)] for (p,g,s),v in sorted(rows.items())]
    for row in paired['00']:
        residual = national_residual.get(tuple(row[:3]), 0)
        row[3] = complete([row[3],residual])
    # Historical totals by sex; county sums follow AF's period-specific LAN field.
    counts = defaultdict(lambda: defaultdict(list))
    fields = ['PERIOD','LAN','KOMMUN_BESKR','KOEN','ALDGR','INSAL','ALTOT','AKTTOT']
    age_values = set()
    for row in cache_rows(sok_path, fields):
        p,s = row['PERIOD'],row['KOEN']; age_values.add(row['ALDGR'])
        county = counties.get(clean(row['LAN'])); code = municipalities.get(clean(row['KOMMUN_BESKR']))
        if row['KOMMUN_BESKR'] and code is None and clean(row['KOMMUN_BESKR']) not in ('uppgift saknas','okänd','okänt'):
            raise ValueError(f"Unknown municipality {row['KOMMUN_BESKR']}")
        vals = [numeric(row[k]) for k in ['INSAL','ALTOT','AKTTOT']]
        for target in [x for x in [code,county,'00'] if x]:
            for sex in [s,'']:
                counts[target][(p,sex)].append(vals)
    history = {}
    for code,rows in counts.items():
        history[code] = [[p,s]+[complete(x[i] for x in v) for i in range(3)] for (p,s),v in sorted(rows.items())]
    assert len(history)==312 and len(paired)==312
    assert max(r[0] for r in history['00']) == expected
    # Cross-source validation on every common geo/period/sex, not just a chosen example.
    checks=0
    for code,rows in history.items():
        lookup = {(p,s):n for p,g,s,n,d in paired[code] if g=='total'}
        for p,s,total,opened,program in rows:
            if all(isinstance(v,(int,float)) for v in [total,opened,program]):
                assert total==opened+program, (code,p,s,'INSAL != ALTOT + AKTTOT')
            if (p,s) in lookup and isinstance(total,(int,float)) and isinstance(lookup[p,s],(int,float)):
                # National BAS aggregates cover named municipalities. AF's national
                # total also includes unknown geography; retain AF's direct total.
                assert total==lookup[p,s], (code,p,s,total,lookup[p,s])
                checks+=1
    # Validate every available published national cell against the visible workbook.
    # This checks the handling of the residual geography and BAS precision as well.
    book = openpyxl.load_workbook(bas_path, read_only=True, data_only=True)
    national = {(p,g,s):(n,d) for p,g,s,n,d in paired['00']}
    published_checks = 0
    for row in book['Andel'].values:
        period = row[0]
        if period not in periods: continue
        for i,(g,s,_) in enumerate(PAIRS):
            n,d = national[(period,g,s)]
            published = row[i+1]
            if isinstance(n,(int,float)) and isinstance(d,(int,float)) and d>0 and isinstance(published,(int,float)):
                assert math.isclose(n/d,published,rel_tol=1e-10,abs_tol=1e-10), (period,g,s,n/d,published)
                published_checks += 1
    book.close()
    assert published_checks > 100
    OUT.mkdir(exist_ok=True)
    catalog = {'source':SOURCE,'periods':periods,'latest':expected,'geographies':geos,'sources':sources,
               'historyStart':min(r[0] for r in history['00']),'ageGroups':sorted(age_values),
               'validation':{'crossSourceChecks':checks,'publishedNationalRateChecks':published_checks},'retrieved':datetime.now(timezone.utc).isoformat()}
    # Store paired and history per geography, comparison per month; all are public aggregates.
    payloads = {f'geo-{c}.json':{'pairs':paired[c],'history':history[c]} for c in geos}
    for period in periods:
        payloads[f'compare-{period}.json'] = [[c,g,s,n,d] for c,rows in paired.items() for p,g,s,n,d in rows if p==period]
    payloads['catalog.json']=catalog
    for name,value in payloads.items():
        (OUT/name).write_text(json.dumps(value,ensure_ascii=False,separators=(',',':'),allow_nan=False)+'\n')
    print(json.dumps({'latest':expected,'geographies':len(geos),'checks':checks,'files':len(payloads)}))

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--bas',type=Path); parser.add_argument('--sok',type=Path); parser.add_argument('--force',action='store_true')
    args=parser.parse_args(); sources=discover()
    old=json.loads((OUT/'catalog.json').read_text()) if (OUT/'catalog.json').exists() else {}
    if old.get('latest','') > sources['bas']['period']:
        raise ValueError('AF source period moved backwards; previous publication retained')
    quarterly=datetime.now(timezone.utc).month in (1,4,7,10) and datetime.now(timezone.utc).day==16
    if not args.force and not quarterly and old.get('latest')==sources['bas']['period']:
        print('AF: unchanged publication period; no workbook download'); raise SystemExit(0)
    with tempfile.TemporaryDirectory() as tmp:
        paths={}
        for key in ['bas','sok']:
            supplied=getattr(args,key); path=supplied or Path(tmp)/f'{key}.xlsx'
            if not supplied:
                r=requests.get(sources[key]['url'],timeout=180); r.raise_for_status(); path.write_bytes(r.content)
            sources[key]['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
            sources[key]['bytes']=path.stat().st_size
            paths[key]=path
        build(paths['bas'],paths['sok'],sources)
