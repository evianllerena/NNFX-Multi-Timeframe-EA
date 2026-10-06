"""Every run of NNFX_OrderTest lists every input (source scan).

The Strategy Tester reuses an EA's last-used value for an input that is left out, or listed with an empty value
(runs restart_20261005_224233 and restart_20261005_225140, kept in checks\\invalid\\). Demo set files have the same
rule (driver guard "inputs read"). So each place that starts NNFX_OrderTest must name every input. Exception: the
five profile names (InpBaseline, InpC1, InpC2, InpExit, InpVolume), which no run changes.
"""
import os
import re
import unittest

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
EA = os.path.join(ROOT, "MQL5", "Experts", "NNFX", "NNFX_OrderTest.mq5")
PROFILE = {"InpBaseline", "InpC1", "InpC2", "InpExit", "InpVolume"}
DRIVERS = {
    # file: number of separate input lists for NNFX_OrderTest in it
    "run_phase5_checks.ps1": 3,
    "run_restart_tests.ps1": 1,
    "run_demo_restarts.ps1": 1,
    "close_test_leftovers.ps1": 1,
    "run_demo_master_test.ps1": 2,
}


def ea_inputs():
    with open(EA, encoding="utf-8") as f:
        names = re.findall(r"^input\s+\w+\s+(Inp\w+)", f.read(), re.M)
    return set(names) - PROFILE


def lists_in(path):
    """Each list of NNFX_OrderTest inputs: a run of "InpX=..." items (or "InpX = ..." hashtable keys) that
    contains InpMagic."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    blocks = re.split(r"\n\s*\n", text)
    out = []
    for b in blocks:
        names = set(re.findall(r"\b(Inp\w+)\s*=", b))
        if "InpMagic" in names and "InpRiskPct" in names:
            out.append(names)
    return out


class TestInputLists(unittest.TestCase):
    def test_every_input_listed(self):
        want = ea_inputs()
        self.assertGreater(len(want), 20)
        for name, n in DRIVERS.items():
            path = os.path.join(ROOT, "tools", name)
            if not os.path.exists(path):
                self.fail("%s missing" % name)
            with self.subTest(driver=name):
                lists = lists_in(path)
                self.assertEqual(len(lists), n, "%s: %d input lists found, expected %d" % (name, len(lists), n))
                for i, got in enumerate(lists):
                    missing = sorted(want - got)
                    self.assertEqual(missing, [], "%s list %d misses %s" % (name, i + 1, missing))


if __name__ == "__main__":
    unittest.main()
