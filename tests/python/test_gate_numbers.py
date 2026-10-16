"""Tests for tools/gate_numbers.py (G2_phase8_1 F1/F2): the sample-size formula and the drawdown bootstrap."""
import os
import random
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

import gate_numbers as g  # noqa: E402


class TestGateNumbers(unittest.TestCase):
    def test_n_needed(self):
        # ((1.959964 + 1.281552) x 1.0 / 0.5)^2 = 42.03 -> 43; two systems: 84.06 -> 85
        self.assertEqual(g.n_needed(1.0, 0.5), 43)
        self.assertEqual(g.n_needed(1.0, 0.5, two_systems=True), 85)
        self.assertGreater(g.n_needed(1.0, 0.5, alpha=0.05 / 3, two_systems=True), 85)

    def test_drawdown_certain_and_impossible(self):
        rng = random.Random(1)
        # every trade -1R at 2%: 10% is passed after 6 trades
        self.assertEqual(g.p_drawdown([-1.0], 6, -1.0, 50, rng), 1.0)
        self.assertEqual(g.p_drawdown([-1.0], 5, -1.0, 50, rng), 0.0)
        # every trade +1R: never a drawdown
        self.assertEqual(g.p_drawdown([1.0], 400, 1.0, 50, rng), 0.0)

    def test_longer_horizon_never_lower(self):
        rs = [-1.0, 1.5, -1.0, 0.5, 2.0, -1.0]
        a = g.p_drawdown(rs, 50, 0.1, 2000, random.Random(3))
        b = g.p_drawdown(rs, 200, 0.1, 2000, random.Random(3))
        self.assertGreaterEqual(b, a)


if __name__ == "__main__":
    unittest.main()
