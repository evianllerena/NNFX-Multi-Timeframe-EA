"""Check an NNFX_ExportBars CSV against the Python answer key (Phase 5).

For every candle it recomputes, from the raw values in the file:
  * C1, C2 and exit directions (nnfx_ref.profiles.direction)
  * the volume reference (average of the previous N readings) and pass / fail
and requires them to equal what the MQL5 slot layer wrote. It also checks the
candles themselves (time order, high/low sane, ATR positive), flags indicators
that never change direction, and prints sample rows for the Data Window check.

Usage (from the repo root):
    python tools/check_export.py path\\to\\EURUSD_H1.csv [more.csv ...] [--replay]

Exit code 0 = every check passed; 1 = at least one failure (details printed).
Standard library only.
"""
import argparse
import math
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "tests", "python"))

from nnfx_ref import profiles as P  # noqa: E402
from nnfx_ref import signals  # noqa: E402

COLUMNS = ["time", "open", "high", "low", "close", "tickvol", "atr", "base", "c1_a", "c1_b", "c2_a", "c2_b",
           "ex_a", "ex_b", "vol", "vol_ref", "c1", "c2", "ex", "vol_pass", "ok", "why"]
NUMERIC = [c for c in COLUMNS[1:16]]
SLOT_KEYS = [("C1", "c1"), ("C2", "c2"), ("EXIT", "ex")]


def tok(text):
    t = text.strip()
    if t == "nan":
        return float("nan")
    if t == "empty":
        return signals.EMPTY_VALUE
    return float(t)


def read_csv(path):
    meta, rows = {}, []
    with open(path, encoding="ascii") as f:
        lines = [ln.rstrip("\r\n") for ln in f]
    i = 0
    while i < len(lines) and lines[i].startswith("#"):
        for part in lines[i][1:].split():
            if "=" in part:
                k, v = part.split("=", 1)
                meta[k] = v
        i += 1
    if i >= len(lines) or lines[i].split(",") != COLUMNS:
        raise SystemExit("%s: unexpected header (is this an NNFX_ExportBars file?)" % path)
    for n, ln in enumerate(lines[i + 1:], i + 2):
        if not ln:
            continue
        parts = ln.split(",")
        if len(parts) != len(COLUMNS):
            raise SystemExit("%s line %d: expected %d columns, got %d" % (path, n, len(COLUMNS), len(parts)))
        r = dict(zip(COLUMNS, parts))
        for k in NUMERIC:
            r[k] = tok(r[k])
        for k in ("c1", "c2", "ex", "vol_pass", "ok"):
            r[k] = int(r[k])
        r["line"] = n
        rows.append(r)
    return meta, rows


def load_profiles(meta, profile_dir):
    names = meta.get("profiles", "").split(",")
    if len(names) != 5:
        raise SystemExit("file header does not list 5 profiles")
    loaded = [P.load(os.path.join(profile_dir, n)) for n in names]
    want = ["BASELINE", "C1", "C2", "EXIT", "VOLUME"]
    for p, w in zip(loaded, want):
        if p.slot != w:
            raise SystemExit("profile %s is %s, expected %s" % (p.name, p.slot, w))
    return dict(zip(want, loaded))


def close_enough(a, b):
    return abs(a - b) <= 1e-9 * max(1.0, abs(a), abs(b))


def check(path, profile_dir, replay=False):
    meta, rows = read_csv(path)
    prof = load_profiles(meta, profile_dir)
    fails, warns = [], []
    name = os.path.basename(path)

    def fail(r, msg):
        fails.append("line %d (%s): %s" % (r["line"], r["time"], msg))

    prev_time, seen_ok = None, False
    vol_p = prof["VOLUME"]
    for idx, r in enumerate(rows):
        # Candles
        if prev_time is not None and r["time"] <= prev_time:
            fail(r, "time not after previous row (%s)" % prev_time)
        prev_time = r["time"]
        o, h, l, c = r["open"], r["high"], r["low"], r["close"]
        if min(o, h, l, c) <= 0 or l > min(o, c) + 1e-12 or h < max(o, c) - 1e-12:
            fail(r, "impossible candle o=%s h=%s l=%s c=%s" % (o, h, l, c))
        warm = {s for s in ("BASELINE", "C1", "C2", "EXIT", "VOLUME") if s + ":warmup" in r["why"]}
        if r["ok"]:
            seen_ok = True
            if signals.is_bad(r["atr"]) or r["atr"] <= 0:
                fail(r, "ok row with bad ATR %s" % r["atr"])
            if signals.is_bad(r["base"]):
                fail(r, "ok row with bad baseline value")
        elif seen_ok and warm:
            fail(r, "warm-up reported after usable rows: %s" % r["why"])

        # Directions
        for slot, key in SLOT_KEYS:
            p = prof[slot]
            vals = [r[key + "_a"], r[key + "_b"]]
            expect = 0 if slot in warm else P.direction(p, vals[:len(p.buffers())])
            if r[key] != expect:
                fail(r, "%s direction: MQL5 wrote %d, Python computes %d from %s" % (slot, r[key], expect, vals))

        # Volume
        if "VOLUME" in warm:
            if r["vol_pass"] != 0:
                fail(r, "volume passes during warm-up")
            continue
        if vol_p.vol_rule == "average":
            n = vol_p.vol_period
            if idx < n:
                continue          # previous readings are not in the file
            hist = [rows[k]["vol"] for k in range(idx - n, idx)]
            if any(signals.is_bad(x) for x in hist):
                exp_pass = False
                if not signals.is_bad(r["vol_ref"]):
                    fail(r, "volume reference should be missing (bad history)")
            else:
                avg = sum(hist) / n
                if signals.is_bad(r["vol_ref"]) or not close_enough(r["vol_ref"], avg):
                    fail(r, "volume average: MQL5 %s, Python %s" % (r["vol_ref"], avg))
                exp_pass = P.volume_passes(vol_p, r["vol"], history=hist)
                if not signals.is_bad(r["vol"]) and close_enough(r["vol"], vol_p.vol_mult * avg):
                    warns.append("line %d: volume exactly at the threshold (rounding could decide)" % r["line"])
                    continue
        elif vol_p.vol_rule == "level":
            exp_pass = P.volume_passes(vol_p, r["vol"])
        else:
            exp_pass = P.volume_passes(vol_p, r["vol"], other=r["vol_ref"])
        if r["vol_pass"] != int(exp_pass):
            fail(r, "volume pass: MQL5 wrote %d, Python computes %d" % (r["vol_pass"], int(exp_pass)))

    usable = [r for r in rows if r["ok"]]
    for slot, key in SLOT_KEYS + [("VOLUME", "vol_pass")]:
        vals = {r[key] for r in usable}
        if usable and len(vals) == 1:
            warns.append("%s never changes (always %s) over %d usable rows: check the profile/buffers"
                         % (slot, vals.pop(), len(usable)))

    print("=" * 70)
    print("%s  (%s %s, profiles %s)" % (name, meta.get("symbol"), meta.get("timeframe"), meta.get("profiles")))
    print("rows: %d   usable: %d   first: %s   last: %s" % (
        len(rows), len(usable), rows[0]["time"] if rows else "-", rows[-1]["time"] if rows else "-"))
    if usable:
        for slot, key in SLOT_KEYS:
            ls = sum(1 for r in usable if r[key] == 1)
            ss = sum(1 for r in usable if r[key] == -1)
            print("  %-4s long %5.1f%%  short %5.1f%%  none %5.1f%%" % (
                slot, 100.0 * ls / len(usable), 100.0 * ss / len(usable),
                100.0 * (len(usable) - ls - ss) / len(usable)))
        vp = sum(r["vol_pass"] for r in usable)
        print("  VOL  passes %5.1f%%" % (100.0 * vp / len(usable)))
        print("Data Window samples (compare these in MT5):")
        for r in (usable[0], usable[len(usable) // 2], usable[-1]):
            print("  %s  close=%s  ATR=%s" % (r["time"], r["close"], r["atr"]))
            print("      %s=%s" % (prof["BASELINE"].name, r["base"]))
            for slot, key in SLOT_KEYS:
                bufs = prof[slot].buffers()
                vals = [r[key + "_a"], r[key + "_b"]][:len(bufs)]
                print("      %s buffers %s = %s" % (prof[slot].name, bufs, vals))
            print("      %s buffer %s = %s" % (vol_p.name, vol_p.buf_main, r["vol"]))
    for w in warns[:20]:
        print("WARN " + w)
    for f_ in fails[:50]:
        print("FAIL " + f_)
    if len(fails) > 50:
        print("... %d more failures" % (len(fails) - 50))

    if replay and usable:
        from nnfx_ref.core import PairCore
        core = PairCore(meta.get("symbol", "?"))
        for r in usable:
            core.on_bar({"t": r["time"], "o": r["open"], "h": r["high"], "l": r["low"], "c": r["close"],
                         "atr": r["atr"], "base": r["base"], "c1": r["c1"], "c2": r["c2"], "ex": r["ex"],
                         "vol": bool(r["vol_pass"]), "block": [], "news": False})
        counts = {}
        for e in core.events:
            k = e["event"] + ":" + e["rule"]
            counts[k] = counts.get(k, 0) + 1
        print("Replay through the Python rules core (sanity only, not pass/fail):")
        print("  " + ", ".join("%s=%d" % kv for kv in sorted(counts.items())))
        rs = [t["r"] for t in core.closed_trades]
        if rs:
            print("  closed trades: %d   total %.2fR   (reference indicators: not a performance result)"
                  % (len(rs), sum(rs)))
    print("RESULT %s: %s (%d failures, %d warnings)" % (name, "PASS" if not fails else "FAIL",
                                                      len(fails), len(warns)))
    return not fails


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("csv", nargs="+")
    ap.add_argument("--profiles", default=os.path.join(ROOT, "profiles"))
    ap.add_argument("--replay", action="store_true", help="also replay usable rows through the rules core")
    a = ap.parse_args(argv)
    ok = all([check(p, a.profiles, a.replay) for p in a.csv])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
