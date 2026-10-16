"""Tests for tools/explore_breakdown.py (G3_explore_1 F1/F2): refusal and DIVERGE kinds, and the one-to-one match."""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

import explore_breakdown as e  # noqa: E402


class TestKinds(unittest.TestCase):
    def test_refusals(self):
        self.assertTrue(e.refusal_kind("too small to size: 0.004 lots").startswith("too small"))
        self.assertTrue(e.refusal_kind("not enough free margin: needs 1030679.76; free 1000000.00 (OD-5)").startswith("not enough"))
        self.assertEqual(e.refusal_kind("half 1 not opened"), "half N not opened")
        self.assertTrue(e.refusal_kind("no price").startswith("other"))

    def test_divergence(self):
        # the trade log writes the EA's "," as ";"
        self.assertEqual(e.divergence_kind("DIVERGE (D6f-1): the rules core is flat; the broker holds T1; closed"),
                         "core flat, broker trade closed")
        self.assertTrue(e.divergence_kind("DIVERGE (D6f-1): the rules core holds a trade; the broker none; no new entry")
                        .startswith("core holds"))
        self.assertTrue(e.divergence_kind("start (x): ...; START-UP: alarm only").startswith("start-up"))
        m = e.DIV_FLAT.search("DIVERGE (D6f-1): the rules core is flat; the broker holds T1901281700_3; closed")
        self.assertEqual(m.group(1), "T1901281700_3")


class TestMatch(unittest.TestCase):
    def test_one_to_one_in_time_order(self):
        broker = [{"id": "A", "symbol": "EURUSD", "dir": 1, "open": "2019.01.02 10:00:05", "entry": 1.10002, "r": -0.1},
                  {"id": "B", "symbol": "EURUSD", "dir": 1, "open": "2019.01.05 10:00:05", "entry": 1.10001, "r": 0.2},
                  {"id": "C", "symbol": "EURUSD", "dir": -1, "open": "2019.01.02 10:00:05", "entry": 1.10000, "r": 0.0}]
        core = [{"close_time": "2019.01.03 12:00", "symbol": "EURUSD", "dir": 1, "entry": 1.10000, "r": 0.0},
                {"close_time": "2019.01.06 12:00", "symbol": "EURUSD", "dir": 1, "entry": 1.10000, "r": 0.3},
                {"close_time": "2019.01.07 12:00", "symbol": "EURUSD", "dir": 1, "entry": 1.20000, "r": 0.3}]
        pairs = e.match(broker, core, 3, {"EURUSD": 0.00001})
        self.assertEqual([(b["id"], c["close_time"]) for b, c in pairs],
                         [("A", "2019.01.03 12:00"), ("B", "2019.01.06 12:00")])

    def test_not_before_the_core_closes(self):
        broker = [{"id": "A", "symbol": "EURUSD", "dir": 1, "open": "2019.01.04 10:00:05", "entry": 1.1, "r": 0.0}]
        core = [{"close_time": "2019.01.03 12:00", "symbol": "EURUSD", "dir": 1, "entry": 1.1, "r": 0.0}]
        self.assertEqual(e.match(broker, core, 3, {"EURUSD": 0.00001}), [])


if __name__ == "__main__":
    unittest.main()
