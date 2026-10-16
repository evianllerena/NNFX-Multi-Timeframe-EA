"""Checks the two restart cases of G1_review2_1 F1/F2 in an NNFX_OrderTest trade log (tools/run_restart_tests.ps1,
runs R5 and R6). Each run has one simulated restart (one REBUILD row) and a test hook on one trade that lasts until it.

  be     (R5, InpBeHoldOn): before the restart, TP1 filled and every breakeven move of the trade was refused (RETRY
         "BE: ... refused", no BE row), half 2 still open. After it, within --within seconds of the REBUILD row: half 2's
         stop set to exactly its entry (a BE row "restored after a restart (A1)"), or, if the price had already passed
         breakeven, half 2 closed at market (EXIT "BE price already passed"). Without the fix nothing happens: the
         rebuilt trade keeps its first stop.
  abort  (R6, InpAbortHoldOn): before the restart, an ABORT whose close of half 1 failed (pending) and no close of
         half 1. After it, within --within seconds of the REBUILD row: an EXIT "lone half 1" row and a CLOSE row for
         half 1 marked (A8); nothing else for the trade (no TP1, SL or BE). Without the fix the lone half 1 is adopted
         as a trade and runs to its stop or TP1.

Usage:  python tools/check_restart_cases.py be R5.csv --trade T0012
        python tools/check_restart_cases.py abort R6.csv --trade T0007
Prints the findings and "RESULT <file>: PASS" or "RESULT <file>: FAIL (n failures)"; exit code 0 only on PASS.
"""
import argparse
import csv
import os
import sys
from datetime import datetime


def read(path):
    with open(path, encoding="ascii", newline="") as f:
        return list(csv.DictReader(f))


def secs(a, b):
    f = "%Y.%m.%d %H:%M:%S"
    return (datetime.strptime(b, f) - datetime.strptime(a, f)).total_seconds()


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return 0.0


def check(case, rows, trade, within=60):
    fails, info = [], []
    rb = [i for i, r in enumerate(rows) if r["event"] == "REBUILD"]
    if len(rb) != 1:
        return ["%d REBUILD rows (must be exactly 1)" % len(rb)], info
    rb = rb[0]
    t_rb = rows[rb]["time"]
    # the restart starts at the PRESTOP row before the REBUILD row: what the rebuild itself does (an ABORT leftover closed
    # by ImportTrades) is logged between the two, so the boundary is the PRESTOP row (first R6 run, restart_20261016_143448)
    ps = [i for i, r in enumerate(rows[:rb]) if r["event"] == "PRESTOP"]
    if not ps:
        return ["no PRESTOP row before the REBUILD row"], info
    rb = ps[-1]
    mine = [(i, r) for i, r in enumerate(rows) if r["trade_id"] == trade]
    before = [r for i, r in mine if i < rb]
    after = [r for i, r in mine if i > rb]
    if not before:
        return ["trade %s has no rows before the restart (not exercised)" % trade], info

    if case == "be":
        if not any(r["event"] == "TP1" for r in before):
            fails.append("%s: no TP1 before the restart (not exercised)" % trade)
        refused = [r for r in before if r["event"] == "RETRY" and r["note"].startswith("BE:") and "refused" in r["note"]]
        if not refused:
            fails.append("%s: no refused breakeven move before the restart (the hook did not act)" % trade)
        if any(r["event"] == "BE" for r in before):
            fails.append("%s: a BE row before the restart (the hook did not hold)" % trade)
        if any(r["half"] == "2" and r["event"] in ("SL", "TP2", "CLOSE") for r in before) or \
                any(r["event"] == "EXIT" for r in before):
            fails.append("%s: half 2 closed before the restart (not exercised)" % trade)
        o2 = next((r for r in before if r["event"] == "OPEN" and r["half"] == "2"), None)
        done = next((r for r in after if r["event"] == "BE" or
                     (r["event"] == "EXIT" and "BE price already passed" in r["note"])), None)
        if done is None:
            fails.append("%s: after the restart half 2 was never moved to breakeven nor closed (G1_review2_1 F1)" % trade)
        else:
            lag = secs(t_rb, done["time"])
            if not 0 <= lag <= within:
                fails.append("%s: %s %d s after the restart (must be within %d s)" % (trade, done["event"], lag, within))
            if done["event"] == "BE":
                entry2 = num(o2["entry"]) or num(o2["price"]) if o2 else 0.0
                tick = num(done["tick_size"]) or 1e-5
                if o2 is None or abs(num(done["sl"]) - entry2) > tick * 0.5:
                    fails.append("%s: breakeven stop %s is not half 2's entry %s" % (trade, done["sl"], entry2))
                if "restored after a restart (A1)" not in done["note"]:
                    fails.append("%s: BE row note %r does not say it was restored after the restart" % (trade, done["note"]))
            if not fails:
                info.append("%s: %d refused breakeven move(s) before the restart at %s; %s at %s (%d s after): %s"
                            % (trade, len(refused), t_rb, done["event"], done["time"], lag, done["note"]))
    elif case == "abort":
        ab = [r for r in before if r["event"] == "ABORT"]
        if not ab or not any("FAILED" in r["note"] and "pending" in r["note"] for r in ab):
            fails.append("%s: no ABORT with a failed, pending close of half 1 before the restart (not exercised)" % trade)
        if any(r["event"] == "OPEN" and r["half"] == "2" for _, r in mine):
            fails.append("%s: half 2 was opened" % trade)
        if any(r["half"] == "1" and r["event"] in ("CLOSE", "SL", "TP1") for r in before):
            fails.append("%s: half 1 closed before the restart (the hook did not hold)" % trade)
        ex = next((r for r in after if r["event"] == "EXIT" and "lone half 1" in r["note"]), None)
        cl = next((r for r in after if r["event"] == "CLOSE" and r["half"] == "1" and "(A8)" in r["note"]), None)
        if ex is None or cl is None:
            fails.append("%s: after the restart the lone half 1 was not closed (EXIT %s, CLOSE (A8) %s; G1_review2_1 F2)"
                         % (trade, "found" if ex else "missing", "found" if cl else "missing"))
        else:
            lag = secs(t_rb, cl["time"])
            if not 0 <= lag <= within:
                fails.append("%s: half 1 closed %d s after the restart (must be within %d s)" % (trade, lag, within))
        other = [r["event"] for r in after if r["event"] in ("TP1", "SL", "BE", "TRAILON", "TRAIL", "TP2")]
        if other:
            fails.append("%s: managed as a trade after the restart: %s" % (trade, ", ".join(other)))
        if not fails:
            info.append("%s: ABORT at %s, half 1's close held; restart at %s; closed at %s: %s"
                        % (trade, ab[0]["time"], t_rb, cl["time"], cl["note"]))
    else:
        raise ValueError("case must be 'be' or 'abort'")
    return fails, info


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("case", choices=("be", "abort"))
    ap.add_argument("csv")
    ap.add_argument("--trade", required=True)
    ap.add_argument("--within", type=int, default=60)
    a = ap.parse_args(argv)
    fails, info = check(a.case, read(a.csv), a.trade, a.within)
    for x in info:
        print("INFO " + x)
    for x in fails:
        print("FAIL " + x)
    name = os.path.basename(a.csv)
    print("RESULT %s: %s" % (name, "PASS" if not fails else "FAIL (%d failures)" % len(fails)))
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
