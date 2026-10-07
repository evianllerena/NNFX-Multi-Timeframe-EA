"""Shared restart-rebuild cases and the state file (Phase 6c).

tests/fixtures/recovery/recovery_cases.txt is also run by MQL5/Scripts/NNFX/NNFX_RecoveryTest.mq5, so the Python
answer key and MQL5/Include/NNFX/State.mqh are checked against identical, hand-worked answers."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nnfx_ref import recovery as rc  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
CASES = os.path.join(ROOT, "tests", "fixtures", "recovery", "recovery_cases.txt")
STATE_FILES = os.path.join(ROOT, "tests", "fixtures", "recovery", "state_files")


def load_cases(path=CASES):
    cases, cur = [], None
    with open(path, encoding="ascii") as f:
        for raw in f:
            line = raw.rstrip("\r\n")
            if not line.strip() or line.startswith("#"):
                continue
            p = line.split("|")
            if p[0] == "CASE":
                cur = {"name": p[1], "pos": [], "deal": [], "candle": [], "strade": [], "exp": [], "note": [],
                       "ignore": False, "state": "absent"}
            elif p[0] == "END":
                cases.append(cur)
                cur = None
            elif p[0] == "MAGIC":
                cur["magic"] = int(p[1])
            elif p[0] == "PERIOD":
                cur["period"] = int(p[1])
            elif p[0] == "UPTO":
                cur["upto"] = rc.tparse(p[1])
            elif p[0] == "IGNORE_COMMENTS":
                cur["ignore"] = p[1] == "1"
            elif p[0] == "STATE":
                cur["state"] = p[1]
            elif p[0] == "STRADE":
                cur["strade"].append(rc.parse_trade(["TRADE"] + p[1:]))
            elif p[0] == "POS":
                cur["pos"].append(rc.Position(int(p[1]), p[2], int(p[3]), int(p[4]), float(p[5]), float(p[6]),
                                              float(p[7]), float(p[8]), p[9]))
            elif p[0] == "DEAL":
                cur["deal"].append(rc.Deal(int(p[1]), rc.tparse(p[2]), int(p[3]), p[4], int(p[5]), p[6], int(p[7]),
                                           float(p[8]), float(p[9]), p[10], p[11]))
            elif p[0] == "CANDLE":
                cur["candle"].append(rc.Candle(p[1], rc.tparse(p[2]), float(p[3]), float(p[4]), int(p[5]), int(p[6])))
            elif p[0] == "EXP":
                cur["exp"].append("|".join(p[1:]))
            elif p[0] == "NOTE":
                cur["note"].append(p[1])
            else:
                raise AssertionError("unknown line %r" % line)
    return cases


def run_case(c):
    trades, conts, notes = rc.rebuild(c["pos"], c["deal"], c["state"], c["strade"], c["candle"], c["period"],
                                      c["magic"], c["upto"], c["ignore"])
    return rc.serialize(trades, conts), notes


class TestRecoveryCases(unittest.TestCase):
    def test_all_cases(self):
        cases = load_cases()
        self.assertGreaterEqual(len(cases), 20)
        for c in cases:
            with self.subTest(case=c["name"]):
                got, notes = run_case(c)
                self.assertEqual(got, c["exp"], "\n".join(notes))
                for n in c["note"]:
                    self.assertTrue(any(n in x for x in notes), "%r not in notes %r" % (n, notes))


class TestStateFile(unittest.TestCase):
    def sample(self):
        t = rc.Trade("T0001", "EURUSD", 1, 11, 12, False, True, 0.33, 1.1, 1.1, 0.002, -1, 1.1, True, False)
        c = rc.Cont("EURUSD", 1, True, False, 0, rc.tparse("2026.06.02 10:00"))
        return t, c

    def test_fnv1a_published_vectors(self):
        self.assertEqual(rc.fnv1a32(""), 0x811C9DC5)
        self.assertEqual(rc.fnv1a32("a"), 0xE40C292C)
        self.assertEqual(rc.fnv1a32("foobar"), 0xBF9CF968)

    def test_round_trip(self):
        t, c = self.sample()
        text = rc.state_file_text("26999", [t], [c], rc.tparse("2026.06.02 13:00"))
        status, trades, conts, proc, why = rc.parse_state_file(text)
        self.assertEqual(status, "present", why)
        self.assertEqual(rc.serialize(trades, conts), rc.serialize([t], [c]))
        self.assertEqual(rc.tfmt(proc), "2026.06.02 13:00")

    def test_core_lines_round_trip(self):
        """6f (DESIGN_6F section 5): each pair's rules-core memory is a PCORE line, sorted by symbol, inside the
        checksum; a file without PCORE lines (the 6c test EA's) still reads as before."""
        t, c = self.sample()
        snap = "CORE|1|" + "|".join(["0"] * (rc.CORE_FIELDS - 2))
        cores = {"GBPUSD": snap, "AUDNZD": snap.replace("CORE|1|0|", "CORE|1|7|")}
        text = rc.state_file_text("26060", [t], [c], 0, cores)
        self.assertLess(text.index("PCORE|AUDNZD|"), text.index("PCORE|GBPUSD|"))
        got = {}
        status, trades, conts, _, why = rc.parse_state_file(text, got)
        self.assertEqual(status, "present", why)
        self.assertEqual(got, cores)
        self.assertEqual(rc.parse_state_file(text.replace("CORE|1|7|", "CORE|1|8|"))[0], "corrupt")
        self.assertEqual(rc.state_file_text("26060", [t], [c], 0), rc.state_file_text("26060", [t], [c], 0, {}))

    def test_one_changed_byte_is_corrupt(self):
        t, c = self.sample()
        text = rc.state_file_text("26999", [t], [c], 0).replace("0.002", "0.003")
        self.assertEqual(rc.parse_state_file(text)[0], "corrupt")

    def test_wrong_version_and_truncation_are_corrupt(self):
        t, c = self.sample()
        text = rc.state_file_text("26999", [t], [c], 0)
        bad = text.replace("NNFXSTATE|1|", "NNFXSTATE|2|")
        body = bad.rsplit("CHECKSUM|", 1)[0]
        bad = body + "CHECKSUM|%08x\n" % rc.fnv1a32(body)
        self.assertEqual(rc.parse_state_file(bad)[0], "corrupt")
        self.assertEqual(rc.parse_state_file(text[: len(text) // 2])[0], "corrupt")

    def test_shared_state_files(self):
        """The same files are read by NNFX_RecoveryTest (MQL5): SFTEST lines in index.txt."""
        with open(os.path.join(STATE_FILES, "index.txt"), encoding="ascii") as f:
            rows = [ln.strip().split("|") for ln in f if ln.strip() and not ln.startswith("#")]
        self.assertGreaterEqual(len(rows), 4)
        for p in rows:
            with self.subTest(file=p[1]):
                with open(os.path.join(STATE_FILES, p[1]), encoding="ascii", newline="") as f:
                    text = f.read()
                cores = {}
                status, trades, conts, _, why = rc.parse_state_file(text, cores)
                self.assertEqual(status, p[2], why)
                self.assertEqual(len(trades), int(p[3]))
                self.assertEqual(len(conts), int(p[4]))
                if len(p) > 5:
                    self.assertEqual(len(cores), int(p[5]))


if __name__ == "__main__":
    unittest.main()
