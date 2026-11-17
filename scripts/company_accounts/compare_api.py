"""Read-only API/bulk comparison. Only aggregate results may leave the runner."""
import hashlib
import io
import json
import re
import time
import zipfile
from collections import Counter
from . import api
from .bolagsverket_api import Client, ApiError, newest
from .import_accounts import extract


def inspect(data):
    if data.startswith(b'%PDF-'):
        return {'pdf':1,'xhtml':0,'other':0}
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            entries = archive.infolist()
            if len(entries)>1000 or sum(i.file_size for i in entries)>100_000_000:
                raise ApiError('Oversized document archive')
            formats = Counter()
            for entry in entries:
                if entry.is_dir():
                    continue
                # Sniff file bytes too: an extension alone does not establish PDF.
                with archive.open(entry) as member:
                    prefix = member.read(1024)
                kind = 'pdf' if prefix.startswith(b'%PDF-') else 'xhtml' if entry.filename.lower().endswith(('.xhtml','.html')) else 'other'
                formats[kind] += 1
            return dict(formats)
    except zipfile.BadZipFile:
        raise ApiError('Unsupported API document format') from None


def sample():
    # A push may start before the separately published ETL route is ready.
    for attempt in range(13):
        try:
            result = api.call('api-sample')
            if not result.get('samples'):
                raise ApiError('No comparison sample available')
            if not {'imported','absent'}.issubset({r.get('bulk_status') for r in result['samples']}):
                raise ApiError('Comparison requires both imported and absent companies')
            return result
        except RuntimeError as exc:
            if str(exc)!='ETL api-sample: HTTP 400' or attempt==12:
                raise
            time.sleep(15)


def main():
    client = Client()  # Fail early if secrets have not been configured.
    selection = sample()
    summary = {'mode':'read_only_comparison','sample_method':'first_uuid_pages_balanced_by_bulk_status',
        'scope_source':selection['source_date'],'groups':{},'requests':0}
    for row in selection['samples']:
        group = summary['groups'].setdefault(row['bulk_status'],Counter())
        group['companies_checked'] += 1
        documents = client.documents(row['org_nr'])
        group['with_api_documents' if documents else 'without_api_documents'] += 1
        group['documents_listed'] += len(documents)
        if not documents:
            continue
        try:
            document = newest(documents)
        except ApiError:
            group['ambiguous_metadata'] += 1
            continue
        period = document['rapporteringsperiodTom']
        if row.get('period_end'):
            relation = 'same_period' if period==row['period_end'] else 'api_newer_period' if period>row['period_end'] else 'api_older_period'
            group[relation] += 1
        data = client.document(document['dokumentId'])
        group['packages_downloaded'] += 1
        for fmt,count in inspect(data).items():
            group[fmt+'_files'] += count
        if row.get('package_sha256'):
            group['same_package_sha256' if hashlib.sha256(data).hexdigest()==row['package_sha256'] else 'different_package_sha256'] += 1
        if zipfile.is_zipfile(io.BytesIO(data)):
            try:
                _, content, parsed = extract(data,{'org_nr':row['org_nr'],'period_end':period})
                group['supported_company_reports'] += 1
                if row.get('document_sha256'):
                    group['same_document_sha256' if hashlib.sha256(content).hexdigest()==row['document_sha256'] else 'different_document_sha256'] += 1
            except (ValueError,zipfile.BadZipFile):
                group['unsupported_or_ambiguous_reports'] += 1
    summary['requests'] = client.requests
    text = json.dumps(summary,ensure_ascii=False,indent=2)
    print(text)
    from pathlib import Path
    Path('company-api-comparison.json').write_text(text+'\n',encoding='utf-8')


if __name__=='__main__':
    try:
        main()
    except Exception as exc:
        # No traceback: urllib errors can embed org numbers, URLs or tokens.
        safe_etl = isinstance(exc,RuntimeError) and re.fullmatch(r'ETL api-sample: HTTP \d{3}( \(SQLSTATE: [A-Z0-9]{5}\))?',str(exc))
        print(json.dumps({'comparison_failed':True,'error':str(exc) if isinstance(exc,ApiError) or safe_etl else type(exc).__name__}))
        raise SystemExit(1)
