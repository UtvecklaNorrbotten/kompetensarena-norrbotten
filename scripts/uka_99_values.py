"""Strict indicator-99 CSV identities, source-native totals and Decimal values."""
import json
from uka_source_audit import canonical_value

COLUMNS = {'Tidsperiod', 'Lärosäte', 'Program', 'Kön', 'Åldersgrupp', 'Värde'}


def observations(rows, metadata, period, universities, programs=None):
    names = {}
    for option in metadata['universities']:
        code = option['value'].removeprefix('uni:')
        if option['label'] in names:
            raise ValueError('Ambiguous university label')
        names[option['label']] = code
    allowed = {o['label'] for o in (programs if programs is not None else metadata['groups'][0]['values'])}
    result = {}
    for row in rows:
        if set(row) != COLUMNS:
            raise ValueError('Unexpected CSV headers')
        university = names.get(row['Lärosäte']) if row['Lärosäte'] else '1'
        if row['Tidsperiod'] != period or university not in universities:
            raise ValueError('Unrequested period or university')
        if row['Kön'] not in {'Kvinnor', 'Män', 'Total'} or row['Åldersgrupp'] != 'Total':
            raise ValueError('Unrequested gender or age')
        if (row['Program'] or 'Total') not in allowed:
            raise ValueError('Unrequested program')
        dims = {'Program': row['Program']} if row['Program'] else {}
        key = json.dumps([period, university, row['Kön'], 'Total', dims], ensure_ascii=False, sort_keys=True)
        if key in result:
            raise ValueError('Duplicate CSV identity regardless of value')
        result[key] = canonical_value(row['Värde'])
    if not result:
        raise ValueError('Empty CSV requires positive references')
    return result
