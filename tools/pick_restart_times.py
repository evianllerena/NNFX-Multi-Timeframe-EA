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

Two more for the restart cases of G1_review2_1 F1/F2, each run with a test hook on ONE trade (NNFX_OrderTest), so
the run is identical to this one up to that trade:

  R5  the R2 trade with InpBeHoldOn = its number: every breakeven move refused until the restart, at R2's time
  R6  the first trade opened at or after --after, with InpAbortHoldOn = its number: half 2 fails (ABORT) and half 1's
      close is refused until the restart, at the candle after its OPEN

Prints one line per state: "R1 <restart time> <state line(s)>"; for R5/R6 "R5 <restart time> trade <id>".
Exit code 1 if a state never occurs.
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


def pick_cases(path, after, picked):
    """R5 and R6: {name: (restart time, trade id)}."""
    out = {}
    if "R2" in picked:
        for x in picked["R2"][1]:
            p = x.split("|")
            if p[0] == "TRADE" and p[7] == "1" and p[14] == "1" and p[15] == "0":
                out["R5"] = (picked["R2"][0], p[1])
                break
    with open(path, encoding="ascii", newline="") as f:
        rows = list(csv.DictReader(f))
    first = next((r for r in rows if r["event"] == "OPEN" and r["half"] == "1" and r["time"] >= after), None)
    if first is not None:
        nxt = next((r["time"] for r in rows if r["event"] == "STATE" and r["time"][:16] > first["time"][:16]), None)
        if nxt:
            out["R6"] = (nxt, first["trade_id"])
    return out


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
    cases = pick_cases(a.base, a.after, picked)
    for r in ("R5", "R6"):
        if r in cases:
            print("%s %s trade %s" % (r, cases[r][0], cases[r][1]))
        else:
            print("%s NONE" % r)
    return 0 if len(picked) == 4 and len(cases) == 2 else 1


if __name__ == "__main__":
    sys.exit(main())
