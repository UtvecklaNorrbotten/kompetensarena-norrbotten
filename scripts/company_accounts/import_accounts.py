"""Resumable latest-account import. Catalog ZIP directories, then fetch only targets.

The catalog includes metadata from every available publication week so companies
with older latest filings are retained. Only one latest candidate's documents
per company are downloaded and parsed; no full accounts history is imported.
"""
import argparse
import hashlib
import io
import json
import re
import zipfile
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, as_completed
from . import api
from .allocation import allocate
from .ixbrl import parse, VERSION
from .source import archives, open_archive, ROOT, request

SOURCE = 'bolagsverket-annual-accounts'
MEMBER = re.compile(r'^(\d{10})_(\d{4}-\d{2}-\d{2})\.zip$')


def scope():
    result = []
    after = None
    while True:
        rows = api.call('scope', **({'after': after} if after else {}))
        if not rows:
            break
        result.extend(rows)
        after = rows[-1]['je_id']
    if not result:
        raise ValueError('Empty AFR company scope')
    return result


def scan(archive, companies, scope_hash):
    reader, z = open_archive(archive)
    candidates = []
    try:
        names = set()
        for info in z.infolist():
            match = MEMBER.fullmatch(info.filename)
            if not match or match[1] not in companies:
                continue
            if info.filename in names:
                raise ValueError('Duplicate filename in source ZIP')
            names.add(info.filename)
            candidates.append(dict(je_id=companies[match[1]], period_end=match[2], member_name=info.filename))
        ar = {**archive, 'members': len(z.infolist()), 'scope_hash': scope_hash, 'downloaded_bytes': reader.bytes_downloaded}
    finally:
        z.close()
        reader.close()
    api.call('catalog', {'archive': ar, 'candidates': candidates})
    return len(candidates), reader.bytes_downloaded


def read_package(candidate):
    if candidate.get('package_sha256'):
        signed = api.call('package', je_id=candidate['je_id'])
        with request(signed['signedUrl']) as response:
            data = response.read(40_000_001)
        if hashlib.sha256(data).hexdigest() != candidate['package_sha256']:
            raise ValueError('Stored package checksum mismatch')
        return data
    archive = dict(key=candidate['archive_key'], size=candidate['archive_size'], etag=candidate['archive_etag'])
    reader, z = open_archive(archive)
    try:
        matches = [i for i in z.infolist() if i.filename == candidate['member_name']]
        if len(matches) != 1 or matches[0].file_size > 40_000_000:
            raise ValueError('Missing, duplicate or oversized company package')
        return z.read(matches[0])
    finally:
        z.close()
        reader.close()


def extract(package, candidate):
    documents = []
    errors = []
    with zipfile.ZipFile(io.BytesIO(package)) as z:
        if sum(i.file_size for i in z.infolist()) > 100_000_000:
            raise ValueError('Oversized uncompressed company package')
        for info in z.infolist():
            if not info.filename.lower().endswith(('.xhtml', '.html')):
                continue
            data = z.read(info)
            try:
                result = parse(data, candidate['org_nr'], candidate['period_end'])
                documents.append((info.filename, data, result))
            except (ValueError, ET.ParseError) as exc:
                # Quarantine reason is summarized below; raw XML is never logged.
                errors.append(type(exc).__name__)
    if not documents:
        raise ValueError('No supported company report')
    signatures = {json.dumps((r['period_start'], r['period_end'], r['currency'], r['metrics']), sort_keys=True) for _, _, r in documents}
    if len(signatures) != 1:
        raise ValueError('Conflicting company reports in one package')
    return sorted(documents, key=lambda d: d[0])[0]


def import_one(candidate):
    package = read_package(candidate)
    package_sha = hashlib.sha256(package).hexdigest()
    path = api.upload(package, package_sha)
    try:
        filename, data, document = extract(package, candidate)
    except (ValueError, zipfile.BadZipFile):
        api.call('quarantine', {'je_id': candidate['je_id'], 'archive_etag': candidate['archive_etag'], 'reason': 'unsupported_or_ambiguous_company_report', 'package_sha256': package_sha, 'parser_version': VERSION})
        return 'quarantined'
    structure = api.call('structure', je_id=candidate['je_id'], period_end=document['period_end'])
    allocations = allocate(structure['establishments'], document['metrics']['net_sales'])
    document.update(document_id=filename, source_reference=ROOT + '/' + candidate['archive_key'],
        archive_key=candidate['archive_key'], member_name=candidate['member_name'], archive_etag=candidate['archive_etag'],
        package_sha256=package_sha, document_sha256=hashlib.sha256(data).hexdigest(), storage_path=path)
    api.call('account', dict(je_id=candidate['je_id'], document=document, allocations=allocations, structure=structure))
    return 'imported'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--max-archives', type=int, default=2000)
    parser.add_argument('--max-companies', type=int, default=50000)
    parser.add_argument('--workers', type=int, default=4)
    args = parser.parse_args()
    sc = scope()
    # Hash scope membership/identity only. A size-class change does not require
    # downloading ZIP directory metadata again.
    pairs = sorted((r['org_nr'], r['je_id']) for r in sc if r['org_nr'] and re.fullmatch(r'\d{10}', r['org_nr']))
    companies = dict(pairs)
    if len(companies) != len(pairs):
        raise ValueError('Ambiguous company identity mapping')
    scope_hash = hashlib.sha256(json.dumps(pairs, separators=(',', ':')).encode()).hexdigest()
    listing = list(archives())
    if not listing:
        raise ValueError('Empty Bolagsverket archive listing')
    known, after = {}, None
    while True:
        rows = api.call('archives', **({'after': after} if after else {}))
        if not rows:
            break
        known.update({r['archive_key']: r for r in rows})
        after = rows[-1]['archive_key']
    pending = [a for a in listing if a['key'] not in known or known[a['key']]['etag'] != a['etag'] or known[a['key']]['scope_hash'] != scope_hash]
    # Newest publication weeks first, with stable ordering of ZIP parts.
    pending.sort(key=lambda a: a['key'], reverse=True)
    period = max(a['key'].split('_')[0].replace('arsredovisningar/', '') for a in listing)
    scanned = 0
    with ThreadPoolExecutor(max_workers=max(1, min(8, args.workers))) as executor:
        jobs = [executor.submit(scan, a, companies, scope_hash) for a in pending[:args.max_archives]]
        for job in as_completed(jobs):
            job.result()
            scanned += 1
            if scanned % 20 == 0:
                print(json.dumps({'archives_scanned_this_run': scanned, 'remaining_at_start': len(pending)}), flush=True)
    remaining = max(0, len(pending) - scanned)
    # Do not call a provisional candidate the latest until the complete catalog
    # has been scanned for this scope. Resume safely in the next bounded run.
    imported = quarantined = 0
    if remaining == 0:
        api.call('prepare', {'parser_version': VERSION})
        after = None
        while imported + quarantined < args.max_companies:
            rows = api.call('candidates', **({'after': after} if after else {}))
            if not rows:
                break
            selected = [row for row in rows if row['org_nr'] in companies and companies[row['org_nr']] == row['je_id']]
            selected = selected[:args.max_companies-imported-quarantined]
            with ThreadPoolExecutor(max_workers=max(1,min(4,args.workers))) as executor:
                jobs = [executor.submit(import_one,row) for row in selected]
                for job in as_completed(jobs):
                    outcome = job.result()
                    imported += outcome == 'imported'
                    quarantined += outcome == 'quarantined'
                    if (imported + quarantined) % 50 == 0:
                        print(json.dumps({'imported_this_run': imported, 'quarantined_this_run': quarantined}), flush=True)
            after = rows[-1]['je_id']
    coverage = api.call('coverage')
    coverage.update(source_archives=len(listing), archives_remaining=remaining, scope_hash=scope_hash, parser_version=VERSION)
    final_pairs = sorted((r['org_nr'],r['je_id']) for r in scope() if r['org_nr'] and re.fullmatch(r'\d{10}',r['org_nr']))
    final_scope_hash = hashlib.sha256(json.dumps(final_pairs,separators=(',',':')).encode()).hexdigest()
    scope_changed = final_scope_hash != scope_hash
    coverage['scope_changed_during_run'] = scope_changed
    status = 'waiting' if remaining or coverage['pending'] or scope_changed else 'succeeded'
    api.log(SOURCE, status, period, coverage)
    print(json.dumps(coverage, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        try:
            api.log(SOURCE, 'failed', 'unknown', {'error_type': type(exc).__name__}, 'Annual accounts import failed; checkpoints retained')
        except Exception:
            pass  # Preserve the original failure if status logging is unavailable.
        raise
