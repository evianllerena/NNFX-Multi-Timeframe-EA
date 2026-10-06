"""Picks the restart times for the simulated restart tests R1-R4 (docs/PLAN_PHASE6.md section 9) from the
STATE rows of a run without a restart (NNFX_OrderTest trade log).

A STATE row is written after each candle is processed and holds the whole memory ("state=" lines). A simulated
restart at candle time T happens before T is processed, so the memory it must rebuild is the STATE row written
at the candle before T. For each state the first STATE row at or after --after that shows it is taken, and the
restart time is the time of the NEXT STATE row:

  R1  a trade with both halves open, TP1 not filled
  R2  TP1 filled, half 2 open, trail not on (stop at breakeven)
  R3  half 2 open with the trail on
  R4  flat (no open trade), continuation armed (waiting for a continuation)

Prints one line per state: "R1 <restart time> <state line(s)>". Exit code 1 if a state never occurs.
Usage:  python tools/pick_restart_times.py BASE.csv [--after "2026.06.10 00:00"]
"""
import argparse
import csv
import sys


def states(path):
    with open(path, encoding="ascii", newline="") as f:
        r = csv.DictReader(f)
        rows = [(row["time"], row["note"]) for row in r if row["event"] == "STATE"]
    out = []
    for t, note in rows:
        s = note.split("state=", 1)[1] if "state=" in note else ""
        lines = [x for x in s.split(" / ") if x]
        trades = [x.split("|") for x in lines if x.startswith("TRADE|")]
        conts = [x.split("|") for x in lines if x.startswith("CONT|")]
        out.append((t, lines, trades, conts))
    return out


def classify(trades, conts):
    found = set()
    for p in trades:
        open1, open2, tp1, trail = p[6] == "1", p[7] == "1", p[14] == "1", p[15] == "1"
        if open1 and open2 and not tp1:
            found.add("R1")
        if tp1 and open2 and not trail:
            found.add("R2")
        if tp1 and open2 and trail:
            found.add("R3")
    if not trades and conts and conts[0][3] == "1":
        found.add("R4")
    return found


def pick(path, after):
    st = states(path)
    picked = {}
    for i in range(len(st) - 1):
        t, lines, trades, conts = st[i]
        if t < after:
            continue
        for r in sorted(classify(trades, conts)):
            if r not in picked:
                picked[r] = (st[i + 1][0], lines)
    return picked


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("base")
    ap.add_argument("--after", default="2026.06.10 00:00")
    a = ap.parse_args(argv)
    picked = pick(a.base, a.after)
    for r in ("R1", "R2", "R3", "R4"):
        if r in picked:
            print("%s %s %s" % (r, picked[r][0], " / ".join(picked[r][1])))
        else:
            print("%s NONE" % r)
    return 0 if len(picked) == 4 else 1


if __name__ == "__main__":
    sys.exit(main())
