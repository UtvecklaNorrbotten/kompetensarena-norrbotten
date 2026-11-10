"""Canonical per-period fingerprints for verified UKÄ staging and PostgreSQL.

Only hashes and counts need to leave the local package. Normalization preserves
all dimensions, native totals and numeric values. PostgreSQL jsonb text ordering
and bytewise row ordering make the comparison independent of database row order.
"""
from collections import defaultdict
from decimal import Decimal
import hashlib
import json
from pathlib import Path
import sqlite3

INDICATORS={13:'uka-forstahandssokande-yrkesprogram',31:'uka-nyborjare-yrkesprogram',97:'uka-antagna-yrkesprogram',108:'uka-examinerade',136:'uka-etablering',77:'uka-kvarvaro-hogskolenyborjare',134:'uka-kvarvaro-program',135:'uka-examensfrekvens'}
DIMENSIONS={'Program':'program','Studieform':'studieform','Utbildningsnivå':'utbildningsniva','Examenskategori':'examenskategori','Examen':'examen','Inriktning':'inriktning'}


def jsonb_text(v):
    if isinstance(v,dict):
        keys=sorted(v,key=lambda k:(len(k.encode()),k.encode()))
        return '{'+', '.join(json.dumps(k,ensure_ascii=False)+': '+jsonb_text(v[k]) for k in keys)+'}'
    if isinstance(v,list):return '['+', '.join(jsonb_text(x) for x in v)+']'
    return json.dumps(v,ensure_ascii=False)


def fixed_value(value):
    number=Decimal(value)
    if not number.is_finite():raise ValueError('Non-finite source value')
    text=format(number,'f')
    return text.rstrip('0').rstrip('.') if '.' in text else text


def audit(root):
    root=Path(root); result=[]
    for i,name in INDICATORS.items():
        m=json.loads((root/str(i)/'metadata.json').read_text())
        names={x['value'].removeprefix('uni:'):x['label'].strip() for x in m['universities']}
        db=sqlite3.connect(f'file:{(root/str(i)/"collection.sqlite").resolve()}?mode=ro',uri=True)
        groups=defaultdict(list);coverage=defaultdict(int);identities=set()
        for raw, in db.execute('SELECT payload FROM observations'):
            p=json.loads(raw);dims={DIMENSIONS[k]:v for k,v in p['dimensions'].items()}
            if p['age']!='Total':dims['aldersgrupp']=p['age']
            identity=jsonb_text([p['period'],names[p['university']],p['gender'],dims])
            if identity in identities:raise ValueError('Duplicate normalized identity regardless of value')
            identities.add(identity)
            line=jsonb_text([p['period'],names[p['university']],p['gender'],dims,fixed_value(p['value'])])
            groups[p['period']].append(line.encode())
            coverage[(p['period'],p['gender'],p['age'])]+=1
        db.close()
        periods=[]
        for period,lines in sorted(groups.items()):
            if len(lines)!=len(set(lines)):raise ValueError('Duplicate normalized rows')
            periods.append({'period':period,'rows':len(lines),'sha256':hashlib.sha256(b'\n'.join(sorted(lines))).hexdigest()})
        result.append({'api_id':i,'indicator':name,'rows':sum(p['rows'] for p in periods),'periods':periods,
                       'coverage':[{'period':p,'gender':g,'age':a,'rows':n} for (p,g,a),n in sorted(coverage.items())]})
    return {'policy':'csv-all-universities-partitions-every-root-v1','snapshot':'2026-11-10-all','archive_sha256':'1be12b057d06285fa97b9eaa314d31e0898de57130f7c4d99c3a4093e2eb4170','canonicalization':'jsonb-array(period,university,gender,dimensions,numeric-text-fixed); bytewise order; newline separator without final newline','indicators':result}


if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--output',required=True);a=p.parse_args()
    Path(a.output).write_text(json.dumps(audit(a.root),ensure_ascii=False,indent=2))
