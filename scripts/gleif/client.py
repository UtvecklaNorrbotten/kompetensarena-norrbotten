"""Public GLEIF API, no credentials. Bounded requests and safe error messages."""
import hashlib
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

BASE='https://api.gleif.org/api/v1/'
MANIFEST='https://goldencopy.gleif.org/api/v2/golden-copies/publishes/latest'
LEI=re.compile(r'^[A-Z0-9]{18}[0-9]{2}$')
ORG=re.compile(r'^([0-9]{6})-?([0-9]{4})$')

class GleifError(RuntimeError):pass

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):
        raise GleifError('Unexpected GLEIF redirect')


def canonical(value):
    return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':'))


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def org_number(value):
    m=ORG.fullmatch(value or '')
    return ''.join(m.groups()) if m else None


def entity(record):
    a=record['attributes'];e=a['entity'];r=a['registration'];lei=record['id']
    if a['lei']!=lei or not LEI.fullmatch(lei):raise GleifError('Invalid LEI record')
    # No source addresses/contacts copied. Original selected record hash retained.
    return dict(lei=lei,name=e['legalName']['name'],registered_as=e.get('registeredAs'),
        registry=e.get('registeredAt',{}).get('id'),jurisdiction=e.get('jurisdiction'),
        entity_status=e.get('status'),registration_status=r.get('status'),
        last_update=r.get('lastUpdateDate'),next_renewal=r.get('nextRenewalDate'),
        source_url=BASE+'lei-records/'+lei,source_record_sha256=digest(record))

class Client:
    def __init__(self):
        self.opener=urllib.request.build_opener(NoRedirect());self.next=0;self.requests=0

    def response(self,url,limit=12_000_000):
        u=urllib.parse.urlparse(url)
        if u.scheme!='https' or u.netloc not in ('api.gleif.org','goldencopy.gleif.org'):
            raise GleifError('Untrusted GLEIF source URL')
        for attempt in range(6):
            time.sleep(max(0,self.next-time.monotonic()));self.next=time.monotonic()+1.3
            self.requests+=1
            try:
                return self.opener.open(urllib.request.Request(url,headers={'User-Agent':'Kompetensarena-Norrbotten-GLEIF/1.0','Accept':'application/json, application/zip'}),timeout=90)
            except urllib.error.HTTPError as exc:
                if exc.code not in (408,429,500,502,503,504) or attempt==5:
                    resource='bulk' if u.path.startswith('/storage/golden-copy-files/') else 'manifest' if url==MANIFEST else 'api'
                    raise GleifError('GLEIF HTTP '+str(exc.code)+' resource='+resource) from None
                retry=exc.headers.get('Retry-After','');delay=min(120,int(retry)) if retry.isdigit() else min(30,2**attempt)
            except (TimeoutError,OSError):
                if attempt==5:raise GleifError('GLEIF network failure') from None
                delay=min(30,2**attempt)
            time.sleep(delay)

    def json(self,url):
        with self.response(url) as r:b=r.read(12_000_001)
        if len(b)>12_000_000:raise GleifError('Oversized GLEIF JSON')
        try:d=json.loads(b)
        except ValueError:raise GleifError('Invalid GLEIF JSON') from None
        if not isinstance(d,dict) or 'data' not in d:raise GleifError('Unexpected GLEIF schema')
        return d

    def search(self,filters):
        records=[];published=None;total=None
        for page in range(1,101):
            url=BASE+'lei-records?'+urllib.parse.urlencode({**filters,'page[size]':200,'page[number]':page})
            d=self.json(url)
            try:
                pub=d['meta']['goldenCopy']['publishDate'];p=d['meta']['pagination'];data=d['data']
                datetime.fromisoformat(pub.replace('Z','+00:00'))
                if not isinstance(data,list) or p['currentPage']!=page:raise ValueError()
                if published is not None and (pub!=published or p['total']!=total):raise ValueError()
                published=pub;total=p['total'];last=p['lastPage']
                if not isinstance(total,int) or not isinstance(last,int) or last>100:raise ValueError()
            except (KeyError,TypeError,ValueError):raise GleifError('Incomplete or changing GLEIF search') from None
            records.extend(data)
            if page>=last:
                if len(records)!=total or len({r['id'] for r in records})!=len(records):raise GleifError('Incomplete GLEIF pagination')
                return records,published
        raise GleifError('GLEIF pagination exceeded bound')

    def identities(self,orgs):
        spellings=[]
        for o in orgs:
            if not ORG.fullmatch(o):raise GleifError('Invalid organisation number')
            spellings.extend([o,o[:6]+'-'+o[6:]])
        records,published=self.search({'filter[entity.registeredAs]':','.join(spellings),'filter[entity.jurisdiction]':'SE'})
        result={o:[] for o in orgs}
        for raw in records:
            e=entity(raw);o=org_number(e['registered_as'])
            if o not in result:raise GleifError('Search returned an unrelated registry identifier')
            if e['registry']=='RA000544' and e['jurisdiction']=='SE':result[o].append(e)
        return {o:dict(status='matched' if len(es)==1 else 'ambiguous' if es else 'not_found',
                       entities=sorted(es,key=lambda e:e['lei'])) for o,es in result.items()},published

    def parents(self,leis):
        if not leis:return {},None
        if any(not LEI.fullmatch(x) for x in leis):raise GleifError('Invalid parent LEI')
        records,pub=self.search({'filter[lei]':','.join(sorted(leis))})
        result={}
        for raw in records:
            e=entity(raw)
            if e['lei'] not in leis:raise GleifError('Unrelated parent LEI')
            result[e['lei']]=e
        return result,pub
