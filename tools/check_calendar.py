"""Calendar export check (Phase 6e; docs/PLAN_PHASE6.md section 6, tools/check_calendar.py).

Over an event file written by NNFX_CalendarExport (mode "export") and its _summary.txt:
  - months:      every month from --from to --to has a "month YYYY.MM: n events, 0 errors" line in the summary, and
                 at least one event in the file (each month has several of VP's events; an empty month means the
                 export lost it)
  - duplicates:  no event twice (same currency, event id and time)
  - VP's list:   every entry of the approved list (news/news_events.txt) appears at least once in each calendar
                 year of the range, unless named with --absent "CUR|VP item" (reported, never silent)
  - time base:   the export is in UTC (the calendar gives history in TODAY's server offset; run
                 calendar_export_20261006_181154, kept in checks/invalid). Every US release with a fixed New York clock time
                 is converted UTC -> New York and must show it: Nonfarm Payrolls 08:30, CPI m/m 08:30, Fed Interest
                 Rate Decision 14:00. Releases that really moved (emergency cuts, a rescheduled report) are named with
                 --exception "YYYY.MM.DD|event name" and reported, never silent.
  - format:      every row has 5 fields, a time "YYYY.MM.DD HH:MM", rows in time order, a "generated ... GMT" header

Usage:  python tools/check_calendar.py EVENTS.txt _summary.txt --from 2019.01 --to 2026.09 --list news/news_events.txt
                                       [--absent "NZD|GDT"] [--exception "2020.03.03|Fed Interest Rate Decision"] ...
Exit code 0 = PASS.
"""
import argparse
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "python"))
from nnfx_ref import guard as g  # noqa: E402
from nnfx_ref import news as n  # noqa: E402

# US releases with a fixed New York clock time (published release schedules)
NY_TIMES = {
    ("USD", "Nonfarm Payrolls"): "08:30",
    ("USD", "CPI m/m"): "08:30",
    ("USD", "Fed Interest Rate Decision"): "14:00",
}


def ny_time(u):
    """UTC -> New York wall clock (US daylight saving)."""
    s, e = g.us_dst_dates(u.year)
    # New York local date/time: EDT (UTC-4) from 2nd Sunday March 07:00 UTC to 1st Sunday November 06:00 UTC
    edt = datetime(s.year, s.month, s.day, 7) <= u < datetime(e.year, e.month, e.day, 6)
    return u - timedelta(hours=4 if edt else 5)


def months_between(a, b):
    y, m = int(a[:4]), int(a[5:7])
    out = []
    while (y, m) <= (int(b[:4]), int(b[5:7])):
        out.append("%04d.%02d" % (y, m))
        m += 1
        if m == 13:
            y, m = y + 1, 1
    return out


def check(events_path, summary_path, frm, to, list_path, absent=(), exceptions=()):
    fails, info = [], []
    with open(events_path, encoding="latin-1") as f:
        lines = [ln.rstrip("\r\n") for ln in f]
    if not lines or "generated" not in lines[0] or "GMT" not in lines[0] or "times in UTC" not in lines[0]:
        fails.append("no '# ... generated ... GMT, times in UTC ...' header line")
    rows = []
    for i, ln in enumerate(lines):
        if ln.startswith("#") or ln.startswith("time_utc|") or not ln.strip():
            continue
        p = ln.split("|")
        if len(p) != 5:
            fails.append("line %d: %d fields, need 5: %s" % (i + 1, len(p), ln))
            continue
        try:
            t = n.parse_time(p[0])
        except ValueError:
            fails.append("line %d: bad time %r" % (i + 1, p[0]))
            continue
        rows.append((t, p[1], p[2], p[3], p[4]))
    for a, b in zip(rows, rows[1:]):
        if b[0] < a[0]:
            fails.append("not in time order at %s" % n.fmt_time(b[0]))
            break
    # duplicates
    seen = set()
    for r in rows:
        k = (r[1], r[2], r[0])
        if k in seen:
            fails.append("duplicate event %s %s %s %s" % (n.fmt_time(r[0]), r[1], r[2], r[3]))
        seen.add(k)
    # months (summary lines and events)
    months = months_between(frm, to)
    with open(summary_path, encoding="latin-1") as f:
        summ = f.read()
    per_month = defaultdict(int)
    for r in rows:
        per_month[n.fmt_time(r[0])[:7]] += 1
    for m in months:
        mm = re.search(r"^month %s: (\d+) events, (\d+) errors" % re.escape(m), summ, re.M)
        if not mm:
            fails.append("month %s: no summary line" % m)
        elif int(mm.group(2)) != 0:
            fails.append("month %s: %s errors in the export" % (m, mm.group(2)))
        if per_month[m] == 0:
            fails.append("month %s: no events in the file" % m)
    outside = [r for r in rows if n.fmt_time(r[0])[:7] not in months]
    if outside:
        fails.append("%d events outside %s..%s (first %s)" % (len(outside), frm, to, n.fmt_time(outside[0][0])))
    # VP's list, every calendar year in the range
    with open(list_path, encoding="ascii") as f:
        entries = n.load_entries(f)
    years = sorted({m[:4] for m in months})
    for e in entries:
        tag = "%s|%s" % (e.currency, e.vp)
        for y in years:
            hit = any(r[1] == e.currency and r[4] == e.vp and n.fmt_time(r[0])[:4] == y for r in rows)
            if not hit:
                if tag in absent:
                    info.append("%s: none in %s (listed as absent)" % (tag, y))
                else:
                    fails.append("%s: none in %s" % (tag, y))
    # time base
    checked, wrong, excused = 0, [], []
    for r in rows:
        want = NY_TIMES.get((r[1], r[3]))
        if not want:
            continue
        checked += 1
        local = ny_time(r[0])
        got = local.strftime("%H:%M")
        if got != want:
            line = "%s %s %s: New York %s, expected %s" % (n.fmt_time(r[0]), r[1], r[3], local.strftime("%Y.%m.%d %H:%M"), want)
            if "%s|%s" % (local.strftime("%Y.%m.%d"), r[3]) in exceptions:
                excused.append(line)
            else:
                wrong.append(line)
    for x in excused:
        info.append("time base exception (named): " + x)
    print("%s: %d events, %d months (%s..%s), %d VP list entries, %d years" %
          (os.path.basename(events_path), len(rows), len(months), frm, to, len(entries), len(years)))
    print("time base: %d US releases checked against their New York clock time: %d wrong, %d named exceptions"
          % (checked, len(wrong), len(excused)))
    if checked < 10:
        fails.append("only %d US releases to check the time base (need 10)" % checked)
    fails += ["time base: " + w for w in wrong]
    for x in info:
        print("  INFO " + x)
    for x in fails[:40]:
        print("  FAIL " + x)
    if len(fails) > 40:
        print("  ... and %d more" % (len(fails) - 40))
    if fails:
        print("RESULT %s: FAIL (%d failures)" % (os.path.basename(events_path), len(fails)))
        return False
    print("RESULT %s: PASS (0 failures)" % os.path.basename(events_path))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("events")
    ap.add_argument("summary")
    ap.add_argument("--from", dest="frm", required=True)
    ap.add_argument("--to", required=True)
    ap.add_argument("--list", required=True)
    ap.add_argument("--absent", action="append", default=[])
    ap.add_argument("--exception", action="append", default=[],
                    help='a release that really moved: "YYYY.MM.DD|event name" (New York date)')
    a = ap.parse_args(argv)
    ok = check(a.events, a.summary, a.frm, a.to, a.list, set(a.absent), set(a.exception))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
