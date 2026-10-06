"""Tests for tools/check_calendar.py (Phase 6e), including exports it must reject."""
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

import check_calendar as c  # noqa: E402

LIST = ("EVENT|USD|Non-Farm Payrolls|Nonfarm Payrolls|840030016\n"
        "EVENT|USD|interest rates|Fed Interest Rate Decision|840050014\n")
HEADER = "# NNFX news events, generated 2026.10.06 22:12 GMT, times in UTC (calendar time - server offset +3.00 h at export), x\n"


def rows():
    # UTC: NFP 08:30 New York = 13:30 UTC in winter (EST), 12:30 UTC in summer (EDT)
    return ["2026.01.09 13:30|USD|840030016|Nonfarm Payrolls|Non-Farm Payrolls",
            "2026.01.28 19:00|USD|840050014|Fed Interest Rate Decision|interest rates",   # 14:00 EST
            "2026.02.06 13:30|USD|840030016|Nonfarm Payrolls|Non-Farm Payrolls",
            "2026.03.06 13:30|USD|840030016|Nonfarm Payrolls|Non-Farm Payrolls",          # US DST starts 8 Mar
            "2026.03.18 18:00|USD|840050014|Fed Interest Rate Decision|interest rates",   # 14:00 EDT
            "2026.04.03 12:30|USD|840030016|Nonfarm Payrolls|Non-Farm Payrolls",
            "2026.05.08 12:30|USD|840030016|Nonfarm Payrolls|Non-Farm Payrolls",
            "2026.06.05 12:30|USD|840030016|Nonfarm Payrolls|Non-Farm Payrolls",
            "2026.07.02 12:30|USD|840030016|Nonfarm Payrolls|Non-Farm Payrolls",
            "2026.08.07 12:30|USD|840030016|Nonfarm Payrolls|Non-Farm Payrolls"]


SUMMARY = "".join("month 2026.%02d: 1 events, 0 errors\n" % m for m in range(1, 9))


class TestCheckCalendar(unittest.TestCase):
    def run_check(self, body_rows, summary=SUMMARY, header=HEADER, exceptions=()):
        d = tempfile.mkdtemp()
        ev, su, li = (os.path.join(d, x) for x in ("events.txt", "_summary.txt", "list.txt"))
        with open(ev, "w", encoding="ascii") as f:
            f.write(header + "time_utc|currency|event_id|name|vp\n" + "\n".join(body_rows) + "\n")
        with open(su, "w", encoding="ascii") as f:
            f.write(summary)
        with open(li, "w", encoding="ascii") as f:
            f.write(LIST)
        buf = io.StringIO()
        with redirect_stdout(buf):
            ok = c.check(ev, su, "2026.01", "2026.08", li, set(), set(exceptions))
        return ok, buf.getvalue()

    def test_good_export_passes(self):
        ok, out = self.run_check(rows())
        self.assertTrue(ok, out)
        self.assertIn("10 US releases checked against their New York clock time: 0 wrong", out)

    def test_server_time_instead_of_utc_fails(self):
        # the bug the first export had: every time shifted by a fixed +3 h (TODAY's server offset)
        shifted = []
        for r in rows():
            p = r.split("|")
            hh = int(p[0][11:13]) + 3
            shifted.append("%s %02d%s|%s" % (p[0][:10], hh, p[0][13:], "|".join(p[1:])))
        ok, out = self.run_check(shifted)
        self.assertFalse(ok)
        self.assertIn("time base: 2026.01.09 16:30 USD Nonfarm Payrolls", out)

    def test_named_exception_passes_and_is_reported(self):
        rs = rows()
        rs[1] = "2026.01.28 15:00|USD|840050014|Fed Interest Rate Decision|interest rates"   # 10:00 New York
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        ok, out = self.run_check(rs, exceptions={"2026.01.28|Fed Interest Rate Decision"})
        self.assertTrue(ok, out)
        self.assertIn("time base exception (named)", out)

    def test_missing_month_fails(self):
        rs = [r for r in rows() if not r.startswith("2026.04")]
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("month 2026.04: no events in the file", out)
        ok, out = self.run_check(rows(), summary=SUMMARY.replace("month 2026.05: 1 events, 0 errors\n", ""))
        self.assertFalse(ok)
        self.assertIn("month 2026.05: no summary line", out)

    def test_month_with_errors_fails(self):
        ok, out = self.run_check(rows(), summary=SUMMARY.replace("2026.06: 1 events, 0 errors", "2026.06: 1 events, 2 errors"))
        self.assertFalse(ok)
        self.assertIn("2 errors in the export", out)

    def test_duplicate_fails(self):
        rs = rows()
        rs.insert(1, rs[0])
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("duplicate event", out)

    def test_order_and_header(self):
        rs = rows()
        rs[0], rs[2] = rs[2], rs[0]
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("not in time order", out)
        ok, out = self.run_check(rows(), header="# NNFX news events, generated 2026.10.06 22:12 GMT\n")
        self.assertFalse(ok)
        self.assertIn("times in UTC", out)

    def test_vp_event_missing_in_a_year_fails(self):
        rs = [r for r in rows() if "Fed" not in r]
        ok, out = self.run_check(rs)
        self.assertFalse(ok)
        self.assertIn("USD|interest rates: none in 2026", out)


if __name__ == "__main__":
    unittest.main()
