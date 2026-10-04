"""Tests for tools/check_trades.py (Phase 6b, SPEC Check 1c).

A small trade log is built by hand with known-correct trades (stop-out, TP1 + breakeven + trail,
runner cap, signal exit, a test stopless position closed with an alarm, a retry). It must pass;
each corruption must fail, except the ones that are information only (a gap through the stop,
float noise in the risk)."""
import copy
import csv
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import check_trades  # noqa: E402

COLS = ("time,event,trade_id,half,symbol,dir,magic,ticket,lots,price,sl,tp,prev_sl,entry,atr_entry,atr,close,"
        "balance,risk_pct,tick_size,tick_value,planned_risk,target_risk,cap_atr,note").split(",")
T = 0.00001


def row(time, event, tid="", half=0, d=0, **kw):
    r = {c: "" for c in COLS}
    r.update(time=time, event=event, trade_id=tid, half=str(half), symbol="EURUSD", dir=str(d), magic="26999",
             ticket=str(kw.pop("ticket", 0)))
    for k, v in kw.items():
        r[k] = repr(v) if isinstance(v, float) else str(v)
    return r


def opened(time, tid, d, entry, lots, sl, tp1, tp2=0.0, cap=-1.0, ticket=1, balance=100000.0):
    common = dict(lots=lots, price=entry, entry=entry, atr_entry=0.002, balance=balance, risk_pct=2.0, tick_size=T,
                  tick_value=1.0, target_risk=balance * 0.02, cap_atr=cap)
    return [row(time, "OPEN", tid, 1, d, ticket=ticket, sl=sl, tp=tp1, **common),
            row(time, "OPEN", tid, 2, d, ticket=ticket + 1, sl=sl, tp=tp2, **common)]


def good_rows():
    rs = []
    # T0001 long: TP1 -> breakeven at once -> trail on -> trail -> stopped at the trail
    rs += opened("2026.06.02 10:00:00", "T0001", 1, 1.10000, 3.33, 1.09700, 1.10200, ticket=11)
    rs.append(row("2026.06.02 13:00:00", "TP1", "T0001", 1, 1, ticket=11, lots=3.33, price=1.10200, entry=1.10000, tick_size=T))
    rs.append(row("2026.06.02 13:00:00", "BE", "T0001", 2, 1, ticket=12, lots=3.33, sl=1.10000, prev_sl=1.09700,
                  entry=1.10000, atr_entry=0.002, tick_size=T))
    rs.append(row("2026.06.02 16:00:00", "TRAILON", "T0001", 2, 1, ticket=12, sl=1.10000, entry=1.10000, atr_entry=0.002,
                  atr=0.002, close=1.10400, tick_size=T))
    rs.append(row("2026.06.02 17:00:00", "TRAIL", "T0001", 2, 1, ticket=12, lots=3.33, sl=1.10200, prev_sl=1.10000,
                  entry=1.10000, atr_entry=0.002, atr=0.002, close=1.10500, tick_size=T))
    rs.append(row("2026.06.02 19:00:00", "SL", "T0001", 2, 1, ticket=12, lots=3.33, price=1.10200, entry=1.10000, tick_size=T))
    # T0002 short: stopped out on both halves
    rs += opened("2026.06.03 10:00:00", "T0002", -1, 1.10000, 3.33, 1.10300, 1.09800, ticket=21)
    rs.append(row("2026.06.03 12:00:00", "SL", "T0002", 1, -1, ticket=21, lots=3.33, price=1.10300, entry=1.10000, tick_size=T))
    rs.append(row("2026.06.03 12:00:00", "SL", "T0002", 2, -1, ticket=22, lots=3.33, price=1.10300, entry=1.10000, tick_size=T))
    # T0003 long with the runner cap at 2 x ATR: TP1, breakeven, TP2; one retry found the position already there
    rs.append(row("2026.06.04 10:00:00", "RETRY", "T0003", note="half 1: position already exists (reply lost?), not sent again"))
    rs += opened("2026.06.04 10:00:00", "T0003", 1, 1.10000, 3.33, 1.09700, 1.10200, tp2=1.10400, cap=2.0, ticket=31)
    rs.append(row("2026.06.04 11:00:00", "TP1", "T0003", 1, 1, ticket=31, lots=3.33, price=1.10200, entry=1.10000, tick_size=T))
    rs.append(row("2026.06.04 11:00:00", "BE", "T0003", 2, 1, ticket=32, lots=3.33, sl=1.10000, prev_sl=1.09700,
                  entry=1.10000, atr_entry=0.002, tick_size=T))
    rs.append(row("2026.06.04 14:00:00", "TP2", "T0003", 2, 1, ticket=32, lots=3.33, price=1.10400, entry=1.10000, tick_size=T))
    # T0004 short: scripted signal exit
    rs += opened("2026.06.05 10:00:00", "T0004", -1, 1.10000, 3.33, 1.10300, 1.09800, ticket=41)
    rs.append(row("2026.06.05 18:00:00", "EXIT", "T0004", note="scripted signal exit"))
    rs.append(row("2026.06.05 18:00:00", "CLOSE", "T0004", 1, -1, ticket=41, lots=3.33, price=1.09950, entry=1.10000, tick_size=T))
    rs.append(row("2026.06.05 18:00:00", "CLOSE", "T0004", 2, -1, ticket=42, lots=3.33, price=1.09950, entry=1.10000, tick_size=T))
    # T0005 ABORT: half 1 opened, half 2 failed, half 1 closed (G1_phase6b_1 F1)
    rs.append(opened("2026.06.06 10:00:00", "T0005", 1, 1.10000, 3.33, 1.09700, 1.10200, ticket=51)[0])
    rs.append(row("2026.06.06 10:00:00", "CLOSE", "T0005", 1, 1, ticket=51, lots=3.33, price=1.09999, tick_size=T,
                  note="closed by ABORT"))
    rs.append(row("2026.06.06 10:00:00", "ABORT", "T0005", ticket=51, note="half 2 not opened; half 1 closed"))
    # T0006 REFUSE: nothing sent
    rs.append(row("2026.06.07 10:00:00", "REFUSE", "T0006", note="not enough free margin: needs 3300.00, free 0.00 (OD-5)"))
    # T0007 MODIFY: SL/TP re-set from the fill (OD-14); the OPEN row holds the stop planned before the fill
    o = opened("2026.06.08 10:00:00", "T0007", 1, 1.10000, 3.33, 1.09720, 1.10220, ticket=71)
    rs += o
    for h, tp in ((1, 1.10200), (2, 0.0)):
        m = dict(o[h - 1])
        m.update(event="MODIFY", sl="1.097", tp=repr(tp), prev_sl="1.0972", note="SL/TP re-set from the fill price (OD-14)")
        rs.append(m)
    # test-only stopless position, closed at once with an alarm
    rs.append(row("2026.06.01 01:00:00", "TESTSTOPLESS", "TS01", ticket=99, note="TEST: position opened without a stop on purpose"))
    rs.append(row("2026.06.01 01:00:00", "ALARM", "", ticket=99, note="missing stop on our position 99: closed at once"))
    return rs


def run(rows, **kw):
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "OrderTest_EURUSD_tester.csv")
        with open(path, "w", encoding="ascii", newline="") as f:
            w = csv.DictWriter(f, fieldnames=COLS, lineterminator="\r\n")
            w.writeheader()
            w.writerows(rows)
        buf = io.StringIO()
        with redirect_stdout(buf):
            ok = check_trades.check(path, **kw)
        return ok, buf.getvalue()


def find(rows, event, tid, half=None):
    for r in rows:
        if r["event"] == event and r["trade_id"] == tid and (half is None or r["half"] == str(half)):
            return r
    raise KeyError((event, tid, half))


class TestCheckTrades(unittest.TestCase):
    def test_good_log_passes(self):
        ok, out = run(good_rows(), min_trades=4,
                      require=("SL", "TP1", "BE", "TRAILON", "TRAIL", "TP2", "EXIT", "RETRY", "TESTSTOPLESS"))
        self.assertTrue(ok, out)
        self.assertIn("PASS (0 failures)", out)

    def corrupt(self, change, expect):
        rows = copy.deepcopy(good_rows())
        change(rows)
        ok, out = run(rows)
        self.assertFalse(ok, out)
        self.assertIn(expect, out)

    def test_no_stop_on_first_record(self):
        self.corrupt(lambda rs: find(rs, "OPEN", "T0002", 2).update(sl="0"), "no stop at its first record")

    def test_halves_unequal(self):
        self.corrupt(lambda rs: find(rs, "OPEN", "T0002", 2).update(lots="3.34"), "halves not equal")

    def test_risk_one_lot_step_above_target(self):
        # G1_phase6a_1 verdict note 1: +1 lot step (0.01 on each half) -> 3.34 x 300 x 2 = 2004 > 2000
        def change(rs):
            find(rs, "OPEN", "T0002", 1).update(lots="3.34")
            find(rs, "OPEN", "T0002", 2).update(lots="3.34")
        self.corrupt(change, "planned risk")

    def test_risk_just_above_target_fails(self):
        # planned 1998.0 vs a target 0.01 lower: far below one lot step (6.00 here), far above float noise.
        # "No tolerance above target" (F4) means even this small real excess fails.
        rows = good_rows()
        bal = repr((3.33 * 300 * 2 - 0.01) / 0.02)
        for h in (1, 2):
            find(rows, "OPEN", "T0002", h).update(balance=bal)
        ok, out = run(rows)
        self.assertFalse(ok, out)
        self.assertIn("planned risk", out)

    def test_risk_float_noise_passes(self):
        # planned 1998.0 vs a target 5e-10 lower: float noise only, inside RISK_BOUND (1e-6)
        rows = good_rows()
        bal = repr((3.33 * 300 * 2 - 5e-10) / 0.02)
        for h in (1, 2):
            find(rows, "OPEN", "T0002", h).update(balance=bal)
        ok, out = run(rows)
        self.assertTrue(ok, out)

    def test_stop_wider_than_sized(self):
        self.corrupt(lambda rs: [find(rs, "OPEN", "T0002", h).update(sl="1.10301") for h in (1, 2)],
                     "stop wider than 1.5 x ATR")

    def test_tp1_two_ticks_off(self):
        self.corrupt(lambda rs: find(rs, "OPEN", "T0002", 1).update(tp="1.09798"), "TP1 1.09798 not within one tick")

    def test_cap_target_wrong(self):
        self.corrupt(lambda rs: find(rs, "OPEN", "T0003", 2).update(tp="1.10500"), "runner cap TP")

    def test_target_on_half2_with_cap_off(self):
        self.corrupt(lambda rs: find(rs, "OPEN", "T0002", 2).update(tp="1.09600"), "runner cap is off")

    def test_breakeven_not_at_entry(self):
        self.corrupt(lambda rs: find(rs, "BE", "T0001").update(sl="1.10005"), "is not half 2's entry")

    def test_breakeven_late(self):
        self.corrupt(lambda rs: find(rs, "BE", "T0001").update(time="2026.06.02 14:00:00"), "not at once")

    def test_trail_backwards(self):
        self.corrupt(lambda rs: find(rs, "TRAIL", "T0001").update(sl="1.09990", close="1.10290"), "backwards")

    def test_trail_on_too_early(self):
        self.corrupt(lambda rs: find(rs, "TRAILON", "T0001").update(close="1.10390"), "less than 2 x entry ATR")

    def test_trail_wrong_distance(self):
        self.corrupt(lambda rs: find(rs, "TRAIL", "T0001").update(sl="1.10250"), "TRAIL stop")

    def test_duplicate_half(self):
        def change(rs):
            rs.insert(rs.index(find(rs, "OPEN", "T0002", 2)), copy.deepcopy(find(rs, "OPEN", "T0002", 2)))
        self.corrupt(change, "duplicate")

    def test_stopless_without_alarm(self):
        self.corrupt(lambda rs: rs.remove(next(r for r in rs if r["event"] == "ALARM")), "never closed with an ALARM")

    def test_alarm_on_our_position(self):
        self.corrupt(lambda rs: rs.append(row("2026.06.06 10:00:00", "ALARM", "", ticket=55,
                                              note="missing stop on our position 55: closed at once")),
                     "ALARM on our own position")

    def test_abort_without_half1_close(self):
        self.corrupt(lambda rs: rs.remove(find(rs, "CLOSE", "T0005", 1)), "no close of half 1")

    def test_abort_close_failed(self):
        self.corrupt(lambda rs: find(rs, "ABORT", "T0005").update(note="half 2 not opened; HALF 1 CLOSE FAILED"),
                     "lone half left")

    def test_refuse_then_order(self):
        self.corrupt(lambda rs: rs.append(opened("2026.06.07 10:00:01", "T0006", 1, 1.1, 3.33, 1.097, 1.102, ticket=61)[0]),
                     "REFUSE row but an order was opened")

    def test_modify_to_wrong_stop(self):
        self.corrupt(lambda rs: [r.update(sl="1.0969") for r in rs if r["event"] == "MODIFY" and r["trade_id"] == "T0007"],
                     "T0007: half 1 SL")

    def test_require_note(self):
        ok, out = run(good_rows(), require_notes=("free margin",))
        self.assertTrue(ok, out)
        ok, out = run(good_rows(), require_notes=("minimum distance",))
        self.assertFalse(ok)
        self.assertIn("coverage: no row with 'minimum distance'", out)

    def test_gap_loss_is_information_only(self):
        rows = good_rows()
        for h in (1, 2):
            find(rows, "SL", "T0002", h).update(price="1.10350")
        ok, out = run(rows)
        self.assertTrue(ok, out)
        self.assertIn("INFO", out)
        self.assertIn("gap through the stop", out)

    def test_coverage_and_minimum(self):
        ok, out = run(good_rows(), min_trades=20)
        self.assertFalse(ok)
        self.assertIn("only 6 trades", out)
        rows = [r for r in good_rows() if r["event"] != "TP2"]
        ok, out = run(rows, require=("TP2",))
        self.assertFalse(ok)
        self.assertIn("coverage: no TP2", out)


if __name__ == "__main__":
    unittest.main()
