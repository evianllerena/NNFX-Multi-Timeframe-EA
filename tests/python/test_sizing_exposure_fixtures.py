"""Shared sizing and exposure cases (Phase 6a).

The same files are run by MQL5/Scripts/NNFX/NNFX_SizingTest.mq5, so the Python answer key
and the MQL5 ports are checked against identical, hand-worked answers."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nnfx_ref import exposure, sizing  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SIZING = os.path.join(ROOT, "tests", "fixtures", "sizing", "sizing_cases.txt")
EXPOSURE = os.path.join(ROOT, "tests", "fixtures", "exposure", "exposure_cases.txt")


def load(path):
    out = []
    with open(path, encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                out.append(line.split("|"))
    return out


def positions(text):
    if text == "-":
        return []
    out = []
    for item in text.split(";"):
        sym, d = item.split(":")
        out.append((sym, int(d)))
    return out


def size_inputs(p):
    vol_max = None if p[9] == "-" else float(p[9])
    return [float(x) for x in p[2:9]] + [vol_max]


class TestSizingCases(unittest.TestCase):
    def test_all_cases(self):
        cases = load(SIZING)
        kinds = [c[0] for c in cases]
        self.assertGreaterEqual(kinds.count("SZ"), 10)
        self.assertGreaterEqual(kinds.count("SE"), 5)
        self.assertGreaterEqual(kinds.count("TV"), 5)
        for p in cases:
            with self.subTest(case=p[1]):
                if p[0] == "SZ":
                    self.assertEqual(len(p), 14)
                    r = sizing.size_trade(*size_inputs(p))
                    self.assertEqual(r.skipped, p[10] == "1")
                    self.assertAlmostEqual(r.half_lots, float(p[11]), places=9)
                    self.assertAlmostEqual(r.total_lots, float(p[12]), places=9)
                    self.assertAlmostEqual(r.risk_money, float(p[13]), places=6)
                    self.assertLessEqual(r.risk_money, r.target_risk_money + 1e-9)
                    if r.skipped:
                        self.assertEqual(r.reason, "too small to size")
                elif p[0] == "SE":
                    self.assertEqual(len(p), 10)
                    with self.assertRaises(ValueError):
                        sizing.size_trade(*size_inputs(p))
                elif p[0] == "TV":
                    self.assertEqual(len(p), 5)
                    got = sizing.tick_value_for_sizing(float(p[2]), float(p[3]))
                    self.assertAlmostEqual(got, float(p[4]), places=12)
                else:
                    self.fail("unknown case kind %r" % p[0])


class TestExposureCases(unittest.TestCase):
    def test_all_cases(self):
        cases = load(EXPOSURE)
        kinds = [c[0] for c in cases]
        self.assertGreaterEqual(kinds.count("EX"), 15)
        self.assertGreaterEqual(kinds.count("CUR"), 7)
        for p in cases:
            with self.subTest(case=p[1]):
                if p[0] == "EX":
                    self.assertEqual(len(p), 7)
                    got = exposure.allocate(positions(p[4]), positions(p[5]), float(p[3]), p[2])
                    want = [float(x) for x in p[6].split(";")]
                    self.assertEqual(got, want)
                elif p[0] == "CUR":
                    self.assertEqual(len(p), 6)
                    if p[3] == "-":
                        with self.assertRaises(ValueError):
                            exposure.currencies(p[2])
                    else:
                        self.assertEqual(exposure.currencies(p[2]), (p[3], p[4]))
                    self.assertEqual(exposure.is_fx(p[2]), p[5] == "1")
                else:
                    self.fail("unknown case kind %r" % p[0])

    def test_nonfx_is_logged(self):
        log = []
        exposure.allocate([("XAUUSD", -1), ("EURUSD", 1)], [("GBPJPY", 1)], 2.0, log=log)
        self.assertEqual(log, ["exposure: ignored non-FX position XAUUSD"])

    def test_nonfx_signal_rejected(self):
        with self.assertRaises(ValueError):
            exposure.allocate([], [("XAUUSD", 1)], 2.0)


if __name__ == "__main__":
    unittest.main()
