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

    def test_late_pair_in_a_later_batch(self):
        """A pair whose candle arrived later is processed after the others, noted "batch 2": allowed. The same row
        without the note, or a batch-2 row placed before batch-1 rows, is out of order."""
        rs = good()
        k = next(i for i, r in enumerate(rs) if r[0] == "2026.06.05 00:00" and r[1] == "EURUSD")
        late = rs.pop(k)
        late[18] = "batch 2; -"
        rs.insert(k + 2, late)
        ok, out = self.run_check(rs)
        self.assertTrue(ok, out)
        self.assertIn("1 row(s) processed in a later batch", out)
        late[18] = "-"
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("2026.06.05 00:00: pairs out of the fixed order", out)
        rs = good()
        rs[k + 1][18] = "batch 2; -"   # AUDNZD noted batch 2 but written before EURGBP of batch 1
        ok, out = self.run_check(rs)
        self.assertFalse(ok)

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

class TestDataGaps(unittest.TestCase):
    """Phase 7 (run ea_explore2_M30_20261014_165013): holiday and history gaps. With --bars, a gap is INFO only where
    the broker's bar export proves there is no candle; a gap over a candle that exists stays a FAIL."""

    def run_with_bars(self, rows, bar_times):
        d = tempfile.mkdtemp()
        dp = os.path.join(d, "dec.csv")
        with open(dp, "w", encoding="ascii", newline="") as f:
            w = csv.writer(f, lineterminator="\r\n")
            w.writerow(c.HEADER)
            w.writerows(rows)
        bd = os.path.join(d, "bars")
        os.makedirs(bd)
        for s in PAIRS:
            with open(os.path.join(bd, "%s_H1.csv" % s), "w", encoding="ascii", newline="") as f:
                f.write("# symbol=%s timeframe=H1\r\ntime,open\r\n" % s)
                for t in bar_times[s]:
                    f.write("%s,1.1\r\n" % t.strftime("%Y.%m.%d %H:%M"))
        buf = io.StringIO()
        with redirect_stdout(buf):
            ok = c.check(dp, 60, PAIRS, None, bd)
        return ok, buf.getvalue()

    def gap_rows(self):
        """Friday 10:00 and 11:00 missing for every pair (a holiday-like gap); EURUSD also misses 15:00 alone."""
        holes = {datetime(2026, 6, 5, 10), datetime(2026, 6, 5, 11)}
        rows = [r for r in good() if datetime.strptime(r[0], "%Y.%m.%d %H:%M") not in holes]
        rows = [r for r in rows if not (r[1] == "EURUSD" and r[0] == "2026.06.05 15:00")]
        times = sorted({datetime.strptime(r[0], "%Y.%m.%d %H:%M") for r in good()})
        return rows, holes, times

    def test_gaps_without_bars_fail(self):
        rows, _, _ = self.gap_rows()
        ok, out = TestCheckDecisionLog.run_check(TestCheckDecisionLog(), rows)
        self.assertFalse(ok, out)
        self.assertIn("gap from 2026.06.05 09:00 to 2026.06.05 12:00", out)

    def test_gaps_where_the_broker_has_no_candle_pass(self):
        rows, holes, times = self.gap_rows()
        bars = {s: [t for t in times if t not in holes] for s in PAIRS}
        bars["EURUSD"] = [t for t in bars["EURUSD"] if t != datetime(2026, 6, 5, 15)]
        ok, out = self.run_with_bars(rows, bars)
        self.assertTrue(ok, out)
        # the 09:00-12:00 gap, the 14:00-16:00 gap, and 15:00 as a time other pairs have: 3 items for EURUSD
        self.assertIn("EURUSD: 3 gap(s) / missing row(s) where the broker's history has no candle", out)

    def test_gap_over_an_existing_candle_fails(self):
        rows, holes, times = self.gap_rows()
        bars = {s: [t for t in times if t not in holes] for s in PAIRS}   # EURUSD 15:00 exists at the broker
        ok, out = self.run_with_bars(rows, bars)
        self.assertFalse(ok, out)
        self.assertIn("EURUSD: gap from 2026.06.05 14:00 to 2026.06.05 16:00", out)

    def test_bars_not_covering_the_gap_fail(self):
        rows, holes, times = self.gap_rows()
        bars = {s: [t for t in times if t not in holes and t >= datetime(2026, 6, 5, 12)] for s in PAIRS}
        ok, out = self.run_with_bars(rows, bars)
        self.assertFalse(ok, out)
        self.assertIn("gap from 2026.06.05 09:00 to 2026.06.05 12:00", out)

class TestLateRows(unittest.TestCase):
    """Phase 7 (explore2 runs): stall catch-up rows, rows written after a later candle time, and an ABORT logged as
    REFUSE are INFO; the same shapes without their reason stay FAILs."""
    run_check = TestCheckDecisionLog.run_check

    def test_stall_row_outside_the_order_rule(self):
        rows = good()
        k = next(i for i, r in enumerate(rows) if r[0] == "2026.06.05 10:00" and r[1] == "EURGBP")
        stall = rows.pop(k)
        stall[18] = "missed (stall; OD-7 (b))"
        rows.insert(k - 2, stall)   # written before EURUSD and AUDNZD of the same time
        ok, out = self.run_check(rows)
        self.assertTrue(ok, out)
        self.assertIn("1 stall catch-up row(s)", out)

    def test_stall_row_acted_on_fails(self):
        rows = good()
        r = next(r for r in rows if r[0] == "2026.06.05 10:00" and r[1] == "EURGBP")
        r[18], r[16], r[17] = "missed (stall; OD-7 (b))", "ENTER:E1:1", "OPEN T0009"
        ok, out = self.run_check(rows)
        self.assertFalse(ok, out)
        self.assertIn("stall row", out)

    def test_row_written_after_a_later_time_is_late(self):
        rows = good()
        k = next(i for i, r in enumerate(rows) if r[0] == "2026.06.05 10:00" and r[1] == "AUDNZD")
        late = rows.pop(k)
        j = next(i for i, r in enumerate(rows) if r[0] == "2026.06.05 11:00" and r[1] == "EURGBP")
        rows.insert(j + 1, late)
        ok, out = self.run_check(rows)
        self.assertTrue(ok, out)
        self.assertIn("1 row(s) written after a later candle time", out)

    def test_out_of_order_within_its_time_still_fails(self):
        rows = good()
        k = next(i for i, r in enumerate(rows) if r[0] == "2026.06.05 10:00" and r[1] == "EURGBP")
        rows.insert(k - 2, rows.pop(k))   # EURGBP before EURUSD at the same time, no stall note
        ok, out = self.run_check(rows)
        self.assertFalse(ok, out)
        self.assertIn("pairs out of the fixed order", out)

    def abort_case(self, with_abort):
        rows = good()
        r = next(r for r in rows if r[0] == "2026.06.05 03:00" and r[1] == "AUDNZD")
        r[17] = "REFUSE T0001; DIVERGE wait"
        tr = trades()
        if with_abort:
            a = dict(tr[0])
            a.update(event="ABORT", half="0", note="half 2 not opened; half 1 closed")
            tr.append(a)
        return self.run_check(rows, tr)

    def test_abort_logged_as_refuse_is_info(self):
        ok, out = self.abort_case(True)
        self.assertTrue(ok, out)
        self.assertIn("closed by ABORT; the decision row says REFUSE T0001", out)

    def test_refuse_with_an_open_trade_and_no_abort_fails(self):
        ok, out = self.abort_case(False)
        self.assertFalse(ok, out)
        self.assertIn("has no decision row", out)


if __name__ == "__main__":
    unittest.main()
