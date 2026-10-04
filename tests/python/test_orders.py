"""Shared order-price and safety cases (Phase 6b).

The same file is run by MQL5/Scripts/NNFX/NNFX_OrderMathTest.mq5 (OP/OE/TR/SD lines) and
MQL5/Scripts/NNFX/NNFX_SafetyTest.mq5 (SF lines), so the Python answer key and the MQL5 code are
checked against identical, hand-worked answers."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nnfx_ref import orders  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
CASES = os.path.join(ROOT, "tests", "fixtures", "orders", "order_cases.txt")


def load():
    out = []
    with open(CASES, encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                out.append(line.split("|"))
    return out


def opt(text):
    return None if text == "-" else float(text)


class TestOrderCases(unittest.TestCase):
    def test_all_cases(self):
        cases = load()
        kinds = [c[0] for c in cases]
        for kind, at_least in (("OP", 8), ("OE", 3), ("TR", 8), ("SD", 3), ("SF", 6)):
            self.assertGreaterEqual(kinds.count(kind), at_least, kind)
        for p in cases:
            with self.subTest(case=p[1]):
                if p[0] == "OP":
                    self.assertEqual(len(p), 13)
                    d, fill, atr, tick = int(p[2]), float(p[3]), float(p[4]), float(p[5])
                    sl, tp1, tp2 = orders.plan_prices(d, fill, atr, tick, float(p[6]), float(p[7]), opt(p[8]))
                    self.assertAlmostEqual(sl, float(p[9]), places=9)
                    self.assertAlmostEqual(tp1, float(p[10]), places=9)
                    if p[11] == "-":
                        self.assertIsNone(tp2)
                    else:
                        self.assertAlmostEqual(tp2, float(p[11]), places=9)
                    self.assertEqual(orders.breakeven_price(fill), float(p[12]))
                    # The stop is never further from the fill than sl_atr x ATR (F4).
                    self.assertLessEqual(abs(fill - sl), float(p[6]) * atr + 1e-12)
                elif p[0] == "OE":
                    self.assertEqual(len(p), 9)
                    with self.assertRaises(ValueError):
                        orders.plan_prices(int(p[2]), float(p[3]), float(p[4]), float(p[5]),
                                           float(p[6]), float(p[7]), opt(p[8]))
                elif p[0] == "TR":
                    self.assertEqual(len(p), 14)
                    sl, active = orders.trail_step(int(p[2]), float(p[3]), float(p[4]), float(p[5]),
                                                   p[6] == "1", float(p[7]), float(p[8]), float(p[9]),
                                                   float(p[10]), float(p[11]))
                    self.assertAlmostEqual(sl, float(p[12]), places=9)
                    self.assertEqual(active, p[13] == "1")
                elif p[0] == "SD":
                    self.assertEqual(len(p), 7)
                    got = orders.stop_distance_ok(float(p[2]), float(p[3]), int(p[4]), float(p[5]))
                    self.assertEqual(got, p[6] == "1")
                elif p[0] == "SF":
                    self.assertEqual(len(p), 5)
                    self.assertEqual(orders.orders_allowed_for(p[2], p[3] == "1"), p[4] == "1")
                else:
                    self.fail("unknown case kind %r" % p[0])

    def test_unknown_trade_mode_rejected(self):
        with self.assertRaises(ValueError):
            orders.orders_allowed_for("LIVE", False)

    def test_planned_risk(self):
        # 3.67 lots x 0.00272 stop (272 ticks) x tick value 1.0 = 998.24
        self.assertAlmostEqual(orders.planned_risk(3.67, 1.10000, 1.09728, 0.00001, 1.0), 3.67 * 272.0, places=6)


if __name__ == "__main__":
    unittest.main()
