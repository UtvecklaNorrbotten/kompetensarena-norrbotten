"""Offline, manifest-bound HST CSV pilot in existing campaign staging. Never publishes.

CSV packages have their own completion boundary; national jobs are never updated.
The first admitted scope is 171/2025-26, verified against all 12 JSON graphs.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import sqlite3
import tempfile
from urllib.parse import urlencode

from uka_campaign import Campaign, CampaignProbe, rows_digest
from uka_csv_bulk_probe import observations, queue_reference
from uka_hst_coverage import audit as audit_subjects
from uka_json_plan import build_plan
from uka_json_probe import BASE
from uka_json_queue import Queue
from uka_source_audit import Source, digest, write_json


def file_hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def reference_observations(manifest, reference_root, probe, subject_metadata):
    """Rebuild closed source graphs, rather than trusting a saved done flag."""
    scope = manifest['scope']; result = {}; contexts = set()
    ages = {'-24': '8', '25-34': '9', '35-': '10', 'Total': None}
    expected = {(u, g, a) for u in scope['universities'] for g in scope['genders'] for a in scope['ages']}
    with tempfile.TemporaryDirectory() as temporary:
        for index, reference in enumerate(manifest['references']):
            if Path(reference['file']).name != reference['file']:
                raise ValueError('Reference must be a local basename')
            path = Path(reference_root) / reference['file']
            if file_hash(path) != reference['sha256']:
                raise ValueError('Reference queue checksum changed')
            db = sqlite3.connect(f'file:{path.resolve()}?mode=ro', uri=True)
            try:
                binding = json.loads(db.execute('SELECT binding FROM meta').fetchone()[0])
            finally:
                db.close()
            if binding != reference['binding'] or binding['snapshot'] != manifest['snapshot'] or binding['indicator'] != 33:
                raise ValueError('Reference binding changed')
            q = binding['root']
            age = next((a for a, token in ages.items() if token == q.get('age_group')), None)
            context = (q.get('university'), q.get('gender', 'Total'), age)
            if (q.get('year') != scope['period'] or context not in expected or context in contexts or
                    set(q) - {'university', 'year', 'gender', 'age_group'} or binding.get('strategy') != 'study-first'):
                raise ValueError('Reference scope differs or repeats a context')
            contexts.add(context)
            # A fresh queue must follow all advertised links from immutable cached bodies.
            replay = Path(temporary) / f'{index}.sqlite'
            with Queue(replay, BASE + '/33?' + urlencode(q), manifest['snapshot'], 'study-first', 33) as queue:
                summary = queue.run(probe, max_nodes=2000, seconds=30)
                if not summary['graph_closed']:
                    raise ValueError('Reference cannot close from verified offline sources')
            coverage = audit_subjects(replay, subject_metadata)
            if coverage['duplicates'] or coverage['invalid_source_subject_paths']:
                raise ValueError('Reference subject paths differ')
            part = queue_reference(replay)
            if not part or part != queue_reference(path) or any(json.loads(k)[1] != context[0] for k in part):
                raise ValueError('Reference observations differ from source replay')
            if result.keys() & part.keys():
                raise ValueError('Duplicate reference observations')
            result.update(part)
    if contexts != expected:
        raise ValueError('Missing positive reference context')
    return result


def stage_package(campaign, manifest, actual, reference):
    """Validate everything before one transaction; same manifest replay is a no-op."""
    if (campaign.indicator != 33 or manifest['indicator'] != 33 or manifest['version'] != 1 or
            manifest['plan_id'] != campaign.plan['plan_id'] or manifest['snapshot'] != campaign.plan['snapshot'] or
            manifest['subject_metadata_hash'] != digest(campaign.subject_metadata) or
            manifest['publish_allowed'] is not False or manifest['source_release_verified'] is not False):
        raise ValueError('CSV manifest differs from campaign policy')
    scope = manifest['scope']
    for field in ('universities', 'genders', 'ages'):
        if not scope[field] or len(set(scope[field])) != len(scope[field]):
            raise ValueError('Invalid or duplicate CSV scope')
    expected_contexts = {(scope['period'], u, g, a) for u in scope['universities'] for g in scope['genders'] for a in scope['ages']}
    if {tuple(json.loads(k)[:4]) for k in actual} != expected_contexts:
        raise ValueError('CSV has missing or unrequested contexts')
    if not actual or len(actual) != manifest['expected_observations'] or actual != reference:
        raise ValueError('CSV coverage or source values differ from positive reference')
    package_id = digest([33, manifest['plan_id'], scope]); manifest_hash = digest(manifest)
    campaign.csv_packages()  # Fail on corrupt previous packages before any writes.
    db = campaign.db
    tables = {r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if 'csv_packages' in tables:
        previous = db.execute('SELECT manifest_hash FROM csv_packages WHERE id=?', (package_id,)).fetchone()
        if previous:
            if previous['manifest_hash'] != manifest_hash:
                raise ValueError('CSV scope already bound to another manifest')
            return package_id, False
    rows = []
    for identity, value in actual.items():
        period, university, gender, age, dimensions = json.loads(identity)
        payload = dict(indicator=33, period=period, university=university, gender=gender,
                       age=age, dimensions=dimensions, value=value)
        key = digest([33, period, gender, age, university, dimensions])
        previous = db.execute('SELECT payload FROM observations WHERE key=?', (key,)).fetchone()
        if previous:
            saved = json.loads(previous['payload'])
            if any(saved.get(k) != v for k, v in payload.items()):
                raise ValueError('CSV conflicts with national staging values')
        rows.append((key, json.dumps(payload, ensure_ascii=False, sort_keys=True), manifest['csv_sha256']))
    rows.sort()
    # No INSERT OR REPLACE: overlapping packages must be reviewed explicitly.
    # DDL and all rows/completion provenance roll back together on an interruption.
    with db:
        db.execute('BEGIN IMMEDIATE')
        db.execute('CREATE TABLE IF NOT EXISTS csv_packages(id TEXT PRIMARY KEY, manifest_hash TEXT NOT NULL, manifest TEXT NOT NULL, staging_sha256 TEXT NOT NULL)')
        db.execute('CREATE TABLE IF NOT EXISTS csv_observations(key TEXT PRIMARY KEY, package_id TEXT NOT NULL REFERENCES csv_packages(id), payload TEXT NOT NULL, source_hash TEXT NOT NULL)')
        db.execute('INSERT INTO csv_packages VALUES (?,?,?,?)',
                   (package_id, manifest_hash, json.dumps(manifest, ensure_ascii=False, sort_keys=True), rows_digest(rows)))
        for key, payload, source_hash in rows:
            db.execute('INSERT INTO csv_observations VALUES (?,?,?,?)', (key, package_id, payload, source_hash))
    return package_id, True


def run(root, csv_root, metadata_path, reference_root, bases, manifest_path, output):
    manifest = json.loads(Path(manifest_path).read_text())
    metadata = json.loads(Path(metadata_path).read_text()); scope = manifest['scope']
    if (metadata.get('indicator') != 33 or metadata.get('snapshot') != manifest['snapshot'] or
            digest(metadata) != manifest['metadata_projection_hash'] or metadata.get('metadata_hash') != manifest['metadata_hash']):
        raise ValueError('CSV metadata projection or provenance changed')
    # Exact receipt/filter/checksum replay only. This command has no live option.
    source = Source(csv_root, manifest['snapshot']); source.export_budget = 0
    filters = ['from:' + scope['period'], 'to:' + scope['period']] + ['uni:' + u for u in scope['universities']]
    filters += [v['value'] for v in metadata['genders']] + [v['value'] for v in metadata['ages']]
    filters += [g['index'] + v['value'] for g in metadata['groups'] for v in g['values']]
    exported = source.export(33, filters, metadata['metadata_hash'])
    if exported['status'] != 'data' or exported['sha256'] != manifest['csv_sha256']:
        raise ValueError('CSV checksum or data status differs from manifest')
    inventory = json.loads(Path('docs/uka-source-inventory-2026-11-06.json').read_text())
    plan = build_plan(inventory, manifest['snapshot'], bases[0] if bases else root)
    probe = CampaignProbe(root, manifest['snapshot'], budget=0, bases=bases)
    with Campaign(root, plan, 33, bases) as campaign:
        before = campaign.report()
        actual = observations(exported['rows'], metadata, scope['period'], scope['universities'], campaign.subject_metadata['paths'])
        reference = reference_observations(manifest, reference_root, probe, campaign.subject_metadata)
        package_id, written = stage_package(campaign, manifest, actual, reference)
        after = campaign.report()
        if any(before[k] != after[k] for k in ('completed_jobs', 'observations', 'staging_sha256', 'manifest_sha256')):
            raise ValueError('CSV pilot changed national staging')
        report = {'indicator': 33, 'snapshot': manifest['snapshot'], 'plan_id': plan['plan_id'],
                  'package_id': package_id, 'manifest_sha256': digest(manifest), 'staging_written': written,
                  'csv_sha256': exported['sha256'], 'observations': len(actual),
                  'coverage': [{'period': p, 'university': u, 'gender': g, 'age': a, 'observations': n}
                               for (p, u, g, a), n in sorted(Counter(tuple(json.loads(k)[:4]) for k in actual).items())],
                  'packages': after['csv_packages'], 'reference_graphs': len(manifest['references']),
                  'national_overlap_observations': campaign.db.execute('SELECT count(*) FROM csv_observations c JOIN observations n ON c.key=n.key WHERE c.package_id=?', (package_id,)).fetchone()[0],
                  'new_requests': probe.requests, 'new_exports': source.network_exports,
                  'national_completed_jobs': after['completed_jobs'], 'national_observations': after['observations'],
                  'national_staging_sha256': after['staging_sha256'], 'national_unchanged': True,
                  'full_source_coverage_verified': False, 'source_release_verified': False, 'publish_allowed': False}
    write_json(Path(output), report)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('root', 'csv-root', 'metadata', 'reference-root', 'output'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--base', action='append', default=[])
    parser.add_argument('--manifest', default='config/uka_hst_csv_pilot.json')
    args = parser.parse_args()
    result = run(args.root, args.csv_root, args.metadata, args.reference_root, args.base, args.manifest, args.output)
    print(json.dumps({k: v for k, v in result.items() if k not in ('coverage', 'packages')}, ensure_ascii=False, indent=2))
