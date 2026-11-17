"""Read-only census of quarantined AB packages. Persist aggregates only.

Never calls prepare, quarantine or account; company/document identifiers and
source bytes stay in runner memory. This diagnostic does not relax the parser.
"""
import hashlib
import io
import json
import time
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
from . import api
from .bolagsverket_api import Client, ApiError, newest
from .compare_api import inspect
from .import_accounts import extract, read_package
from .ixbrl import parse, VERSION

REASONS = {
    'missing report scope declaration': 'missing_report_scope',
    'missing or ambiguous reporting period': 'missing_or_ambiguous_period',
    'reversed reporting period': 'reversed_period',
    'missing or conflicting reporting currency': 'missing_or_conflicting_currency',
    'no company-level metrics in supported taxonomy': 'no_supported_company_metrics',
    'conflicting accounting frameworks': 'conflicting_frameworks',
    'oversized XML or DTD/entity declaration': 'xml_security_limit',
    'No supported company report': 'no_supported_company_report',
    'Conflicting company reports in one package': 'conflicting_company_reports',
    'Oversized uncompressed company package': 'archive_security_limit',
}


def reason(exc):
    if isinstance(exc, ET.ParseError):
        return 'invalid_xml'
    if isinstance(exc, zipfile.BadZipFile):
        return 'invalid_zip'
    return REASONS.get(str(exc), 'unclassified_parser_error')


def diagnose(data, row):
    formats = inspect(data)
    hashes = set()
    errors = Counter()
    valid = 0
    if data.startswith(b'%PDF-'):
        return {'outcome': 'pdf_only', 'formats': formats, 'errors': {}, 'hashes': hashes, 'valid_documents': 0}
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for entry in z.infolist():
            if not entry.filename.lower().endswith(('.xhtml', '.html')):
                continue
            content = z.read(entry)
            hashes.add(hashlib.sha256(content).hexdigest())
            try:
                parse(content, row['org_nr'], row['period_end'])
                valid += 1
            except (ValueError, ET.ParseError) as exc:
                errors[reason(exc)] += 1
    try:
        extract(data, row)
        outcome = 'supported_company_report'
    except (ValueError, zipfile.BadZipFile) as exc:
        outcome = reason(exc)
    return {'outcome': outcome, 'formats': formats, 'errors': dict(errors), 'hashes': hashes, 'valid_documents': valid}


def inventory():
    rows, after = [], None
    for page in range(100):
        # Publication is separate from git sync; wait only on unknown route.
        for attempt in range(21):
            try:
                batch = api.call('quarantine-audit', **({'after': after} if after else {}))
                break
            except RuntimeError as exc:
                if str(exc) != 'ETL quarantine-audit: HTTP 400' or attempt == 20:
                    raise
                time.sleep(15)
        if not batch:
            return rows
        rows.extend(batch)
        after = batch[-1]['je_id']
    raise ApiError('Quarantine inventory exceeds safety bound')


def add_diagnostic(summary, prefix, result):
    summary[prefix + '_outcomes'][result['outcome']] += 1
    summary[prefix + '_document_errors'].update(result['errors'])
    summary[prefix + '_formats'].update(result['formats'])
    # Count companies affected, as well as documents (packages can contain
    # auxiliary filings that are correctly rejected as non-annual-reports).
    for code in result['errors']:
        summary[prefix + '_companies_with_document_error'][code] += 1


def save(summary):
    Path('company-quarantine-audit.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')


def main():
    client = Client()
    rows = inventory()
    summary = {'mode': 'read_only_quarantine_census', 'parser_version': VERSION,
               'inventory_count': len(rows), 'companies_checked': 0, 'requests': 0,
               'counts': Counter(), 'comparison_matrix': Counter()}
    for prefix in ('stored', 'api'):
        for suffix in ('outcomes', 'document_errors', 'formats', 'companies_with_document_error'):
            summary[prefix + '_' + suffix] = Counter()
    save(summary)
    for row in rows:
        counts = summary['counts']
        try:
            original = diagnose(read_package(row), row)
            add_diagnostic(summary, 'stored', original)
            counts['stored_packages_verified'] += 1
        except Exception:
            # Request errors may contain signed URLs; never stringify them.
            counts['stored_read_or_diagnostic_failures'] += 1
            summary['companies_checked'] += 1
            save(summary)
            continue
        try:
            documents = client.documents(row['org_nr'])
            counts['api_documents_listed'] += len(documents)
            if not documents:
                counts['api_no_documents'] += 1
                continue
            counts['api_with_documents'] += 1
            try:
                latest = newest(documents)
            except ApiError:
                counts['api_ambiguous_selection'] += 1
                continue
            period = latest['rapporteringsperiodTom']
            counts['api_same_period' if period == row['period_end'] else 'api_newer_period' if period > row['period_end'] else 'api_older_period'] += 1
            data = client.document(latest['dokumentId'])
            result = diagnose(data, {**row, 'period_end': period})
            add_diagnostic(summary, 'api', result)
            counts['api_downloaded'] += 1
            counts['same_package_sha256' if hashlib.sha256(data).hexdigest() == row['package_sha256'] else 'different_package_sha256'] += 1
            if original['hashes'] and result['hashes']:
                counts['identical_xhtml_set' if original['hashes'] == result['hashes'] else 'different_xhtml_set'] += 1
                if original['hashes'] & result['hashes']:
                    counts['shared_xhtml_document'] += 1
            summary['comparison_matrix'][original['outcome'] + ' -> ' + result['outcome']] += 1
        except Exception:
            counts['api_request_or_diagnostic_failures'] += 1
        finally:
            summary['companies_checked'] += 1
            summary['requests'] = client.requests
            save(summary)
            if summary['companies_checked'] % 10 == 0:
                print(json.dumps({'checked': summary['companies_checked'], 'total': len(rows)}), flush=True)
    summary['complete'] = (summary['companies_checked'] == len(rows)
                           and not summary['counts']['stored_read_or_diagnostic_failures']
                           and not summary['counts']['api_request_or_diagnostic_failures'])
    save(summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    if not summary['complete']:
        raise SystemExit(1)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        # Never log arbitrary exceptions, identities or signed URLs.
        print(json.dumps({'audit_failed': True, 'error_type': type(exc).__name__}))
        raise SystemExit(1)
