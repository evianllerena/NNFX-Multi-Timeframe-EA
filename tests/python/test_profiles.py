"""Profiles and the shared signal cases (Phase 5)."""
import math
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nnfx_ref import profiles, signals  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROFILE_DIR = os.path.join(ROOT, "profiles")
BAD_DIR = os.path.join(ROOT, "tests", "fixtures", "profiles_bad")
CASES = os.path.join(ROOT, "tests", "fixtures", "signals", "signal_cases.txt")


def tok(text):
    t = text.strip()
    if t == "nan":
        return float("nan")
    if t == "inf":
        return float("inf")
    if t == "empty":
        return signals.EMPTY_VALUE
    return float(t)


def load_cases():
    out = []
    with open(CASES, encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                out.append(line.split("|"))
    return out


def run_case(p):
    kind = p[0]
    if kind == "PL":
        return signals.price_line_dir(tok(p[2]), tok(p[3])), int(p[4])
    if kind == "TL":
        return signals.two_line_dir(tok(p[2]), tok(p[3])), int(p[4])
    if kind == "CL":
        return signals.centre_line_dir(tok(p[2]), tok(p[3])), int(p[4])
    if kind == "VL":
        return int(signals.volume_pass("level", tok(p[2]), level=tok(p[3]))), int(p[4])
    if kind == "VA":
        hist = [tok(x) for x in p[4].split(";")]
        return int(signals.volume_pass("average", tok(p[2]), mult=tok(p[3]), history=hist)), int(p[5])
    if kind == "VC":
        return int(signals.volume_pass("cross", tok(p[2]), other=tok(p[3]))), int(p[4])
    raise AssertionError("unknown case kind %r" % kind)


class TestSignalCases(unittest.TestCase):
    def test_all_cases(self):
        cases = load_cases()
        self.assertGreaterEqual(len(cases), 30)
        names = [c[1] for c in cases]
        self.assertEqual(len(names), len(set(names)), "duplicate case names")
        for c in cases:
            with self.subTest(case=c[1]):
                got, want = run_case(c)
                self.assertEqual(got, want, "|".join(c))


class TestReferenceProfiles(unittest.TestCase):
    def test_all_reference_profiles_parse(self):
        files = sorted(f for f in os.listdir(PROFILE_DIR) if f.endswith(".txt"))
        self.assertEqual(len(files), 5)
        slots = set()
        for f in files:
            with self.subTest(profile=f):
                p = profiles.load(os.path.join(PROFILE_DIR, f))
                slots.add(p.slot)
        self.assertEqual(slots, {"BASELINE", "C1", "C2", "EXIT", "VOLUME"})

    def test_reference_details(self):
        c1 = profiles.load(os.path.join(PROFILE_DIR, "ref_c1_rvi10.txt"))
        self.assertEqual((c1.signal, c1.buf_fast, c1.buf_slow), ("two_line", 0, 1))
        c2 = profiles.load(os.path.join(PROFILE_DIR, "ref_c2_macd_main.txt"))
        self.assertEqual((c2.signal, c2.buf_main, c2.centre), ("centre_line", 0, 0.0))
        self.assertEqual(c2.inputs, [("int", "12"), ("int", "26"), ("int", "9"), ("enum", "PRICE_CLOSE")])
        base = profiles.load(os.path.join(PROFILE_DIR, "ref_baseline_sma20.txt"))
        self.assertEqual(base.inputs, [("int", "20"), ("int", "0"), ("enum", "MODE_SMA"), ("enum", "PRICE_CLOSE")])
        vol = profiles.load(os.path.join(PROFILE_DIR, "ref_volume_ticks20.txt"))
        self.assertEqual((vol.vol_rule, vol.vol_period, vol.vol_mult), ("average", 20, 1.0))

    def test_direction_and_volume_helpers(self):
        c2 = profiles.load(os.path.join(PROFILE_DIR, "ref_c2_macd_main.txt"))
        self.assertEqual(profiles.direction(c2, [0.0002]), 1)
        self.assertEqual(profiles.direction(c2, [-0.0002]), -1)
        base = profiles.load(os.path.join(PROFILE_DIR, "ref_baseline_sma20.txt"))
        self.assertEqual(profiles.direction(base, [1.1000], close=1.1010), 1)
        vol = profiles.load(os.path.join(PROFILE_DIR, "ref_volume_ticks20.txt"))
        self.assertTrue(profiles.volume_passes(vol, 120, history=[100] * 20))
        self.assertFalse(profiles.volume_passes(vol, 99, history=[100] * 20))
        with self.assertRaises(profiles.ProfileError):
            profiles.direction(vol, [1.0])


class TestBadProfiles(unittest.TestCase):
    def test_every_bad_profile_is_rejected(self):
        files = sorted(f for f in os.listdir(BAD_DIR) if f.endswith(".txt"))
        self.assertGreaterEqual(len(files), 10)
        for f in files:
            with self.subTest(profile=f):
                with self.assertRaises(profiles.ProfileError):
                    profiles.load(os.path.join(BAD_DIR, f))


if __name__ == "__main__":
    unittest.main()
