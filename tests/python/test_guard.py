"""Shared guard cases (Phase 6d): tests/fixtures/guard/guard_cases.txt through the answer key nnfx_ref/guard.py.

The same file is run by MQL5/Scripts/NNFX/NNFX_GuardTest.mq5."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nnfx_ref import guard as g  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
CASES = os.path.join(ROOT, "tests", "fixtures", "guard", "guard_cases.txt")


def load():
    rows = []
    with open(CASES, encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                rows.append(line.split("|"))
    brokers = {r[1]: g.Broker(r[1], int(r[2]), r[3]) for r in rows if r[0] == "BROKER"}
    return rows, brokers


def trades(text):
    if text == "-":
        return []
    out = []
    for item in text.split(";"):
        t, p = item.split("=")
        out.append((g.parse_time(t), float(p)))
    return out


class TestGuardFixtures(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rows, cls.brokers = load()

    def kind(self, k):
        return [r for r in self.rows if r[0] == k]

    def test_case_counts(self):
        counts = {k: len(self.kind(k)) for k in ("TDB", "ROLL", "WEEK", "DLOSS", "DD", "BLK")}
        self.assertEqual(counts, {"TDB": 20, "ROLL": 14, "WEEK": 7, "DLOSS": 6, "DD": 3, "BLK": 6})

    def test_trading_day_boundary(self):
        for r in self.kind("TDB"):
            with self.subTest(case=r[1]):
                got = g.trading_day_start(self.brokers[r[2]], g.parse_time(r[3]))
                self.assertEqual(g.fmt_time(got), r[4])

    def test_rollover(self):
        for r in self.kind("ROLL"):
            with self.subTest(case=r[1]):
                self.assertEqual(int(g.in_rollover(self.brokers[r[2]], g.parse_time(r[3]))), int(r[4]))

    def test_weekend(self):
        for r in self.kind("WEEK"):
            with self.subTest(case=r[1]):
                got = g.in_weekend_block(self.brokers[r[2]], g.parse_time(r[3]), float(r[4]))
                self.assertEqual(int(got), int(r[5]))

    def test_daily_loss(self):
        for r in self.kind("DLOSS"):
            with self.subTest(case=r[1]):
                pl, limit, blocked = g.daily_loss(self.brokers[r[2]], g.parse_time(r[3]), float(r[4]), float(r[5]),
                                                  trades(r[6]))
                self.assertAlmostEqual(pl, float(r[7]), places=6)
                self.assertAlmostEqual(limit, float(r[8]), places=6)
                self.assertEqual(int(blocked), int(r[9]))

    def test_drawdown(self):
        for r in self.kind("DD"):
            with self.subTest(case=r[1]):
                got = g.run_drawdown(r[2].split(","))
                want = [(int(x.split(":")[0]), float(x.split(":")[1])) for x in r[3].split(",")]
                self.assertEqual(got, want)

    def test_blocks(self):
        for r in self.kind("BLK"):
            with self.subTest(case=r[1]):
                b, t = self.brokers[r[6]], g.parse_time(r[7])
                master = None if r[2] == "-" else r[2] == "1"
                got = g.blocks(master, r[3] == "1", r[4] == "1", r[5] == "1", g.in_rollover(b, t),
                               g.in_weekend_block(b, t, float(r[8])), float(r[9]), float(r[10]), r[11] == "1")
                self.assertEqual(got or "-", r[12])


class TestGuardUnits(unittest.TestCase):
    def test_dst_dates(self):
        self.assertEqual([str(d) for d in g.us_dst_dates(2026)], ["2026-03-08", "2026-11-01"])
        self.assertEqual([str(d) for d in g.eu_dst_dates(2026)], ["2026-03-29", "2026-10-25"])
        self.assertEqual([str(d) for d in g.us_dst_dates(2027)], ["2027-03-14", "2027-11-07"])
        self.assertEqual([str(d) for d in g.eu_dst_dates(2027)], ["2027-03-28", "2027-10-31"])

    def test_unknown_rule_rejected(self):
        with self.assertRaises(ValueError):
            g.server_offset(g.Broker("x", 2, "AU"), g.parse_time("2026.01.01 00:00"))


if __name__ == "__main__":
    unittest.main()
