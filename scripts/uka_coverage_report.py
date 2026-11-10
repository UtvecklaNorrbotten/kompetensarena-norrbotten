"""Build auditable UKÄ coverage inventory from frozen metadata and staged sources.

Reports observed combinations, positive absence scopes and unresolved omissions
separately. Does not enumerate a speculative Cartesian product or publish data.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
from urllib.parse import urlencode

from uka_csv_bulk_probe import compare, queue_reference
from uka_json_probe import BASE, Probe
from uka_json_queue import Queue, SOURCE_DIMENSIONS
from uka_source_audit import digest, write_json
from uka_verified_collection import Collection, GROUP_LEVELS, paths


def independent_reference(indicator, metadata, collection_root, legacy_cache, output):
    """Rebuild the old linked graph with a zero network budget, then compare values.

    This is an explicitly historical reference/revision check, not an immutable
    release guarantee. The legacy queue's stored done flags are not trusted.
    """
    period = metadata['retained_periods'][0]['value'].removeprefix('from:')
    url = BASE + f'/{indicator}?' + urlencode({'university':'1','year':period})
    probe = Probe(legacy_cache, '2026-11-06', 0)
    with tempfile.TemporaryDirectory() as tmp:
        database = Path(tmp) / 'reference.sqlite'
        with Queue(database, url, '2026-11-06', indicator=indicator) as q:
            state = q.run(probe,max_nodes=2000,seconds=120)
        if not state['graph_closed'] or probe.requests:
            raise ValueError('Historical graph cannot be verified offline')
        reference = queue_reference(database)
    db = sqlite3.connect(f'file:{Path(collection_root).resolve() / "collection.sqlite"}?mode=ro',uri=True)
    try:
        actual = {}
        for (raw,) in db.execute('SELECT payload FROM observations WHERE period=?',(period,)):
            p=json.loads(raw)
            if p['gender']=='Total' and p['age']=='Total':
                key=json.dumps([p['period'],p['university'],p['gender'],p['age'],p['dimensions']],ensure_ascii=False,sort_keys=True)
                if key in actual: raise ValueError('Duplicate staged identity')
                actual[key]=p['value']
    finally:db.close()
    result={'indicator':indicator,'period':period,'gender':'Total','age':'Total',
            'historical_snapshot':'2026-11-06','comparison':compare(reference,actual),
            'new_requests':probe.requests,'graph_rebuilt_from_hash_checked_sources':True,
            'source_release_verified':False}
    write_json(output,result)
    if not result['comparison']['exact']:raise ValueError('Historical JSON / current CSV mismatch')
    return result


def build(root, output, legacy_cache=None):
    root=Path(root)
    report={'date':'2026-11-10','scope':'Ten configured indicators; exact offered values are separate from observed combinations',
            'classifications':{
                'verified_data':'Observation in successful controlled source exports; independent JSON comparison scope is explicit',
                'verified_missing_combination':'Only the exact scope absent from positive broader references; never inferred from HTTP/empty response',
                'suppressed_or_unreported':'Explicit source null or marker; reason remains unknown unless official definition explains it',
                'technical_error':'HTTP/transport/zero-byte/malformed source failure; never a missing observation',
                'unclear':'Insufficient evidence, unresolved validation error or absent detail without positive reference'},
            'indicators':[],'publish_allowed':False}
    for i in (13,31,33,97,99,108,136,77,134,135):
        m=json.loads((root/'metadata'/f'{i}.json').read_text())
        if m['metadata_hash']!=digest({k:v for k,v in m.items() if k!='metadata_hash'}):raise ValueError('Metadata hash mismatch')
        entry={'indicator':i,'metadata':m,'offered_values_are_not_observations':True,
               'json_dimensions':list(SOURCE_DIMENSIONS[i]),'verified_missing_scopes':[],
               'uncertainties':['Unadvertised detail cells cannot be universally classified','No immutable source release ID verified','No blanket suppression rule inferred from other indicators']}
        if i not in GROUP_LEVELS:
            entry['existing_collection_report']='uka-hst-full-collection-2026-11-09.json' if i==33 else 'uka-99-full-collection-2026-11-10.json'
            entry['existing_restart_document']=f'uka-indicator-{i}.md'
            entry['reacquired_in_this_campaign']=False
            saved = root / f'{i}-existing-report.json'
            if saved.exists():
                prior = json.loads(saved.read_text())
                entry.update(state='previous_collection_reverified_offline', observations=prior['observations'],
                             staged_periods=prior.get('staged_periods',prior.get('staged_years')),
                             previous_collection=prior, offline_recheck=json.loads((root/f'{i}-recheck.json').read_text()))
            report['indicators'].append(entry);continue
        entry['dimension_paths']=[{'index':g['index'],'levels':list(levels),'paths':paths(g,levels)} for g,levels in zip(m['groups'],GROUP_LEVELS[i])]
        if not (root/str(i)/'collection.sqlite').exists():
            entry['state']='unclear_not_collected';report['indicators'].append(entry);continue
        with Collection(root/str(i),m,m['snapshot']) as c:
            status=c.report();entry.update(state='staged' if status['all_planned_periods_staged'] else 'partial',
                staged_periods=status['staged_periods'],planned_periods=status['planned_periods'],observations=status['observations'])
            entry['periods']=[]
            for p in status['periods']:
                period=p['period']; combinations={}; scalar=defaultdict(set); value_counts=Counter()
                for (raw,) in c.db.execute('SELECT payload FROM observations WHERE period=?',(period,)):
                    row=json.loads(raw)
                    for field in ('university','gender','age'):scalar[field].add(row[field])
                    key=json.dumps(row['dimensions'],ensure_ascii=False,sort_keys=True)
                    combinations[key]=row['dimensions']
                    value_counts['suppressed_or_unreported' if row['value'] in (None,'','..','.','-','…') else 'verified_data']+=1
                entry['periods'].append({'period':period,'observations':p['observations'],'staging_sha256':p['staging_sha256'],
                    'observed_values':{k:sorted(v) for k,v in scalar.items()},'observed_dimension_paths':list(combinations.values()),
                    'value_classifications':dict(value_counts),'source_controls':p['coverage'],
                    'csv_receipts':p['exports'],'json_root_hashes':p['root_hashes'],
                    'leaf_absence_classification':'unclear_without_further_positive_reference'})
                for coverage in p['coverage']:
                    if coverage['not_advertised_universities']:
                        entry['verified_missing_scopes'].append({'period':period,'gender':coverage['gender'],'age':coverage['age'],
                            'universities':coverage['not_advertised_universities'],'dimensions':'all requested source dimensions',
                            'evidence':'Successful explicit broad CSV + positive national JSON university list',
                            'cause':'Not inferred; may reflect population or reporting restrictions'})
        if legacy_cache:
            entry['independent_historical_json_comparison']=independent_reference(i,m,root/str(i),legacy_cache,root/str(i)/'independent-json-reference.json')
        report['indicators'].append(entry)
    write_json(output,report);return report


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',required=True);p.add_argument('--output',required=True);p.add_argument('--legacy-cache')
    a=p.parse_args();r=build(a.root,Path(a.output),a.legacy_cache)
    print(json.dumps({'indicators':len(r['indicators']),'publish_allowed':r['publish_allowed']}))
