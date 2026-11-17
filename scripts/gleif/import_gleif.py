"""Resumable exact matching plus dated accounting-consolidation evidence.

Identity batches are checkpointed before downloading bulk relationship sources.
Full files are streamed once per run, not one parent API request per company.
Only normalized scoped facts and their provenance are written to protected tables.
"""
import json
from collections import Counter
from datetime import datetime,timezone
from company_accounts import api
from .client import Client,canonical,digest,LEI,GleifError
from .bulk import load

SOURCE='gleif-parent-relations'
RR={'direct':'IS_DIRECTLY_CONSOLIDATED_BY','ultimate':'IS_ULTIMATELY_CONSOLIDATED_BY'}
EX={'direct':'DIRECT_ACCOUNTING_CONSOLIDATION_PARENT','ultimate':'ULTIMATE_ACCOUNTING_CONSOLIDATION_PARENT'}


def due(record):
    return not record or datetime.fromisoformat(record['next_check_at'].replace('Z','+00:00'))<=datetime.now(timezone.utc)


def scope():
    rows=[];after=None
    for page in range(1000):
        batch=api.call('gleif-scope',**({'after':after} if after else {}))
        if not batch:return rows
        if after is not None and batch[-1]['je_id']<=after:raise GleifError('Scope cursor did not advance')
        rows.extend(batch);after=batch[-1]['je_id']
    raise GleifError('Scope exceeds bound')


def store(stage,records):
    for i in range(0,len(records),50):
        chunk=records[i:i+50]
        result=api.call('gleif-store',{'stage':stage,'records':chunk})
        if result.get('stored')!=len(chunk):raise GleifError('Incomplete protected write')


def record(row,payload,source):
    return dict(je_id=row['je_id'],canonical_payload=canonical(payload),payload_sha256=digest(payload),source=source)


def expired_relation(row,today):
    for i in range(1,6):
        if row.get(f'Relationship.Period.{i}.periodType')=='RELATIONSHIP_PERIOD':
            end=row.get(f'Relationship.Period.{i}.endDate')
            if end and datetime.fromisoformat(end.replace('Z','+00:00')).date()<today:return True
    return False


def relation(lei,kind,rr,exceptions,today=None):
    today=today or datetime.now(timezone.utc).date()
    rows=[r for r in rr if r.get('Relationship.RelationshipType')==RR[kind]]
    active=[];warnings=[]
    for r in rows:
        if r.get('Relationship.StartNode.NodeID')!=lei or r.get('Relationship.StartNode.NodeIDType')!='LEI':
            raise GleifError('Invalid relationship child')
        if not LEI.fullmatch(r.get('Relationship.EndNode.NodeID','')) or r.get('Relationship.EndNode.NodeIDType')!='LEI':
            raise GleifError('Invalid relationship parent')
        if (not r.get('DeletedAt') and r.get('Relationship.RelationshipStatus')=='ACTIVE'
            and r.get('Registration.RegistrationStatus') in ('PUBLISHED','LAPSED') and not expired_relation(r,today)):
            active.append(r)
            if r['Registration.RegistrationStatus']=='LAPSED':warnings.append('relationship_registration_lapsed')
    ex=[r for r in exceptions if r.get('LEI')==lei and r.get('Exception.Category')==EX[kind] and not r.get('DeletedAt')]
    parents={r['Relationship.EndNode.NodeID'] for r in active}
    state='conflict' if len(parents)>1 or (active and ex) else 'relation' if active else 'exception' if ex else 'unreported'
    return dict(state=state,relations=sorted(active,key=canonical),exceptions=sorted(ex,key=canonical),
                historical_records=sorted([r for r in rows if r not in active],key=canonical),warnings=sorted(set(warnings)))


def reserved_tree(identity,data,parents):
    status=identity['status']
    if status!='matched':return dict(status='no_exact_lei' if status=='not_found' else 'ambiguous_lei',entities=[],parents=[])
    e=identity['entities'][0];lei=e['lei'];rr=data.get('rr',{}).get(lei,[]);ex=data.get('repex',{}).get(lei,[])
    direct=relation(lei,'direct',rr,ex);ultimate=relation(lei,'ultimate',rr,ex)
    parent_ids={r['Relationship.EndNode.NodeID'] for rel in (direct,ultimate) for r in rel['relations']}
    warnings=[]
    if e.get('entity_status')!='ACTIVE':warnings.append('entity_not_active')
    if e.get('registration_status')!='ISSUED':warnings.append('lei_registration_not_issued')
    if parent_ids-set(parents):warnings.append('parent_name_not_available')
    return dict(status='resolved',entities=[dict(lei=lei,direct=direct,ultimate=ultimate,warnings=warnings)],
                parents=[parents[p] for p in sorted(parent_ids) if p in parents])


def main():
    client=Client()
    print(json.dumps({'phase':'read_scope'}),flush=True)
    rows=scope()
    if not rows:raise GleifError('Empty legal-entity scope')
    pending=[r for r in rows if due(r['identity'])]
    for offset in range(0,len(pending),100):
        batch=pending[offset:offset+100];orgs=[r['org_nr'] for r in batch]
        payloads,published=client.identities(orgs)
        records=[record(r,payloads[r['org_nr']],{'provider':'GLEIF','api_publish_date':published,
            'source_url':'https://api.gleif.org/api/v1/lei-records','matching_rule':'SE-RA000544-exact-org-1','license':'CC0-1.0','afr_sync_id':r['afr_sync_id']}) for r in batch]
        store('identity',records)
        print(json.dumps({'identity_checked_this_run':min(offset+100,len(pending)),'identity_due_at_start':len(pending)}),flush=True)
    if pending:rows=scope()
    print(json.dumps({'phase':'read_relationship_sources'}),flush=True)
    pending=[r for r in rows if r['identity'] and (due(r['relations']) or
        r['relations']['source'].get('identity_sha256')!=r['identity']['sha256'])]
    if not pending:
        coverage=api.call('gleif-coverage')
        period=max((r['relations']['source'].get('release','identity-only') for r in rows),default='identity-only')
        details={**coverage,'remaining_due':0,'api_requests':client.requests,'license':'CC0-1.0'}
        api.log(SOURCE,'no_change',period,details)
        print(json.dumps(details),flush=True)
        return
    needed={e['lei'] for r in pending if r['identity']['payload']['status']=='matched' for e in r['identity']['payload']['entities']}
    data,source=load(client,needed) if needed else ({'rr':{},'repex':{}},{'license':'CC0-1.0'})
    parent_ids={r['Relationship.EndNode.NodeID'] for rs in data['rr'].values() for r in rs
                if r.get('Relationship.RelationshipType') in RR.values() and r.get('Relationship.EndNode.NodeIDType')=='LEI'}
    print(json.dumps({'phase':'read_parent_names','parents_to_check':len(parent_ids)}),flush=True)
    parents={};parent_dates=set()
    for offset in range(0,len(parent_ids),100):
        found,pub=client.parents(set(sorted(parent_ids)[offset:offset+100]));parents.update(found)
        if pub:parent_dates.add(pub)
    print(json.dumps({'phase':'store_relations','records_to_store':len(pending)}),flush=True)
    counts=Counter()
    for offset in range(0,len(pending),50):
        batch=pending[offset:offset+50];records=[]
        for r in batch:
            payload=reserved_tree(r['identity']['payload'],data,parents);counts[payload['status']]+=1
            provenance={**source,'afr_sync_id':r['afr_sync_id'],'identity_sha256':r['identity']['sha256'],'parent_api_publish_dates':sorted(parent_dates)}
            records.append(record(r,payload,provenance))
        store('relations',records)
        if (offset+len(batch))%500==0:print(json.dumps({'relations_stored_this_run':offset+len(batch),'counts':counts}),flush=True)
    coverage=api.call('gleif-coverage')
    # Re-read current scope; a publication during the run must not look complete.
    print(json.dumps({'phase':'verify_final_scope'}),flush=True)
    final=scope();missing=sum(1 for r in final if due(r['identity']) or due(r['relations']) or
        r['relations']['source'].get('identity_sha256')!=r['identity']['sha256'])
    details={**coverage,'remaining_due':missing,'api_requests':client.requests,'semantic_scope':'accounting_consolidation_not_shareholding',
             'relation_source':source,'license':'CC0-1.0'}
    api.log(SOURCE,'waiting' if missing else 'succeeded',source.get('release','identity-only'),details)
    print(json.dumps(details,ensure_ascii=False),flush=True)


if __name__=='__main__':
    try:main()
    except Exception as exc:
        try:api.log(SOURCE,'failed','unknown',{'error_type':type(exc).__name__},'GLEIF import failed; previous snapshots retained')
        except Exception:pass
        # GleifError messages are controlled constants / HTTP codes, never source records.
        details={'gleif_failed':True,'error_type':type(exc).__name__}
        if isinstance(exc,GleifError):details['reason']=str(exc)
        print(json.dumps(details),flush=True)
        raise SystemExit(1)
