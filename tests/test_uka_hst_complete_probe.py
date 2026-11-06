"""Synthetic graph with two routes to the same source combination."""
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
from uka_hst_complete_probe import traverse

ROOT = "https://statistik-api.uka.se/api/totals/33?university=171&year=2025%2F26&gender=Kvinnor"


def fixture():
    def body(value, groups=()):
        return {"yearly_totals": {"totals": [{"year": "2025/26", "value": value}]}, "groups": list(groups)}
    def group(column, name, slug, value):
        return {"column": column, "totals": [{"name": name, "url": ROOT + "&group_slug=" + slug, "value": value}]}
    return {ROOT: body(6, [group("Ämnesområde", "Exempelämne", "A", 4), group("Studieform", "Exempelform", "S", 5)]),
            ROOT + "&group_slug=A": body(4, [group("Studieform", "Exempelform", "AS", 3)]),
            ROOT + "&group_slug=S": body(5, [group("Ämnesområde", "Exempelämne", "AS", 3)]),
            ROOT + "&group_slug=AS": body(3)}


class CompleteTests(unittest.TestCase):
    def probe(self, data):
        class MemoryProbe:
            def get(self, url, indicator):
                return data[url]
        return MemoryProbe()

    def test_exhausts_both_routes_without_duplicate_observations(self):
        p = self.probe(fixture())
        a, checks = traverse(p, ROOT)
        b, _ = traverse(p, ROOT, study_first=True)
        self.assertEqual(a, b)
        self.assertEqual(len(a), 4)
        self.assertEqual(checks, 4)
        self.assertEqual(a['{}'], '6')

    def test_same_counts_with_changed_child_value_fail(self):
        d = fixture(); d[ROOT + '&group_slug=AS']['yearly_totals']['totals'][0]['value'] = 99
        with self.assertRaisesRegex(ValueError, 'differs'):
            traverse(self.probe(d), ROOT)

    def test_same_endpoint_cannot_mean_different_dimensions(self):
        d = fixture(); d[ROOT + '&group_slug=S']['groups'][0]['totals'][0]['name'] = 'Annat exempelämne'
        with self.assertRaisesRegex(ValueError, 'conflicting dimensions'):
            traverse(self.probe(d), ROOT)


if __name__ == '__main__':
    unittest.main()
