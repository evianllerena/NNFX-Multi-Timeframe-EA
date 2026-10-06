"""Tests for tools/check_master_test.py (Phase 6d demo master-switch check), including logs it must reject."""
import csv
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

import check_master_test as c  # noqa: E402

COLS = ("time,event,trade_id,half,symbol,dir,magic,ticket,lots,price,sl,tp,prev_sl,entry,atr_entry,atr,close,"
        "balance,risk_pct,tick_size,tick_value,planned_risk,target_risk,cap_atr,note").split(",")


def row(time, event, note="", **kw):
    r = {k: "0" for k in COLS}
    r.update(time=time, event=event, trade_id=kw.pop("tid", ""), symbol="EURUSD", note=note)
    for k, v in kw.items():
        r[k] = str(v)
    return r


def log_a():
    return [
        row("2026.10.06 19:00:01", "INFO", "orders allowed: DEMO"),
        row("2026.10.06 19:00:01", "GUARD", "TEST master switch: NNFX_MASTER = 1; chart GBPUSD opened (id 1) with template nnfx_master_b: applied; error 0"),
        row("2026.10.06 19:02:00", "OPEN", tid="T0001", half=1),
        row("2026.10.06 19:05:00", "GUARD", "TEST master switch: NNFX_MASTER = 0 (OFF)"),
        row("2026.10.06 19:06:00", "TRAIL", tid="T0001", half=2),
        row("2026.10.06 19:07:00", "SKIP", "blocked:master"),
        row("2026.10.06 19:10:00", "GUARD", "TEST master switch: NNFX_MASTER = 1 (ON)"),
        row("2026.10.06 19:11:00", "OPEN", tid="T0002", half=1),
    ]


def log_b():
    return [
        row("2026.10.06 19:00:05", "INFO", "orders allowed: DEMO"),
        row("2026.10.06 19:05:00", "OPEN", tid="T0001", half=1),           # same minute as OFF: allowed
        row("2026.10.06 19:06:00", "SKIP", "blocked:master"),
        row("2026.10.06 19:10:00", "SKIP", "blocked:master"),              # B saw ON one candle late: allowed
        row("2026.10.06 19:11:00", "OPEN", tid="T0002", half=1),
    ]


class TestCheckMasterTest(unittest.TestCase):
    def run_logs(self, a, b):
        paths = []
        for rows in (a, b):
            tmp = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, newline="", encoding="ascii")
            w = csv.DictWriter(tmp, fieldnames=COLS, lineterminator="\r\n")
            w.writeheader()
            w.writerows(rows)
            tmp.close()
            paths.append(tmp.name)
        buf = io.StringIO()
        try:
            with redirect_stdout(buf):
                ok = c.check(*paths)
        finally:
            for p in paths:
                os.remove(p)
        return ok, buf.getvalue()

    def test_good_logs_pass(self):
        ok, out = self.run_logs(log_a(), log_b())
        self.assertTrue(ok, out)

    def test_entry_while_off_fails(self):
        b = log_b() + [row("2026.10.06 19:08:00", "OPEN", tid="T0009", half=1)]
        ok, out = self.run_logs(log_a(), b)
        self.assertFalse(ok)
        self.assertIn("while the master switch was OFF", out)

    def test_b_never_blocked_fails(self):
        b = [r for r in log_b() if r["event"] != "SKIP"]
        ok, out = self.run_logs(log_a(), b)
        self.assertFalse(ok)
        self.assertIn("B: no SKIP blocked:master", out)

    def test_skip_outside_window_fails(self):
        b = log_b() + [row("2026.10.06 19:20:00", "SKIP", "blocked:master")]
        ok, out = self.run_logs(log_a(), b)
        self.assertFalse(ok)
        self.assertIn("outside the OFF window", out)

    def test_template_not_applied_fails(self):
        a = log_a()
        a[1]["note"] = a[1]["note"].replace("applied", "FAILED")
        ok, out = self.run_logs(a, log_b())
        self.assertFalse(ok)
        self.assertIn("did not open B's chart", out)

    def test_b_did_not_run_fails(self):
        b = [r for r in log_b() if r["event"] != "INFO"]
        ok, out = self.run_logs(log_a(), b)
        self.assertFalse(ok)
        self.assertIn("did it run?", out)


if __name__ == "__main__":
    unittest.main()
