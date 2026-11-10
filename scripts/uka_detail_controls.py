"""Targeted linked-JSON checks against committed CSV details; no guessed slugs."""
import argparse
import json
from pathlib import Path
import sqlite3
from urllib.parse import urlencode

from uka_99_full_csv import observation_key
from uka_json_probe import BASE, Probe, edge_value, validate_url, yearly
from uka_source_audit import canonical_value, write_json
from uka_verified_collection import GROUP_LEVELS


def run(root, budget=0):
    root=Path(root); m=json.loads((root/'metadata.json').read_text()); i=m['indicator']
    probe=Probe(root,m['snapshot'],budget)
    db=sqlite3.connect(f'file:{root.resolve() / "collection.sqlite"}?mode=ro',uri=True)
    planned=[m['retained_periods'][n]['value'].removeprefix('from:') for n in (0,-1)]
    cases=[]
    try:
        for n,period in enumerate(planned):
            if not db.execute('SELECT 1 FROM periods WHERE period=?',(period,)).fetchone():
                raise ValueError('Detail reference period not staged')
            gender=('Kvinnor','Män')[n]
            offered_ages={o['label']:o['value'].removeprefix('age:') for o in m['ages']}
            age=('-24','35-')[n] if len(offered_ages)>1 else 'Total'
            q={'university':'1','year':period,'gender':gender}
            if age!='Total':q['age_group']=offered_ages[age]
            url=BASE+f'/{i}?'+urlencode(q);body=probe.get(url,i);dims={};checks=[]
            def compare_observation(university,dimensions,value,source_url):
                key=observation_key(period,university,gender,age,dimensions)
                # Database keys use the full indicator identity digest; inspect payload.
                found=[]
                for raw, in db.execute('SELECT payload FROM observations WHERE period=?',(period,)):
                    r=json.loads(raw)
                    if observation_key(period,r['university'],r['gender'],r['age'],r['dimensions'])==key:found.append(r['value'])
                if len(found)!=1 or found[0]!=value:
                    raise ValueError('CSV detail differs from direct JSON: '+key)
                checks.append({'university':university,'dimensions':dict(dimensions),'value':value,'url':source_url,'classification':'verified_data' if value is not None else 'suppressed_or_unreported'})
            for levels in GROUP_LEVELS[i]:
                for col in levels:
                    candidates=[r for g in body.get('groups',[]) if g['column']==col for r in g.get('totals',[])]
                    if not candidates:break
                    wanted='Yrkesexamina' if i==108 and col=='Examenskategori' else 'Civilingenjörsexamina' if i==108 and col=='Examen' else None
                    row=next((r for r in candidates if r['name']==wanted),candidates[0])
                    child=probe.get(row['url'],i);value=edge_value(url,row['url'],child,row['value'],i)
                    dims[col]=row['name'];compare_observation('1',dims,value,row['url'])
                    url,body=row['url'],child
            institutions=[r for g in body.get('groups',[]) if g['column']=='Lärosäten' for r in g.get('totals',[])]
            if not institutions:raise ValueError('No positive university detail reference')
            r=next((r for r in institutions if validate_url(r['url'],i)['university']=='32'),institutions[0])
            child=probe.get(r['url'],i);actual=yearly(child)[period];expected=None if r['value'] is None else canonical_value(str(r['value']))
            before,after=validate_url(url,i),validate_url(r['url'],i)
            if any(before.get(k)!=after.get(k) for k in ('year','gender','age_group','group_slug')) or actual!=expected:
                raise ValueError('University detail source context/value mismatch')
            compare_observation(after['university'],dims,actual,r['url'])
            cases.append({'period':period,'gender':gender,'age':age,'checks':checks})
        result={'indicator':i,'cases':cases,'new_requests':probe.requests,'all_checks_passed':True,'publish_allowed':False}
        write_json(root/'detail-controls.json',result);return result
    finally:db.close();probe.session.close()


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',required=True);p.add_argument('--max-new-requests',type=int,default=0)
    a=p.parse_args();r=run(a.root,a.max_new_requests);print(json.dumps(r,ensure_ascii=False,indent=2))
