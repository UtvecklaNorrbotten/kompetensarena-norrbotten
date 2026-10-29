"""UKÄ genomströmning och regional rekrytering; publicering via ordinarie UKÄ-batch-API.

Kör utan --publish för en fullständig käll- och dimensionskontroll. Inga härledda
antal skapas. Uppgifter som inte kan tolkas säkert stoppar aktuell källa.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import time
import subprocess
from datetime import date, datetime, timezone
from email.utils import parsedate_to_datetime
from urllib.parse import urljoin
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from bs4 import BeautifulSoup
from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/uka_extended'
SM_PAGE = 'https://www.uka.se/statistik-och-analys/om-var-statistik/statistiska-meddelanden'
SCB205 = 'https://www.scb.se/uf0205'
SCB208 = 'https://www.scb.se/uf0208'
EXPORT = 'https://statistik-www.uka.se/export'
SOURCE_ID = 'uka-genomstromning-regional'
API_IDS = {77: 'uka-kvarvaro-hogskolenyborjare', 134: 'uka-kvarvaro-program', 135: 'uka-examensfrekvens'}
REGIONAL_IDS = ['uka-regional-examinerade', 'uka-regional-rekryterade-antal', 'uka-regional-bosatta-antal',
                'uka-regional-rekryterade-andel', 'uka-regional-bosatta-andel']
SESSION = requests.Session()
SESSION.headers['User-Agent'] = 'Kompetensarena-Norrbotten-UKA-ETL/2.0'
SESSION.mount('https://', HTTPAdapter(max_retries=Retry(total=4, backoff_factor=2,
    status_forcelist=[429, 500, 502, 503, 504], allowed_methods=['GET', 'HEAD'])))


def get(url):
    r = SESSION.get(url, timeout=(30, 240))
    r.raise_for_status()
    return r


def digest(x):
    return hashlib.sha256(json.dumps(x, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def number(x):
    if x is None or str(x).strip() in ('', '.', '..', '...', ':'):
        return None
    if str(x).strip() in ('–', '—', '-'):
        return 0.0  # SCB:s teckenförklaring: noll
    v = float(str(x).replace('\xa0', '').replace(' ', '').replace(',', '.'))
    if not math.isfinite(v):
        raise ValueError(f'Icke ändligt värde: {x}')
    return v


def validate(rows, percentage=True, required_program=False):
    if not rows:
        raise ValueError('Tom källa får inte ersätta aktiv batch')
    seen = set()
    for r in rows:
        if not re.fullmatch(r'\d{4}/\d{2}', r['period']):
            raise ValueError(f'Oväntad period: {r["period"]}')
        y = int(r['period'][:4])
        if r['period'][-2:] != f'{(y+1)%100:02d}' or not 1977 <= y <= date.today().year:
            raise ValueError(f'Orimlig period: {r["period"]}')
        if not r['university'] or r.get('gender', 'Total') not in ('Total', 'Kvinnor', 'Män'):
            raise ValueError('Ogiltigt lärosäte/kön')
        dims = r.get('dimensions', {})
        if required_program and 'program' not in dims:
            raise ValueError('Programdimension saknas')
        if any('bakgrund' in k.lower() for k in dims):
            raise ValueError('Bakgrundsdimension får inte importeras')
        v = r['value']
        if v is not None and (not math.isfinite(v) or v < 0 or (percentage and v > 100)):
            raise ValueError(f'Orimligt värde: {r}')
        key = (r['period'], r['university'], r.get('gender', ''), json.dumps(dims, sort_keys=True))
        if key in seen:
            raise ValueError(f'Dubblett: {key}')
        seen.add(key)
    if not any(r['university'] == 'Luleå tekniska universitet' for r in rows):
        raise ValueError('LTU saknas: kontrollera att hela lärosätesurvalet hämtats')


def options(html, prefix):
    s = BeautifulSoup(html, 'html.parser')
    return list(dict.fromkeys(e['value'] for e in s.select('[value]') if e['value'].startswith(prefix)))


def api_metadata(id):
    return get(f'https://statistik-api.uka.se/api/totals/{id}/').json()


def api_rows(id, cache=None):
    html = {}
    for ep in ['academic_term.php?direction=from', 'university.php', 'gender.php', 'age.php', 'group.php']:
        k = ep.split('.')[0]
        local = Path(cache) / f'{id}_{k}.html' if cache else None
        html[k] = local.read_text() if local and local.exists() else get(
            f'{EXPORT}/filters/{ep}'+('&' if '?' in ep else '?')+'indicator='+requests.utils.quote(json.dumps([str(id)]))).text
    periods = options(html['academic_term'], 'from:')
    if not periods:
        raise ValueError(f'UKÄ {id}: perioder saknas')
    filters = [periods[-1], periods[0].replace('from:', 'to:')]
    for key, prefix in [('university','uni:'),('gender','gender:'),('age','age:')]:
        vals = options(html[key], prefix)
        if not vals:
            raise ValueError(f'UKÄ {id}: filter {key} saknas')
        filters += vals
    s = BeautifulSoup(html['group'], 'html.parser')
    for g in s.select('.groupTitles'):
        ix = g.select_one('.dynamic-filter-index').get_text(strip=True)
        filters += [ix+v for v in options(str(g), 'dynamic:')]
    local = Path(cache) / f'export{id}.csv' if cache else None
    if local and local.exists():
        raw = local.read_text(encoding='utf-8-sig')
    else:
        # Export skapar bara en källfil; återförsök av detta anrop ändrar inga observationer.
        r = SESSION.post(f'{EXPORT}/api/index.php', data=[('indicator', str(id))]+[('filters[]',v) for v in filters],
                         headers={'X-Requested-With':'XMLHttpRequest'}, timeout=(30,300))
        r.raise_for_status()
        raw = get(r.json()['fileUrl']).content.decode('utf-8-sig')
    reader = csv.DictReader(io.StringIO(raw), delimiter=';')
    expected = {'Tidsperiod','Lärosäte','Kön','Åldersgrupp','Värde'} | ({'Program'} if id != 77 else set())
    if set(reader.fieldnames or []) != expected:
        raise ValueError(f'UKÄ {id}: ändrade CSV-kolumner {reader.fieldnames}')
    rows=[]
    for r in reader:
        period = r['Tidsperiod'].removeprefix('="').removesuffix('"')
        if 'from:'+period not in periods:
            raise ValueError('Export innehåller ej begärd period')
        dims={'aldersgrupp':r['Åldersgrupp']}
        if id != 77:
            dims['program'] = r['Program'] or 'Total'
        if not dims['aldersgrupp']:
            raise ValueError('Åldersgrupp saknas')
        rows.append(dict(period=period, university=r['Lärosäte'] or 'Riket', gender=r['Kön'],
                         value=number(r['Värde']), dimensions=dims))
    validate(rows, required_program=id != 77)
    return rows


def performance_rows(content):
    wb=load_workbook(io.BytesIO(content), read_only=True, data_only=True)
    result=[]
    for sheet,gender in [('Totalt','Total'),('Kvinnor_Women','Kvinnor'),('Män_Men','Män')]:
        data=list(wb[sheet].values)
        header=next((i for i,r in enumerate(data) if any(str(x)=='Prestationsgrad i procent' for x in r)),None)
        if header is None:
            raise ValueError('Prestationsgradens rubrik saknas')
        start=data[header].index('Prestationsgrad i procent')
        cols=[(j,str(v)) for j,v in enumerate(data[header+1]) if j>=start and re.fullmatch(r'\d{4}/\d{2}',str(v))]
        if not cols:
            raise ValueError('Prestationsgradens perioder saknas')
        university=program=mode=None
        for r in data[header+2:]:
            if not any(v is not None for v in r[3:]):
                continue
            if r[0]:
                university=str(r[0]).strip();program=mode='Total'
            elif r[1]:
                program=str(r[1]).strip();mode='Total'
            elif r[2]:
                mode=str(r[2]).strip()
            else:
                raise ValueError('Rad utan dimensionsetikett')
            if not university or program not in ('Total','Yrkesexamensprogram','Generella program','Fristående kurser','Fristående kurs') or mode not in ('Total','Campus','Distans'):
                raise ValueError(f'Ändrad prestationsstruktur: {r[:3]}')
            for col,period in cols:
                result.append(dict(period=period,university=university,gender=gender,value=number(r[col]),
                                   dimensions={'program-kurs':program,'campus-distans':mode}))
    wb.close()
    validate(result)
    return result


def discover_link(page, text):
    s=BeautifulSoup(page.text,'html.parser')
    links=[urljoin(page.url,a['href']) for a in s.select('a[href]') if text in a.get_text(' ',strip=True)]
    links=list(dict.fromkeys(links))
    if len(links)!=1:
        raise ValueError(f'Förväntade en källa för {text}: {links}')
    return links[0]


def report_sources(page):
    s=BeautifulSoup(page.text,'html.parser')
    return [(a.get_text(' ',strip=True), urljoin(page.url,a['href'])) for a in s.select('a[href]')
            if 'Tabellbilaga' not in a.get_text() and 'Studenter och examinerade på grundnivå och avancerad nivå' in a.get_text() and '.pdf' in a['href'].lower()]


def regional_rows(content):
    """Läs fem separata sifferkolumner geometriskt; aldrig procent -> antal."""
    import pdfplumber
    result={k:[] for k in REGIONAL_IDS}
    warnings=[]
    with pdfplumber.open(io.BytesIO(content)) as pdf:
        found=False
        text_pages=subprocess.run(['pdftotext','-layout','-','-'], input=content, capture_output=True, check=True).stdout.decode('utf-8').split('\f')
        candidates=[i for i,t in enumerate(text_pages) if 'Luleå tekniska universitet' in t and 'högskolelänet' in t]
        for index in candidates:
            pg=pdf.pages[index]
            text=pg.extract_text() or ''
            normalized=re.sub(r'-\s+', '', text).replace('\n',' ')
            if 'högskolelänet' not in normalized or 'Luleå tekniska universitet' not in text:
                pg.close();continue
            title=re.search(r'(?:Tabell\s+(\d+)\.\s*)?Examinerade personer\s+(\d{4}/\d{2}).*?per lärosäte',normalized)
            follow=re.search(r'boende i högskolelänet\s+(\d{4}-12-31)',normalized,re.I)
            if not title or not follow:
                pg.close();continue
            lines=pg.extract_text_lines()
            anchor=next(l for l in lines if l['text'].startswith('Luleå tekniska universitet'))
            words=pg.crop((0,anchor['top']-1,pg.width,anchor['bottom']+1)).extract_words()
            nums=[w for w in words if re.fullmatch(r'\d+',w['text'])]
            groups=[]
            for w in nums:
                if groups and w['x0']-groups[-1][-1]['x1']<5:
                    groups[-1].append(w)
                else:
                    groups.append([w])
            if len(groups)!=5:
                raise ValueError('Kunde inte identifiera fem regionala sifferkolumner')
            ends=[g[-1]['x1']+1 for g in groups]
            first=ends[0]-45
            rows=[]
            for l in lines:
                if not re.search(r'\s\d[\d ]+\s\d+\s\d+$',l['text']):
                    continue
                if l['top'] < anchor['top']-500 or l['top'] > anchor['top']+250:
                    continue
                chars=sorted(l['chars'],key=lambda c:c['x0'])
                name_match=re.match(r'^(.*?[A-Za-zÅÄÖåäö])([1-9])?\s+\d',l['text'])
                if not name_match:continue
                name=name_match[1]
                name=re.sub(r'\d+$','',name).strip()
                if not re.search(r'universitet|högskol|institut|Högskol',name):
                    continue
                vals=[]
                for j,end in enumerate(ends):
                    lower=first if j==0 else ends[j-1]
                    token=''.join(c['text'] for c in chars if c['x0']>=lower and c['x1']<=end).replace(' ','')
                    if not token.isdigit():
                        raise ValueError(f'Otydlig regional cell {name}: {token}')
                    vals.append(int(token))
                if vals[0]<500 or not all(0<=v<=vals[0] for v in vals[1:3]) or not all(0<=v<=100 for v in vals[3:]):
                    raise ValueError(f'Orimliga regionala värden {name}: {vals}')
                for count,pct in [(vals[1],vals[3]),(vals[2],vals[4])]:
                    if abs(count/vals[0]*100-pct)>max(1.6,100*10/vals[0]):
                        raise ValueError(f'Antal/andel stämmer inte {name}: {vals}')
                rows.append((name,vals,name_match[2]))
            if not 20<=len(rows)<=50 or len({r[0] for r in rows})!=len(rows):
                raise ValueError(f'Oväntat antal regionala lärosäten: {len(rows)}')
            expected_counties={'Mälardalens högskola':['Södermanlands','Västmanlands'],
                               'Mälardalens universitet':['Södermanlands','Västmanlands'],
                               'Mittuniversitetet':['Västernorrlands','Jämtlands']}
            for name,vals,note in rows:
                if name in expected_counties and note:
                    footnote=re.search(r'\b'+note+r'\)\s*(.*?)(?=\b\d\)|SLU|$)',normalized)
                    if not footnote or any(c not in footnote[1] for c in expected_counties[name]):
                        warnings.append(f'{name} {title[2]}: motsägande hemlänsfotnot; raden spärrad');continue
                prose_share=re.search(r'Handelshögskolan i Stockholm där\s+(\d+)\s+procent',normalized)
                for id,v in zip(REGIONAL_IDS,vals):
                    if name=='Handelshögskolan i Stockholm' and id=='uka-regional-rekryterade-andel' and prose_share and int(prose_share[1])!=v:
                        warnings.append(f'{name} {title[2]}: tabell {v} %, löptext {prose_share[1]} %; andelen spärrad');continue
                    result[id].append(dict(period=title[2],university=name,value=v,
                         dimensions={'uppfoljningsdatum':follow[1]}))
            found=True
            pg.close()
            break
        if not found:
            raise ValueError('Regional tabell med verifierbar kohort saknas')
    for id,rows in result.items():
        validate(rows,percentage=id.endswith('andel'))
    return result,warnings


class Publisher:
    def __init__(self):
        self.base=os.environ['ETL_BASE_URL'].rstrip('/')
        self.session=requests.Session()
        self.session.headers.update({'Authorization':'Bearer '+os.environ['ETL_PUBLISH_KEY']})

    def request(self,path,payload=None,retry=False):
        for attempt in range(5 if retry else 1):
            try:
                r=self.session.request('GET' if payload is None else 'POST',self.base+'/api/public/jobs/'+path,
                                       json=payload,timeout=(30,240))
                if retry and r.status_code in (429,500,502,503,504) and attempt<4:
                    time.sleep(min(30,2**attempt));continue
                if not r.ok:
                    raise RuntimeError(f'{path}: HTTP {r.status_code}: {r.text[:800]}')
                return r.json()
            except (requests.Timeout,requests.ConnectionError):
                if not retry or attempt==4:raise
                time.sleep(min(30,2**attempt))

    def publish(self,id,rows,updated=None):
        chunks=[rows[i:i+2000] for i in range(0,len(rows),2000)]
        body=dict(indicator_id=id,source='UKÄ',expected_chunks=len(chunks),expected_rows=len(rows))
        if updated:body['kalla_uppdaterad_datum']=updated
        batch=self.request('uka/start',body)['batch_id']
        try:
            for i,c in enumerate(chunks):
                self.request('uka/chunk',dict(batch_id=batch,indicator_id=id,chunk_index=i,observations=c),retry=True)
                print(f'{id}: chunk {i+1}/{len(chunks)}',flush=True)
            result=self.request('uka/finalize',dict(batch_id=batch),retry=True)
            if result.get('rows')!=len(rows):raise ValueError(f'Publicerat radantal avviker: {result}')
            return result
        except Exception:
            self.request('uka/abort',dict(batch_id=batch,reason='UKÄ-utökning misslyckades'),retry=True)
            raise


def http_marker(url):
    r=SESSION.head(url,timeout=(30,60),allow_redirects=True)
    r.raise_for_status()
    return {'url':url,'last_modified':r.headers.get('Last-Modified'),'etag':r.headers.get('ETag'),
            'content_length':r.headers.get('Content-Length')}


def summarize(rows):
    return dict(rows=len(rows),null_values=sum(r['value'] is None for r in rows),
                periods=sorted({r['period'] for r in rows}),universities=len({r['university'] for r in rows}),
                dimensions=sorted({k for r in rows for k in r.get('dimensions',{})}),
                ltu_example=[r for r in rows if r['university']=='Luleå tekniska universitet' and r.get('gender','Total')=='Total'][:12])


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--publish',action='store_true')
    parser.add_argument('--force',action='store_true')
    parser.add_argument('--expect-no-change',action='store_true',help='Verifiera att ingen ny batch behövs')
    parser.add_argument('--cache',help='Lokal källkatalog för reproducerbar kontroll; kan inte publiceras')
    args=parser.parse_args()
    if args.cache and args.publish:raise ValueError('Lokala kontrollfiler får inte publiceras')
    OUT.mkdir(parents=True,exist_ok=True)
    pub=Publisher() if args.publish else None
    state=(pub.request('source-state?source_id='+SOURCE_ID).get('state') or {}) if pub else {}
    old=state.get('details') or {}
    quarter=f'{date.today().year}-Q{(date.today().month-1)//3+1}'
    summary={'sources':{},'warnings':[],'indicators':{}}
    sm=get(SM_PAGE)
    scb=get(SCB208)
    performance=discover_link(scb,'Prestationsgrad efter kön, lärosäte och program/kurs')
    regional=report_sources(sm)
    if len(regional)!=1:raise ValueError('Förväntade exakt en aktuell UF0205-rapport')
    history=json.loads((ROOT/'config/uka_regional_sources.json').read_text())
    # Senaste officiella rapporten prioriteras över den tidigare sparade URL:en.
    prior_reports=old.get('report',{}).get('sources',{}).get('regional',[])
    reports=[dict(title=regional[0][0],url=regional[0][1])]
    for r in prior_reports+history:
        if not any(r['title'][-7:] in x['title'] for x in reports):reports.append(r)
    markers={f'api-{id}':api_metadata(id) for id in API_IDS}
    markers['performance']=http_marker(performance)
    markers['regional']={'parser_version':2,'reports':[http_marker(r['url']) for r in reports]}
    hashes={k:digest(v) for k,v in markers.items()}
    summary['sources']={'http_metadata':{'performance':markers['performance'],'regional':markers['regional']},'performance':performance,'regional':reports,'metadata_fingerprints':hashes,
                        'api':{str(id):markers[f'api-{id}']['indicator'] for id in API_IDS}}
    force=args.force or old.get('revision_quarter')!=quarter
    if args.expect_no_change and (force or old.get('fingerprints')!=hashes):
        raise ValueError('Källmarkörer har ändrats; oförändrad kontroll kan inte bekräftas')
    def publish(id,rows,updated=None):
        summary['indicators'][id]=summarize(rows)
        if pub:summary['indicators'][id]['publication']=pub.publish(id,rows,updated)
        print(id,json.dumps(summary['indicators'][id],ensure_ascii=False)[:700],flush=True)
    try:
        for id,key in API_IDS.items():
            if force or old.get('fingerprints',{}).get(f'api-{id}')!=hashes[f'api-{id}'] or not pub:
                publish(key,api_rows(id,args.cache))
                # UKÄ:s totals-API saknar verifierbart uppdateringsdatum. Skicka inte hämtdatum som källdatum.
        if force or old.get('fingerprints',{}).get('performance')!=hashes['performance'] or not pub:
            raw=(Path(args.cache)/'performance.xlsx').read_bytes() if args.cache else get(performance).content
            modified=markers['performance']['last_modified']
            updated=parsedate_to_datetime(modified).date().isoformat() if modified else None
            publish('uka-prestationsgrad',performance_rows(raw),updated)
        if force or old.get('fingerprints',{}).get('regional')!=hashes['regional'] or not pub:
            all_rows={id:[] for id in REGIONAL_IDS}
            periods=set()
            for idx,report in enumerate(reports):
                raw=(Path(args.cache)/('report.pdf' if idx==0 else f'history-{report["title"][-7:].replace("/","-")}.pdf')).read_bytes() if args.cache else get(report['url']).content
                try:
                    data,warnings=regional_rows(raw)
                except ValueError as e:
                    # Hela importen stoppas om senaste rapportens struktur inte längre kan valideras.
                    raise ValueError(report['title']+': '+str(e)) from e
                period=data[REGIONAL_IDS[0]][0]['period']
                if period in periods:continue  # nyaste utgåvan vinner vid överlapp/revidering
                periods.add(period)
                summary['warnings']+=warnings
                for id,rows in data.items():all_rows[id]+=rows
            dates=[parsedate_to_datetime(m['last_modified']).date().isoformat() for m in markers['regional']['reports'] if m['last_modified']]
            updated=max(dates,default=None)
            for id,rows in all_rows.items():
                validate(rows,percentage=id.endswith('andel'))
                publish(id,rows,updated)
        if pub:
            period_report=summary['indicators'] or old.get('report',{}).get('indicators',{})
            latest=max((p for v in period_report.values() for p in v['periods']),default=state.get('latest_available_period'))
            pub.request('source-state',dict(source_id=SOURCE_ID,latest_available_period=latest,status='succeeded' if summary['indicators'] else 'no_change',
                details={'fingerprints':hashes,'revision_quarter':quarter,'report':summary}))
    except Exception as e:
        summary['error']=str(e)
        if pub:pub.request('source-state',dict(source_id=SOURCE_ID,status='failed',error_message=str(e)[:1000],details=old))
        raise
    finally:
        (OUT/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2))
    print(json.dumps({'rows':sum(s['rows'] for s in summary['indicators'].values()),'warnings':summary['warnings']},ensure_ascii=False),flush=True)

if __name__=='__main__':main()
