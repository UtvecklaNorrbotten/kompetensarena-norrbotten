"""Reproducible, bounded historical-ad audit. Outputs no employer/ad identities.

This is an audit of the Historical Ads index at retrieval time, NOT a complete
publication series: still-active ads are absent from that index. Repeated hiring
intent is deliberately not deduplicated across different original_ids.
"""
from __future__ import annotations
import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import requests
from fetch_af_unemployment import ROOT

API='https://historical.api.jobtechdev.se/search'

def normalize(text): return re.sub(r'\s+',' ',str(text or '')).strip().casefold()

def summarize(hits,start,end):
    boundary=[h for h in hits if not start<=str(h.get('publication_date',''))[:19]<end]
    included=[h for h in hits if start<=str(h.get('publication_date',''))[:19]<end]
    by_id={}
    for h in included:
        key=h.get('original_id') or h['id']
        # Deterministic latest version; identity is kept only in process memory.
        if key not in by_id or str(h.get('last_publication_date',''))>str(by_id[key].get('last_publication_date','')): by_id[key]=h
    fingerprints=Counter();municipalities=Counter();fields=Counter();groups=Counter()
    for h in by_id.values():
        address=h.get('workplace_address') or {}; group=h.get('occupation_group') or {}
        identity=((h.get('employer') or {}).get('organization_number'),normalize(h.get('headline')),group.get('legacy_ams_taxonomy_id'),address.get('municipality_code'))
        fingerprints[hashlib.sha256(json.dumps(identity).encode()).hexdigest()]+=1
        municipalities[address.get('municipality_code') or 'unknown']+=1
        fields[(h.get('occupation_field') or {}).get('concept_id') or 'unknown']+=1
        groups[group.get('legacy_ams_taxonomy_id') or 'unknown']+=1
    vacancies=[h.get('number_of_vacancies') for h in by_id.values()]
    return {'fetchedRows':len(hits),'boundaryExcluded':len(boundary),'inWindowRows':len(included),
            'uniqueOriginalIds':len(by_id),'repeatedIdentityRows':len(included)-len(by_id),
            'sumKnownAdvertisedPositions':sum(v for v in vacancies if isinstance(v,int)),
            'unknownAdvertisedPositions':sum(not isinstance(v,int) for v in vacancies),
            'zeroAdvertisedPositions':vacancies.count(0),
            'sameEmployerHeadlineGroupMunicipalityClusters':sum(v>1 for v in fingerprints.values()),
            'rowsInSuchClusters':sum(v for v in fingerprints.values() if v>1),
            'municipalityCounts':dict(municipalities),'occupationFieldConceptCounts':dict(fields),'ssyk2012Counts':dict(groups)}

def main():
    p=argparse.ArgumentParser();p.add_argument('--month',required=True);p.add_argument('--region',default='25');p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    if not re.fullmatch(r'\d{4}-\d{2}',args.month) or not re.fullmatch(r'\d{2}',args.region):raise ValueError('Invalid period/region')
    y,m=map(int,args.month.split('-'));start=args.month+'-01T00:00:00';end=f'{y+(m==12):04d}-{m%12+1:02d}-01T00:00:00'
    params={'region':args.region,'published-after':start,'published-before':end,'sort':'pubdate-asc','limit':100}
    def fetch(offset):
        r=requests.get(API,params={**params,'offset':offset},timeout=120);r.raise_for_status();return r.json(),hashlib.sha256(r.content).hexdigest()
    first,sha=fetch(0);total=first['total']['value']
    if total>2000:raise ValueError('Audit exceeds pagination limit; choose a smaller region/window, never truncate')
    hits=list(first['hits']);hashes=[sha]
    with ThreadPoolExecutor(max_workers=2) as executor:
        for data,sha in executor.map(fetch,range(100,total,100)):hits.extend(data['hits']);hashes.append(sha)
    assert len(hits)==total,(len(hits),total)
    report={'api':API,'month':args.month,'region':args.region,'retrieved':datetime.now(timezone.utc).isoformat(),
            'scope':'Historical Ads only; excludes still-active ads, not a complete monthly publication count',
            'window':'publication_date >= start and < next month, checked locally; API endpoints include boundaries',
            'query':params,'sourceResponseSha256':hashes,'audit':summarize(hits,start,end),
            'limitations':['Possible repost clusters are not verified duplicates and are not removed.',
                           'workplace_address is one published location; hidden/multiple workplaces cannot be enumerated reliably.',
                           'JobAd Links external advertisements are not mixed with Platsbanken.',
                           'Historical Ads is a moving index; archived counts may increase when active advertisements close.']}
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(report['audit']))

if __name__=='__main__':main()
