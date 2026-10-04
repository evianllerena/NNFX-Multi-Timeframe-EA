"""Independent recalculation of MT5's standard indicators from an export (Phase 5).

Replaces the by-eye Data Window check. For every candle in an NNFX_ExportBars CSV,
it recalculates from the raw prices in the file:

  * ATR(14)          (the fixed engine ATR)
  * the baseline     if its profile is MT5's Moving Average (simple, close)
  * C1 / C2 / exit   if their profile is MT5's RVI or MACD (close)
  * the volume value if its profile is MT5's Volumes (tick volume)

using the formulas in MT5's own source files, read from the owner's terminal on
2026-10-04 (MQL5\\Indicators\\Examples\\ATR.mq5, RVI.mq5, MACD.mq5 and
MQL5\\Include\\MovingAverages.mqh):

  ATR     TR = max(high, prev close) - min(low, prev close); ATR = simple average of
          the last N TR values (ATR.mq5 keeps a running sum, which is the same average).
  SMA     simple average of the last N closes.
  RVI     main = sum over the last N candles of (c-o + 2(c-o)[1] + 2(c-o)[2] + (c-o)[3])
                 / sum of (h-l + 2(h-l)[1] + 2(h-l)[2] + (h-l)[3]);
          signal = (main + 2 main[1] + 2 main[2] + main[3]) / 6.
  MACD    main = EMA(fast) - EMA(slow) of close, EMA factor 2/(1+period);
          signal = simple average of the last `signal` main values.
  Volumes buffer 0 = the candle's tick volume.

Every value MT5 wrote must equal the recalculated one (to floating-point rounding).
EMA-based values depend on all earlier history, which the export doesn't contain, so
MACD is compared only after a burn-in of 600 candles, by which point any difference in
the starting value has shrunk below 1e-15 of itself.

Usage:  python tools/check_indicators.py path\\to\\EURUSD_H1.csv [more.csv ...]
Exit code 0 = every recalculated value matched; 1 = a mismatch or too few candles.
"""
import argparse
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "tests", "python"))
sys.path.insert(0, os.path.join(ROOT, "tools"))

import check_export  # noqa: E402
from nnfx_ref import signals  # noqa: E402

EMA_BURN_IN = 600
ATR_PERIOD = 14


# ------------------------------------------------------------------ formulas
def sma(values, period, i):
    if i < period - 1:
        return None
    return sum(values[i - period + 1:i + 1]) / period


def atr_series(h, l, c, period):
    tr = [None] + [max(h[i], c[i - 1]) - min(l[i], c[i - 1]) for i in range(1, len(c))]
    out = [None] * len(c)
    for i in range(period, len(c)):
        out[i] = sum(tr[i - period + 1:i + 1]) / period
    return out


def rvi_series(o, h, l, c, period):
    n = len(c)
    co = [c[i] - o[i] for i in range(n)]
    hl = [h[i] - l[i] for i in range(n)]
    main = [None] * n
    for i in range(period + 2, n):
        up = down = 0.0
        ok = True
        for j in range(i, i - period, -1):
            if j - 3 < 0:
                ok = False
                break
            up += co[j] + 2 * co[j - 1] + 2 * co[j - 2] + co[j - 3]
            down += hl[j] + 2 * hl[j - 1] + 2 * hl[j - 2] + hl[j - 3]
        if ok:
            main[i] = up / down if down != 0.0 else up
    sig = [None] * n
    for i in range(3, n):
        if None not in (main[i], main[i - 1], main[i - 2], main[i - 3]):
            sig[i] = (main[i] + 2 * main[i - 1] + 2 * main[i - 2] + main[i - 3]) / 6.0
    return main, sig


def ema_series(values, period):
    k = 2.0 / (1.0 + period)
    out = [values[0]]
    for v in values[1:]:
        out.append(v * k + out[-1] * (1.0 - k))
    return out


def macd_series(c, fast, slow, signal):
    ef, es = ema_series(c, fast), ema_series(c, slow)
    main = [a - b for a, b in zip(ef, es)]
    sig = [sma(main, signal, i) for i in range(len(main))]
    return main, sig


# ------------------------------------------------------------------ comparison
class Result:
    def __init__(self, label, tol):
        self.label, self.tol = label, tol
        self.checked, self.max_diff, self.worst, self.fails = 0, 0.0, None, 0
        self.missing = 0

    def add(self, row, got, want, scale=1.0):
        if want is None:
            return
        if signals.is_bad(got):
            # MT5 wrote no value where the formula gives one. Before the first compared
            # candle this is the indicator's own warm-up; after it, it is a failure.
            if self.checked:
                self.missing += 1
                self.fails += 1
            return
        d = abs(got - want)
        self.checked += 1
        if d > self.max_diff:
            self.max_diff, self.worst = d, (row["time"], got, want)
        if d > self.tol * max(1.0, abs(scale)):
            self.fails += 1

    def line(self, min_checked):
        if self.checked < min_checked:
            status = "FAIL (only %d candles compared, need %d)" % (self.checked, min_checked)
        else:
            status = "PASS" if self.fails == 0 else "FAIL (%d mismatches, %d of them missing values)" % (
                self.fails, self.missing)
        w = "" if not self.worst else "  worst at %s: MT5 %.17g vs %.17g" % self.worst
        return "  %-34s %-6s compared %5d  max diff %.3g%s" % (self.label, status.split()[0], self.checked,
                                                              self.max_diff, "" if status == "PASS" else
                                                              "  <- " + status + w), status == "PASS"


def check(path, profile_dir, min_checked=1000):
    meta, rows = check_export.read_csv(path)
    prof = check_export.load_profiles(meta, profile_dir)
    n = len(rows)
    o = [r["open"] for r in rows]
    h = [r["high"] for r in rows]
    l = [r["low"] for r in rows]
    c = [r["close"] for r in rows]
    results, skipped = [], []

    # ATR (fixed engine machinery)
    res = Result("ATR(%d)" % ATR_PERIOD, 1e-10)
    for i, want in enumerate(atr_series(h, l, c, ATR_PERIOD)):
        res.add(rows[i], rows[i]["atr"], want, c[i])
    results.append(res)

    def inputs(p):
        return [v for _, v in p.inputs]

    # Baseline
    b = prof["BASELINE"]
    if b.source == "builtin" and b.indicator == "MA" and inputs(b)[1:] == ["0", "MODE_SMA", "PRICE_CLOSE"]:
        period = int(inputs(b)[0])
        res = Result("%s (SMA %d)" % (b.name, period), 1e-10)
        for i in range(n):
            res.add(rows[i], rows[i]["base"], sma(c, period, i), c[i])
        results.append(res)
    else:
        skipped.append(b.name)

    # C1, C2, exit
    for slot, key in check_export.SLOT_KEYS:
        p = prof[slot]
        ins = inputs(p)
        cols = {0: key + "_a", 1: key + "_b"}
        bufs = p.buffers()
        series = None
        if p.source == "builtin" and p.indicator == "RVI" and len(ins) == 1:
            series = rvi_series(o, h, l, c, int(ins[0]))
            tol, start, label = 1e-8, 0, "%s (RVI %s)" % (p.name, ins[0])
        elif p.source == "builtin" and p.indicator == "MACD" and len(ins) == 4 and ins[3] == "PRICE_CLOSE":
            series = macd_series(c, int(ins[0]), int(ins[1]), int(ins[2]))
            tol, start, label = 1e-10, EMA_BURN_IN, "%s (MACD %s/%s/%s)" % (p.name, ins[0], ins[1], ins[2])
        if series is None:
            skipped.append(p.name)
            continue
        for k, buf in enumerate(bufs):
            if buf not in (0, 1):
                skipped.append("%s buffer %d" % (p.name, buf))
                continue
            res = Result("%s buffer %d" % (label, buf), tol)
            for i in range(start, n):
                res.add(rows[i], rows[i][cols[k]], series[buf][i], c[i] if tol < 1e-9 else 1.0)
            results.append(res)

    # Volume
    v = prof["VOLUME"]
    if v.source == "builtin" and v.indicator == "VOLUMES" and inputs(v) == ["VOLUME_TICK"] and v.buf_main == 0:
        res = Result("%s (tick volume)" % v.name, 0.0)
        for r in rows:
            res.add(r, r["vol"], r["tickvol"])
        results.append(res)
    else:
        skipped.append(v.name)

    name = os.path.basename(path)
    print("=" * 70)
    print("%s  (%d candles, %s to %s)" % (name, n, rows[0]["time"] if rows else "-", rows[-1]["time"] if rows else "-"))
    all_ok = True
    for res in results:
        text, ok = res.line(min_checked if "MACD" not in res.label else max(1, min_checked - EMA_BURN_IN))
        print(text)
        all_ok &= ok
    for s in skipped:
        print("  %-34s not a standard MT5 indicator with a known formula: not recalculated" % s)
    print("RESULT %s: %s" % (name, "PASS" if all_ok else "FAIL"))
    return all_ok


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("csv", nargs="+")
    ap.add_argument("--profiles", default=os.path.join(ROOT, "profiles"))
    ap.add_argument("--min-checked", type=int, default=1000,
                    help="minimum candles compared per indicator (default 1000)")
    a = ap.parse_args(argv)
    ok = all([check(p, a.profiles, a.min_checked) for p in a.csv])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
