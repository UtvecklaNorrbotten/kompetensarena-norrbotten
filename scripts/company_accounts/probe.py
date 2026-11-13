"""Read real AFR contracts without logging identities, names or addresses."""
import json
import os
import urllib.request
from collections import Counter
from .source import archives


def main():
    key = os.environ['SCB_AFR_API_KEY']
    result = {}
    for entity, field in [('juridiskaenheter', 'jes'), ('arbetsstallen', 'arbetsstallen')]:
        req = urllib.request.Request('https://apiafr.scb.se/v1/' + entity + '/full?limit=5000', headers={'X-API-Key': key})
        with urllib.request.urlopen(req, timeout=180) as response:
            rows = json.load(response)[field]
        shapes = {}
        def shape(obj, prefix=''):
            for name, value in obj.items():
                path = prefix + name
                shapes.setdefault(path, set()).add(type(value).__name__)
                if isinstance(value, dict):
                    shape(value, path + '.')
        for row in rows:
            shape(row)
        item = {'sample_rows': len(rows), 'fields': {k: sorted(v) for k, v in shapes.items()}}
        if entity == 'juridiskaenheter':
            item['expImp_observed'] = dict(Counter(str(r.get('expImp')) for r in rows))
        result[entity] = item
    for table in ('anstklkoder',):
        req = urllib.request.Request('https://apiafr.scb.se/v1/kodtabeller/' + table, headers={'X-API-Key': key})
        with urllib.request.urlopen(req, timeout=90) as response:
            result[table] = json.load(response)
    listing = list(archives())
    result['bolagsverket'] = {'archives': len(listing), 'bulk_bytes': sum(a['size'] for a in listing),
                             'latest_key': listing[-1]['key']}
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
