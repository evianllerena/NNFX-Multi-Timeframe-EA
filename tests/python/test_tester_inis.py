"""Every Strategy Tester ini written by the tools pins the deposit and the leverage (G1_phase7_1 F1).

The tester keeps the last deposit and leverage used. A tool that leaves them out runs at whatever the previous run
used: after the G3 backtests (deposit 1 000 000) every later run did, set 3's evidence included, and every check
still passed. So each "[Tester]" ini line in tools/*.ps1 must carry "Deposit=" and "Leverage=" itself.
The scanned folder can be changed with the environment variable NNFX_SCAN_ROOT (repo root).
"""
import glob
import os
import re
import unittest

ROOT = os.environ.get("NNFX_SCAN_ROOT") or os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TESTER = re.compile(r'"\[Tester\]"')


def unpinned():
    found = []
    for path in sorted(glob.glob(os.path.join(ROOT, "tools", "*.ps1"))):
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
        for i, line in enumerate(lines):
            if not TESTER.search(line):
                continue
            # the ini's [Tester] keys are listed on this line and the next ones, up to "[TesterInputs]" or the end
            block = []
            for nxt in lines[i:i + 8]:
                block.append(nxt)
                if '"[TesterInputs]"' in nxt or "Set-Content" in nxt:
                    break
            text = " ".join(block)
            for key in ("Deposit=", "Leverage="):
                if '"%s' % key not in text:
                    found.append("%s:%d: no %s in the tester ini" % (os.path.relpath(path, ROOT), i + 1, key))
    return found


class TestTesterInis(unittest.TestCase):
    def test_every_tester_ini_pins_deposit_and_leverage(self):
        self.assertEqual(unpinned(), [])

    def test_some_tester_inis_found(self):
        n = 0
        for path in glob.glob(os.path.join(ROOT, "tools", "*.ps1")):
            with open(path, encoding="utf-8", errors="replace") as f:
                n += len(TESTER.findall(f.read()))
        self.assertGreaterEqual(n, 5)


if __name__ == "__main__":
    unittest.main()
