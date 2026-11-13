"""Relative establishment weights, independent of accounts' employee count."""
from decimal import Decimal
from statistics import median

INTERVALS = {1: (0, 0), 2: (1, 4), 3: (5, 9), 4: (10, 19), 5: (20, 49),
             6: (50, 99), 7: (100, 199), 8: (200, 499), 9: (500, 999),
             10: (1000, 1499), 11: (1500, 1999), 12: (2000, 2999),
             13: (3000, 3999), 14: (4000, 4999), 15: (5000, 9999),
             16: (10000, 14999)}
VERSION = 'afr-midpoint-1'


def allocate(establishments, net_sales):
    if not establishments:
        return []
    if len({str(e['cfar_nr']) for e in establishments}) != len(establishments):
        raise ValueError('Duplicate CFAR in allocation denominator')
    rows = sorted(establishments, key=lambda e: int(e['cfar_nr']))
    midpoints = []
    flags = []
    for row in rows:
        code = row.get('anst_kl')
        interval = INTERVALS.get(code)
        midpoints.append(None if interval is None else Decimal(sum(interval)) / 2)
        flags.append(['missing_class'] if interval is None else ['open_top_10000_14999'] if code == 16 else ['zero_employees'] if code == 1 else [])
    positives = [m for m in midpoints if m is not None and m > 0]
    imputed = median(positives) if positives else Decimal(1)
    for i, midpoint in enumerate(midpoints):
        if midpoint is None:
            midpoints[i] = imputed
            flags[i].append('imputed_company_median' if positives else 'imputed_one')
    total = sum(midpoints)
    if total == 0:
        midpoints = [Decimal(1)] * len(rows)
        total = Decimal(len(rows))
        for flag in flags:
            flag.append('all_zero_equal_weights')
    weights = [(m / total).quantize(Decimal('0.000000000000000001')) for m in midpoints]
    # Exact residual ensures sum=1, even with repeating fractions. Deterministic
    # last positive CFAR absorbs at most a few 1e-18, never a zero-weight unit.
    last = max(i for i, m in enumerate(midpoints) if m > 0)
    weights[last] += Decimal(1) - sum(weights)
    revenue = None if net_sales is None else Decimal(net_sales)
    allocated = [None if revenue is None else (revenue * w).quantize(Decimal('0.00000001')) for w in weights]
    if revenue is not None:
        allocated[last] += revenue - sum(allocated)
    return [dict(cfar_nr=str(row['cfar_nr']), structure_history_id=row.get('history_id'),
                 midpoint=str(midpoints[i]), weight=str(weights[i]),
                 estimated_net_sales=None if allocated[i] is None else str(allocated[i]),
                 flags=flags[i], is_estimate=True, rule_version=VERSION)
            for i, row in enumerate(rows)]
