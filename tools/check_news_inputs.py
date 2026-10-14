"""News into the rules core, end to end (Phase 6f; PLAN 6f carry-over from G1_phase6e_2 note 3).

The EA feeds News.mqh's answers into the core: N1/N2 into `block`, the X5 first-close flag into `news`. Over an EA
decision log and the same event file, this recomputes both with the Python reference (tests/python/nnfx_ref/news.py,
the answer key News.mqh was ported from) and checks, row by row:
  inputs   the N1/N2 reasons in the row's block (the block minus the guard's own reason words) equal news.blocked()
           at the candle close; the news column equals news.first_close() with the pair's previous actual close
  core     no ENTER event on a row whose block has an N1/N2 reason (the core honoured the block), and every X5 exit
           (EXIT:X5) is on a row with news = 1 (the core acted on the flag only)
  coverage at least one N1-blocked SKIP and at least one news = 1 row (with --require-x5: one EXIT:X5 as well)
Rows the EA could not build (ind_ok 0) are left out (the core was not fed); they still count as the previous close.

Usage:  python tools/check_news_inputs.py DECISIONS.csv --events EVENTS.txt --tf 60 [--winter 2] [--dst US]
                                          [--blackouts "CUR:YYYY.MM.DD-YYYY.MM.DD;..."] [--require-x5]
Exit code 0 = PASS.
"""
import argparse
import bisect
import csv
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "python"))
from nnfx_ref import guard, news  # noqa: E402

GUARD_WORDS = {"master", "instance", "drawdown", "dailyloss", "rollover", "weekend", "spread", "indicator",
               "exposure", "diverge", "missed", "start", "newsfile"}


def news_part(block):
    """The N1/N2 reasons of a logged block: every ';'-separated piece that is not one of the guard's own words."""
    if block == "-":
        return ""
    return ";".join(p for p in block.split(";") if p not in GUARD_WORDS)


def check(dec_path, events_path, tf, winter=2, dst="US", blackouts="", require_x5=False, warmup_path=None):
    b = guard.Broker("check", winter, dst)
    with open(events_path, encoding="ascii", errors="replace") as f:
        events = news.load_export(f, b)
    bo = news.parse_blackouts(blackouts) if blackouts else []
    times = [e.time for e in events]   # the export is in time order

    def near(t):
        """The events within 4 days of t, in file order: a block window never reaches further from its event
        (from the earlier of 24 h before and 15:00 New York on the previous trading day, to the 17:00 close)."""
        lo = bisect.bisect_left(times, t - timedelta(days=4))
        hi = bisect.bisect_right(times, t + timedelta(days=4))
        return events[lo:hi]
    with open(dec_path, encoding="ascii", newline="") as f:
        rows = list(csv.reader(f))[1:]
    by_pair = defaultdict(list)
    for r in rows:
        by_pair[r[1]].append(r)
    # Phase 7: the EA's last warm-up candle per pair (its close is the previous close of the first logged row). Without
    # it, the first row assumes the candle before was there (wrong after a gap: run ea_explore2_M30_20261014_165013,
    # AUDNZD 2019.01.02 06:00 after the New Year gap)
    last_warm = {}
    if warmup_path:
        with open(warmup_path, encoding="ascii", newline="") as f:
            for r in list(csv.reader(f))[1:]:
                t_w = datetime.strptime(r[0], "%Y.%m.%d %H:%M")
                if r[1] not in last_warm or t_w > last_warm[r[1]]:
                    last_warm[r[1]] = t_w
    fails, info = [], []
    n_checked = n_n1 = n_news = n_x5 = n_n1_skip = 0
    for sym, rs in by_pair.items():
        rs.sort(key=lambda r: r[0])
        prev = None
        for r in rs:
            t_open = datetime.strptime(r[0], "%Y.%m.%d %H:%M")
            t = t_open + timedelta(minutes=tf)
            if prev is None:
                # the close of the EA's last warm-up candle; without the warm-up file, assume the candle before
                prev = last_warm[sym] + timedelta(minutes=tf) if sym in last_warm else t_open
            if r[13] == "1":
                n_checked += 1
                cand = near(t)
                want = ";".join(w.replace(",", ";") for w in news.blocked(sym, t, cand, b, bo))
                got = news_part(r[14])
                if got != want:
                    fails.append("%s %s: N1/N2 in the block %r, the reference says %r" % (r[0], sym, got, want))
                fc = news.first_close(sym, t, prev, cand, b)
                if (r[15] == "1") != fc:
                    fails.append("%s %s: news flag %s, the reference says %d" % (r[0], sym, r[15], int(fc)))
                if want:
                    n_n1 += 1
                    if "ENTER:" in r[16]:
                        fails.append("%s %s: ENTER on a row blocked by news (%s)" % (r[0], sym, want[:60]))
                    if "SKIP:" in r[16]:
                        n_n1_skip += 1
                if r[15] == "1":
                    n_news += 1
                if "EXIT:X5:" in r[16]:
                    n_x5 += 1
                    if r[15] != "1":
                        fails.append("%s %s: X5 exit on a row with news = 0" % (r[0], sym))
            prev = t
    info.append("%d rows checked; %d with an N1/N2 reason (%d of them with a SKIP); %d with news = 1; %d X5 exits"
                % (n_checked, n_n1, n_n1_skip, n_news, n_x5))
    if n_n1_skip == 0:
        fails.append("coverage: no SKIP on a news-blocked row")
    if n_news == 0:
        fails.append("coverage: no row with news = 1")
    if require_x5 and n_x5 == 0:
        fails.append("coverage: no X5 exit")
    name = os.path.basename(dec_path)
    print("%s vs %s (broker rule winter %+d, %s)" % (name, os.path.basename(events_path), winter, dst))
    for x in info:
        print("  INFO " + x)
    for x in fails[:40]:
        print("  FAIL " + x)
    if len(fails) > 40:
        print("  ... and %d more" % (len(fails) - 40))
    print("RESULT news %s: %s" % (name, "PASS (0 failures)" if not fails else "FAIL (%d failures)" % len(fails)))
    return not fails


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("decisions")
    ap.add_argument("--events", required=True)
    ap.add_argument("--tf", type=int, required=True)
    ap.add_argument("--winter", type=int, default=2)
    ap.add_argument("--dst", default="US")
    ap.add_argument("--blackouts", default="")
    ap.add_argument("--require-x5", action="store_true")
    ap.add_argument("--warmup", default=None, help="the EA's warm-up log (<log>_warmup.csv): the previous close of each pair's first row")
    a = ap.parse_args(argv)
    return 0 if check(a.decisions, a.events, a.tf, a.winter, a.dst, a.blackouts, a.require_x5, a.warmup) else 1


if __name__ == "__main__":
    sys.exit(main())
