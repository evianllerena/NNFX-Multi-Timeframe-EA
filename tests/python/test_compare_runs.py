"""Tests for tools/compare_runs.py (Phase 6c restart comparison)."""
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

import compare_runs  # noqa: E402

COLS = ("time,event,trade_id,half,symbol,dir,magic,ticket,lots,price,sl,tp,prev_sl,entry,atr_entry,atr,close,"
        "balance,risk_pct,tick_size,tick_value,planned_risk,target_risk,cap_atr,note").split(",")
S1 = "state=TRADE|T0001|EURUSD|1|11|12|1|1|0.33|1.1|1.1|0.002|-1|1.097|0|0 / CONT|EURUSD|1|1|0|0|2026.06.02 10:00"
S2 = "state=TRADE|T0001|EURUSD|1|11|12|0|1|0.33|1.1|1.1|0.002|-1|1.1|1|0 / CONT|EURUSD|1|1|0|0|2026.06.02 10:00"


def row(time, event, note="", **kw):
    r = {c: "0" for c in COLS}
    r.update(time=time, event=event, trade_id=kw.pop("tid", ""), symbol="EURUSD", note=note)
    for k, v in kw.items():
        r[k] = str(v)
    return [r[c] for c in COLS]


def base_rows():
    return [
        row("2026.06.02 10:00:05", "OPEN", tid="T0001", half=1, sl="1.097", ticket=11),
        row("2026.06.02 10:00:05", "OPEN", tid="T0001", half=2, sl="1.097", ticket=12),
        row("2026.06.02 11:00:00", "STATE", S1),
        row("2026.06.02 11:30:20", "TP1", tid="T0001", half=1, price="1.102", ticket=11),
        row("2026.06.02 11:30:20", "BE", tid="T0001", half=2, sl="1.1", note="via=tick", ticket=12),
        row("2026.06.02 12:00:00", "STATE", S2),
        row("2026.06.02 13:20:00", "SL", tid="T0001", half=2, price="1.1", ticket=12),
    ]


def restart_rows():
    rs = base_rows()
    rs.insert(3, row("2026.06.02 11:00:00", "PRESTOP", S1))
    rs.insert(4, row("2026.06.02 11:00:00", "REBUILD", "match=yes; " + S1 + "; notes=state file: present"))
    rs.insert(5, row("2026.06.02 11:00:00", "INFO", "memory rebuilt: 1 open trades imported"))
    return rs


def write(rows, path):
    with open(path, "w", encoding="ascii", newline="") as f:
        w = csv.writer(f, lineterminator="\r\n")
        w.writerow(COLS)
        w.writerows(rows)


def run(fn, *paths, **kw):
    buf = io.StringIO()
    with redirect_stdout(buf):
        ok = fn(*paths, **kw)
    return ok, buf.getvalue()


class TestCompareRuns(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.a = os.path.join(self.tmp.name, "base.csv")
        self.b = os.path.join(self.tmp.name, "restart.csv")

    def tearDown(self):
        self.tmp.cleanup()

    def cmp(self, base, restart, frm="2026.06.02 11:00"):
        write(base, self.a)
        write(restart, self.b)
        return run(compare_runs.compare, self.a, self.b, frm)

    def test_identical_after_restart(self):
        ok, out = self.cmp(base_rows(), restart_rows())
        self.assertTrue(ok, out)
        self.assertIn("IDENTICAL (0 differing rows, 5 compared)", out)

    def test_every_column_is_compared(self):
        for col in COLS:
            if col in ("time", "event"):
                continue
            with self.subTest(col=col):
                rs = restart_rows()
                i = COLS.index(col)
                rs[-1][i] = rs[-1][i] + "9"
                ok, out = self.cmp(base_rows(), rs)
                self.assertFalse(ok, out)
                self.assertIn("differs in " + col, out)

    def test_missing_and_extra_rows(self):
        rs = restart_rows()
        rs.pop()
        ok, out = self.cmp(base_rows(), rs)
        self.assertFalse(ok)
        self.assertIn("presence", out)
        ok, out = self.cmp(base_rows(), restart_rows() + [row("2026.06.02 14:00:00", "STATE", S2)])
        self.assertFalse(ok)

    def test_rows_before_from_are_ignored(self):
        rs = restart_rows()
        rs[0][COLS.index("sl")] = "1.0971"
        ok, out = self.cmp(base_rows(), rs)
        self.assertTrue(ok, out)

    def test_rebuilds_match(self):
        write(restart_rows(), self.a)
        ok, out = run(compare_runs.rebuilds, self.a)
        self.assertTrue(ok, out)
        self.assertIn("REBUILDS MATCH (1 of 1)", out)

    def test_rebuild_differs_even_if_ea_says_match(self):
        rs = restart_rows()
        rs[4][COLS.index("note")] = "match=yes; " + S2 + "; notes=x"
        write(rs, self.a)
        ok, out = run(compare_runs.rebuilds, self.a)
        self.assertFalse(ok, out)
        self.assertIn("differs", out)

    def test_rebuilds_minimum(self):
        write(base_rows(), self.a)
        ok, out = run(compare_runs.rebuilds, self.a, 1)
        self.assertFalse(ok)
        self.assertIn("only 0 restarts", out)


if __name__ == "__main__":
    unittest.main()
