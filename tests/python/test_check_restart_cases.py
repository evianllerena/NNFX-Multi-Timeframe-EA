"""Tests for tools/check_restart_cases.py and the R5/R6 picks of tools/pick_restart_times.py (G1_review2_1 F1/F2):
the fixed behaviour passes; the unfixed behaviour and a run that never exercised the case fail."""
import csv
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

import check_restart_cases as c  # noqa: E402
import pick_restart_times as p  # noqa: E402

TCOLS = ("time,event,trade_id,half,symbol,dir,magic,ticket,lots,price,sl,tp,prev_sl,entry,atr_entry,atr,close,"
         "balance,risk_pct,tick_size,tick_value,planned_risk,target_risk,cap_atr,note").split(",")


def row(t, event, tid="", half="0", note="-", **kw):
    r = {k: "0" for k in TCOLS}
    r.update(time=t, event=event, trade_id=tid, half=half, note=note, symbol="EURUSD", tick_size="0.00001")
    r.update({k: str(v) for k, v in kw.items()})
    return r


def be_run(fixed=True):
    rs = [row("2026.06.10 10:00:05", "OPEN", "T0012", "1", price="1.10000", sl="1.09850"),
          row("2026.06.10 10:00:05", "OPEN", "T0012", "2", price="1.10002", sl="1.09852"),
          row("2026.06.10 12:20:00", "TP1", "T0012", "1"),
          row("2026.06.10 12:20:00", "TEST", "T0012", note="TEST: BE stop move refused (held until the restart)"),
          row("2026.06.10 12:20:00", "RETRY", "T0012", note="BE: stop move to 1.10002 refused; tried again (A1)"),
          row("2026.06.10 13:00:00", "PRESTOP", note="simulated restart"),
          row("2026.06.10 13:00:00", "REBUILD", note="match=yes")]
    if fixed:
        rs += [row("2026.06.10 13:00:00", "RETRY", "T0012", note="BE: not in place after TP1 and no failed move on record"),
               row("2026.06.10 13:00:20", "BE", "T0012", "2", sl="1.10002", note="via=tick; restored after a restart (A1)")]
    return rs


def abort_run(fixed=True):
    rs = [row("2026.06.10 14:00:03", "OPEN", "T0007", "1", price="1.1", sl="1.0985", note="half 2 failed"),
          row("2026.06.10 14:00:03", "ABORT", "T0007", note="half 2 not opened; HALF 1 CLOSE FAILED; pending, tried again (A8)"),
          row("2026.06.10 15:00:00", "PRESTOP", note="simulated restart")]
    # as NNFX_OrderTest writes it: what the rebuild closes is logged before the REBUILD row
    if fixed:
        rs += [row("2026.06.10 15:00:00", "EXIT", "T0007", note="lone half 1, half 2 never opened: closed (A8)"),
               row("2026.06.10 15:00:00", "CLOSE", "T0007", "1", note="ABORT leftover closed after the restart (A8), deal reason 3"),
               row("2026.06.10 15:00:00", "REBUILD", note="match=no")]
    else:
        rs += [row("2026.06.10 15:00:00", "REBUILD", note="match=no"), row("2026.06.10 16:10:00", "SL", "T0007", "1")]
    return rs


class TestBeCase(unittest.TestCase):
    def test_fixed_passes(self):
        fails, info = c.check("be", be_run(), "T0012")
        self.assertEqual(fails, [])
        self.assertIn("restored after a restart", info[0])

    def test_price_passed_close_passes(self):
        rs = be_run(fixed=False) + [row("2026.06.10 13:00:01", "EXIT", "T0012",
                                        note="BE price already passed after 0 failed moves: half 2 closed at market")]
        self.assertEqual(c.check("be", rs, "T0012")[0], [])

    def test_unfixed_fails(self):
        fails, _ = c.check("be", be_run(fixed=False), "T0012")
        self.assertTrue(any("never moved to breakeven" in f for f in fails), fails)

    def test_wrong_stop_fails(self):
        rs = be_run()
        rs[-1]["sl"] = "1.10010"
        self.assertTrue(any("is not half 2's entry" in f for f in c.check("be", rs, "T0012")[0]))

    def test_late_fails(self):
        rs = be_run()
        rs[-1]["time"] = "2026.06.10 13:05:00"
        self.assertTrue(any("after the restart" in f for f in c.check("be", rs, "T0012")[0]))

    def test_not_exercised_fails(self):
        rs = [r for r in be_run() if not (r["event"] == "RETRY" and "refused" in r["note"])]
        self.assertTrue(any("hook did not act" in f for f in c.check("be", rs, "T0012")[0]))
        rs = be_run()
        rs.insert(5, row("2026.06.10 12:40:00", "SL", "T0012", "2"))
        self.assertTrue(any("not exercised" in f for f in c.check("be", rs, "T0012")[0]))

    def test_two_rebuilds_fail(self):
        rs = be_run() + [row("2026.06.10 14:00:00", "REBUILD")]
        self.assertTrue(any("REBUILD rows" in f for f in c.check("be", rs, "T0012")[0]))

    def test_no_prestop_fails(self):
        rs = [r for r in be_run() if r["event"] != "PRESTOP"]
        self.assertTrue(any("no PRESTOP" in f for f in c.check("be", rs, "T0012")[0]))


class TestAbortCase(unittest.TestCase):
    def test_fixed_passes(self):
        self.assertEqual(c.check("abort", abort_run(), "T0007")[0], [])

    def test_unfixed_fails(self):
        fails, _ = c.check("abort", abort_run(fixed=False), "T0007")
        self.assertTrue(any("not closed" in f for f in fails), fails)
        self.assertTrue(any("managed as a trade" in f for f in fails), fails)

    def test_closed_before_restart_fails(self):
        rs = abort_run()
        rs.insert(2, row("2026.06.10 14:00:09", "CLOSE", "T0007", "1", note="closed by retry 1 (A8)"))
        self.assertTrue(any("hook did not hold" in f for f in c.check("abort", rs, "T0007")[0]))


class TestPickCases(unittest.TestCase):
    def write(self, rows):
        fd, path = tempfile.mkstemp(suffix=".csv")
        os.close(fd)
        with open(path, "w", newline="", encoding="ascii") as f:
            w = csv.DictWriter(f, fieldnames=TCOLS)
            w.writeheader()
            w.writerows(rows)
        self.addCleanup(os.remove, path)
        return path

    def test_r5_r6(self):
        tr_open = "TRADE|T0012|EURUSD|1|31|32|1|1|0.1|1.1|1.1|0.001|-1|1.0985|0|0"
        tr_tp1 = "TRADE|T0012|EURUSD|1|31|32|0|1|0.1|1.1|1.1|0.001|-1|1.1|1|0"
        rows = [row("2026.06.10 09:00:00", "STATE", note="proc=x; state=CONT|EURUSD|1|0"),
                row("2026.06.10 10:00:05", "OPEN", "T0012", "1"),
                row("2026.06.10 10:00:05", "STATE", note="proc=x; state=" + tr_open),
                row("2026.06.10 11:00:00", "STATE", note="proc=x; state=" + tr_open),
                row("2026.06.10 12:00:00", "STATE", note="proc=x; state=" + tr_tp1),
                row("2026.06.10 13:00:00", "STATE", note="proc=x; state=" + tr_tp1)]
        path = self.write(rows)
        picked = p.pick(path, "2026.06.10 00:00")
        cases = p.pick_cases(path, "2026.06.10 00:00", picked)
        self.assertEqual(cases["R5"], ("2026.06.10 13:00:00", "T0012"))
        self.assertEqual(cases["R6"], ("2026.06.10 11:00:00", "T0012"))


if __name__ == "__main__":
    unittest.main()
