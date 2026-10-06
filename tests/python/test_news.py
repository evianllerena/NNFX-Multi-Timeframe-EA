"""Shared news cases (Phase 6e): tests/fixtures/news/news_cases.txt through the answer key nnfx_ref/news.py, with
the owner-approved event list news/news_events.txt (D6e-1). The same file is run by NNFX_NewsTest.mq5."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nnfx_ref import news as n  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
CASES = os.path.join(ROOT, "tests", "fixtures", "news", "news_cases.txt")
LIST = os.path.join(ROOT, "news", "news_events.txt")


def rows():
    with open(CASES, encoding="ascii") as f:
        return [ln.strip().split("|") for ln in f if ln.strip() and not ln.startswith("#")]


class TestNewsFixtures(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(LIST, encoding="ascii") as f:
            cls.entries = n.load_entries(f)
        r = rows()
        cls.rows = r
        cls.events = [n.Event(n.parse_time(x[1]), x[2], x[3], x[4]) for x in r if x[0] == "EV"]
        cls.blackouts = n.parse_blackouts(";".join(x[1] for x in r if x[0] == "BLACKOUT"))

    def kind(self, k):
        return [r for r in self.rows if r[0] == k]

    def test_list_is_approved(self):
        with open(LIST, encoding="ascii") as f:
            self.assertIn("STATUS: APPROVED by the owner 2026-10-06 (D6e-1)", f.read())
        self.assertEqual(len(self.entries), 21)

    def test_counts(self):
        self.assertEqual({k: len(self.kind(k)) for k in ("MATCH", "EV", "BLACKOUT", "N1", "X5", "UTC")},
                         {"MATCH": 13, "EV": 6, "BLACKOUT": 1, "N1": 13, "X5": 14, "UTC": 4})

    def test_match(self):
        for r in self.kind("MATCH"):
            with self.subTest(case=r[1]):
                e = n.match(self.entries, r[2], r[3], r[4])
                self.assertEqual(e.vp if e else "-", r[5])

    def test_new_chair_and_president_caught_by_pattern_only(self):
        # the owner's request: the id is NOT in the list, only the role pattern can catch it
        for cur, eid, name in (("USD", "840050099", "Fed Chair Warsh Speech"),
                               ("EUR", "999010099", "ECB President Nagel Speech")):
            with self.subTest(name=name):
                self.assertFalse(any(eid in e.ids for e in self.entries))
                self.assertIsNotNone(n.match(self.entries, cur, eid, name))

    def test_n1(self):
        for r in self.kind("N1"):
            with self.subTest(case=r[1]):
                got = n.blocked(r[2], n.parse_time(r[3]), self.events, self.blackouts)
                self.assertEqual(";".join(got) or "-", r[4])

    def test_x5(self):
        for r in self.kind("X5"):
            with self.subTest(case=r[1]):
                prev = None if r[3] == "-" else n.parse_time(r[3])
                got = n.first_close(r[2], n.parse_time(r[4]), prev, self.events)
                self.assertEqual(int(got), int(r[5]))


    def test_utc_to_server(self):
        from nnfx_ref import guard as g
        for r in self.kind("UTC"):
            with self.subTest(case=r[1]):
                b = g.Broker("b", int(r[2]), r[3])
                line = "%s|USD|1|x|y" % r[4]
                ev = n.load_export([line], b)
                self.assertEqual(n.fmt_time(ev[0].time), r[5])


if __name__ == "__main__":
    unittest.main()
