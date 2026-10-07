"""Tests for tools/check_ea_restart.py (Phase 6f, DESIGN_6F section 5): a restart run that keeps the core memory,
closes nothing and logs the missed candle passes; each defect fails."""
import copy
import csv
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

import check_ea_restart as c  # noqa: E402

DHEAD = "time,symbol,tf,o,h,l,c,atr,base,c1,c2,ex,vol,ind_ok,block,news,events,action,note".split(",")
TCOLS = ("time,event,trade_id,half,symbol,dir,magic,ticket,lots,price,sl,tp,prev_sl,entry,atr_entry,atr,close,"
         "balance,risk_pct,tick_size,tick_value,planned_risk,target_risk,cap_atr,note").split(",")
PAIRS = ("EURUSD", "EURGBP")


def drow(t, sym, block="-", events="-", action="-", note="-"):
    return [t, sym, "H1", "1", "1", "1", "1", "0.001", "1", "1", "1", "0", "1", "1", block, "0", events, action, note]


def trow(t, event, sym="", tid="", note="-"):
    r = {k: "0" for k in TCOLS}
    r.update(time=t, event=event, symbol=sym, trade_id=tid, note=note, magic="26060")
    return r


def baseline():
    d = []
    for h in range(10, 16):
        for s in PAIRS:
            block = "master" if h in (10, 11) else "-"
            ev = "SKIP:E1:-1" if (h == 11 and s == "EURGBP") else "-"
            d.append(drow("2026.06.02 %02d:00" % h, s, block, ev))
    t = [trow("2026.06.02 09:00:00", "INFO", note="orders allowed: TESTER"),
         trow("2026.06.02 14:00:00", "OPEN", "EURUSD", "T1")]
    return d, t


def restart_run():
    d, t = baseline()
    d = [list(r) for r in d]
    for r in d:
        if r[0] == "2026.06.02 12:00":
            r[14] = "missed"
            r[18] = "missed while stopped (OD-7 (b))"
    t = [dict(x) for x in t]
    t.insert(1, trow("2026.06.02 13:00:00", "PRESTOP", note="simulated restart (tester; InpRestartAt 2026.06.02 12:00)"))
    t.insert(2, trow("2026.06.02 13:00:00", "REBUILD", note="simulated restart; broker: 0 open trade(s); notes=state file: present"))
    t.insert(3, trow("2026.06.02 13:00:00", "INFO", "EURUSD", note="start (simulated restart): restored; core flat; broker flat; "
                                                                  "replay with no blocks flat; the replay agrees"))
    t.insert(4, trow("2026.06.02 13:00:00", "INFO", "EURGBP", note="start (simulated restart): restored; core flat; broker flat; "
                                                                  "replay with no blocks short; the replay differs: information only"))
    return d, t


class TestCheckEaRestart(unittest.TestCase):
    def run_check(self, d, t, base=None, **kw):
        tmp = tempfile.mkdtemp()

        def write(name, drows, trows):
            dp, tp = os.path.join(tmp, name + "_d.csv"), os.path.join(tmp, name + "_t.csv")
            with open(dp, "w", encoding="ascii", newline="") as f:
                w = csv.writer(f, lineterminator="\r\n")
                w.writerow(DHEAD)
                w.writerows(drows)
            with open(tp, "w", encoding="ascii", newline="") as f:
                w = csv.DictWriter(f, fieldnames=TCOLS, lineterminator="\r\n")
                w.writeheader()
                w.writerows(trows)
            return dp, tp
        dp, tp = write("run", d, t)
        bd = bt = None
        if base:
            bd, bt = write("base", base[0], base[1])
        buf = io.StringIO()
        with redirect_stdout(buf):
            ok = c.check(dp, tp, kw.get("master_off"), kw.get("replay_sym"), bd, bt)
        return ok, buf.getvalue()

    def full(self, d, t):
        return self.run_check(d, t, baseline(), master_off="2026.06.02 10:00;2026.06.02 12:00", replay_sym="EURGBP")

    def test_good_restart_passes(self):
        ok, out = self.full(*restart_run())
        self.assertTrue(ok, out)
        self.assertIn("the core memory was restored exactly", out)
        self.assertIn("managed through the restart", out)

    def test_missed_row_with_news_reasons(self):
        # a missed candle inside a news block: "missed;N1 ..." is still a missed row (run final_restart_open_20261006 on d80dd0e)
        d, t = restart_run()
        next(r for r in d if r[14] == "missed" and r[1] == "EURGBP")[14] = "missed;N1 GBP GDP 2026.06.03 09:00"
        ok, out = self.full(d, t)
        self.assertTrue(ok, out)

    def test_no_restart(self):
        d, t = restart_run()
        t = [x for x in t if x["event"] not in ("PRESTOP", "REBUILD")]
        ok, out = self.full(d, t)
        self.assertFalse(ok)
        self.assertIn("need exactly one simulated restart", out)

    def test_close_at_the_restart(self):
        d, t = restart_run()
        t.insert(5, trow("2026.06.02 13:00:00", "EXIT", "EURUSD", "T0", "D6f-1: the rules core is flat"))
        ok, out = self.full(d, t)
        self.assertFalse(ok)
        self.assertIn("closed at the restart", out)

    def test_missed_candle_acted_on(self):
        d, t = restart_run()
        next(r for r in d if r[14] == "missed")[17] = "OPEN T9"
        ok, out = self.full(d, t)
        self.assertFalse(ok)
        self.assertIn("a missed candle was acted on", out)

    def test_missed_candle_not_logged(self):
        d, t = restart_run()
        d = [r for r in d if not (r[14] == "missed" and r[1] == "EURGBP")]
        ok, out = self.full(d, t)
        self.assertFalse(ok)
        self.assertIn("EURGBP: no missed-candle row", out)

    def test_replay_used_as_the_memory(self):
        # the restart took the replay's answer (short) as the core memory: the start-up row no longer says flat/flat
        d, t = restart_run()
        t[4]["note"] = "start (simulated restart): no saved memory; core short; broker flat; replay with no blocks short"
        ok, out = self.full(d, t)
        self.assertFalse(ok)
        self.assertIn("EURGBP: start-up row is not", out)

    def test_memory_not_restored_exactly(self):
        d, t = restart_run()
        next(r for r in d if r[0] == "2026.06.02 14:00" and r[1] == "EURGBP")[16] = "ENTER:E2:1"
        ok, out = self.full(d, t)
        self.assertFalse(ok)
        self.assertIn("differs from the baseline", out)

    def test_trade_not_managed_through_the_restart(self):
        d, t = restart_run()
        t = [x for x in t if x["event"] != "OPEN"]
        ok, out = self.full(d, t)
        self.assertFalse(ok)
        self.assertIn("trade log differs from the run without the restart", out)

    def test_master_block_not_seen(self):
        d, t = restart_run()
        for r in d:
            if r[14] == "master":
                r[14] = "-"
        ok, out = self.full(d, t)
        self.assertFalse(ok)
        self.assertIn("no entry was blocked by the master switch", out)


if __name__ == "__main__":
    unittest.main()
