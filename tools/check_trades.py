"""Trade-log checker (SPEC Check 1c; docs/PLAN_PHASE6.md section 3).

Reads a trade log written by MQL5/Include/NNFX/TradeLog.mqh and checks, trade by trade:

  stop     every position had a broker-held stop from its first moment (OPEN row SL != 0)   P-5, M3
  halves   two halves, one OPEN each, equal lots; a lone half only with an ABORT row       M5
  risk     planned risk at entry <= target (F4): for each half, lots x stop distance in
           ticks x the tick value used, summed, against balance x risk % at entry.
           Allowed above target: only float representation noise, RISK_BOUND = 1e-6 account
           currency (G1_phase6a_1 verdict note 1). Sizing floors to the lot step, so a real
           excess is at least one lot step and is always a failure.
  prices   SL within one tick of entry -/+ 1.5 x entry ATR and never further (M3, T1);
           TP1 within one tick of entry +/- 1 x entry ATR (T1); half 2 no target, or the
           runner cap within one tick (T3, T7)
  T2       BE only after TP1, at exactly half 2's entry (OD-15), and at once: the BE row is
           in the same second as the TP1 row when half 2 was still open
  T4       a TRAILON row (close >= 2 x entry ATR beyond entry) before any TRAIL; TRAIL only
           after TP1; each TRAIL stop within one tick of close -/+ 1.5 x ATR; never backwards
  test     a TESTSTOPLESS position must be closed with an ALARM in the same second; any other
           ALARM on our own position is a failure; manual-position alarms are information
  ABORT    a trade with an ABORT row has no half 2 and half 1 is closed (a CLOSE/SL row for
           half 1 after its OPEN; the ABORT note does not say the close failed): no lone half
  REFUSE   a trade id with a REFUSE row has no OPEN row: nothing was sent (stops level, OD-5 margin)
  info     realised loss larger than planned (a gap through the stop) is reported, never
           a pass or a fail; REFUSE and RETRY rows are counted

Usage:  python tools/check_trades.py LOG.csv [more.csv] [--min-trades N]
                                     [--require SL,TP1,BE,TRAILON,TRAIL,TP2,EXIT,RETRY,TESTSTOPLESS]
                                     [--require-note TEXT ...]   (some row's note must contain TEXT)
Exit code 0 = every file PASS.
"""
import argparse
import csv
import os
import sys
from collections import defaultdict

RISK_BOUND = 1e-6          # account currency: float noise only (verdict note 1)
SL_ATR, TP1_ATR = 1.5, 1.0
TRAIL_START, TRAIL_DIST = 2.0, 1.5

FLOAT_COLS = ("lots", "price", "sl", "tp", "prev_sl", "entry", "atr_entry", "atr", "close", "balance", "risk_pct",
              "tick_size", "tick_value", "planned_risk", "target_risk", "cap_atr")


def read_log(path):
    with open(path, encoding="ascii", newline="") as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        for c in FLOAT_COLS:
            r[c] = float(r[c]) if r.get(c, "") not in ("", None) else 0.0
        r["half"] = int(r["half"] or 0)
        r["dir"] = int(r["dir"] or 0)
        r["ticket"] = int(r["ticket"] or 0)
    return rows


def near(a, b, tol):
    return abs(a - b) <= tol + 1e-12


def check(path, min_trades=0, require=(), require_notes=()):
    rows = read_log(path)
    fails, info = [], []
    counts = defaultdict(int)
    for r in rows:
        counts[r["event"]] += 1
    by_trade = defaultdict(list)
    for i, r in enumerate(rows):
        if r["trade_id"]:
            by_trade[r["trade_id"]].append((i, r))

    trades = [t for t in by_trade if any(r["event"] == "OPEN" for _, r in by_trade[t])]
    for tid in trades:
        evs = by_trade[tid]
        opens = defaultdict(list)
        for i, r in evs:
            if r["event"] == "OPEN":
                opens[r["half"]].append((i, r))
        # halves and duplicates
        for h in (1, 2):
            if len(opens[h]) > 1:
                fails.append("%s: half %d opened %d times (duplicate)" % (tid, h, len(opens[h])))
        aborts = [r for _, r in evs if r["event"] == "ABORT"]
        if aborts:
            if opens[2]:
                fails.append("%s: ABORT but half 2 was opened" % tid)
            if any("FAILED" in a["note"] for a in aborts):
                fails.append("%s: ABORT could not close half 1 (lone half left)" % tid)
            if opens[1]:
                if opens[1][0][1]["sl"] == 0.0:
                    fails.append("%s: half 1 had no stop at its first record" % tid)
                i1 = opens[1][0][0]
                if not any(i > i1 and r["half"] == 1 and r["event"] in ("CLOSE", "SL") for i, r in evs):
                    fails.append("%s: ABORT but no close of half 1 is logged (lone half left)" % tid)
            continue
        if not opens[1] or not opens[2]:
            fails.append("%s: only one half opened and no ABORT row" % tid)
            continue
        o1, o2 = opens[1][0][1], opens[2][0][1]
        d = o1["dir"]
        if o2["dir"] != d:
            fails.append("%s: halves in different directions" % tid)
        if abs(o1["lots"] - o2["lots"]) > 1e-9:
            fails.append("%s: halves not equal (%.8g vs %.8g lots)" % (tid, o1["lots"], o2["lots"]))
        # stop from the first moment
        for o in (o1, o2):
            if o["sl"] == 0.0:
                fails.append("%s: half %d had no stop at its first record" % (tid, o["half"]))
        # final SL/TP per half: the last OPEN/MODIFY row
        final = {}
        for h in (1, 2):
            last = None
            for i, r in evs:
                if r["half"] == h and r["event"] in ("OPEN", "MODIFY"):
                    last = r
            final[h] = last
        tick = o1["tick_size"]
        atr_e = o1["atr_entry"]
        planned = 0.0
        for h in (1, 2):
            f = final[h]
            entry = f["entry"] or f["price"]
            want_sl = entry - d * SL_ATR * atr_e
            if f["sl"] == 0.0 or not near(f["sl"], want_sl, tick):
                fails.append("%s: half %d SL %.10g not within one tick of %.10g" % (tid, h, f["sl"], want_sl))
            if abs(entry - f["sl"]) > SL_ATR * atr_e + 1e-9:
                fails.append("%s: half %d stop wider than 1.5 x ATR (%.10g > %.10g)"
                             % (tid, h, abs(entry - f["sl"]), SL_ATR * atr_e))
            if h == 1:
                want_tp = entry + d * TP1_ATR * atr_e
                if not near(f["tp"], want_tp, tick):
                    fails.append("%s: TP1 %.10g not within one tick of %.10g" % (tid, f["tp"], want_tp))
            else:
                cap = o1["cap_atr"]
                if cap > 0:
                    want_tp2 = entry + d * cap * atr_e
                    if not near(f["tp"], want_tp2, tick):
                        fails.append("%s: runner cap TP %.10g not within one tick of %.10g" % (tid, f["tp"], want_tp2))
                elif f["tp"] != 0.0:
                    fails.append("%s: half 2 has a target %.10g but the runner cap is off" % (tid, f["tp"]))
            planned += f["lots"] * (abs(entry - f["sl"]) / f["tick_size"]) * o1["tick_value"]
        target = o1["balance"] * o1["risk_pct"] / 100.0
        if planned > target + RISK_BOUND:
            fails.append("%s: planned risk %.8f above target %.8f (by %.3g)" % (tid, planned, target, planned - target))
        # T2 breakeven
        tp1_rows = [(i, r) for i, r in evs if r["event"] == "TP1"]
        be_rows = [(i, r) for i, r in evs if r["event"] == "BE"]
        h2_closed_before = {}
        for i, r in evs:
            if r["half"] == 2 and r["event"] in ("SL", "TP2", "CLOSE"):
                h2_closed_before.setdefault("i", i)
        for i, r in be_rows:
            if not tp1_rows or i < tp1_rows[0][0]:
                fails.append("%s: breakeven before TP1 (T2)" % tid)
            entry2 = final[2]["entry"] or final[2]["price"]
            if not near(r["sl"], entry2, tick * 0.5):
                fails.append("%s: breakeven stop %.10g is not half 2's entry %.10g" % (tid, r["sl"], entry2))
        if tp1_rows:
            ti, tr = tp1_rows[0]
            half2_open = h2_closed_before.get("i", len(rows)) > ti
            if half2_open:
                if not be_rows:
                    fails.append("%s: TP1 filled but half 2 never moved to breakeven" % tid)
                elif be_rows[0][1]["time"] != tr["time"]:
                    fails.append("%s: breakeven at %s, not at once after TP1 at %s" % (tid, be_rows[0][1]["time"], tr["time"]))
        # T4 trail
        on_rows = [(i, r) for i, r in evs if r["event"] == "TRAILON"]
        for i, r in on_rows:
            if not tp1_rows or i < tp1_rows[0][0]:
                fails.append("%s: trail switched on before TP1 (I-11)" % tid)
            if (r["close"] - r["entry"]) * d < TRAIL_START * r["atr_entry"] - 1e-9:
                fails.append("%s: trail switched on at close %.10g, less than 2 x entry ATR beyond entry" % (tid, r["close"]))
        last_sl = None
        for i, r in evs:
            if r["half"] == 2 and r["event"] in ("BE",):
                last_sl = r["sl"]
            if r["event"] != "TRAIL":
                continue
            if not on_rows or i < on_rows[0][0]:
                fails.append("%s: TRAIL before the trail switched on" % tid)
            want = r["close"] - d * TRAIL_DIST * r["atr"]
            if not near(r["sl"], want, r["tick_size"] or tick):
                fails.append("%s: TRAIL stop %.10g not within one tick of %.10g" % (tid, r["sl"], want))
            prev = last_sl if last_sl is not None else r["prev_sl"]
            if (r["sl"] - prev) * d <= 0:
                fails.append("%s: TRAIL moved backwards or not at all (%.10g after %.10g)" % (tid, r["sl"], prev))
            last_sl = r["sl"]
        # info: realised loss beyond planned (gap through the stop)
        for i, r in evs:
            if r["event"] == "SL" and r["half"] in (1, 2):
                f = final[r["half"]]
                entry = f["entry"] or f["price"]
                lost = f["lots"] * ((entry - r["price"]) * d / f["tick_size"]) * o1["tick_value"]
                planned_h = f["lots"] * (abs(entry - f["sl"]) / f["tick_size"]) * o1["tick_value"]
                if lost > planned_h + RISK_BOUND and not tp1_rows:
                    info.append("%s: half %d lost %.2f, more than its planned %.2f (gap through the stop; information only)"
                                % (tid, r["half"], lost, planned_h))

    # test-only stopless position and alarms
    alarms = [(i, r) for i, r in enumerate(rows) if r["event"] == "ALARM"]
    test_tickets = {}
    for i, r in enumerate(rows):
        if r["event"] == "TESTSTOPLESS" and r["ticket"]:
            test_tickets[r["ticket"]] = (i, r)
    for tk, (i, r) in test_tickets.items():
        match = [a for a in alarms if a[1]["ticket"] == tk and a[0] > i]
        if not match:
            fails.append("TESTSTOPLESS position %d was never closed with an ALARM" % tk)
        elif match[0][1]["time"] != r["time"] or "closed at once" not in match[0][1]["note"]:
            fails.append("TESTSTOPLESS position %d: alarm at %s, not closed at once" % (tk, match[0][1]["time"]))
    for i, a in alarms:
        if "manual position" in a["note"]:
            info.append("manual position %d without a stop: alarm only (OD-8)" % a["ticket"])
        elif a["ticket"] not in test_tickets:
            fails.append("ALARM on our own position: %s" % a["note"])

    for tid, evs in by_trade.items():
        if any(r["event"] == "REFUSE" for _, r in evs) and any(r["event"] == "OPEN" for _, r in evs):
            fails.append("%s: REFUSE row but an order was opened anyway" % tid)

    if len(trades) < min_trades:
        fails.append("only %d trades, need at least %d" % (len(trades), min_trades))
    for ev in require:
        if counts[ev] == 0:
            fails.append("coverage: no %s row in the log" % ev)
    for text in require_notes:
        if not any(text in r["note"] for r in rows):
            fails.append("coverage: no row with %r in its note" % text)

    name = os.path.basename(path)
    print("=" * 70)
    print("%s  (%d trades, %d rows)" % (name, len(trades), len(rows)))
    print("  events: " + ", ".join("%s %d" % (k, counts[k]) for k in sorted(counts)))
    for line in info:
        print("  INFO " + line)
    for line in fails:
        print("  FAIL " + line)
    ok = not fails
    print("RESULT %s: %s" % (name, "PASS (0 failures)" if ok else "FAIL (%d failures)" % len(fails)))
    return ok


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("csv", nargs="+")
    ap.add_argument("--min-trades", type=int, default=0)
    ap.add_argument("--require", default="", help="comma-separated events that must appear at least once")
    ap.add_argument("--require-note", action="append", default=[], help="a row's note must contain this text")
    a = ap.parse_args(argv)
    req = [x.strip() for x in a.require.split(",") if x.strip()]
    ok = all([check(p, a.min_trades, req, a.require_note) for p in a.csv])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
