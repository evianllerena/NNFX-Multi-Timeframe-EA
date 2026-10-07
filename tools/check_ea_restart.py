"""Restart check for NNFX_EA (Phase 6f; docs/DESIGN_6F.md section 5, the reviewer's restart note).

Over one tester run with a simulated restart (InpRestartAt) - its decision log and trade log:
  restart    exactly one PRESTOP "simulated restart" row, then a REBUILD "simulated restart" row
  start-up   one INFO/DIVERGE "start (simulated restart)" row per pair; a start-up DIVERGE row says "alarm only,
             nothing closed"
  no close   nothing is closed by the restart: no EXIT row in the trade log at the restart's second, and the
             decision rows written at the restart (block "missed") have action "-" (OD-7 (b): never acted on)
  missed     each pair's missed candles are logged (block "missed", note "missed while stopped"), so the log has no gap
  master     (--master-off FROM;TO) at least one entry was blocked by the master switch in that window ("master" in
             the block and a SKIP event on the row)
  replay     (--replay-differs SYM) SYM's start-up row says the restored core and the broker agree (both flat) and the
             replay with no blocks "differs: information only": the master switch's earlier block is remembered, and
             the replay's different answer is not acted on
  baseline   (--baseline DECISIONS) the same run without the restart: every decision row equal (time, symbol, inputs,
             events, actions) except the restart candle's block and note, which proves the core memory was restored
             exactly. Valid only if the baseline has no ENTER at the restart candle (said so if it has).
  trades     (--baseline-trades TRADES) the same run's trade log: every row equal leaving out INFO, PRESTOP and
             REBUILD rows, so open trades were managed through the restart (S-2; a missed trail is caught)

Usage:  python tools/check_ea_restart.py DECISIONS.csv TRADES.csv [--master-off "A;B"] [--replay-differs SYM]
                                         [--baseline BASELINE_DECISIONS.csv] [--baseline-trades BASELINE_TRADES.csv]
Exit code 0 = PASS.
"""
import argparse
import csv
import os
import sys
from datetime import datetime


def read(path):
    with open(path, encoding="ascii", newline="") as f:
        return list(csv.reader(f))


def check(dec_path, trades_path, master_off=None, replay_sym=None, baseline=None, baseline_trades=None):
    fails, info = [], []
    dec = read(dec_path)
    head, drows = dec[0], dec[1:]
    with open(trades_path, encoding="ascii", newline="") as f:
        trows = list(csv.DictReader(f))
    pairs = []
    for r in drows:
        if r[1] not in pairs:
            pairs.append(r[1])
    pre = [r for r in trows if r["event"] == "PRESTOP" and "simulated restart" in r["note"]]
    reb = [r for r in trows if r["event"] == "REBUILD" and r["note"].startswith("simulated restart")]
    if len(pre) != 1 or len(reb) != 1:
        fails.append("need exactly one simulated restart (PRESTOP %d, REBUILD %d)" % (len(pre), len(reb)))
        restart_time = None
    else:
        restart_time = reb[0]["time"]
        info.append("restart at %s" % restart_time)
    starts = [r for r in trows if "start (simulated restart)" in r["note"]]
    for p in pairs:
        n = sum(1 for r in starts if r["symbol"] == p)
        if n != 1:
            fails.append("%s: %d start-up rows, need 1" % (p, n))
    for r in starts:
        if r["event"] == "DIVERGE" and "alarm only, nothing closed" not in r["note"]:
            fails.append("%s: start-up DIVERGE without 'alarm only, nothing closed'" % r["symbol"])
        info.append("%s %s: %s" % (r["symbol"], r["event"], r["note"].split("): ", 1)[-1]))
    if restart_time:
        closes = [r for r in trows if r["time"] == restart_time and r["event"] in ("EXIT", "CLOSE")]
        for r in closes:
            fails.append("closed at the restart: %s %s %s" % (r["event"], r["trade_id"], r["note"]))
    missed = [r for r in drows if r[14] == "missed"]
    for r in missed:
        if r[17] != "-":
            fails.append("%s %s: a missed candle was acted on: %s" % (r[0], r[1], r[17]))
        if "missed while stopped" not in r[18]:
            fails.append("%s %s: missed row without the note" % (r[0], r[1]))
    for p in pairs:
        if not any(r[1] == p for r in missed):
            fails.append("%s: no missed-candle row at the restart" % p)
    if master_off:
        a, b = [datetime.strptime(x.strip(), "%Y.%m.%d %H:%M") for x in master_off.split(";")]
        blocked = [r for r in drows if a <= datetime.strptime(r[0], "%Y.%m.%d %H:%M") < b
                   and "master" in r[14].split(";") and "SKIP:" in r[16]]
        if not blocked:
            fails.append("no entry was blocked by the master switch in %s" % master_off)
        else:
            info.append("master switch blocked: " + ", ".join("%s %s %s" % (r[0], r[1], r[16]) for r in blocked[:6]))
    if replay_sym:
        rows = [r for r in starts if r["symbol"] == replay_sym]
        if not rows:
            fails.append("%s: no start-up row" % replay_sym)
        else:
            n = rows[0]["note"]
            if "core flat; broker flat" not in n or "the replay differs: information only" not in n:
                fails.append("%s: start-up row is not 'core flat; broker flat ... the replay differs': %s" % (replay_sym, n))
    if baseline:
        base = read(baseline)[1:]
        mt = {r[0] for r in missed}
        if len(base) != len(drows):
            fails.append("baseline has %d rows, this run %d" % (len(base), len(drows)))
        enter_at_restart = [r for r in base if r[0] in mt and "ENTER:" in r[16]]
        if enter_at_restart:
            info.append("baseline has an ENTER at the restart candle (%s): compared up to it only" % enter_at_restart[0][1])
        diff = 0
        for x, y in zip(base, drows):
            if enter_at_restart and x[0] >= enter_at_restart[0][0]:
                break
            if x[0] in mt and x[0] == y[0] and x[1] == y[1]:
                same = x[:14] == y[:14] and x[15:18] == y[15:18]
            else:
                same = x == y
            if not same:
                diff += 1
                if diff <= 5:
                    fails.append("differs from the baseline: %s %s\n      base %s\n      this %s" % (y[0], y[1], x, y))
        if diff == 0:
            info.append("every decision row equals the run without the restart (except the restart candle's block "
                        "and note): the core memory was restored exactly")
    if baseline_trades:
        skip = ("INFO", "PRESTOP", "REBUILD")
        with open(baseline_trades, encoding="ascii", newline="") as f:
            b = [r for r in csv.DictReader(f) if r["event"] not in skip]
        t = [r for r in trows if r["event"] not in skip]
        bad = [(x, y) for x, y in zip(b, t) if x != y]
        if len(b) != len(t) or bad:
            fails.append("trade log differs from the run without the restart (INFO/PRESTOP/REBUILD rows left out): "
                         "%d vs %d rows; first difference: %s"
                         % (len(b), len(t), ("\n      base %s\n      this %s" % (dict(bad[0][0]), dict(bad[0][1])))
                            if bad else "a row missing at the end"))
        else:
            info.append("every trade-log row equals the run without the restart (INFO/PRESTOP/REBUILD rows left out): "
                        "the open trades were managed through the restart (S-2)")
    print("%s: %d decision rows, %d pairs" % (os.path.basename(dec_path), len(drows), len(pairs)))
    for x in info:
        print("  INFO " + x)
    for x in fails:
        print("  FAIL " + x)
    res = "PASS (0 failures)" if not fails else "FAIL (%d failures)" % len(fails)
    print("RESULT restart %s: %s" % (os.path.basename(dec_path), res))
    return not fails


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("decisions")
    ap.add_argument("trades")
    ap.add_argument("--master-off")
    ap.add_argument("--replay-differs")
    ap.add_argument("--baseline")
    ap.add_argument("--baseline-trades")
    a = ap.parse_args(argv)
    return 0 if check(a.decisions, a.trades, a.master_off, a.replay_differs, a.baseline, a.baseline_trades) else 1


if __name__ == "__main__":
    sys.exit(main())
