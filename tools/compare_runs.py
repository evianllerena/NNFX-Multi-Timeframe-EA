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
           every REBUILD row's state is the same, field for field (the lines after "state=", split on
           " / "), as the state just before the restart: the PRESTOP row if the EA wrote one, else (a hard
           kill: OnDeinit never ran) the last STATE row before it. Each restart line says which. The EA's
           own "match=" flag is not trusted: the comparison is redone here.
           -> RESULT: REBUILDS MATCH (<n> of <n>)   or   RESULT: REBUILD MISMATCH (...)

  --fallback-ids (both commands; "deal history only" restarts, G1_phase6c_1 F3)
           With no order comments and no state file, the rebuild cannot know the old trade ID. It uses the
           documented fallback ID "R" + half 1's position ticket (State.mqh, recovery.py) and logs
           "fallback id R54 = positions 54+55" in the REBUILD note. compare: trade IDs in both runs are
           replaced by "pos<half 1 ticket>" before comparing (base IDs from the OPEN rows of half 1; "R<n>" IDs
           -> pos<n>), in the trade_id column and in the TRADE lines of state=. rebuilds: a TRADE line may
           differ in its ID only, and only if the rebuilt ID is "R" + its half-1 position AND the note logs it.

Usage:  python tools/compare_runs.py compare BASE.csv RESTART.csv --from TIME [--fallback-ids]
        python tools/compare_runs.py rebuilds LOG.csv [--min N] [--fallback-ids]
Exit code 0 = PASS.
"""
import argparse
import csv
import os
import re
import sys

SKIP = ("PRESTOP", "REBUILD", "INFO")


def read(path):
    with open(path, encoding="ascii", newline="") as f:
        r = csv.reader(f)
        header = next(r)
        return header, [row for row in r]


_TRADE_ID = re.compile(r"TRADE\|([^|]+)\|")


def normalise_ids(header, rows):
    """Trade IDs -> "pos<half 1 ticket>" (see --fallback-ids)."""
    ti, hi, ki, ni = header.index("trade_id"), header.index("half"), header.index("ticket"), header.index("note")
    ei = header.index("event")
    pos1 = {}
    for r in rows:
        if r[ei] == "OPEN" and r[hi] == "1" and r[ti]:
            pos1.setdefault(r[ti], r[ki])

    def key(tid):
        if tid in pos1:
            return "pos" + pos1[tid]
        if re.fullmatch(r"R\d+", tid):
            return "pos" + tid[1:]
        return tid

    out = []
    for r in rows:
        r = list(r)
        if r[ti]:
            r[ti] = key(r[ti])
        r[ni] = _TRADE_ID.sub(lambda m: "TRADE|%s|" % key(m.group(1)), r[ni])
        out.append(r)
    return out


def compare(base_path, restart_path, from_time, fallback_ids=False):
    hb, rb = read(base_path)
    hr, rr = read(restart_path)
    if hb != hr:
        print("RESULT: DIFFERENT (headers differ)")
        return False
    if fallback_ids:
        rb, rr = normalise_ids(hb, rb), normalise_ids(hr, rr)
        print("trade IDs compared as pos<half 1 ticket> (--fallback-ids)")
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


def fallback_ok(b, a, note):
    """A TRADE line that differs only in its ID: allowed if the rebuilt ID is "R" + half 1's position and the
    REBUILD note logs that mapping. Returns the mapping text or None."""
    fb, fa = b.split("|"), a.split("|")
    if len(fb) != len(fa) or len(fb) < 6 or fb[0] != "TRADE" or fb[2:] != fa[2:] or fb[1] == fa[1]:
        return None
    if fa[1] != "R" + fa[4]:
        return None
    logged = "fallback id %s = positions %s+%s" % (fa[1], fa[4], fa[5])
    return "%s -> %s" % (fb[1], fa[1]) if logged in note else None


def rebuilds(path, min_count=1, fallback_ids=False):
    h, rows = read(path)
    ei, ni, ti = h.index("event"), h.index("note"), h.index("time")
    pairs, bad, pending = 0, [], None
    for r in rows:
        if r[ei] in ("PRESTOP", "STATE"):
            pending = r
        elif r[ei] == "REBUILD":
            if pending is None:
                bad.append("REBUILD at %s without a PRESTOP or STATE row before it" % r[ti])
                continue
            pairs += 1
            src = "PRESTOP" if pending[ei] == "PRESTOP" else "last STATE row %s, no PRESTOP: hard stop" % pending[ti]
            before, after = state_of(pending[ni]), state_of(r[ni])
            maps = []
            if (fallback_ids and before is not None and after is not None and before != after
                    and len(before) == len(after)):
                rest = []
                for x, y in zip(sorted(before), sorted(after, key=lambda s: s.split("|")[2:])):
                    m = fallback_ok(x, y, r[ni]) if x != y else None
                    if m:
                        maps.append(m)
                    elif x != y:
                        rest.append((x, y))
                if not rest:
                    before = after
            if before is None or after is None:
                bad.append("REBUILD at %s: no state= in the row before it or in REBUILD" % r[ti])
            elif before != after:
                only_b = [x for x in before if x not in after]
                only_a = [x for x in after if x not in before]
                bad.append("REBUILD at %s differs from %s: before %s, rebuilt %s" % (r[ti], src, only_b, only_a))
            else:
                print("  restart at %s: rebuilt state = state before (%s), %d lines%s"
                      % (r[ti], src, len(after), "; fallback IDs " + ", ".join(maps) if maps else ""))
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
    c.add_argument("--fallback-ids", action="store_true")
    r = sub.add_parser("rebuilds")
    r.add_argument("log")
    r.add_argument("--min", type=int, default=1)
    r.add_argument("--fallback-ids", action="store_true")
    a = ap.parse_args(argv)
    ok = (compare(a.base, a.restart, a.from_time, a.fallback_ids) if a.cmd == "compare"
          else rebuilds(a.log, a.min, a.fallback_ids))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
