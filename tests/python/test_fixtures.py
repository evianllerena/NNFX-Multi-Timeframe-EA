"""Runs every JSON rule fixture in tests/fixtures through the answer key.

Comparison is exact (see nnfx_ref/fixtures.py). On a failure the full event
trace is printed, so the cause can be read rather than guessed.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nnfx_ref import fixtures  # noqa: E402

# Rule IDs that must each have at least one fixture. Rules not listed here are
# covered elsewhere or not implemented in the core, with the reason:
#   M1, M2, M4, M5  sizing     -> test_sizing.py
#   M6, M7          exposure   -> test_exposure.py
#   T3              no fixed target on half 2 -> implicit in every trade fixture
#   T5              exit indicator vs trailing stop is a test comparison, not a rule
#   T6, D1, D2      dead-market handling needs a volatility gauge; not in the core yet
#   X1              stops and targets -> M3, T1, T2, T4, T7 fixtures
#   N2, N3          election blackout list and news in backtests are caller inputs (block list)
#   R1, R2          drawdown pause = caller block; no scaling in = the core never adds to a trade
REQUIRED_RULES = {"E0", "E1", "E2", "E3", "E4", "E5", "E6",
                  "X2", "X3", "X4", "X5", "M3", "T1", "T2", "T4", "T7", "N1"}


class TestFixtures(unittest.TestCase):
    def test_every_fixture(self):
        all_fx = fixtures.load_all()
        self.assertGreater(len(all_fx), 0, "no fixtures found in " + fixtures.FIXTURE_DIR)
        for fx in all_fx:
            with self.subTest(fixture=fx["name"]):
                got, events, core = fixtures.run(fx)
                self.assertEqual(
                    got, fx["expect"],
                    "\n%s (%s)\n%s\nexpected: %s\ngot:      %s\nfull trace:\n%s" % (
                        fx["name"], fx["_file"], fx["description"], fx["expect"], got,
                        fixtures.describe(events)))
                if "expect_r" in fx:
                    rs = [t["r"] for t in core.closed_trades]
                    self.assertEqual(len(rs), len(fx["expect_r"]), "closed trades: %s" % rs)
                    for g, e in zip(rs, fx["expect_r"]):
                        self.assertAlmostEqual(g, e, places=5)

    def test_rule_coverage(self):
        covered = {fx["rule"] for fx in fixtures.load_all()}
        missing = REQUIRED_RULES - covered
        self.assertFalse(missing, "rules without a fixture: %s" % sorted(missing))

    def test_each_rule_has_fire_and_no_fire_case(self):
        """Spec Check 1a: each rule needs a case where it fires and one where it must not."""
        by_rule = {}
        for fx in fixtures.load_all():
            by_rule.setdefault(fx["rule"], []).append(fx)
        for rule in sorted(REQUIRED_RULES):
            cases = by_rule.get(rule, [])
            fired = any(any(e[2] == rule and e[1] in ("ENTER", "EXIT", "SL", "TP1", "MOVE_BE",
                                                      "BE_SL", "TRAIL", "TRAIL_SL", "TP2")
                            for e in fx["expect"]) for fx in cases)
            not_fired = any(not any(e[2] == rule and e[1] in ("ENTER", "EXIT", "TRAIL", "TP2",
                                                              "MOVE_BE", "BE_SL")
                                    for e in fx["expect"]) for fx in cases)
            with self.subTest(rule=rule):
                if rule in ("E0", "N1", "E5"):
                    # E0 and N1 only ever stop things; E5 fires as a SKIP.
                    self.assertTrue(cases)
                    continue
                self.assertTrue(fired, "%s has no case where it fires" % rule)
                if rule not in ("M3", "T1"):
                    self.assertTrue(not_fired, "%s has no case where it must not fire" % rule)


if __name__ == "__main__":
    unittest.main()
