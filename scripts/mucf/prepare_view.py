"""Publish bounded public read models only for fully published, validated MUCF years."""
import argparse,gzip,json,hashlib
from pathlib import Path

def prepare(root,out,asset_out=None):
    asset_out = asset_out or out
    catalog=json.loads((root/'catalog.json').read_text())
    published=json.loads((root/'published.json').read_text()) if (root/'published.json').exists() else {}
    result={'years':[],'regions':{},'notes':[],'source':'https://www.mucf.se/rapporter-och-statistik/statistik-om-unga-som-varken-arbetar-eller-studerar'}
    payloads={}
    for path in sorted((root/'snapshots').glob('*.json.gz')):
        snap=json.loads(gzip.decompress(path.read_bytes())); year=snap['year']; state=published.get(year,{})
        if any(state.get(m)!=snap['data_sha256'] for m in ('count','share')):continue
        raw=json.dumps([snap['geographies'],snap['rows'],snap['notes']],ensure_ascii=False,separators=(',',':'),allow_nan=False).encode()
        if hashlib.sha256(raw).hexdigest()!=snap['data_sha256']:raise ValueError('MUCF snapshot checksum mismatch')
        if catalog.get('snapshots',{}).get(year)!=snap['data_sha256']:raise ValueError('MUCF catalog checksum mismatch')
        rows=[r for r in snap['rows'] if r[4]=='Master']
        if len({tuple(r[:5]) for r in rows})!=len(rows):raise ValueError('Duplicate MUCF cells')
        result['years'].append(year);result['notes']=snap['notes'];result['retrieved']=snap['last_fetched_at']
        for g in snap['geographies']:result['regions'][g['code']]=g['label']
        payloads[f'{year}.json']=rows
    out.mkdir(parents=True,exist_ok=True)
    # Only replace after the entire input has been checked. An empty initial catalog
    # is legitimate while waiting for publication; never erase an existing year.
    old=json.loads((out/'catalog.json').read_text()) if (out/'catalog.json').exists() else {'years':[]}
    if not set(old['years'])<=set(result['years']):raise ValueError('Previously public MUCF year disappeared')
    asset_out.mkdir(parents=True,exist_ok=True)
    for name,data in payloads.items():(asset_out/name).write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
    (out/'catalog.json').write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n')
    print('Published MUCF view years:',result['years'])
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--out',type=Path,default=Path('src/data/uvas'));p.add_argument('--assets',type=Path,default=Path('public/data/uvas'));a=p.parse_args();prepare(a.root,a.out,a.assets)
