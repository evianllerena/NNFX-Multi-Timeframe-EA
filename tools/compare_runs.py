"""Restart comparison (Phase 6c; docs/PLAN_PHASE6.md section 9, SPEC "Rebuilding after a restart").

SPEC pass test: "restart MT5 in each state (before TP1, after TP1, trailing, flat but waiting for a
continuation). The trades and logs afterwards must match a run with no restart."

Two checks, on trade logs written by MQL5/Include/NNFX/TradeLog.mqh:

  compare  BASE.csv RESTART.csv --from "YYYY.MM.DD HH:MM[:SS]"
           every row at or after --from, in order, must be identical in EVERY column between the run
           without a restart and the run with one. Rows that only the restart run writes (PRESTOP,
           REBUILD) and INFO rows are left out; nothing else is.
           -> RESULT: IDENTICAL (0 differing rows, <n> compared)   or   RESULT: DIFFERENT (...)

  rebuilds LOG.csv
           every PRESTOP row (the state just before a restart) is followed by a REBUILD row whose state
           is the same, field for field (the lines after "state=", split on " / "). The EA's own
           "match=" flag is not trusted: the comparison is redone here.
           -> RESULT: REBUILDS MATCH (<n> of <n>)   or   RESULT: REBUILD MISMATCH (...)

Usage:  python tools/compare_runs.py compare BASE.csv RESTART.csv --from TIME
        python tools/compare_runs.py rebuilds LOG.csv [--min N]
Exit code 0 = PASS.
"""
import argparse
import csv
import os
import sys

SKIP = ("PRESTOP", "REBUILD", "INFO")


def read(path):
    with open(path, encoding="ascii", newline="") as f:
        r = csv.reader(f)
        header = next(r)
        return header, [row for row in r]


def compare(base_path, restart_path, from_time):
    hb, rb = read(base_path)
    hr, rr = read(restart_path)
    if hb != hr:
        print("RESULT: DIFFERENT (headers differ)")
        return False
    ti, ei = hb.index("time"), hb.index("event")
    a = [r for r in rb if r[ti] >= from_time and r[ei] not in SKIP]
    b = [r for r in rr if r[ti] >= from_time and r[ei] not in SKIP]
    diffs = []
    for k in range(max(len(a), len(b))):
        x = a[k] if k < len(a) else None
        y = b[k] if k < len(b) else None
        if x != y:
            cols = [] if x is None or y is None else [hb[i] for i in range(len(hb)) if x[i] != y[i]]
            diffs.append((k, x, y, cols))
    print("compare %s vs %s from %s: %d and %d rows" % (os.path.basename(base_path), os.path.basename(restart_path),
                                                         from_time, len(a), len(b)))
    for k, x, y, cols in diffs[:5]:
        print("  row %d differs in %s" % (k, ",".join(cols) if cols else "presence"))
        print("    no restart: %s" % (",".join(x) if x else "-"))
        print("    restart:    %s" % (",".join(y) if y else "-"))
    if diffs:
        print("RESULT: DIFFERENT (%d differing rows)" % len(diffs))
        return False
    print("RESULT: IDENTICAL (0 differing rows, %d compared)" % len(a))
    return True


def state_of(note):
    i = note.find("state=")
    if i < 0:
        return None
    s = note[i + len("state="):]
    j = s.find("; ")
    s = s if j < 0 else s[:j]
    return [x for x in s.split(" / ") if x]


def rebuilds(path, min_count=1):
    h, rows = read(path)
    ei, ni, ti = h.index("event"), h.index("note"), h.index("time")
    pairs, bad, pending = 0, [], None
    for r in rows:
        if r[ei] == "PRESTOP":
            pending = r
        elif r[ei] == "REBUILD":
            if pending is None:
                bad.append("REBUILD at %s without a PRESTOP before it" % r[ti])
                continue
            pairs += 1
            before, after = state_of(pending[ni]), state_of(r[ni])
            if before is None or after is None:
                bad.append("REBUILD at %s: no state= in PRESTOP or REBUILD" % r[ti])
            elif before != after:
                only_b = [x for x in before if x not in after]
                only_a = [x for x in after if x not in before]
                bad.append("REBUILD at %s differs: before %s, rebuilt %s" % (r[ti], only_b, only_a))
            else:
                print("  restart at %s: rebuilt state = state before, %d lines" % (r[ti], len(after)))
            pending = None
    if pairs < min_count:
        bad.append("only %d restarts in the log, need %d" % (pairs, min_count))
    for b in bad:
        print("  FAIL " + b)
    if bad:
        print("RESULT: REBUILD MISMATCH (%d problems)" % len(bad))
        return False
    print("RESULT: REBUILDS MATCH (%d of %d)" % (pairs, pairs))
    return True


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("compare")
    c.add_argument("base")
    c.add_argument("restart")
    c.add_argument("--from", dest="from_time", required=True)
    r = sub.add_parser("rebuilds")
    r.add_argument("log")
    r.add_argument("--min", type=int, default=1)
    a = ap.parse_args(argv)
    ok = compare(a.base, a.restart, a.from_time) if a.cmd == "compare" else rebuilds(a.log, a.min)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
