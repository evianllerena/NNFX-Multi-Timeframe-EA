"""Demo master-switch check (Phase 6d; docs/PLAN_PHASE6.md section 5, "Master switch").

Two test-EA instances on two charts of one terminal: A (it runs the test and switches the terminal global variable
NNFX_MASTER) and B (opened by A from a template). A's GUARD rows give the times:
    "TEST master switch: NNFX_MASTER = 1; chart ... applied ..."   start
    "TEST master switch: NNFX_MASTER = 0 (OFF)"                     off
    "TEST master switch: NNFX_MASTER = 1 (ON)"                      on
Pass:
  - B's chart was opened and its template applied, and B wrote its own log (it ran)
  - BOTH logs have at least one SKIP naming "master", and every such SKIP is inside [off, on + 59 s]
    (the two charts handle the same minute in either order, so B may see the switch up to one candle late)
  - no new entry (OPEN, half 1) in either log from off + 60 s to on (exclusive)
  - INFO: management rows (TP1, BE, TRAILON, TRAIL, SL, TP2, EXIT, CLOSE) inside the window (open trades kept)

Usage:  python tools/check_master_test.py A.csv B.csv
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


def check(path_a, path_b):
    a, b = read(path_a), read(path_b)
    fails = []
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
        print("%s %s: SKIP master %d (inside the window %d); new entries in the window %d; management rows in it %d"
              % (name, os.path.basename(path_a if name == "A" else path_b), len(skips), len(inside), len(opens),
                 len(managed)))
        if not skips:
            fails.append("%s: no SKIP blocked:master" % name)
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
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(0 if check(sys.argv[1], sys.argv[2]) else 1)
