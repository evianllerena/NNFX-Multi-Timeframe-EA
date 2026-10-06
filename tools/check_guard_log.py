"""Guard check over a test-EA trade log (Phase 6d; docs/PLAN_PHASE6.md section 5).

The test EA (NNFX_OrderTest, InpGuard=true) writes a SKIP row "blocked:<reasons>" when a new entry is due but the
guard blocks it, and an OPEN row when it enters. The rollover and weekend windows are recomputed here with the answer
key (tests/python/nnfx_ref/guard.py) from each row's server time and the broker's clock rule:

  - every new entry (OPEN, half 1) is outside the rollover window and the weekend block
  - every SKIP that names rollover / weekend is inside that window, and every SKIP that does not name it is outside
  - open trades keep being managed while new entries are blocked (S-2): with --require-managed, at least one
    management row (TP1, BE, TRAILON, TRAIL, SL, TP2, EXIT, CLOSE) inside a rollover window
  - at least --min-skips SKIP rows naming rollover (the window really was exercised)
  - with --managed-during-pause: from the first GUARD row starting a drawdown pause (real or "TEST: ... forced"),
    no new entry at all (the pause is reset by hand only, S-6) and at least one management row of a trade that was
    open when the pause started (S-2)

Times in the log are the EA's TimeCurrent() (server time) to the second; the windows are evaluated at that second.

Usage:  python tools/check_guard_log.py LOG.csv --winter-offset 2 --dst US [--weekend-hours H] [--min-skips N]
                                        [--require-managed] [--managed-during-pause]
Exit code 0 = PASS.
"""
import argparse
import csv
import os
import sys
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "python"))
from nnfx_ref import guard as g  # noqa: E402

MANAGED = ("TP1", "BE", "TRAILON", "TRAIL", "SL", "TP2", "EXIT", "CLOSE")


def check(path, broker, weekend_hours, min_skips, require_managed, during_pause=False):
    with open(path, encoding="ascii", newline="") as f:
        rows = list(csv.DictReader(f))
    fails, counts = [], {"open": 0, "skip": 0, "skip_rollover": 0, "skip_weekend": 0, "managed_in_rollover": 0}
    for r in rows:
        t = datetime.strptime(r["time"], "%Y.%m.%d %H:%M:%S")
        ev = r["event"]
        roll = g.in_rollover(broker, t)
        week = g.in_weekend_block(broker, t, weekend_hours)
        if ev == "OPEN" and r["half"] == "1":
            counts["open"] += 1
            if roll:
                fails.append("%s OPEN %s inside the rollover window" % (r["time"], r["trade_id"]))
            if week:
                fails.append("%s OPEN %s inside the weekend block" % (r["time"], r["trade_id"]))
        elif ev == "SKIP" and r["note"].startswith("blocked:"):
            counts["skip"] += 1
            reasons = r["note"][len("blocked:"):].replace(";", ",").split(",")
            if ("rollover" in reasons) != roll:
                fails.append("%s SKIP %s but the rollover window is %s" % (r["time"], r["note"], "on" if roll else "off"))
            if ("weekend" in reasons) != week:
                fails.append("%s SKIP %s but the weekend block is %s" % (r["time"], r["note"], "on" if week else "off"))
            counts["skip_rollover"] += "rollover" in reasons
            counts["skip_weekend"] += "weekend" in reasons
        elif ev in MANAGED and roll:
            counts["managed_in_rollover"] += 1
    if during_pause:
        start = next((i for i, r in enumerate(rows) if r["event"] == "GUARD" and "drawdown pause" in r["note"]), None)
        if start is None:
            fails.append("no GUARD row starting a drawdown pause")
        else:
            opened = {r["trade_id"] for r in rows[:start] if r["event"] == "OPEN"}
            closed_before = {r["trade_id"] for r in rows[:start] if r["event"] in ("SL", "TP2", "EXIT", "CLOSE") and r["half"] == "2"}
            open_then = opened - closed_before
            after = rows[start + 1:]
            new = [r for r in after if r["event"] == "OPEN"]
            managed = [r for r in after if r["event"] in MANAGED and r["trade_id"] in open_then]
            print("pause from %s (%s): trades open then %s; management rows after it %d (%s); new entries after it %d"
                  % (rows[start]["time"], rows[start]["note"][:60], sorted(open_then), len(managed),
                     ", ".join("%s %s" % (r["time"][5:16], r["event"]) for r in managed[:8]), len(new)))
            if new:
                fails.append("%d new entries after the drawdown pause started (first %s)" % (len(new), new[0]["time"]))
            if not managed:
                fails.append("no management row of an open trade after the drawdown pause started")
    print("%s: %d rows; new entries %d; SKIP %d (rollover %d, weekend %d); management rows inside rollover %d"
          % (os.path.basename(path), len(rows), counts["open"], counts["skip"], counts["skip_rollover"],
             counts["skip_weekend"], counts["managed_in_rollover"]))
    if counts["skip_rollover"] < min_skips:
        fails.append("only %d SKIP rows for rollover, need %d" % (counts["skip_rollover"], min_skips))
    if require_managed and counts["managed_in_rollover"] == 0:
        fails.append("no management row inside a rollover window (open trades must keep being managed)")
    for f in fails[:20]:
        print("  FAIL " + f)
    if fails:
        print("RESULT %s: FAIL (%d failures)" % (os.path.basename(path), len(fails)))
        return False
    print("RESULT %s: PASS (0 failures)" % os.path.basename(path))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("log")
    ap.add_argument("--winter-offset", type=int, required=True)
    ap.add_argument("--dst", choices=("none", "EU", "US"), required=True)
    ap.add_argument("--weekend-hours", type=float, default=0.0)
    ap.add_argument("--min-skips", type=int, default=1)
    ap.add_argument("--require-managed", action="store_true")
    ap.add_argument("--managed-during-pause", action="store_true")
    a = ap.parse_args(argv)
    ok = check(a.log, g.Broker("log", a.winter_offset, a.dst), a.weekend_hours, a.min_skips, a.require_managed,
               a.managed_during_pause)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
