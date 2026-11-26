"""Validated public AF aggregates and SCB LOR; no advertisement/person records.

Run with --places/--occupations to reuse downloaded original workbooks.
All dimensions survive in compressed, versioned aggregates. Publish with git only
after the whole command succeeds. A failed build never replaces the active model.
"""
from __future__ import annotations
import argparse
import base64
from collections import defaultdict
from datetime import datetime, timezone
import gzip
import hashlib
import itertools
import json
from pathlib import Path
import re
import tempfile
from urllib.parse import urljoin
import xml.etree.ElementTree as ET
import zipfile
import openpyxl
import requests
from fetch_af_unemployment import geography, clean, NS, numeric, SOURCE

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'src/data/demand'
PREFIXES = {'places':'web-platser', 'occupations':'web-allajobb-yrkesomrade'}
MEASURES = ['NYATOT','KVARTOT','NYA','KVAR']

def discover():
    r=requests.get(SOURCE,timeout=60); r.raise_for_status()
    result={}
    for href in re.findall(r'href=[\"\']([^\"\']+)',r.text):
        for key,prefix in PREFIXES.items():
            m=re.search(prefix+r'-(\d{4}-\d{2})\.xlsx',href,re.I)
            if m and (key not in result or m[1]>result[key]['period']):
                result[key]={'url':urljoin(SOURCE,href),'period':m[1]}
    if len(result)!=2 or result['places']['period']!=result['occupations']['period']:
        raise ValueError('AF sources have different publication periods')
    return result

def cache_rows(path, dimensions, measures):
    """Exact field set prevents silently choosing a cache with extra dimensions."""
    with zipfile.ZipFile(path) as archive:
        matches=[]
        for f in archive.namelist():
            if not re.fullmatch(r'xl/pivotCache/pivotCacheDefinition\d+\.xml',f): continue
            root=ET.fromstring(archive.read(f)); fields=list(root.find(NS+'cacheFields'))
            names=[a.get('name') for a in fields]
            if set(names)==set(dimensions+measures): matches.append((f,fields,names))
        if len(matches)!=1: raise ValueError(f'Ambiguous/missing cache: {dimensions}')
        f,fields,names=matches[0]
        shared=[[c.get('v') for c in a.find(NS+'sharedItems')] for a in fields]
        with archive.open(f.replace('Definition','Records')) as stream:
            context=ET.iterparse(stream,events=('start','end')); _,document=next(context)
            for event,row in context:
                if event!='end' or row.tag!=NS+'r': continue
                vals=[shared[i][int(c.get('v'))] if c.tag==NS+'x' else c.get('v') for i,c in enumerate(row)]
                yield dict(zip(names,vals))
                document.clear()

def add(acc,key,values):
    if key not in acc: acc[key]=[0]*len(values)
    for i,v in enumerate(values):
        old=acc[key][i]
        acc[key][i]='<5' if '<5' in (old,v) else None if old is None or v is None else old+v

def encode(value):
    raw=json.dumps(value,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode()
    return {'gzip':base64.b64encode(gzip.compress(raw,mtime=0)).decode()}

def build_af(paths,sources,output):
    geos=geography()
    municipalities={clean(v['name']):c for c,v in geos.items() if v['level']=='kommun'}
    municipalities.update({'malung':'2023','falun':'2080'})
    counties={clean(v['name']):c for c,v in geos.items() if v['level']=='län'}
    aliases=(ROOT/'R/etl/af_geography.R').read_text().split('.af_geo_cache')[0]
    counties.update({clean(n):c for n,c in re.findall(r'"([^"\n]+)" = "(\d{2})"',aliases)})
    def targets(row):
        n,l=row['KOMMUN_BESKR'],row['LAN_BESKR']
        if n is None and l is None: return ['00']
        if clean(n) not in municipalities or clean(l) not in counties:
            raise ValueError(f'Unknown AF geography {n}/{l}')
        return [municipalities[clean(n)],counties[clean(l)],'00']
    models={c:{} for c in geos}; validation={}; dimensions={}; fields=set(); groups={}; relations=set()
    definitions=[
        ('totals','places',[],MEASURES),
        ('fields','places',['YRKESOMRÅDE','KOMPETENSKRAV'],MEASURES),
        ('industry','places',['SNI2007_AVD'],MEASURES),
        ('groups','occupations',['ÅR','MÅNAD','YRKESOMRÅDE','SSYK2012_BESKR','YRKE'],['KVAR']),
    ]
    for dataset,source,extra,measures in definitions:
        acc=defaultdict(dict); source_rows=0; seen=set(); values=defaultdict(set)
        dims=['PERIOD','LAN_BESKR','KOMMUN_BESKR','SOMMARJOBB']+extra
        for row in cache_rows(paths[source],dims,measures):
            source_rows+=1; p=row['PERIOD']; seen.add(p)
            numbers=[numeric(row[k]) for k in measures]
            for k in extra: values[k].add(row[k])
            field=row.get('YRKESOMRÅDE') or 'Uppgift saknas'
            if dataset in ('fields','groups'): fields.add(field)
            if dataset=='totals': key=(p,row['SOMMARJOBB'])
            elif dataset=='fields': key=(p,field,row['KOMPETENSKRAV'],row['SOMMARJOBB'])
            elif dataset=='industry': key=(p,row['SNI2007_AVD'],row['SOMMARJOBB'])
            else:
                label=(row['SSYK2012_BESKR'] or '').strip() or 'Uppgift saknas'
                match=re.match(r'^(\d{4})\s+(.+)$',label)
                code=match[1] if match else 'unknown'
                if code=='unknown' and label not in ('Uppgift saknas','--'): raise ValueError(label)
                groups[code]=match[2] if match else label
                relations.add((field,code,row['YRKE']))
                key=(p,field,code,row['SOMMARJOBB'])
            for target in targets(row): add(acc[target],key,numbers)
        for geo,records in acc.items():
            models[geo][dataset]=[list(k)+v for k,v in sorted(records.items(),key=lambda x:str(x[0]))]
        periods=sorted(seen)
        for a,b in zip(periods,periods[1:]):
            y,m=map(int,a.split('-')); assert b==f'{y+(m==12):04d}-{m%12+1:02d}',(dataset,a,b)
        assert periods[-1]==sources[source]['period']
        dimensions[dataset]={'start':periods[0],'end':periods[-1],'periods':periods,
                             'values':{k:sorted(v,key=str) for k,v in values.items()}}
        validation[dataset]={'sourceRows':source_rows,'nationalRows':len(models['00'][dataset])}
        print(dataset,validation[dataset],flush=True)
    # Independent visible national table verifies all four measures, all months.
    national=defaultdict(dict)
    for p,s,*v in models['00']['totals']: add(national,p,v)
    book=openpyxl.load_workbook(paths['places'],read_only=True,data_only=True)
    checks=0
    for row in book['1996-01-'].values:
        if row[0] not in national: continue
        # Workbook presentation: new total, remaining total, new >10, remaining >10.
        assert list(row[1:5])==national[row[0]],(row[0],row[1:5],national[row[0]])
        checks+=4
    book.close(); assert checks>=120*4
    validation['publishedNationalCells']=checks
    # Keep differing source populations separate; report reconciliation, never force equality.
    for key in ['fields','industry','groups']:
        comparison=defaultdict(dict)
        for p,*rest in models['00'][key]: add(comparison,p,rest[-(1 if key=='groups' else 4):])
        differences=[]
        for p,vals in comparison.items():
            expected=[national[p][3]] if key=='groups' else national[p]
            if vals!=expected: differences.append({'period':p,'difference':[a-b for a,b in zip(vals,expected)]})
        validation[key]['differencesFromTotals']=differences
    assert len(models)==312 and all(m.get('totals') for m in models.values())
    output.mkdir(parents=True,exist_ok=True)
    for geo,model in models.items():
        (output/f'geo-{geo}.json').write_text(json.dumps(encode(model),separators=(',',':'))+'\n')
    return {'source':SOURCE,'sources':sources,'latest':sources['places']['period'],
            'geographies':geos,'dimensions':dimensions,'fields':sorted(fields),
            'groups':groups,'occupationRelations':[list(x) for x in sorted(relations,key=str)],
            'validation':validation}

def fetch_lor(old,force):
    result={}
    for table in ['TAB6606','TAB6989']:
        base=f'https://statistikdatabasen.scb.se/api/v2/tables/{table}'
        r=requests.get(base+'/metadata',timeout=60);r.raise_for_status();meta=r.json()
        if not force and old.get(table,{}).get('updated')==meta['updated']:
            result[table]=old[table];continue
        params={'lang':'sv','outputFormat':'json-stat2'}
        for d in meta['id']: params[f'valueCodes[{d}]']='*'
        r=requests.get(base+'/data',params=params,timeout=120);r.raise_for_status();data=r.json()
        assert data['id']==meta['id'] and data['size']==meta['size']
        assert len(data['value'])==__import__('math').prod(data['size'])
        assert any(v is not None for v in data['value'])
        result[table]={'updated':meta['updated'],'url':base,'metadata':meta,'data':data,
                       'sha256':hashlib.sha256(r.content).hexdigest()}
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--force',action='store_true');parser.add_argument('--source',choices=['af','lor','all'],default='all')
    parser.add_argument('--places',type=Path);parser.add_argument('--occupations',type=Path)
    args=parser.parse_args(); sources=discover() if args.source != 'lor' else None
    old=json.loads((OUT/'catalog.json').read_text()) if (OUT/'catalog.json').exists() else {}
    prior_lor=json.loads((OUT/'lor.json').read_text()) if (OUT/'lor.json').exists() else {}
    quarterly=datetime.now(timezone.utc).month in (1,4,7,10) and datetime.now(timezone.utc).day==16
    force=args.force or quarterly
    if sources and old.get('latest','')>sources['places']['period']: raise ValueError('AF period moved backwards')
    lor=fetch_lor(prior_lor,force) if args.source != 'af' else None
    with tempfile.TemporaryDirectory() as tmp:
        staging=Path(tmp)/'output';staging.mkdir(); paths={}
        if sources and (force or old.get('latest')!=sources['places']['period']):
            for key in PREFIXES:
                path=getattr(args,key) or Path(tmp)/f'{key}.xlsx'
                if not getattr(args,key):
                    r=requests.get(sources[key]['url'],timeout=240);r.raise_for_status();path.write_bytes(r.content)
                sources[key]['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
                sources[key]['bytes']=path.stat().st_size; paths[key]=path
            catalog=build_af(paths,sources,staging)
            catalog['retrieved']=datetime.now(timezone.utc).isoformat()
            (staging/'catalog.json').write_text(json.dumps(catalog,ensure_ascii=False,separators=(',',':'))+'\n')
        if lor is not None: (staging/'lor.json').write_text(json.dumps(lor,ensure_ascii=False,separators=(',',':'))+'\n')
        OUT.mkdir(exist_ok=True)
        for path in staging.iterdir():
            destination=(ROOT/'public/data/demand') if path.name.startswith('geo-') else OUT
            destination.mkdir(parents=True,exist_ok=True)
            (destination/path.name).write_bytes(path.read_bytes())
    print('Validated demand model ready; git commit publishes the complete snapshot.')

if __name__=='__main__': main()
