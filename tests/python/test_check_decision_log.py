"""Tests for tools/check_decision_log.py (Phase 6f), including logs it must reject (the plan's planted-bug list)."""
import csv
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

import check_decision_log as c  # noqa: E402

PAIRS = ["EURUSD", "AUDNZD", "EURGBP"]
TCOLS = ("time,event,trade_id,half,symbol,dir,magic,ticket,lots,price,sl,tp,prev_sl,entry,atr_entry,atr,close,"
         "balance,risk_pct,tick_size,tick_value,planned_risk,target_risk,cap_atr,note").split(",")


def drow(t, sym, events="-", action="-", block="-"):
    return [t.strftime("%Y.%m.%d %H:%M"), sym, "H1", "1.1", "1.2", "1.0", "1.15", "0.001", "1.1", "1", "1", "0", "1", "1",
            block, "0", events, action, "-"]


def good():
    rows = []
    t0 = datetime(2026, 6, 4, 20)          # Thursday 20:00
    times = [t0 + timedelta(hours=k) for k in range(4)]            # Thu 20:00 .. 23:00
    times += [datetime(2026, 6, 5, 0) + timedelta(hours=k) for k in range(24)]   # Friday
    times += [datetime(2026, 6, 8, 0) + timedelta(hours=k) for k in range(3)]    # Monday (weekend gap)
    for t in times:
        for s in PAIRS:
            ev, act = "-", "-"
            if t == datetime(2026, 6, 5, 3) and s == "AUDNZD":
                ev, act = "ENTER:E1:1", "OPEN T0001"
            if t == datetime(2026, 6, 5, 9) and s == "EURGBP":
                ev, act = "SKIP:E2:-1", "-"
            rows.append(drow(t, s, ev, act, "rollover" if t.hour == 0 else "-"))
    return rows


def trades(ids=("T0001",)):
    out = []
    for tid in ids:
        r = {k: "0" for k in TCOLS}
        r.update(time="2026.06.05 04:00:02", event="OPEN", trade_id=tid, half="1", symbol="AUDNZD", note="-")
        out.append(r)
    return out


class TestCheckDecisionLog(unittest.TestCase):
    def run_check(self, rows, trade_rows=None, tf=60):
        d = tempfile.mkdtemp()
        dp, tp = os.path.join(d, "dec.csv"), os.path.join(d, "trades.csv")
        with open(dp, "w", encoding="ascii", newline="") as f:
            w = csv.writer(f, lineterminator="\r\n")
            w.writerow(c.HEADER)
            w.writerows(rows)
        tpath = None
        if trade_rows is not None:
            with open(tp, "w", encoding="ascii", newline="") as f:
                w = csv.DictWriter(f, fieldnames=TCOLS, lineterminator="\r\n")
                w.writeheader()
                w.writerows(trade_rows)
            tpath = tp
        buf = io.StringIO()
        with redirect_stdout(buf):
            ok = c.check(dp, tf, PAIRS, tpath)
        return ok, buf.getvalue()

    def test_good_log_passes(self):
        ok, out = self.run_check(good(), trades())
        self.assertTrue(ok, out)
        self.assertIn("1 ENTER events, 1 OPEN actions", out)

    def test_missing_row(self):
        rs = [r for r in good() if not (r[0] == "2026.06.05 07:00" and r[1] == "EURGBP")]
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("EURGBP: gap from 2026.06.05 06:00 to 2026.06.05 08:00", out)

    def test_duplicate_row(self):
        rs = good()
        rs.insert(10, list(rs[9]))
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("duplicate row", out)

    def test_out_of_order(self):
        rs = good()
        rs[3], rs[4] = rs[4], rs[3]
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("out of the fixed order", out)

    def test_enter_without_trade_log_open(self):
        ok, out = self.run_check(good(), trades(ids=()))
        self.assertFalse(ok)
        self.assertIn("the trade log has no OPEN for it", out)

    def test_trade_log_open_without_enter(self):
        ok, out = self.run_check(good(), trades(ids=("T0001", "T0002")))
        self.assertFalse(ok)
        self.assertIn("trade log OPEN T0002 has no decision row", out)

    def test_enter_with_no_action(self):
        rs = good()
        for r in rs:
            if r[17] == "OPEN T0001":
                r[17] = "-"
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("ENTER at 2026.06.05 03:00 AUDNZD but the action is '-'", out)

    def test_row_mid_candle(self):
        rs = good()
        rs[5][0] = "2026.06.04 21:30"
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("not on a 60-minute candle boundary", out)

    def test_malformed_event(self):
        rs = good()
        for r in rs:
            if r[16] == "SKIP:E2:-1":
                r[16] = "SKIP:E2"
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("malformed event", out)

    def test_weekend_gap_allowed_but_early_friday_stop_not(self):
        ok, out = self.run_check(good())
        self.assertTrue(ok, out)
        rs = [r for r in good() if r[0][:10] != "2026.06.05" or int(r[0][11:13]) < 12]   # drop Friday afternoon
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("gap from 2026.06.05 11:00 to 2026.06.08 00:00", out)


if __name__ == "__main__":
    unittest.main()
