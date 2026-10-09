"""Tests for tools/check_news_inputs.py (Phase 6f): a decision log whose news inputs come from the reference passes;
each corruption (a dropped N1 reason, a wrong first-close flag, an ENTER on a blocked row, an X5 exit without the
flag) fails."""
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
sys.path.insert(0, HERE)

import check_news_inputs as c  # noqa: E402
from nnfx_ref import guard, news  # noqa: E402

HEADER = "time,symbol,tf,o,h,l,c,atr,base,c1,c2,ex,vol,ind_ok,block,news,events,action,note".split(",")
EVENTS = ["# NNFX news events, generated 2026.10.06 12:00 GMT, times in UTC",
          "time_utc|currency|event_id|name|vp",
          "2026.06.05 12:30|USD|840030016|Nonfarm Payrolls|Non-Farm Payrolls",
          "2026.06.03 01:30|AUD|36010003|GDP q/q|GDP"]


def build():
    """EURUSD and AUDCAD, H1, Mon 2026.06.01 00:00 .. Fri 2026.06.05 23:00, inputs from the reference."""
    b = guard.Broker("t", 2, "US")
    ev = news.load_export(EVENTS, b)
    rows = []
    for sym in ("EURUSD", "AUDCAD"):
        prev = None
        for k in range(5 * 24):
            t0 = datetime(2026, 6, 1) + timedelta(hours=k)
            t = t0 + timedelta(hours=1)
            prev = prev or t0
            why = ";".join(news.blocked(sym, t, ev, b))
            flag = news.first_close(sym, t, prev, ev, b)
            events = "SKIP:E1:1" if why and k % 7 == 0 else "-"
            rows.append([t0.strftime("%Y.%m.%d %H:%M"), sym, "H1", "1", "1", "1", "1", "0.001", "1", "0", "0", "0",
                         "1", "1", ("rollover;" if k % 24 == 23 else "") + (why or ("-" if k % 24 != 23 else "")),
                         "1" if flag else "0", events, "-", "-"])
            if rows[-1][14] == "rollover;":
                rows[-1][14] = "rollover"
            prev = t
    return rows


class TestCheckNewsInputs(unittest.TestCase):
    def run_check(self, rows, require_x5=False):
        d = tempfile.mkdtemp()
        dp, ep = os.path.join(d, "dec.csv"), os.path.join(d, "events.txt")
        with open(dp, "w", encoding="ascii", newline="") as f:
            w = csv.writer(f, lineterminator="\r\n")
            w.writerow(HEADER)
            w.writerows(rows)
        with open(ep, "w", encoding="ascii", newline="") as f:
            f.write("\r\n".join(EVENTS) + "\r\n")
        buf = io.StringIO()
        with redirect_stdout(buf):
            ok = c.check(dp, ep, 60, require_x5=require_x5)
        return ok, buf.getvalue()

    def test_reference_inputs_pass(self):
        rows = build()
        ok, out = self.run_check(rows)
        self.assertTrue(ok, out)
        self.assertIn("with news = 1", out)

    def test_dropped_n1_reason(self):
        rows = build()
        r = next(r for r in rows if r[14].startswith("N1 USD") or ";N1 USD" in r[14])
        r[14] = "-"
        ok, out = self.run_check(rows)
        self.assertFalse(ok)
        self.assertIn("N1/N2 in the block", out)

    def test_wrong_first_close_flag(self):
        rows = build()
        r = next(r for r in rows if r[15] == "1")
        r[15] = "0"
        ok, out = self.run_check(rows)
        self.assertFalse(ok)
        self.assertIn("news flag 0, the reference says 1", out)

    def test_enter_on_a_news_blocked_row(self):
        rows = build()
        r = next(r for r in rows if "N1" in r[14])
        r[16] = "ENTER:E1:1"
        ok, out = self.run_check(rows)
        self.assertFalse(ok)
        self.assertIn("ENTER on a row blocked by news", out)

    def test_x5_exit_without_the_flag(self):
        rows = build()
        r = next(r for r in rows if r[15] == "0" and r[13] == "1")
        r[16] = "EXIT:X5:1"
        ok, out = self.run_check(rows)
        self.assertFalse(ok)
        self.assertIn("X5 exit on a row with news = 0", out)

    def test_require_x5_coverage(self):
        ok, out = self.run_check(build(), require_x5=True)
        self.assertFalse(ok)
        self.assertIn("coverage: no X5 exit", out)


if __name__ == "__main__":
    unittest.main()
