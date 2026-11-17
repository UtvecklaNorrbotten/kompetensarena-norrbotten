"""Stored-only structural diagnostic. No API requests, values or identifiers in output."""
import io
import json
import re
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path
from company_accounts.audit_quarantine import inventory, diagnose
from company_accounts.import_accounts import read_package
from company_accounts.ixbrl import IX, TAXONOMY, XBRLI, METRICS


def structure(data, row):
    if b'<!ENTITY' in data.upper():
        return {'structure': 'entity_declaration_blocked'}
    if b'<!DOCTYPE' in data.upper():
        # Do not parse a DTD in a diagnostic. Presence is enough to explain the
        # current parser's protective rejection; no XML relaxation is enabled.
        return {'structure': 'doctype_blocked'}
    namespaces, stack, pending = {}, [], {}
    root = None
    try:
        for event, value in ET.iterparse(io.BytesIO(data), events=('start-ns', 'start', 'end')):
            if event == 'start-ns':
                pending[value[0]] = value[1]
            elif event == 'start':
                ns = (stack[-1].copy() if stack else {}) | pending
                pending = {}
                stack.append(ns)
                namespaces[id(value)] = ns
                if root is None:
                    root = value
            else:
                stack.pop()
    except ET.ParseError:
        return {'structure': 'invalid_xml'}
    def qname(element):
        prefix, sep, name = element.get('name', '').partition(':')
        return namespaces[id(element)].get(prefix if sep else '', ''), name if sep else prefix
    def local(tag):
        return tag.rsplit('}', 1)[-1]
    facts = [e for e in root.iter() if e.tag.startswith(tuple('{' + ns + '}' for ns in IX))]
    scopes = [(e, qname(e)[0]) for e in facts if qname(e)[1] == 'FinansiellRapportList']
    metrics = [e for e in facts if qname(e)[1] in METRICS]
    contexts = list(root.iter('{' + XBRLI + '}context'))
    matching = []
    matching_end = []
    dimensional = []
    for c in contexts:
        identifier = c.find('.//{' + XBRLI + '}identifier')
        org = re.sub(r'\D', '', identifier.text or '') if identifier is not None else ''
        if org != row['org_nr']:
            continue
        matching.append(c)
        ends = [c.findtext('.//{' + XBRLI + '}' + name) for name in ('instant', 'endDate')]
        if row['period_end'] in ends:
            matching_end.append(c)
            if any(local(e.tag) in ('explicitMember', 'typedMember') for e in c.iter()):
                dimensional.append(c)
    entrypoints = [e.get('{http://www.w3.org/1999/xlink}href', '') for e in root.iter() if local(e.tag) == 'schemaRef']
    # Emit only fixed categories. Never output XML text, namespaces or URIs.
    return {
        'structure': 'no_inline_facts' if not facts else 'no_scope_fact' if not scopes else 'scope_namespace_rejected' if not any(TAXONOMY.fullmatch(ns) for _, ns in scopes) else 'supported_scope_fact',
        'entrypoint': 'k2' if any('/se/fr/gaap/k2' in u for u in entrypoints) else 'k3' if any('/se/fr/gaap/k3/' in u for u in entrypoints) else 'other_or_missing',
        'metric_names': 'recognized' if metrics else 'none_recognized',
        'metric_namespace': 'accepted' if any(TAXONOMY.fullmatch(qname(e)[0]) for e in metrics) else 'none_accepted',
        'company_contexts': 'present' if matching else 'missing',
        'expected_end_contexts': 'present' if matching_end else 'missing',
        'end_context_dimensions': 'all' if matching_end and len(dimensional) == len(matching_end) else 'some' if dimensional else 'none',
    }


def main():
    rows = inventory()
    counts, packages = Counter(), Counter()
    checked = failed = 0
    for row in rows:
        try:
            data = read_package(row)
            combinations = set()
            with zipfile.ZipFile(io.BytesIO(data)) as z:
                for entry in z.infolist():
                    if not entry.filename.lower().endswith(('.xhtml', '.html')):
                        continue
                    content = z.read(entry)
                    result = structure(content, row)
                    for key, value in result.items():
                        counts[key + ':' + value] += 1
                    combinations.add(' | '.join(key + ':' + value for key, value in result.items()))
            for combination in combinations:
                packages[combination] += 1
            checked += 1
        except Exception:
            failed += 1
    result = {'mode': 'stored_only_structure', 'inventory_count': len(rows), 'packages_checked': checked,
              'failures': failed, 'document_properties': counts, 'packages_by_structure': packages,
              'complete': checked == len(rows) and not failed}
    text = json.dumps(result, ensure_ascii=False, indent=2)
    print(text)
    Path('company-quarantine-structure.json').write_text(text + '\n')
    if failed:
        raise SystemExit(1)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(json.dumps({'failed': True, 'error_type': type(exc).__name__}))
        raise SystemExit(1)
