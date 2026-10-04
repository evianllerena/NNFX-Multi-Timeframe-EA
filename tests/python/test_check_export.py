"""Tests for tools/check_export.py: a correct export passes, and each kind of
corruption it is meant to catch makes it fail."""
import io
import math
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))

import check_export  # noqa: E402
from nnfx_ref import profiles as P, signals  # noqa: E402

PROFILES = ["ref_baseline_sma20.txt", "ref_c1_rvi10.txt", "ref_c2_macd_main.txt",
            "ref_exit_macd_cross.txt", "ref_volume_ticks20.txt"]


def num(v):
    if signals.is_bad(v):
        return "nan" if (v != v) else "empty"
    return repr(float(v))


def make_rows(n=80, warm=5):
    """A synthetic export whose directions are computed exactly as MQL5 should."""
    prof = [P.load(os.path.join(ROOT, "profiles", f)) for f in PROFILES]
    vol_p = prof[4]
    rows = []
    vols = []
    for i in range(n):
        c = 1.1000 + 0.002 * math.sin(i / 5.0)
        o = c - 0.0003
        h, l = max(o, c) + 0.0005, min(o, c) - 0.0005
        base = 1.1000 + 0.001 * math.sin(i / 9.0)
        rvi_m, rvi_s = math.sin(i / 3.0) * 0.2, math.sin((i - 1) / 3.0) * 0.2
        macd_m, macd_s = math.sin(i / 4.0) * 0.0005, math.sin((i - 2) / 4.0) * 0.0005
        vol = 100 + 40 * math.sin(i / 2.0)
        vols.append(vol)
        is_warm = i < warm
        why = "BASELINE:warmup;C1:warmup;C2:warmup;EXIT:warmup;VOLUME:warmup" if is_warm else ""
        c1 = 0 if is_warm else P.direction(prof[1], [rvi_m, rvi_s])
        c2 = 0 if is_warm else P.direction(prof[2], [macd_m])
        ex = 0 if is_warm else P.direction(prof[3], [macd_m, macd_s])
        if i >= vol_p.vol_period:
            hist = vols[i - vol_p.vol_period:i]
            ref = sum(hist) / len(hist)
            vp = 0 if is_warm else int(P.volume_passes(vol_p, vol, history=hist))
        else:
            ref, vp = signals.EMPTY_VALUE, 0
        ok = 0 if is_warm else 1
        rows.append(["2026.09.%02d %02d:00" % (1 + i // 24, i % 24), num(o), num(h), num(l), num(c),
                     num(0.0012), num(base), num(rvi_m), num(rvi_s), num(macd_m), "empty",
                     num(macd_m), num(macd_s), num(vol), num(ref), str(c1), str(c2), str(ex),
                     str(vp), str(ok), why])
    return rows


def write(rows, folder):
    path = os.path.join(folder, "TEST_H1.csv")
    with open(path, "w", encoding="ascii", newline="") as f:
        f.write("# symbol=TEST timeframe=H1 profiles=%s atr=14 build=0\r\n" % ",".join(PROFILES))
        f.write(",".join(check_export.COLUMNS) + "\r\n")
        for r in rows:
            f.write(",".join(r) + "\r\n")
    return path


def run(rows):
    with tempfile.TemporaryDirectory() as d:
        path = write(rows, d)
        buf = io.StringIO()
        with redirect_stdout(buf):
            ok = check_export.check(path, os.path.join(ROOT, "profiles"), replay=True)
        return ok, buf.getvalue()


class TestCheckExport(unittest.TestCase):
    def test_correct_export_passes(self):
        ok, out = run(make_rows())
        self.assertTrue(ok, out)
        self.assertIn("RESULT TEST_H1.csv: PASS", out)
        self.assertIn("Data Window samples", out)

    def test_wrong_direction_fails(self):
        rows = make_rows()
        rows[40][15] = str(-int(rows[40][15]) if rows[40][15] != "0" else 1)
        ok, out = run(rows)
        self.assertFalse(ok)
        self.assertIn("C1 direction", out)

    def test_wrong_volume_average_fails(self):
        rows = make_rows()
        rows[50][14] = repr(float(rows[50][14]) * 1.01)
        ok, out = run(rows)
        self.assertFalse(ok)
        self.assertIn("volume average", out)

    def test_time_out_of_order_fails(self):
        rows = make_rows()
        rows[30][0], rows[31][0] = rows[31][0], rows[30][0]
        ok, out = run(rows)
        self.assertFalse(ok)
        self.assertIn("time not after previous row", out)

    def test_impossible_candle_fails(self):
        rows = make_rows()
        rows[35][2] = repr(float(rows[35][4]) - 0.01)   # high below close
        ok, out = run(rows)
        self.assertFalse(ok)
        self.assertIn("impossible candle", out)

    def test_signal_on_warmup_row_fails(self):
        rows = make_rows()
        rows[2][17] = "1"
        ok, out = run(rows)
        self.assertFalse(ok)
        self.assertIn("EXIT direction", out)

    def test_constant_indicator_is_flagged(self):
        rows = make_rows()
        for r in rows[5:]:
            r[16] = "1"
            r[9] = "0.001"     # C2 value always above centre -> always long
        ok, out = run(rows)
        self.assertTrue(ok, out)
        self.assertIn("C2 never changes", out)


if __name__ == "__main__":
    unittest.main()
