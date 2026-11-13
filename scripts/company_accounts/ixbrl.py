"""Conservative iXBRL extraction. Never substitutes group or comparative facts.

Only six explicitly mapped Swedish standard concepts are imported. Unknown
taxonomies, dimensions, transforms and conflicting duplicate facts are reported
as gaps rather than guessed. Monetary facts retain original scale/unit/decimals
and are normalized to currency units using Decimal.
"""
import io
import re
import xml.etree.ElementTree as ET
from collections import defaultdict
from decimal import Decimal, InvalidOperation

VERSION = 'bv-ixbrl-1'
XBRLI = 'http://www.xbrl.org/2003/instance'
IX = {'http://www.xbrl.org/2013/inlineXBRL', 'http://www.xbrl.org/2008/inlineXBRL'}
METRICS = {
    'Nettoomsattning': ('net_sales', 'duration'),
    'Rorelseresultat': ('operating_profit', 'duration'),
    'AretsResultat': ('profit_for_year', 'duration'),
    'EgetKapital': ('equity', 'instant'),
    'Tillgangar': ('total_assets', 'instant'),
    'MedelantaletAnstallda': ('average_employees', 'duration'),
}
TAXONOMY = re.compile(r'https?://www\.taxonomier\.se/se/fr/(gen-base|cd-base|mem-base)/\d{4}-\d{2}-\d{2}$')
TRANSFORMS = {'numspacecomma', 'numcommadecimal', 'numdotdecimal', 'numcommadot', 'numspacedot', 'numcomma', 'numdot', 'zerodash', 'fixed-zero'}


def local(qname):
    return qname.rsplit('}', 1)[-1].rsplit(':', 1)[-1]


def fact_text(element):
    result = element.text or ''
    for child in element:
        if not (local(child.tag) == 'exclude' and child.tag.startswith(tuple('{' + ns + '}' for ns in IX))):
            result += fact_text(child)
        result += child.tail or ''
    return result


def numeric(element):
    if element.get('{http://www.w3.org/2001/XMLSchema-instance}nil') in ('true', '1'):
        return None
    fmt = local(element.get('format', ''))
    text = fact_text(element).strip().replace('\u2212', '-')
    if element.get('continuedAt'):
        raise ValueError('continued numeric fact')
    if fmt and fmt not in TRANSFORMS:
        raise ValueError('unsupported numeric transform ' + fmt)
    if fmt in ('zerodash', 'fixed-zero'):
        value = Decimal(0)
    else:
        text = re.sub(r'\s', '', text)
        if fmt in ('numspacecomma', 'numcommadecimal', 'numcomma'):
            text = text.replace('.', '').replace(',', '.')
        elif fmt == 'numcommadot':
            text = text.replace(',', '')
        elif fmt in ('numdotdecimal', 'numspacedot', 'numdot'):
            text = text.replace(',', '')
        elif not re.fullmatch(r'[+-]?\d+(\.\d+)?', text):
            raise ValueError('untransformed non-numeric fact')
        try:
            value = Decimal(text)
        except InvalidOperation as exc:
            raise ValueError('invalid numeric fact') from exc
    if not value.is_finite() or abs(int(element.get('scale', '0'))) > 12:
        raise ValueError('invalid scale or nonfinite value')
    value *= Decimal(10) ** int(element.get('scale', '0'))
    if element.get('sign') == '-':
        if value < 0:
            raise ValueError('conflicting lexical and attribute signs')
        value = -value
    return value


def parse(data, expected_org, expected_end):
    if len(data) > 40_000_000 or b'<!DOCTYPE' in data.upper() or b'<!ENTITY' in data.upper():
        raise ValueError('oversized XML or DTD/entity declaration')
    # Capture the namespace scope at every element; prefixes are arbitrary.
    scopes, stack, pending = {}, [], {}
    root = None
    for event, value in ET.iterparse(io.BytesIO(data), events=('start-ns', 'start', 'end')):
        if event == 'start-ns':
            pending[value[0]] = value[1]
        elif event == 'start':
            ns = (stack[-1].copy() if stack else {}) | pending
            pending = {}
            stack.append(ns)
            scopes[id(value)] = ns
            if root is None:
                root = value
        else:
            stack.pop()

    def expanded(qname, element):
        prefix, sep, name = qname.partition(':')
        return scopes[id(element)].get(prefix if sep else '', ''), name if sep else prefix

    facts = [e for e in root.iter() if e.tag.startswith('{') and e.tag[1:].split('}')[0] in IX]
    report_types = []
    for fact in facts:
        ns, name = expanded(fact.get('name', ''), fact)
        if name == 'FinansiellRapportList' and TAXONOMY.fullmatch(ns):
            report_types.append(''.join(fact.itertext()).strip())
    if not report_types:
        raise ValueError('missing report scope declaration')
    has_group_declaration = any('Koncern' in t for t in report_types)
    contexts = {}
    for context in root.iter('{' + XBRLI + '}context'):
        identifier = context.find('.//{' + XBRLI + '}identifier')
        org = re.sub(r'\D', '', identifier.text or '') if identifier is not None else ''
        if org != expected_org:
            continue
        instant = context.findtext('.//{' + XBRLI + '}instant')
        start = context.findtext('.//{' + XBRLI + '}startDate')
        end = context.findtext('.//{' + XBRLI + '}endDate')
        members = [e for e in context.iter() if local(e.tag) in ('explicitMember', 'typedMember')]
        # Unscoped facts in a document explicitly declaring a group report are
        # not assumed to be company facts. They stay quarantined.
        scope = 'unresolved' if has_group_declaration else 'company'
        if members:
            scope = 'unresolved'
            if len(members) == 1 and local(members[0].tag) == 'explicitMember':
                member = members[0]
                member_ns, member_name = expanded(''.join(member.itertext()).strip(), member)
                axis_ns, axis_name = expanded(member.get('dimension', ''), member)
                if TAXONOMY.fullmatch(member_ns) and '/se/fr/' in axis_ns and axis_name in ('KoncernForetagDimension', 'KoncernForetagAxis'):
                    scope = {'ForetagMember': 'company', 'ModerforetagMember': 'company',
                             'KoncernMember': 'group'}.get(member_name, 'unresolved')
        contexts[context.get('id')] = dict(org=org, start=start, end=end or instant,
                                          kind='instant' if instant else 'duration', scope=scope)
    units = {}
    for unit in root.iter('{' + XBRLI + '}unit'):
        measures = list(unit.iter('{' + XBRLI + '}measure'))
        if len(measures) != 1 or unit.find('{' + XBRLI + '}divide') is not None:
            continue
        measure = measures[0]
        uri, name = expanded(measure.text or '', measure)
        units[unit.get('id')] = ('currency', name) if uri == 'http://www.xbrl.org/2003/iso4217' else ('other', (measure.text or ''))

    candidates = defaultdict(list)
    issues = []
    for fact in facts:
        if local(fact.tag) != 'nonFraction':
            continue
        ns, concept = expanded(fact.get('name', ''), fact)
        if concept not in METRICS or not TAXONOMY.fullmatch(ns) or '/gen-base/' not in ns:
            continue
        metric, kind = METRICS[concept]
        context = contexts.get(fact.get('contextRef'))
        if not context or context['end'] != expected_end or context['kind'] != kind:
            continue
        if context['scope'] != 'company':
            issues.append(metric + ':unresolved_or_group_context')
            continue
        unit = units.get(fact.get('unitRef'))
        if not unit or (metric != 'average_employees' and unit[0] != 'currency'):
            issues.append(metric + ':invalid_unit')
            continue
        if metric == 'average_employees' and (unit[0] == 'currency' or not ('AntalAnstallda' in unit[1] or unit[1].endswith(':pure'))):
            issues.append(metric + ':invalid_employee_unit')
            continue
        try:
            value = numeric(fact)
        except ValueError as exc:
            issues.append(metric + ':' + str(exc))
            continue
        candidates[metric].append(dict(value=None if value is None else (format(value, 'f').rstrip('0').rstrip('.') if '.' in format(value, 'f') else format(value, 'f')),
            start=context['start'], unit=unit[1], scale=int(fact.get('scale', '0')),
            decimals=fact.get('decimals'), context=fact.get('contextRef'),
            concept='{' + ns + '}' + concept))
    duration_starts = {f['start'] for metric, rows in candidates.items()
                       if metric in ('net_sales', 'operating_profit', 'profit_for_year', 'average_employees')
                       for f in rows if f['value'] is not None}
    # Prefer the reporting period stated explicitly by the document, not the
    # longest/shortest period or a comparative context.
    stated_starts = set()
    for fact in facts:
        ns, name = expanded(fact.get('name', ''), fact)
        if name == 'RakenskapsarForstaDag' and TAXONOMY.fullmatch(ns):
            context = contexts.get(fact.get('contextRef'))
            text = ''.join(fact.itertext()).strip()
            if context and context['end'] == expected_end and re.fullmatch(r'\d{4}-\d{2}-\d{2}', text):
                stated_starts.add(text)
    starts = stated_starts or duration_starts
    if len(starts) != 1:
        raise ValueError('missing or ambiguous reporting period')
    period_start = starts.pop()
    if period_start > expected_end:
        raise ValueError('reversed reporting period')
    result = {}
    provenance = {}
    for metric, _ in METRICS.values():
        rows = [r for r in candidates.get(metric, []) if not r['start'] or r['start'] == period_start]
        values = {(r['value'], r['unit']) for r in rows if r['value'] is not None}
        if len(values) == 1:
            result[metric] = next(iter(values))[0]
            provenance[metric] = rows
        else:
            result[metric] = None
            issues.append(metric + (':conflicting_facts' if len(values) > 1 else ':missing'))
    currencies = {r['unit'] for metric, rows in provenance.items() if metric != 'average_employees' for r in rows}
    if len(currencies) != 1:
        raise ValueError('missing or conflicting reporting currency')
    if all(v is None for v in result.values()):
        raise ValueError('no company-level metrics in supported taxonomy')
    return dict(period_start=period_start, period_end=expected_end, currency=currencies.pop(),
                unit='currency_units', report_type=';'.join(sorted(set(report_types))) or 'annual_report',
                scope='company', metrics=result, provenance=provenance,
                issues=sorted(set(issues)), parser_version=VERSION)
