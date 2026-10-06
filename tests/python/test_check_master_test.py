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
        row("2026.10.06 19:05:00", "GUARD", "blocks: master (was none)"),
        row("2026.10.06 19:06:00", "TRAIL", tid="T0001", half=2),
        row("2026.10.06 19:07:00", "SKIP", "blocked:master"),
        row("2026.10.06 19:10:00", "GUARD", "TEST master switch: NNFX_MASTER = 1 (ON)"),
        row("2026.10.06 19:10:00", "GUARD", "blocks: none (was master)"),
        row("2026.10.06 19:11:00", "OPEN", tid="T0002", half=1),
    ]


def log_b():
    return [
        row("2026.10.06 19:00:05", "INFO", "orders allowed: DEMO"),
        row("2026.10.06 19:05:00", "OPEN", tid="T0001", half=1),           # same minute as OFF: allowed
        row("2026.10.06 19:06:00", "GUARD", "blocks: master (was none)"),     # B saw OFF one candle late: allowed
        row("2026.10.06 19:06:00", "SKIP", "blocked:master"),
        row("2026.10.06 19:10:00", "SKIP", "blocked:master"),              # B saw ON one candle late: allowed
        row("2026.10.06 19:11:00", "GUARD", "blocks: none (was master)"),
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

    def test_b_never_saw_the_switch_fails(self):
        b = [r for r in log_b() if not r["note"].startswith("blocks:")]
        ok, out = self.run_logs(log_a(), b)
        self.assertFalse(ok)
        self.assertIn("B: no GUARD 'blocks: ...master' row", out)

    def test_b_in_a_trade_without_skips_passes(self):
        # B held a trade the whole time: no entry due, so no SKIP, but its guard saw the switch
        b = [r for r in log_b() if r["event"] != "SKIP"]
        ok, out = self.run_logs(log_a(), b)
        self.assertTrue(ok, out)

    def test_b_first_evaluation_inside_off_window_passes(self):
        # B started late: its very first evaluation already sees master OFF (run master_20261006_135454)
        b = [r for r in log_b() if r["note"] != "blocks: master (was none)"]
        b.insert(1, row("2026.10.06 19:08:01", "GUARD", "blocks: master (was -)"))
        ok, out = self.run_logs(log_a(), b)
        self.assertTrue(ok, out)

    def test_b_first_evaluation_after_on_fails(self):
        b = [r for r in log_b() if not r["note"].startswith("blocks:")]
        b.insert(1, row("2026.10.06 19:12:01", "GUARD", "blocks: none (was -)"))
        ok, out = self.run_logs(log_a(), b)
        self.assertFalse(ok)

    def test_b_never_saw_on_fails(self):
        b = [r for r in log_b() if r["note"] != "blocks: none (was master)"]
        ok, out = self.run_logs(log_a(), b)
        self.assertFalse(ok)
        self.assertIn("without master within 2 candles of ON", out)

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


def panel_rows():
    """Instance A's chart-button steps after the master switch is back ON."""
    return [
        # the test EA holds one trade at a time: T0001 and T0002 (log_a) closed before T0003
        row("2026.10.06 19:11:20", "SL", tid="T0001", half=2),
        row("2026.10.06 19:11:40", "SL", tid="T0002", half=2),
        row("2026.10.06 19:12:00", "OPEN", tid="T0003", half=1),
        row("2026.10.06 19:12:00", "OPEN", tid="T0003", half=2),
        row("2026.10.06 19:12:00", "STATE", "proc=...; state=TRADE|T0003|... / CONT|..."),
        row("2026.10.06 19:13:00", "GUARD", "instance switch OFF by the chart button"),
        row("2026.10.06 19:14:00", "TRAIL", tid="T0003", half=2),
        row("2026.10.06 19:15:00", "GUARD", "instance switch ON by the chart button"),
        row("2026.10.06 19:17:00", "GUARD", "drawdown reset requested by the chart button (confirmed): NNFX_DD_RESET = 1"),
        row("2026.10.06 19:18:00", "GUARD", "drawdown reset by hand (D6d-3): was not paused; peak 100000.00 -> 99990.00"),
        row("2026.10.06 19:19:00", "GUARD", "close-all by the chart button (confirmed): 1 trade(s) of this instance"),
        row("2026.10.06 19:19:00", "EXIT", "close-all button (confirmed)", tid="T0003"),
        row("2026.10.06 19:19:00", "CLOSE", tid="T0003", half=1),
        row("2026.10.06 19:19:00", "CLOSE", tid="T0003", half=2),
        row("2026.10.06 19:19:00", "STATE", "proc=...; state=CONT|EURUSD|1|0|0|1|2026.10.06 19:12"),
    ]


class TestCheckMasterPanel(unittest.TestCase):
    def run_panel(self, a_rows):
        paths = []
        for rows in (log_a() + a_rows, log_b()):
            tmp = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, newline="", encoding="ascii")
            w = csv.DictWriter(tmp, fieldnames=COLS, lineterminator="\r\n")
            w.writeheader()
            w.writerows(rows)
            tmp.close()
            paths.append(tmp.name)
        buf = io.StringIO()
        try:
            with redirect_stdout(buf):
                ok = c.check(paths[0], paths[1], panel=True)
        finally:
            for p in paths:
                os.remove(p)
        return ok, buf.getvalue()

    def test_panel_passes(self):
        ok, out = self.run_panel(panel_rows())
        self.assertTrue(ok, out)
        self.assertIn("close-all at 2026.10.06 19:19:00: trades open then ['T0003']", out)

    def test_entry_while_instance_off_fails(self):
        rs = panel_rows()
        rs.insert(6, row("2026.10.06 19:14:00", "OPEN", tid="T0004", half=1))   # after the OFF row
        ok, out = self.run_panel(rs)
        self.assertFalse(ok)
        self.assertIn("while the instance switch was OFF", out)

    def test_reset_not_logged_fails(self):
        rs = [r for r in panel_rows() if "D6d-3" not in r["note"]]
        ok, out = self.run_panel(rs)
        self.assertFalse(ok)
        self.assertIn("no 'drawdown reset by hand (D6d-3)' row", out)

    def test_close_all_leaves_a_trade_fails(self):
        rs = [r for r in panel_rows() if r["event"] != "EXIT"]
        rs[-1] = row("2026.10.06 19:19:00", "STATE", "proc=...; state=TRADE|T0003|... / CONT|...")
        ok, out = self.run_panel(rs)
        self.assertFalse(ok)
        self.assertIn("without an EXIT row", out)
        self.assertIn("still open after close-all", out)

    def test_new_trade_after_close_all_passes(self):
        rs = panel_rows() + [row("2026.10.06 19:20:00", "OPEN", tid="T0004", half=1),
                             row("2026.10.06 19:20:00", "STATE", "proc=...; state=TRADE|T0004|... / CONT|...")]
        ok, out = self.run_panel(rs)
        self.assertTrue(ok, out)

    def test_reset_applied_by_the_other_instance_passes(self):
        # the reset is account-wide: B may reach its next candle first (run master_20261006_130813)
        rs = [r for r in panel_rows() if "D6d-3" not in r["note"]]
        paths = []
        b = log_b() + [row("2026.10.06 19:18:00", "GUARD", "drawdown reset by hand (D6d-3): was not paused")]
        for rows in (log_a() + rs, b):
            tmp = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, newline="", encoding="ascii")
            w = csv.DictWriter(tmp, fieldnames=COLS, lineterminator="\r\n")
            w.writeheader()
            w.writerows(rows)
            tmp.close()
            paths.append(tmp.name)
        buf = io.StringIO()
        try:
            with redirect_stdout(buf):
                ok = c.check(paths[0], paths[1], panel=True)
        finally:
            for p in paths:
                os.remove(p)
        self.assertTrue(ok, buf.getvalue())
        self.assertIn("(B)", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
