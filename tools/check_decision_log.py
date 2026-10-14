"""Decision-log check (Phase 6f; docs/PLAN_PHASE6.md 6f, docs/DESIGN_6F.md section 6).

Over a decision log written by NNFX_EA (MQL5/Include/NNFX/DecisionLog.mqh) and, optionally, its trade log:
  - format:     the header, 19 fields per row, times "YYYY.MM.DD HH:MM", events "EV:RULE:DIR" joined by ";"
  - boundary:   every time is on a candle boundary of --tf minutes (the closed candle's open time)
  - duplicates: one row per pair per candle time
  - no gaps:    every pair has a row at every candle time that any pair has (between its first and last row), and a
                pair's consecutive rows are --tf apart except across a weekend (Friday to Sunday/Monday, at most
                2 days + one candle + 1 hour)
  - order:      within one candle time the pairs appear in the --pairs order, batch by batch: a pair whose new
                candle arrived after the others' is processed in a later visit and its note starts "batch N;"
                (N >= 2); rows must be sorted by (batch, place in --pairs)
  - trades:     (with --trades) every ENTER event's row has an action "OPEN <id>" or "REFUSE ..."; every "OPEN <id>"
                action has an OPEN row (half 1) for that id in the trade log, and every trade-log OPEN (half 1) has
                its decision row

Usage:  python tools/check_decision_log.py DECISIONS.csv --tf 60 --pairs EURUSD,AUDNZD,EURGBP,AUDCAD,CHFJPY
                                           [--trades TRADES.csv]
Exit code 0 = PASS.
"""
import argparse
import bisect
import csv
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta

HEADER = "time,symbol,tf,o,h,l,c,atr,base,c1,c2,ex,vol,ind_ok,block,news,events,action,note".split(",")
EVENT = re.compile(r"^[A-Z_0-9]+:[A-Z0-9]+:-?[01]$")
BATCH = re.compile(r"^batch (\d+);")


def weekend_gap(a, b, tf):
    """a and b are consecutive rows of one pair: allowed if the gap is the weekend only (Fri -> Sun/Mon, at most
    2 days + one candle + 1 hour, e.g. Fri 23:00 -> Mon 00:00 on 1H), so rows stopping early on Friday still fail."""
    return (a.weekday() == 4 and b.weekday() in (6, 0)
            and (b - a) <= timedelta(days=2, minutes=tf + 60))


def load_bars(bars_dir, pairs, tf):
    """{pair: sorted candle open times} from NNFX_ExportBars files <dir>/<pair>_<M30|H1|H4>.csv (Phase 7, V3)."""
    name = {30: "M30", 60: "H1", 240: "H4"}.get(tf, "M%d" % tf)
    out = {}
    for p in pairs:
        path = os.path.join(bars_dir, "%s_%s.csv" % (p, name))
        if not os.path.exists(path):
            continue
        ts = []
        with open(path, encoding="ascii", errors="replace") as f:
            for line in f:
                if line.startswith("#") or line.startswith("time,"):
                    continue
                try:
                    ts.append(datetime.strptime(line[:16], "%Y.%m.%d %H:%M"))
                except ValueError:
                    pass
        out[p] = sorted(set(ts))
    return out


def check(path, tf, pairs, trades_path=None, bars_dir=None):
    fails, info = [], []
    bars = load_bars(bars_dir, pairs, tf) if bars_dir else {}
    data_gaps = defaultdict(int)
    with open(path, encoding="ascii", newline="") as f:
        rd = csv.reader(f)
        header = next(rd, [])
        rows = list(rd)
    if header != HEADER:
        fails.append("header is not the decision-log header")
    parsed = []
    for i, r in enumerate(rows, start=2):
        if len(r) != 19:
            fails.append("line %d: %d fields, need 19" % (i, len(r)))
            continue
        try:
            t = datetime.strptime(r[0], "%Y.%m.%d %H:%M")
        except ValueError:
            fails.append("line %d: bad time %r" % (i, r[0]))
            continue
        minutes = t.hour * 60 + t.minute
        if minutes % tf != 0:
            fails.append("line %d: %s %s not on a %d-minute candle boundary" % (i, r[0], r[1], tf))
        if r[16] != "-":
            for ev in r[16].split(";"):
                if not EVENT.match(ev):
                    fails.append("line %d: malformed event %r" % (i, ev))
        parsed.append((i, t, r))
    # duplicates and per-pair rows
    seen = set()
    by_pair = defaultdict(list)
    for i, t, r in parsed:
        k = (r[1], t)
        if k in seen:
            fails.append("line %d: duplicate row %s %s" % (i, r[1], r[0]))
        seen.add(k)
        by_pair[r[1]].append(t)
    unknown = sorted(set(by_pair) - set(pairs))
    if unknown:
        fails.append("pairs not in --pairs: %s" % unknown)
    all_times = sorted({t for _, t, _ in parsed})
    for p in pairs:
        ts = sorted(set(by_pair.get(p, [])))
        if not ts:
            fails.append("%s: no rows" % p)
            continue
        bp = bars.get(p)
        bset = set(bp) if bp else set()

        def broker_has_none(lo, hi):
            """True if the bar export covers lo..hi and holds no candle strictly between them (V3: the broker's
            history has none there, so the EA had no candle to log)."""
            if not bp or bp[0] > lo or bp[-1] < hi:
                return False
            k = bisect.bisect_right(bp, lo)
            return k >= len(bp) or bp[k] >= hi
        for a, b in zip(ts, ts[1:]):
            if b - a != timedelta(minutes=tf) and not weekend_gap(a, b, tf):
                if broker_has_none(a, b):
                    data_gaps[p] += 1
                else:
                    fails.append("%s: gap from %s to %s" % (p, a.strftime("%Y.%m.%d %H:%M"), b.strftime("%Y.%m.%d %H:%M")))
        tset = set(ts)
        missing = [t for t in all_times if ts[0] <= t <= ts[-1] and t not in tset]
        if bp:
            covered = [t for t in missing if bp[0] <= t <= bp[-1] and t not in bset]
            data_gaps[p] += len(covered)
            missing = [t for t in missing if t not in covered]
        for t in missing[:5]:
            fails.append("%s: no row at %s (other pairs have one)" % (p, t.strftime("%Y.%m.%d %H:%M")))
        if len(missing) > 5:
            fails.append("%s: %d more times with no row" % (p, len(missing) - 5))
    for p in sorted(data_gaps):
        info.append("%s: %d gap(s) / missing row(s) where the broker's history has no candle (bar export; V3 data gap, "
                    "not an EA fault)" % (p, data_gaps[p]))
    # fixed order within a candle time, per batch: a pair whose new candle arrived after the others' was processed
    # in a later visit, noted "batch N" (each pair keeps its own clock; SPEC Candle timing)
    order = {p: k for k, p in enumerate(pairs)}
    by_time = defaultdict(list)
    stall = 0
    late_written = 0
    max_seen = None
    for i, t, r in parsed:
        # a stall catch-up row (the pair's candle was processed late, fed and logged, never acted on; in the tester the
        # pairs are visited on the chart symbol's ticks, so a pair still trading while the chart symbol's market is
        # closed catches up when it reopens: run ea_explore2_M30_20261014_165013, 2019.12.24) is outside the order rule
        if r[18].startswith("missed (stall"):
            stall += 1
            if "ENTER:" in r[16] and r[17] != "-":
                fails.append("line %d: stall row %s %s acted on (%s)" % (i, r[0], r[1], r[17]))
            continue
        # a row written after rows of a LATER candle time was processed late (its pair's next candle came after a gap in
        # that pair's own history, so its close was seen late; run ea_explore2_M30_20261014_165013, AUDNZD 2022.12.26
        # 10:30): outside the order rule within its candle time
        if max_seen is not None and t < max_seen:
            late_written += 1
            continue
        max_seen = t if max_seen is None or t > max_seen else max_seen
        m = BATCH.match(r[18])
        by_time[t].append((int(m.group(1)) if m else 1, r[1]))
    for t, lst in by_time.items():
        ranks = [(b, order.get(s, 99)) for b, s in lst]
        if ranks != sorted(ranks):
            fails.append("%s: pairs out of the fixed order: %s" % (t.strftime("%Y.%m.%d %H:%M"),
                                                                   ["%s(batch %d)" % (s, b) for b, s in lst]))
    if stall:
        info.append("%d stall catch-up row(s) (processed late, fed, never acted on): outside the order rule" % stall)
    if late_written:
        info.append("%d row(s) written after a later candle time (its pair's candle closed late, after a gap in that "
                    "pair's history): outside the order rule" % late_written)
    late = sum(1 for _, _, r in parsed if BATCH.match(r[18]))
    if late:
        info.append("%d row(s) processed in a later batch than their candle time's first (their candle arrived later)"
                    % late)
    # trades
    enters = sum(1 for _, _, r in parsed if "ENTER:" in r[16])
    opens_decided = {}
    for i, t, r in parsed:
        acts = r[17]
        if "ENTER:" in r[16] and not (acts.startswith("OPEN ") or acts.startswith("REFUSE")):
            fails.append("line %d: ENTER at %s %s but the action is %r" % (i, r[0], r[1], acts))
        m = re.match(r"^OPEN (\S+)", acts)
        if m:
            opens_decided[m.group(1)] = (i, r[1], r[0])
            if "ENTER:" not in r[16]:
                fails.append("line %d: action %s without an ENTER event" % (i, acts))
    if trades_path:
        with open(trades_path, encoding="ascii", newline="") as f:
            trows = list(csv.DictReader(f))
        topen = {r["trade_id"] for r in trows if r["event"] == "OPEN" and r["half"] == "1"}
        aborted = {r["trade_id"] for r in trows if r["event"] == "ABORT"}
        refused = {m.group(1) for _, _, r in parsed for m in [re.match(r"^REFUSE ([^;\s]+)", r[17])] if m}
        # an ABORT (half 1 opened, half 2 failed, half 1 closed) is logged by the EA as "REFUSE <id>": the trade did not open
        for tid in sorted(topen & aborted & refused - set(opens_decided)):
            info.append("trade log OPEN %s: half 1 only, closed by ABORT; the decision row says REFUSE %s" % (tid, tid))
            topen = topen - {tid}
        for tid, (i, sym, tm) in sorted(opens_decided.items()):
            if tid not in topen:
                fails.append("line %d: %s %s decided OPEN %s but the trade log has no OPEN for it" % (i, tm, sym, tid))
        for tid in sorted(topen - set(opens_decided)):
            fails.append("trade log OPEN %s has no decision row (no ENTER acted on)" % tid)
        info.append("trade log: %d trades opened" % len(topen))
    print("%s: %d rows, %d pairs, %d candle times, %d ENTER events, %d OPEN actions"
          % (os.path.basename(path), len(parsed), len(by_pair), len(all_times), enters, len(opens_decided)))
    for x in info:
        print("  INFO " + x)
    for x in fails[:40]:
        print("  FAIL " + x)
    if len(fails) > 40:
        print("  ... and %d more" % (len(fails) - 40))
    if fails:
        print("RESULT %s: FAIL (%d failures)" % (os.path.basename(path), len(fails)))
        return False
    print("RESULT %s: PASS (0 failures)" % os.path.basename(path))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("decisions")
    ap.add_argument("--tf", type=int, required=True, help="candle length in minutes (30, 60, 240)")
    ap.add_argument("--pairs", required=True, help="the preset's pairs in their fixed order")
    ap.add_argument("--trades")
    ap.add_argument("--bars", default=None, help="folder of NNFX_ExportBars files: a gap where the broker has no candle is INFO (V3)")
    a = ap.parse_args(argv)
    return 0 if check(a.decisions, a.tf, [p.strip() for p in a.pairs.split(",") if p.strip()], a.trades, a.bars) else 1


if __name__ == "__main__":
    sys.exit(main())
