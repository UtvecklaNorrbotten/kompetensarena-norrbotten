"""Delta-only protected names/address history; contact values are overwritten.

Consumes filtered pages captured during the existing AFR traversal. If a core
sync needed no traversal (e.g. first profile backfill), stages one verified full
AFR traversal before any enrichment writes. Never changes core AFR tables.
"""
import gzip
import hashlib
import json
import os
from pathlib import Path
import time
from collections import Counter
from . import api
from .source import request

SOURCE = 'scb-afr-profiles'
FIELDS = {'je': ('peOrgNr','namn','foretagsnamn','postAdress','expImp','tel','epost'),
          'ae': ('cfarNr','ben','postAdress','belagenhetsadress','geografiskInformation','tel','epost')}


def canonical(obj):
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(',', ':'))


def text(value):
    if value is None:
        return None
    if not isinstance(value, str):
        raise ValueError('Unexpected AFR string field type')
    return value.strip() or None


def profile(row, entity):
    post = row.get('postAdress') or {}
    dat = {'postAdress': {k: text(post.get(k)) for k in ('gatuAdress','coAdress','postNr','postOrt')}}
    if entity == 'je':
        dat.update(namn=text(row.get('namn')), foretagsnamn=text(row.get('foretagsnamn')), expImp=text(row.get('expImp')))
        key = row['peOrgNr']
    else:
        address = row.get('belagenhetsadress') or {}
        geo = row.get('geografiskInformation') or {}
        coords = {k: geo.get(k) for k in ('nordKoordinatAdressSW','ostKoordinatAdressSW')}
        if any(v is not None and (not isinstance(v, int) or isinstance(v, bool)) for v in coords.values()):
            raise ValueError('Unexpected AFR coordinate type')
        # SCB uses zero coordinates when no geocoding is available.
        coords = {k: None if v == 0 else v for k, v in coords.items()}
        dat.update(ben=text(row.get('ben')), belagenhetsadress={k:text(address.get(k)) for k in ('bGatuAdress','bPostNr','bPostOrt')}, address_coordinates=coords)
        key = str(row['cfarNr'])
    if not key:
        raise ValueError('Missing profile identity')
    con = {k:text(row.get(k)) for k in ('tel','epost')}
    pc, cc = canonical(dat), canonical(con)
    return dict(key=key, profile_canonical=pc, contact_canonical=cc,
                profile_hash=hashlib.sha256(pc.encode()).hexdigest(), contact_hash=hashlib.sha256(cc.encode()).hexdigest())


_last_call = 0

def scb(path, **params):
    global _last_call
    from urllib.parse import urlencode
    wait = _last_call + 3 - time.monotonic()
    if wait > 0:
        time.sleep(wait)
    _last_call = time.monotonic()
    url = 'https://apiafr.scb.se/v1/' + path + ('?' + urlencode(params) if params else '')
    with request(url, {'X-API-Key': os.environ['SCB_AFR_API_KEY']}) as response:
        return json.load(response)


def stage(folder, sync):
    info = scb('api-info')
    if info['senasteUppdateringsDatum'] != sync['source_date']:
        raise ValueError('AFR core must publish current SCB source before profile backfill')
    counts = {e:scb(p+'/count')['count'] for e,p in [('je','juridiskaenheter'),('ae','arbetsstallen')]}
    for entity, path, field in [('je','juridiskaenheter','jes'),('ae','arbetsstallen','arbetsstallen')]:
        cursor = None
        seen, cursors = set(), set()
        page = 0
        while True:
            body = scb(path+'/full', limit=5000, **({'cursorId':cursor} if cursor is not None else {}))
            rows = body[field]
            filtered = []
            for row in rows:
                identifier = str(row['peOrgNr' if entity=='je' else 'cfarNr'])
                if identifier in seen:
                    raise ValueError('Duplicate profile identity in AFR traversal')
                seen.add(identifier)
                filtered.append({k:row[k] for k in FIELDS[entity] if k in row})
            page += 1
            with gzip.open(folder/f'{entity}_{page:05}.json.gz','wt',encoding='utf-8') as target:
                json.dump(filtered,target,ensure_ascii=False)
            pagination = body['pagination']
            if pagination['hasMore'] is False:
                break
            cursor = pagination['nextCursorId']
            if cursor in cursors:
                raise ValueError('AFR profile cursor repeated')
            cursors.add(cursor)
        if len(seen) != counts[entity] or counts[entity] != sync[entity+'_source_count']:
            raise ValueError('AFR profile traversal count mismatch')
    after = {e:scb(p+'/count')['count'] for e,p in [('je','juridiskaenheter'),('ae','arbetsstallen')]}
    if after != counts or scb('api-info')['senasteUppdateringsDatum'] != sync['source_date']:
        raise ValueError('AFR source changed during profile traversal')
    proof = dict(source_date=sync['source_date'],je_observed=counts['je'],ae_observed=counts['ae'],has_more_false=True)
    (folder/'manifest.json').write_text(json.dumps(proof))
    return proof


def main():
    state = api.call('state')
    sync = state['sync']
    if not sync:
        raise ValueError('No published AFR source')
    if state['profiles'] and state['profiles']['source_date'] == sync['source_date']:
        print('AFR profile source unchanged')
        return
    folder = Path(os.environ.get('AFR_PROFILE_CACHE', '/tmp/afr-profile-pages'))
    folder.mkdir(parents=True,exist_ok=True)
    manifest = folder/'manifest.json'
    if manifest.exists():
        proof = json.loads(manifest.read_text())
        if proof['source_date'] != sync['source_date']:
            raise ValueError('Profile staging source does not match published AFR')
    else:
        for p in folder.glob('*.json.gz'):
            p.unlink()
        proof = stage(folder,sync)
    observed = {'je':0,'ae':0}
    versions = contacts = 0
    codes = Counter()
    for entity in ('je','ae'):
        seen = set()
        for path in sorted(folder.glob(entity+'_*.json.gz')):
            with gzip.open(path,'rt',encoding='utf-8') as file:
                rows = json.load(file)
            for start in range(0,len(rows),1000):
                records = [profile(r,entity) for r in rows[start:start+1000]]
                for record in records:
                    if record['key'] in seen:
                        raise ValueError('Duplicate profile cache identity')
                    seen.add(record['key'])
                    if entity=='je':
                        codes[json.loads(record['profile_canonical'])['expImp']] += 1
                old = {r[0]:(r[1],r[2]) for r in api.call('profile-hashes',dict(entity=entity,keys=[r['key'] for r in records]))}
                changed = [r for r in records if old.get(r['key']) != (r['profile_hash'],r['contact_hash'])]
                if changed:
                    result = api.call('profiles',dict(sync_id=sync['id'],entity=entity,records=changed))
                    versions += result['versions']
                    contacts += result['contacts_updated']
                observed[entity] += len(records)
            if observed[entity] % 100000 == 0:
                print(json.dumps({'entity':entity,'observed':observed[entity],'new_versions':versions}),flush=True)
        if observed[entity] != proof[entity+'_observed'] or observed[entity] != sync[entity+'_source_count']:
            raise ValueError('Profile cache count mismatch')
    proof.update(versions_created_this_run=versions,contacts_updated_this_run=contacts,expImp_observed=dict(codes))
    api.call('profiles-complete',dict(sync_id=sync['id'],details=proof))
    api.log(SOURCE,'succeeded',sync['source_date'],proof)
    print(json.dumps(proof,ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        try:
            api.log(SOURCE,'failed','unknown',{'error_type':type(exc).__name__},'AFR profile enrichment failed; existing history retained')
        finally:
            raise
