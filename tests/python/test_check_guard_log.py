"""Tests for tools/check_guard_log.py (Phase 6d), including logs it must reject."""
import csv
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

import check_guard_log as c  # noqa: E402
from nnfx_ref import guard as g  # noqa: E402

COLS = ("time,event,trade_id,half,symbol,dir,magic,ticket,lots,price,sl,tp,prev_sl,entry,atr_entry,atr,close,"
        "balance,risk_pct,tick_size,tick_value,planned_risk,target_risk,cap_atr,note").split(",")
MQ = g.Broker("MQDEMO", 2, "US")   # boundary 00:00 server -> rollover [23:45, 01:00)


def row(time, event, note="", **kw):
    r = {k: "0" for k in COLS}
    r.update(time=time, event=event, trade_id=kw.pop("tid", ""), symbol="EURUSD", note=note)
    for k, v in kw.items():
        r[k] = str(v)
    return r


def good():
    return [
        row("2026.06.02 10:00:01", "OPEN", tid="T0001", half=1),
        row("2026.06.02 10:00:01", "OPEN", tid="T0001", half=2),
        row("2026.06.03 00:00:02", "SKIP", "blocked:rollover"),
        row("2026.06.03 00:00:02", "TRAIL", tid="T0001", half=2),           # managed while blocked
        row("2026.06.05 21:00:01", "SKIP", "blocked:weekend"),               # Fri 21:00, 4 h before Sat 00:00
        row("2026.06.05 23:50:00", "SKIP", "blocked:rollover;weekend"),
        row("2026.06.08 01:00:00", "OPEN", tid="T0002", half=1),
    ]


class TestCheckGuardLog(unittest.TestCase):
    def run_rows(self, rows, **kw):
        tmp = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, newline="", encoding="ascii")
        w = csv.DictWriter(tmp, fieldnames=COLS, lineterminator="\r\n")
        w.writeheader()
        w.writerows(rows)
        tmp.close()
        buf = io.StringIO()
        try:
            with redirect_stdout(buf):
                ok = c.check(tmp.name, MQ, kw.get("weekend", 4.0), kw.get("min_skips", 1), kw.get("managed", True))
        finally:
            os.remove(tmp.name)
        return ok, buf.getvalue()

    def test_good_log_passes(self):
        ok, out = self.run_rows(good())
        self.assertTrue(ok, out)
        self.assertIn("SKIP 3 (rollover 2, weekend 2)", out)

    def test_open_inside_rollover_fails(self):
        rs = good() + [row("2026.06.09 00:30:00", "OPEN", tid="T0003", half=1)]
        ok, out = self.run_rows(rs)
        self.assertFalse(ok)
        self.assertIn("OPEN T0003 inside the rollover window", out)

    def test_open_inside_weekend_fails(self):
        rs = good() + [row("2026.06.12 22:00:00", "OPEN", tid="T0003", half=1)]
        ok, out = self.run_rows(rs)
        self.assertFalse(ok)
        self.assertIn("inside the weekend block", out)

    def test_skip_outside_window_fails(self):
        rs = good() + [row("2026.06.09 12:00:00", "SKIP", "blocked:rollover")]
        ok, out = self.run_rows(rs)
        self.assertFalse(ok)
        self.assertIn("rollover window is off", out)

    def test_missing_rollover_reason_fails(self):
        rs = good() + [row("2026.06.09 00:10:00", "SKIP", "blocked:spread")]
        ok, out = self.run_rows(rs)
        self.assertFalse(ok)
        self.assertIn("rollover window is on", out)

    def test_window_end_is_exclusive(self):
        ok, out = self.run_rows(good() + [row("2026.06.09 01:00:00", "OPEN", tid="T0003", half=1)])
        self.assertTrue(ok, out)
        ok, out = self.run_rows(good() + [row("2026.06.09 00:59:59", "OPEN", tid="T0003", half=1)])
        self.assertFalse(ok)

    def test_management_required(self):
        rs = [r for r in good() if r["event"] != "TRAIL"]
        ok, out = self.run_rows(rs)
        self.assertFalse(ok)
        self.assertIn("no management row inside a rollover window", out)

    def test_min_skips(self):
        ok, out = self.run_rows(good(), min_skips=3)
        self.assertFalse(ok)
        self.assertIn("only 2 SKIP rows for rollover", out)


if __name__ == "__main__":
    unittest.main()
