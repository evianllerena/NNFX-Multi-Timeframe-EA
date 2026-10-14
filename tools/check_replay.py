"""Phase 7 bar-by-bar replay (docs/SPEC.md Check 1b; docs/DESIGN_6F.md section 6).

Replays the inputs NNFX_EA's rules core saw, row by row from its decision log, through the Python answer key
(tests/python/nnfx_ref/core.py PairCore) and compares the events of every pair at every candle. The comparison is
exact: the same event names, rule IDs and directions, in the same order.

  inputs      each row's o h l c atr base c1 c2 ex vol, block (";" list, "-" none) and news flag, as the EA logged them
  not fed     rows with ind_ok 0 (the EA never feeds a candle with missing values) are skipped, as the EA does
  warm-up     --warmup FILE: the candles the EA fed before its first logged row (its flat warm-up), written by the EA
              to <log>_warmup.csv; fed first, compared too (their events are information: blocked by "start").
              Without it the replay starts cold, and the first candles of each pair can differ for that reason only
              (the C1 run length and the previous candle are unknown); such a run is labelled "no warm-up" and its
              RESULT can never be PASS
  settings    --inputs "InpTrailOn=false ..." or --inputs-from SUMMARY.txt (the "inputs:" line written by
              tools/run_ea_tester.ps1): the EA inputs that are rule settings are mapped to nnfx_ref Settings
  restarts    one continuous run only: a time going backwards, or a "missed while stopped" row, stops the replay of
              that pair with a FAIL (a restart rebuilds the EA's core from its snapshot; that is check_ea_restart's job)

Usage:  python tools/check_replay.py DECISIONS.csv [--warmup WARMUP.csv] [--inputs-from SUMMARY.txt | --inputs "..."]
                                     [--max-list 40]
Exit code 0 = PASS (0 mismatches, warm-up given).
"""
import argparse
import csv
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tests", "python"))

from nnfx_ref.core import PairCore  # noqa: E402
from nnfx_ref.settings import Settings  # noqa: E402

HEADER = "time,symbol,tf,o,h,l,c,atr,base,c1,c2,ex,vol,ind_ok,block,news,events,action,note".split(",")

# EA input -> (Settings field, converter)
INPUT_MAP = {
    "InpTrailOn": ("trail_on", lambda v: v.lower() in ("true", "1")),
    "InpTrailStart": ("trail_start_atr", float),
    "InpTrailDist": ("trail_dist_atr", float),
    "InpRunnerCap": ("runner_cap_atr", lambda v: None if v in ("0", "0.0", "none", "") or float(v) == 0.0 else float(v)),
    "InpExitOnExitInd": ("exit_on_exit_ind", lambda v: v.lower() in ("true", "1")),
    "InpExitOnC1": ("exit_on_c1", lambda v: v.lower() in ("true", "1")),
    "InpExitOnBaseline": ("exit_on_baseline", lambda v: v.lower() in ("true", "1")),
    "InpNewsExit": ("news_exit", lambda v: v.lower() in ("true", "1")),
    "InpPullback": ("pullback_on", lambda v: v.lower() in ("true", "1")),
    "InpOneCandle": ("one_candle", lambda v: v.lower() in ("true", "1")),
    "InpBridgeTooFar": ("btf_on", lambda v: v.lower() in ("true", "1")),
    "InpBridgeBars": ("btf_bars", int),
    "InpContinuation": ("continuation", str),
}


def settings_from_inputs(pairs):
    over = {}
    for k, v in pairs.items():
        if k in INPUT_MAP:
            name, conv = INPUT_MAP[k]
            over[name] = conv(v)
    s = Settings.from_dict(over)
    s.validate()
    return s


def parse_inputs(text):
    return dict(m.groups() for m in re.finditer(r"\b(Inp\w+)=(\S*)", text))


def inputs_from_summary(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("inputs:"):
                return parse_inputs(line)
    raise ValueError("no 'inputs:' line in %s" % path)


def read_rows(path):
    with open(path, encoding="ascii", newline="") as f:
        rd = csv.reader(f)
        header = next(rd, [])
        if header != HEADER:
            raise ValueError("%s: not a decision-log header" % path)
        return [dict(zip(HEADER, r)) for r in rd]


def bar_of(r):
    return {"t": r["time"], "o": float(r["o"]), "h": float(r["h"]), "l": float(r["l"]), "c": float(r["c"]),
            "atr": float(r["atr"]), "base": float(r["base"]), "c1": int(r["c1"]), "c2": int(r["c2"]),
            "ex": int(r["ex"]), "vol": r["vol"] == "1",
            "block": [] if r["block"] in ("-", "") else [b for b in r["block"].split(";") if b],
            "news": r["news"] == "1"}


def events_text(evs):
    return ";".join("%s:%s:%d" % (e["event"], e["rule"], e["dir"]) for e in evs)


def replay(dec_path, warm_path, settings, max_list=40, trades_out=None):
    rows = read_rows(dec_path)
    warm = read_rows(warm_path) if warm_path else []
    fails, info, mism = [], [], []
    by_pair = defaultdict(list)
    for r in warm:
        by_pair[r["symbol"]].append(("warm", r))
    for r in rows:
        by_pair[r["symbol"]].append(("log", r))
    stats = {}
    core_trades = []   # the answer key's own simulated trades (R from candles, no money, no costs): information
    for sym, items in by_pair.items():
        core = PairCore(sym, Settings(**vars(settings)))
        fed_times = []
        last_t, fed, skipped, compared, bad, warm_bad = None, 0, 0, 0, 0, 0
        for kind, r in items:
            if last_t is not None and r["time"] <= last_t:
                fails.append("%s: time %s not after %s (a restart or a duplicate): replay of this pair stopped"
                             % (sym, r["time"], last_t))
                break
            if "missed while stopped" in r["note"]:
                fails.append("%s: %s is a missed-candle row (a restart): replay of this pair stopped" % (sym, r["time"]))
                break
            last_t = r["time"]
            if r["ind_ok"] != "1":
                skipped += 1
                if r["events"] not in ("", "-"):
                    fails.append("%s %s: not fed (ind_ok 0) but the EA logged events %s" % (sym, r["time"], r["events"]))
                continue
            got = events_text(core.on_bar(bar_of(r)))
            fed_times.append(r["time"])
            fed += 1
            want = "" if r["events"] == "-" else r["events"]
            if kind == "log":
                compared += 1
            if got != want:
                if kind == "warm":
                    warm_bad += 1
                else:
                    bad += 1
                mism.append((sym, kind, r["time"], want, got, r["block"]))
        stats[sym] = (len(items), fed, skipped, compared, bad, warm_bad)
        for ct in core.closed_trades:
            core_trades.append({"symbol": sym, "rule": ct["rule"], "dir": ct["dir"], "entry": ct["entry"], "r": ct["r"],
                                "close_time": fed_times[ct["closed_i"]] if 0 <= ct["closed_i"] < len(fed_times) else ""})
    total_bad = sum(s[4] + s[5] for s in stats.values())
    if total_bad:
        fails.append("%d candle(s) where the EA's events differ from the answer key's" % total_bad)
    if not warm_path:
        fails.append("no warm-up file: the replay started cold (not a valid Check 1b result)")
    name = os.path.basename(dec_path)
    print("=" * 70)
    print("%s  replay through nnfx_ref.core (settings: %s)" % (name, ", ".join("%s=%s" % kv for kv in sorted(vars(settings).items()))))
    for sym in sorted(stats):
        n, fed, skipped, compared, bad, warm_bad = stats[sym]
        print("  %-8s rows %6d  fed %6d  not fed %4d  compared %6d  mismatches %d%s"
              % (sym, n, fed, skipped, compared, bad, ("  (warm-up mismatches %d)" % warm_bad) if warm_path else ""))
    for sym, kind, t, want, got, blk in mism[:max_list]:
        print("  MISMATCH %s %s%s: EA %r  answer key %r  (block %s)" % (sym, t, " (warm-up)" if kind == "warm" else "",
                                                                          want, got, blk))
    if len(mism) > max_list:
        print("  ... %d more mismatches" % (len(mism) - max_list))
    if core_trades:
        core_trades.sort(key=lambda x: (x["close_time"], x["symbol"]))
        rs = [x["r"] for x in core_trades]
        cum = peak = dd = 0.0
        for x in rs:
            cum += x
            peak = max(peak, cum)
            dd = max(dd, peak - cum)
        print("  CORE (answer key's simulation, candles only, no costs): trades %d  win rate %.1f%%  expectancy %+.3fR  "
              "total %+.1fR  max DD %.1fR" % (len(rs), 100.0 * sum(1 for x in rs if x > 0) / len(rs), sum(rs) / len(rs),
                                             sum(rs), dd))
        for sym in sorted({x["symbol"] for x in core_trades}):
            mine = [x["r"] for x in core_trades if x["symbol"] == sym]
            print("  CORE %-8s trades %5d  expectancy %+.3fR  total %+7.1fR" % (sym, len(mine), sum(mine) / len(mine), sum(mine)))
        if trades_out:
            with open(trades_out, "w", encoding="ascii", newline="") as f:
                w = csv.DictWriter(f, fieldnames=["close_time", "symbol", "rule", "dir", "entry", "r"], lineterminator="\r\n")
                w.writeheader()
                w.writerows(core_trades)
    for line in info:
        print("  INFO " + line)
    for line in fails:
        print("  FAIL " + line)
    ok = not fails
    print("RESULT replay %s: %s" % (name, "PASS (0 mismatches over %d compared candles)" % sum(s[3] for s in stats.values())
                                     if ok else "FAIL (%d failures)" % len(fails)))
    return ok


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("decisions")
    ap.add_argument("--warmup", default=None)
    ap.add_argument("--inputs", default="", help='EA inputs, e.g. "InpTrailOn=false InpRunnerCap=2"')
    ap.add_argument("--inputs-from", default=None, help="a run_ea_tester SUMMARY.txt with an 'inputs:' line")
    ap.add_argument("--max-list", type=int, default=40)
    ap.add_argument("--trades-out", default=None, help="write the answer key's simulated closed trades (R) to this CSV")
    a = ap.parse_args(argv)
    pairs = inputs_from_summary(a.inputs_from) if a.inputs_from else {}
    pairs.update(parse_inputs(a.inputs))
    s = settings_from_inputs(pairs)
    return 0 if replay(a.decisions, a.warmup, s, a.max_list, a.trades_out) else 1


if __name__ == "__main__":
    sys.exit(main())
