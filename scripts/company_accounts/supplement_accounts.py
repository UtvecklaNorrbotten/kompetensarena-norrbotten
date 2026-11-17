"""Checkpointed private supplements. Never changes verified accounts or allocations."""
import hashlib
import io
import json
import time
import zipfile
from collections import Counter
import xml.etree.ElementTree as ET
from . import api
from .bolagsverket_api import Client, ApiError, newest
from .import_accounts import read_package
from .ixbrl import parse

VERSION = 'bv-supplement-1'


def extract_reserved(package, org, end):
    reports = []
    with zipfile.ZipFile(io.BytesIO(package)) as z:
        entries = z.infolist()
        if len(entries)>1000 or sum(i.file_size for i in entries)>100_000_000:
            raise ValueError('Oversized package')
        for entry in entries:
            if not entry.filename.lower().endswith(('.xhtml','.html')):
                continue
            content = z.read(entry)
            try:
                report = parse(content,org,end,allow_legacy_k2=True)
                reports.append((entry.filename,content,report))
            except (ValueError,ET.ParseError):
                continue
    signatures = {json.dumps((r['period_start'],r['period_end'],r['currency'],r['metrics']),sort_keys=True) for _,_,r in reports}
    if len(signatures)!=1:
        raise ValueError('No unique supported report')
    _,content,report = sorted(reports,key=lambda x:x[0])[0]
    return report,hashlib.sha256(content).hexdigest()


def as_zip(data):
    if zipfile.is_zipfile(io.BytesIO(data)):
        return data
    if data.startswith(b'%PDF-'):
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as z:
            z.writestr('source.pdf',data)
        return stream.getvalue()
    if data.lstrip().startswith((b'<?xml',b'<html',b'<!DOCTYPE')):
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as z:
            z.writestr('source.xhtml',data)
        return stream.getvalue()
    stream=io.BytesIO()
    with zipfile.ZipFile(stream,'w',zipfile.ZIP_DEFLATED) as z:
        z.writestr('source.bin',data)
    return stream.getvalue()


def queue(mode,after=None):
    for attempt in range(21):
        try:
            return api.call('supplement-queue',mode=mode,**({'after':after} if after else {}))
        except RuntimeError as exc:
            if str(exc)!='ETL supplement-queue: HTTP 400' or attempt==20:
                raise
            time.sleep(15)


def process(row,mode,client=None):
    result=dict(origin=mode,package_sha256=None,document_sha256=None,period_end=row.get('period_end'),
        document=None,quality_status='source_only',reason='unsupported_report',documents_count=0,source={})
    if mode=='bulk':
        data=read_package(row)
        result['source']={'archive_etag':row['archive_etag'],'storage_path':'accounts/'+row['package_sha256']+'.zip'}
    else:
        try:
            docs=client.documents(row['org_nr'])
            result['documents_count']=len(docs)
            if not docs:
                result['reason']='api_no_documents'
                return result
            try:
                doc=newest(docs)
            except ApiError:
                result['reason']='api_ambiguous'
                return result
            result['period_end']=doc['rapporteringsperiodTom']
            raw=client.document(doc['dokumentId'])
            data=as_zip(raw)
            result['source']={'document_id':doc['dokumentId'],'registration':doc.get('registreringstidpunkt'),
                'source_reference':'https://gw.api.bolagsverket.se/vardefulla-datamangder/v1/dokument/'+doc['dokumentId'],
                'download_sha256':hashlib.sha256(raw).hexdigest()}
        except ApiError:
            result['reason']='api_error'
            return result
    sha=hashlib.sha256(data).hexdigest()
    api.upload(data,sha)
    result['package_sha256']=sha
    try:
        report,document_sha=extract_reserved(data,row['org_nr'],result['period_end'])
        result.update(document=report,document_sha256=document_sha,quality_status='with_reservation',
            reason='legacy_k2_missing_scope' if 'legacy_k2_missing_scope_declaration' in report['issues'] else 'api_report_saved')
    except (ValueError,zipfile.BadZipFile):
        result['reason']='unsupported_report'
    return result


def run_mode(mode,limit):
    client=Client() if mode=='api' else None
    counts=Counter();after=None
    while sum(counts.values())<limit:
        rows=queue(mode,after)
        if not rows:break
        for row in rows[:limit-sum(counts.values())]:
            result=process(row,mode,client)
            api.call('supplement-result',{'je_id':row['je_id'],'result':result})
            counts[result['reason']]+=1
            after=row['je_id']
            if sum(counts.values())%25==0:
                print(json.dumps({'mode':mode,'completed':sum(counts.values()),'counts':counts}),flush=True)
    print(json.dumps({'mode':mode,'completed':sum(counts.values()),'counts':counts,
        'api_requests':client.requests if client else 0,'more_due':bool(queue(mode))}),flush=True)


def main():
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--api-limit',type=int,default=500);args=p.parse_args()
    run_mode('bulk',1000)
    run_mode('api',args.api_limit)


if __name__=='__main__':
    try:main()
    except Exception as exc:
        print(json.dumps({'supplement_failed':True,'error_type':type(exc).__name__}),flush=True)
        raise SystemExit(1)
