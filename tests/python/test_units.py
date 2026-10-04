"""Unit tests for signals, sizing, exposure and settings."""
import math
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nnfx_ref import exposure, signals, sizing  # noqa: E402
from nnfx_ref.settings import Settings  # noqa: E402


class TestSignals(unittest.TestCase):
    def test_price_line(self):
        self.assertEqual(signals.price_line_dir(1.1010, 1.1000), 1)
        self.assertEqual(signals.price_line_dir(1.0990, 1.1000), -1)
        self.assertEqual(signals.price_line_dir(1.1000, 1.1000), 0)

    def test_two_line(self):
        self.assertEqual(signals.two_line_dir(2.0, 1.0), 1)
        self.assertEqual(signals.two_line_dir(1.0, 2.0), -1)
        self.assertEqual(signals.two_line_dir(1.0, 1.0), 0)

    def test_centre_line_uses_its_own_centre(self):
        self.assertEqual(signals.centre_line_dir(55, 50), 1)
        self.assertEqual(signals.centre_line_dir(45, 50), -1)
        self.assertEqual(signals.centre_line_dir(10, 50), -1, "10 is below a centre of 50 even though > 0")

    def test_centre_line_never_defaults_to_zero(self):
        with self.assertRaises(ValueError):
            signals.centre_line_dir(1.0, None)

    def test_bad_values_are_never_signals(self):
        for bad in (None, float("nan"), float("inf"), -float("inf"), signals.EMPTY_VALUE, "x"):
            with self.subTest(bad=bad):
                self.assertEqual(signals.two_line_dir(bad, 1.0), 0)
                self.assertEqual(signals.two_line_dir(1.0, bad), 0)
                self.assertEqual(signals.price_line_dir(bad, 1.0), 0)
                self.assertEqual(signals.centre_line_dir(bad, 0.0), 0)
                self.assertFalse(signals.volume_pass("level", bad, level=1.0))

    def test_volume_rules(self):
        self.assertTrue(signals.volume_pass("level", 5.0, level=4.0))
        self.assertFalse(signals.volume_pass("level", 4.0, level=4.0))
        self.assertTrue(signals.volume_pass("average", 10.0, history=[8, 10, 12]))
        self.assertFalse(signals.volume_pass("average", 9.9, history=[8, 10, 12]))
        self.assertFalse(signals.volume_pass("average", 10.0, history=[]))
        self.assertTrue(signals.volume_pass("cross", 3.0, other=2.0))
        self.assertFalse(signals.volume_pass("cross", 3.0, other=None))
        with self.assertRaises(ValueError):
            signals.volume_pass("rsi_70", 1.0)

    def test_warmup(self):
        self.assertFalse(signals.warmed_up(49, 50))
        self.assertTrue(signals.warmed_up(50, 50))


class TestSizing(unittest.TestCase):
    # EURUSD-like: tick size 0.00001, tick value 1.00 (account currency) per lot.
    def test_two_percent_rounded_down(self):
        r = sizing.size_trade(10000, 2.0, 0.0030, 0.00001, 1.0, 0.01, 0.01)
        # 200 / (300 per lot) = 0.6667 lots -> halves 0.3333 -> 0.33 each
        self.assertFalse(r.skipped)
        self.assertAlmostEqual(r.half_lots, 0.33)
        self.assertAlmostEqual(r.total_lots, 0.66)
        self.assertAlmostEqual(r.risk_money, 198.0)
        self.assertLessEqual(r.risk_money, r.target_risk_money)

    def test_never_rounds_up_to_min_lot(self):
        r = sizing.size_trade(100, 2.0, 0.0030, 0.00001, 1.0, 0.01, 0.01)
        # 2 / 300 = 0.0067 lots -> halves 0.0033 < 0.01: skip (old harness traded 0.02 here)
        self.assertTrue(r.skipped)
        self.assertEqual(r.total_lots, 0.0)

    def test_exact_min_lot_halves(self):
        r = sizing.size_trade(900, 2.0, 0.0030, 0.00001, 1.0, 0.01, 0.01)
        # 18 / 300 = 0.06 -> 0.03 each
        self.assertAlmostEqual(r.half_lots, 0.03)

    def test_float_step_edge(self):
        # 0.3 / 0.1 is 2.9999999999999996 in floating point; must still give 3 steps.
        r = sizing.size_trade(1500, 2.0, 0.0050, 0.00001, 1.0, 0.1, 0.1)
        # 30 / 500 = 0.06 total -> 0.03 half < 0.1 -> skip
        self.assertTrue(r.skipped)
        r = sizing.size_trade(30000, 2.0, 0.0010, 0.00001, 1.0, 0.1, 0.1)
        # 600 / 100 = 6 total -> 3.0 half
        self.assertAlmostEqual(r.half_lots, 3.0)

    def test_risk_never_above_target(self):
        for bal in (137, 999, 2500, 7777, 12345, 98765):
            for stop in (0.0007, 0.0013, 0.0042, 0.0150):
                r = sizing.size_trade(bal, 2.0, stop, 0.00001, 1.0, 0.01, 0.01)
                with self.subTest(balance=bal, stop=stop):
                    self.assertLessEqual(r.risk_money, r.target_risk_money + 1e-6)

    def test_bad_inputs(self):
        with self.assertRaises(ValueError):
            sizing.size_trade(10000, 2.0, 0.0, 0.00001, 1.0, 0.01, 0.01)


class TestExposure(unittest.TestCase):
    def test_currencies_with_suffix(self):
        self.assertEqual(exposure.currencies("EURUSD"), ("EUR", "USD"))
        self.assertEqual(exposure.currencies("eurusd.m"), ("EUR", "USD"))
        self.assertEqual(exposure.currencies("GBPJPY#"), ("GBP", "JPY"))

    def test_legs(self):
        self.assertEqual(exposure.legs("EURUSD", 1), [("EUR", 1), ("USD", -1)])
        self.assertEqual(exposure.legs("EURUSD", -1), [("EUR", -1), ("USD", 1)])

    def test_vp_example_all_short_aud(self):
        # VP's example: EUR/AUD long, AUD/USD short, AUD/CAD short = three times short AUD.
        out = exposure.allocate([], [("EURAUD", 1), ("AUDUSD", -1), ("AUDCAD", -1)], 2.0, "first")
        self.assertEqual(out, [2.0, 0.0, 0.0])

    def test_open_position_blocks_same_direction(self):
        out = exposure.allocate([("EURUSD", 1)], [("EURGBP", 1)], 2.0)   # both long EUR
        self.assertEqual(out, [0.0])

    def test_opposite_direction_is_allowed(self):
        # Decision S-4: only same-direction exposure counts.
        out = exposure.allocate([("EURUSD", 1)], [("EURGBP", -1)], 2.0)  # long EUR vs short EUR
        self.assertEqual(out, [2.0])

    def test_unrelated_pairs(self):
        out = exposure.allocate([("EURUSD", 1)], [("AUDNZD", 1)], 2.0)
        self.assertEqual(out, [2.0])

    def test_split_mode_halves_simultaneous_signals(self):
        out = exposure.allocate([], [("EURUSD", 1), ("EURGBP", 1)], 2.0, "split")
        self.assertEqual(out, [1.0, 1.0])

    def test_split_mode_still_respects_open_positions(self):
        out = exposure.allocate([("EURJPY", 1)], [("EURUSD", 1), ("EURGBP", 1)], 2.0, "split")
        self.assertEqual(out, [0.0, 0.0])


class TestSettings(unittest.TestCase):
    def test_defaults_match_spec(self):
        s = Settings()
        self.assertEqual((s.risk_pct, s.sl_atr, s.tp1_atr, s.max_dist_atr), (2.0, 1.5, 1.0, 1.0))
        self.assertEqual((s.trail_on, s.trail_start_atr, s.trail_dist_atr), (True, 2.0, 1.5))
        self.assertIsNone(s.runner_cap_atr)
        self.assertTrue(s.exit_on_exit_ind and s.exit_on_c1 and s.exit_on_baseline and s.news_exit)
        self.assertTrue(s.one_candle and s.btf_on and s.pullback_on)
        self.assertEqual((s.btf_bars, s.continuation), (7, "a"))

    def test_unknown_setting_rejected(self):
        with self.assertRaises(ValueError):
            Settings.from_dict({"risk_percent": 1})

    def test_validation(self):
        with self.assertRaises(ValueError):
            Settings(continuation="c").validate()
        with self.assertRaises(ValueError):
            Settings(runner_cap_atr=0).validate()


if __name__ == "__main__":
    unittest.main()
