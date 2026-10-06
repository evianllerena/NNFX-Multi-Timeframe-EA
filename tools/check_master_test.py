"""Demo master-switch check (Phase 6d; docs/PLAN_PHASE6.md section 5, "Master switch").

Two test-EA instances on two charts of one terminal: A (it runs the test and switches the terminal global variable
NNFX_MASTER) and B (opened by A from a template). A's GUARD rows give the times:
    "TEST master switch: NNFX_MASTER = 1; chart ... applied ..."   start
    "TEST master switch: NNFX_MASTER = 0 (OFF)"                     off
    "TEST master switch: NNFX_MASTER = 1 (ON)"                      on
Pass:
  - B's chart was opened and its template applied, and B wrote its own log (it ran)
  - BOTH instances saw the switch: a GUARD row "blocks: ...master..." (the guard logs every change of its block
    reasons, open trade or not) inside [off, off + 119 s] OR, if it is the instance's very first evaluation
    ("was -"), anywhere inside [off, on] (B can start late; run master_20261006_135454), and a later one without
    "master" inside [on, on + 119 s] (the two charts handle the same minute in either order)
  - every SKIP naming "master" is inside [off, on + 59 s] (a SKIP is written only when an entry is due)
  - no new entry (OPEN, half 1) in either log from off + 60 s to on (exclusive)
  - INFO: management rows (TP1, BE, TRAILON, TRAIL, SL, TP2, EXIT, CLOSE) inside the window (open trades kept)

With --panel (instance A's chart buttons, driven by the test EA through the panel's own handlers):
  - "instance switch OFF by the chart button", later "... ON ...": no new entry of A in between; any SKIP of A
    in between names "instance"
  - "drawdown reset requested by the chart button" is followed, at a later candle, by the guard's
    "drawdown reset by hand (D6d-3)" row (manual, logged) in A's OR B's log: the reset is account-wide and the
    first instance to reach its next candle applies it (run master_20261006_130813: B at 20:25; run
    master_20261006_135454: B 1 s after the request, at its own next candle)
  - "close-all by the chart button": every trade of A open at that moment gets an EXIT row "close-all button",
    its open halves a CLOSE (or SL/TP2) row, and it is in no later STATE row (A may open a NEW trade after it)

Usage:  python tools/check_master_test.py A.csv B.csv [--panel]
Exit code 0 = PASS.
"""
import csv
import os
import sys
from datetime import datetime, timedelta

MANAGED = ("TP1", "BE", "TRAILON", "TRAIL", "SL", "TP2", "EXIT", "CLOSE")


def read(path):
    with open(path, encoding="ascii", newline="") as f:
        return list(csv.DictReader(f))


def ts(r):
    return datetime.strptime(r["time"], "%Y.%m.%d %H:%M:%S")


def check_panel(a, fails, b=()):
    g = [(i, r) for i, r in enumerate(a) if r["event"] == "GUARD"]
    off = next((i for i, r in g if "instance switch OFF by the chart button" in r["note"]), None)
    on = next((i for i, r in g if off is not None and i > off and "instance switch ON by the chart button" in r["note"]), None)
    req = next((i for i, r in g if "drawdown reset requested by the chart button" in r["note"]), None)
    done_row = None
    if req is not None:
        t_req = ts(a[req])
        done_row = next((r for r in list(a) + list(b) if r["event"] == "GUARD" and ts(r) > t_req
                         and "drawdown reset by hand (D6d-3)" in r["note"]), None)
    ca = next((i for i, r in g if "close-all by the chart button" in r["note"]), None)
    if off is None or on is None:
        fails.append("panel: no instance OFF and ON rows from the chart button")
    else:
        between = a[off + 1:on]
        opens = [r for r in between if r["event"] == "OPEN"]
        bad_skips = [r for r in between if r["event"] == "SKIP" and "instance" not in r["note"]]
        print("panel: instance OFF %s .. ON %s: new entries %d, SKIP %d (all naming instance: %s)"
              % (a[off]["time"], a[on]["time"], len(opens), sum(r["event"] == "SKIP" for r in between), not bad_skips))
        if opens:
            fails.append("panel: new entry %s at %s while the instance switch was OFF" % (opens[0]["trade_id"], opens[0]["time"]))
        for r in bad_skips:
            fails.append("panel: SKIP at %s does not name instance: %s" % (r["time"], r["note"]))
    if req is None or done_row is None:
        fails.append("panel: drawdown reset requested by the button but no 'drawdown reset by hand (D6d-3)' row after it")
    else:
        print("panel: drawdown reset requested %s, done and logged %s (%s): %s"
              % (a[req]["time"], done_row["time"], "A" if done_row in a else "B", done_row["note"]))
    if ca is None:
        fails.append("panel: no close-all row from the chart button")
    else:
        opened, closed = set(), set()
        for r in a[:ca]:
            if r["event"] == "OPEN":
                opened.add(r["trade_id"])
            if r["event"] in ("SL", "TP2", "EXIT", "CLOSE") and r["half"] == "2":
                closed.add(r["trade_id"])
        open_then = opened - closed
        after = a[ca + 1:]
        exits = {r["trade_id"] for r in after if r["event"] == "EXIT" and "close-all button" in r["note"]}
        shut = {r["trade_id"] for r in after if r["event"] in ("CLOSE", "SL", "TP2")}
        later = [r for r in after if r["event"] == "STATE"]
        still = sorted(t for t in open_then if any("TRADE|%s|" % t in r["note"] for r in later))
        print("panel: close-all at %s: trades open then %s, EXIT rows %s, closed %s, in a later STATE %s"
              % (a[ca]["time"], sorted(open_then), sorted(exits), sorted(shut & open_then), still))
        if open_then - exits:
            fails.append("panel: close-all left %s without an EXIT row" % sorted(open_then - exits))
        if open_then - shut:
            fails.append("panel: close-all did not close %s" % sorted(open_then - shut))
        if still:
            fails.append("panel: %s still open after close-all" % still)


def check(path_a, path_b, panel=False):
    a, b = read(path_a), read(path_b)
    fails = []
    if panel:
        check_panel(a, fails, b)
    guard = [r for r in a if r["event"] == "GUARD" and "TEST master switch" in r["note"]]
    start = next((r for r in guard if "chart" in r["note"]), None)
    off = next((r for r in guard if "(OFF)" in r["note"]), None)
    on = next((r for r in guard if "(ON)" in r["note"]), None)
    if start is None or "applied" not in start["note"]:
        fails.append("instance A did not open B's chart with its template: %s" % (start["note"] if start else "no start row"))
    if off is None or on is None:
        fails.append("instance A's log has no OFF and ON rows")
        return report(fails, path_a)
    t_off, t_on = ts(off), ts(on)
    print("master OFF %s, ON %s (A: %s)" % (off["time"], on["time"], os.path.basename(path_a)))
    if not any(r["event"] == "INFO" and "orders allowed" in r["note"] for r in b):
        fails.append("instance B wrote no 'orders allowed' row (did it run?)")
    for name, rows in (("A", a), ("B", b)):
        skips = [r for r in rows if r["event"] == "SKIP" and "master" in r["note"].replace(";", ",").split(":")[-1].split(",")]
        inside = [r for r in skips if t_off <= ts(r) <= t_on + timedelta(seconds=59)]
        opens = [r for r in rows if r["event"] == "OPEN" and r["half"] == "1"
                 and t_off + timedelta(seconds=60) <= ts(r) < t_on]
        managed = [r for r in rows if r["event"] in MANAGED and t_off <= ts(r) <= t_on]
        changes = [r for r in rows if r["event"] == "GUARD" and r["note"].startswith("blocks: ")]
        saw_off = next((r for r in changes if "master" in r["note"].split(" (was")[0]
                        and (t_off <= ts(r) <= t_off + timedelta(seconds=119)
                             or (r["note"].endswith("(was -)") and t_off <= ts(r) < t_on))), None)
        saw_on = next((r for r in changes if saw_off is not None and ts(r) > ts(saw_off)
                       and "master" not in r["note"].split(" (was")[0]
                       and t_on <= ts(r) <= t_on + timedelta(seconds=119)), None)
        print("%s saw OFF: %s; saw ON: %s" % (name, saw_off["time"] + " " + saw_off["note"] if saw_off else "NO",
                                            saw_on["time"] + " " + saw_on["note"] if saw_on else "NO"))
        if saw_off is None:
            fails.append("%s: no GUARD 'blocks: ...master' row within 2 candles of OFF" % name)
        if saw_on is None:
            fails.append("%s: no GUARD 'blocks:' row without master within 2 candles of ON" % name)
        print("%s %s: SKIP master %d (inside the window %d); new entries in the window %d; management rows in it %d"
              % (name, os.path.basename(path_a if name == "A" else path_b), len(skips), len(inside), len(opens),
                 len(managed)))
        for r in skips:
            if r not in inside:
                fails.append("%s: SKIP %s at %s, outside the OFF window" % (name, r["note"], r["time"]))
        for r in opens:
            fails.append("%s: new entry %s at %s while the master switch was OFF" % (name, r["trade_id"], r["time"]))
    return report(fails, path_a)


def report(fails, path):
    for f in fails[:20]:
        print("  FAIL " + f)
    if fails:
        print("RESULT master switch: FAIL (%d failures)" % len(fails))
        return False
    print("RESULT master switch: PASS (0 failures)")
    return True


if __name__ == "__main__":
    args = [x for x in sys.argv[1:] if x != "--panel"]
    if len(args) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(0 if check(args[0], args[1], "--panel" in sys.argv[1:]) else 1)
