"""Tests for tools/check_indicators.py.

A synthetic price history is built and its indicator values are computed here in the
same incremental way MT5's own source files do (running sums, EMA seeded with the first
price of the FULL history). Only the last part of the history is written to the export,
so the checker never sees the start, exactly as with a real MT5 export. A correct file
must pass; each kind of corruption must fail."""
import io
import os
import random
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))

import check_export  # noqa: E402
import check_indicators  # noqa: E402

PROFILES = ["ref_baseline_sma20.txt", "ref_c1_rvi10.txt", "ref_c2_macd_main.txt",
            "ref_exit_macd_cross.txt", "ref_volume_ticks20.txt"]
HISTORY, EXPORT = 3200, 2000


def mt5_like(n, seed=7):
    """Prices plus indicator values, computed the way MT5's example sources do."""
    rnd = random.Random(seed)
    o, h, l, c, tv = [], [], [], [], []
    price = 1.1000
    for _ in range(n):
        # Gaps between candles (open != previous close) so ATR's true range differs from high - low
        op = price + rnd.gauss(0, 0.0004)
        cl = max(0.5, op + rnd.gauss(0, 0.0015))
        hi = max(op, cl) + abs(rnd.gauss(0, 0.0007))
        lo = min(op, cl) - abs(rnd.gauss(0, 0.0007))
        o.append(op), h.append(hi), l.append(lo), c.append(cl), tv.append(rnd.randint(200, 5000))
        price = cl
    # ATR.mq5: running sum of TR
    atr = [None] * n
    tr = [0.0] + [max(h[i], c[i - 1]) - min(l[i], c[i - 1]) for i in range(1, n)]
    run = sum(tr[1:15])
    atr[14] = run / 14
    for i in range(15, n):
        atr[i] = atr[i - 1] + (tr[i] - tr[i - 14]) / 14
    # SMA 20, running sum
    sma = [None] * n
    s = sum(c[:20])
    sma[19] = s / 20
    for i in range(20, n):
        s += c[i] - c[i - 20]
        sma[i] = s / 20
    # RVI.mq5, period 10
    rvi, sig = [None] * n, [None] * n
    for i in range(12, n):
        up = sum(c[j] - o[j] + 2 * (c[j - 1] - o[j - 1]) + 2 * (c[j - 2] - o[j - 2]) + c[j - 3] - o[j - 3]
                 for j in range(i, i - 10, -1))
        dn = sum(h[j] - l[j] + 2 * (h[j - 1] - l[j - 1]) + 2 * (h[j - 2] - l[j - 2]) + h[j - 3] - l[j - 3]
                 for j in range(i, i - 10, -1))
        rvi[i] = up / dn if dn else up
    for i in range(15, n):
        sig[i] = (rvi[i] + 2 * rvi[i - 1] + 2 * rvi[i - 2] + rvi[i - 3]) / 6
    # MACD 12/26/9: EMAs seeded with the first price of the whole history
    def ema(p):
        k, out = 2 / (1 + p), [c[0]]
        for v in c[1:]:
            out.append(v * k + out[-1] * (1 - k))
        return out
    f, sl = ema(12), ema(26)
    main = [a - b for a, b in zip(f, sl)]
    msig = [None] * n
    for i in range(8, n):
        msig[i] = sum(main[i - 8:i + 1]) / 9
    return dict(o=o, h=h, l=l, c=c, tv=tv, atr=atr, sma=sma, rvi=rvi, sig=sig, main=main, msig=msig)


def make_rows():
    d = mt5_like(HISTORY)
    rows = []
    for i in range(HISTORY - EXPORT, HISTORY):
        rows.append(["T%06d" % i, repr(d["o"][i]), repr(d["h"][i]), repr(d["l"][i]), repr(d["c"][i]),
                     str(d["tv"][i]), repr(d["atr"][i]), repr(d["sma"][i]), repr(d["rvi"][i]), repr(d["sig"][i]),
                     repr(d["main"][i]), "empty", repr(d["main"][i]), repr(d["msig"][i]), repr(float(d["tv"][i])),
                     "empty", "0", "0", "0", "0", "1", ""])
    return rows


def run(rows, min_checked=1000):
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "TEST_H1.csv")
        with open(path, "w", encoding="ascii", newline="") as fh:
            fh.write("# symbol=TEST timeframe=H1 profiles=%s atr=14 build=0\r\n" % ",".join(PROFILES))
            fh.write(",".join(check_export.COLUMNS) + "\r\n")
            for r in rows:
                fh.write(",".join(r) + "\r\n")
        buf = io.StringIO()
        with redirect_stdout(buf):
            ok = check_indicators.check(path, os.path.join(ROOT, "profiles"), min_checked)
        return ok, buf.getvalue()


COL = {name: k for k, name in enumerate(check_export.COLUMNS)}


class TestCheckIndicators(unittest.TestCase):
    def test_correct_export_passes(self):
        ok, out = run(make_rows())
        self.assertTrue(ok, out)
        for label in ("ATR(14)", "SMA 20", "RVI 10", "MACD 12/26/9", "tick volume"):
            self.assertIn(label, out)
        self.assertNotIn("not recalculated", out)

    def test_each_value_corrupted_fails(self):
        for col in ("atr", "base", "c1_a", "c1_b", "c2_a", "ex_a", "ex_b", "vol"):
            with self.subTest(col=col):
                rows = make_rows()
                k = COL[col]
                rows[1500][k] = repr(float(rows[1500][k]) * (1 + 1e-6) + 1e-9)
                ok, out = run(rows)
                self.assertFalse(ok, out)
                self.assertIn("mismatches", out)

    def test_missing_value_mid_file_fails(self):
        rows = make_rows()
        rows[1200][COL["c1_a"]] = "empty"
        ok, out = run(rows)
        self.assertFalse(ok)
        self.assertIn("missing values", out)

    def test_wrong_ema_seeding_too_close_fails(self):
        """MACD values that only agree after a short history must not pass: the
        checker skips 600 candles, so a 50-candle-old EMA start shows up."""
        d = mt5_like(HISTORY)
        rows = make_rows()
        c = d["c"]
        start = HISTORY - EXPORT + 700   # EMA started late: differs inside the compared range
        k12, k26 = 2 / 13, 2 / 27
        f = s = c[start]
        for i in range(start, HISTORY):
            if i > start:
                f = c[i] * k12 + f * (1 - k12)
                s = c[i] * k26 + s * (1 - k26)
            r = i - (HISTORY - EXPORT)
            rows[r][COL["c2_a"]] = repr(f - s)
        ok, out = run(rows)
        self.assertFalse(ok, out)

    def test_too_few_candles_fails(self):
        ok, out = run(make_rows()[:900])
        self.assertFalse(ok)
        self.assertIn("only", out)

    def test_volume_must_be_exact(self):
        rows = make_rows()
        rows[1000][COL["vol"]] = repr(float(rows[1000][COL["vol"]]) + 1)
        ok, out = run(rows)
        self.assertFalse(ok)


if __name__ == "__main__":
    unittest.main()
