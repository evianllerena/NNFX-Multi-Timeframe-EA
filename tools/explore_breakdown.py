"""Breakdown of one backtest run for the write-up (G3_explore_1 F1, F2 and note 2): what the broker-side numbers are
made of, from the raw logs.

  refusals   the trade log's REFUSE rows by reason: "too small to size" (below the minimum lot), "not enough free
             margin (OD-5)", "half N not opened", other
  DIVERGE    the trade log's DIVERGE rows (D6f-1) by kind: "core flat, broker trade closed", "core holds a trade, broker
             none (entries skipped)", "start-up"; and the R of the broker trades closed by a DIVERGE against the rest
  matched    broker trades matched to the answer key's own trades (core_trades_*.csv, written by check_replay): same pair
             and direction, entry within --ticks ticks, the broker trade opened before the core trade closed; one to
             one, in time order. Mean broker R - core R over the matched pairs, overall and per pair
  swap       the report's swap per closing deal, matched to the trade log's closing rows (same second, same pair),
             divided by that trade's 1R in money (target_risk on its OPEN row): swap in R

R per trade as tools/summarize_trades.py (the same function). Years in summarize_trades are the year a trade CLOSED.

Usage:  python tools/explore_breakdown.py TRADES.csv --core CORE_TRADES.csv [--report REPORT.htm] [--ticks 3]
"""
import argparse
import csv
import os
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import summarize_trades as st  # noqa: E402

DIV_FLAT = re.compile(r"rules core is flat[,;] the broker holds ([^;,\s]+)[;,] closed")   # the log writes "," as ";"


def refusal_kind(note):
    if "too small to size" in note:
        return "too small to size (below the minimum lot)"
    if "free margin" in note:
        return "not enough free margin (OD-5)"
    if re.search(r"half \d not opened", note):
        return "half N not opened"
    return "other: " + re.sub(r"[\d.]+", "#", note)[:60]


def divergence_kind(note):
    if "START-UP" in note:
        return "start-up (alarm only)"
    if "rules core is flat" in note:
        return "core flat, broker trade closed"
    if re.search(r"rules core holds a trade[,;] the broker none", note):
        return "core holds a trade, broker none (no entry until the core closes)"
    return "other"


def read_rows(path):
    with open(path, encoding="ascii", newline="") as f:
        return list(csv.DictReader(f))


def match(broker, core, ticks, tick_of):
    """One-to-one: each core trade (in close order) takes the earliest unused broker trade of the same pair and
    direction whose fill is within `ticks` ticks of the core's entry and which opened before the core trade closed."""
    pool = defaultdict(list)
    for b in sorted(broker, key=lambda t: t["open"]):
        pool[(b["symbol"], b["dir"])].append(b)
    used, pairs = set(), []
    for c in sorted(core, key=lambda x: x["close_time"]):
        tick = tick_of.get(c["symbol"], 0.0)
        for b in pool[(c["symbol"], c["dir"])]:
            if b["id"] in used or b["open"][:16] > c["close_time"][:16]:
                continue
            if tick > 0 and abs(b["entry"] - c["entry"]) <= ticks * tick + 1e-12:
                used.add(b["id"])
                pairs.append((b, c))
                break
    return pairs


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("trades")
    ap.add_argument("--core", required=True)
    ap.add_argument("--report", default=None)
    ap.add_argument("--ticks", type=int, default=3)
    a = ap.parse_args(argv)

    rows = read_rows(a.trades)
    trades, still_open, aborted = st.read_trades(a.trades)
    by_id = {t["id"]: t for t in trades}
    print("trade log %s: %d trades counted, %d ABORT, %d still open" % (os.path.basename(a.trades), len(trades),
                                                                       len(aborted), len(still_open)))

    ref = Counter(refusal_kind(r["note"]) for r in rows if r["event"] == "REFUSE")
    print("REFUSE rows: %d" % sum(ref.values()))
    for k, n in ref.most_common():
        print("  %6d  %s" % (n, k))

    div = [r for r in rows if r["event"] == "DIVERGE"]
    kinds = Counter(divergence_kind(r["note"]) for r in div)
    print("DIVERGE rows: %d" % len(div))
    for k, n in kinds.most_common():
        print("  %6d  %s" % (n, k))
    closed_ids = set()
    for r in div:
        m = DIV_FLAT.search(r["note"])
        if m:
            closed_ids.add(m.group(1))
    a_r = [by_id[i]["r"] for i in closed_ids if i in by_id]
    b_r = [t["r"] for t in trades if t["id"] not in closed_ids]
    if a_r:
        print("  broker trades closed by a DIVERGE: %d, mean %+.3fR; the other %d trades: mean %+.3fR"
              % (len(a_r), sum(a_r) / len(a_r), len(b_r), sum(b_r) / max(1, len(b_r))))

    # matched trades
    tick_of, entry_of = {}, {}
    for r in rows:
        if r["event"] == "OPEN" and r["half"] == "1":
            tick_of.setdefault(r["symbol"], st.fnum(r["tick_size"]))
            entry_of[r["trade_id"]] = st.fnum(r["entry"]) or st.fnum(r["price"])
    broker = [dict(t, entry=entry_of.get(t["id"], 0.0)) for t in trades]
    core = []
    with open(a.core, encoding="ascii", newline="") as f:
        for c in csv.DictReader(f):
            core.append({"close_time": c["close_time"], "symbol": c["symbol"], "dir": int(c["dir"]),
                         "entry": float(c["entry"]), "r": float(c["r"])})
    pairs = match(broker, core, a.ticks, tick_of)
    if pairs:
        gap = [b["r"] - c["r"] for b, c in pairs]
        print("matched (same pair and direction, entry within %d ticks): %d of %d broker / %d core trades; "
              "broker - core %+.3fR per trade (broker %+.3fR, core %+.3fR on the matched)"
              % (a.ticks, len(pairs), len(broker), len(core), sum(gap) / len(gap),
                 sum(b["r"] for b, _ in pairs) / len(pairs), sum(c["r"] for _, c in pairs) / len(pairs)))
        per = defaultdict(list)
        for b, c in pairs:
            per[b["symbol"]].append(b["r"] - c["r"])
        for s in sorted(per, key=lambda s: sum(per[s]) / len(per[s])):
            print("  %-7s %5d matched, broker - core %+.3fR" % (s, len(per[s]), sum(per[s]) / len(per[s])))

    if a.report:
        figs, deals, _ = st.read_report(a.report)
        closes = defaultdict(list)
        for r in rows:
            if r["event"] in ("SL", "TP1", "TP2", "CLOSE") and r["trade_id"] in by_id:
                closes[(r["time"], r["symbol"])].append(r["trade_id"])
        risk = {}
        for r in rows:
            if r["event"] == "OPEN" and r["half"] == "1":
                risk[r["trade_id"]] = st.fnum(r["target_risk"])
        total, in_r, matched, n_swap = 0.0, 0.0, 0, 0
        for d in deals:
            if d["swap"] == 0.0 or d["dir"] != "out":
                continue
            n_swap += 1
            total += d["swap"]
            ids = closes.get((d["time"], d["symbol"]), [])
            if len(set(ids)) == 1 and risk.get(ids[0], 0) > 0:
                matched += 1
                in_r += d["swap"] / risk[ids[0]]
        print("swap on closing deals: %.2f in money over %d deals; %d deals matched to one trade: %+.1fR in total "
              "(%+.4fR per counted trade)" % (total, n_swap, matched, in_r, in_r / max(1, len(trades))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
