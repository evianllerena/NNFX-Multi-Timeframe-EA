"""Tests for tools/check_replay.py (Phase 7, SPEC Check 1b).

A decision log is generated here by the answer key itself over a seeded random walk (two pairs, warm-up file
included), so its replay must match exactly. Each corruption must fail: a changed event, a dropped event, an event
on a candle that was not fed, a missing warm-up file, a time going backwards, and settings that differ from the run's."""
import csv
import io
import os
import random
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, HERE)

import check_replay  # noqa: E402
from nnfx_ref.core import PairCore  # noqa: E402
from nnfx_ref.settings import Settings  # noqa: E402


def synthetic(seed, n, settings):
    """(warm-up rows, log rows) for two pairs, events written by the answer key."""
    rnd = random.Random(seed)
    out = {"warm": [], "log": []}
    for sym in ("EURUSD", "AUDNZD"):
        core = PairCore(sym, Settings(**vars(settings)))
        price, base = 1.1, 1.1
        c1 = c2 = ex = 1
        for i in range(n):
            o = price
            c = o + rnd.gauss(0, 0.002)
            h, l = max(o, c) + abs(rnd.gauss(0, 0.001)), min(o, c) - abs(rnd.gauss(0, 0.001))
            base = base + 0.2 * (c - base)
            for _ in range(1):
                if rnd.random() < 0.15:
                    c1 = -c1
                if rnd.random() < 0.15:
                    c2 = -c2
                if rnd.random() < 0.2:
                    ex = -ex
            vol = rnd.random() < 0.8
            warm = i < 40
            block = ["start"] if warm else (["drawdown"] if rnd.random() < 0.05 else [])
            news = (not warm) and rnd.random() < 0.02
            t = "2026.01.%02d %02d:00" % (1 + i // 24, i % 24)
            bar = {"t": t, "o": o, "h": h, "l": l, "c": c, "atr": 0.002, "base": base, "c1": c1, "c2": c2, "ex": ex,
                   "vol": vol, "block": block, "news": news}
            evs = check_replay.events_text(core.on_bar(bar))
            out["warm" if warm else "log"].append({
                "time": t, "symbol": sym, "tf": "H1", "o": repr(o), "h": repr(h), "l": repr(l), "c": repr(c),
                "atr": "0.002", "base": repr(base), "c1": str(c1), "c2": str(c2), "ex": str(ex), "vol": "1" if vol else "0",
                "ind_ok": "1", "block": ";".join(block) or "-", "news": "1" if news else "0", "events": evs or "-",
                "action": "-", "note": "warm-up" if warm else "-"})
            price = c
    return out["warm"], out["log"]


def write(path, rows):
    with open(path, "w", encoding="ascii", newline="") as f:
        w = csv.DictWriter(f, fieldnames=check_replay.HEADER, lineterminator="\r\n")
        w.writeheader()
        w.writerows(sorted(rows, key=lambda r: (r["time"], r["symbol"])))


def run(warm, log, settings, with_warm=True):
    with tempfile.TemporaryDirectory() as tmp:
        dp, wp = os.path.join(tmp, "decisions.csv"), os.path.join(tmp, "decisions_warmup.csv")
        write(dp, log)
        write(wp, warm)
        buf = io.StringIO()
        with redirect_stdout(buf):
            ok = check_replay.replay(dp, wp if with_warm else None, settings)
        return ok, buf.getvalue()


class TestCheckReplay(unittest.TestCase):
    S = Settings()

    def setUp(self):
        self.warm, self.log = synthetic(7, 600, self.S)
        self.with_events = [r for r in self.log if r["events"] != "-"]

    def test_generated_log_has_entries_and_exits(self):
        text = ";".join(r["events"] for r in self.log)
        for ev in ("ENTER:", "OPEN:", "SKIP:", "PENDING:"):
            self.assertIn(ev, text)

    def test_exact_replay_passes(self):
        ok, out = run(self.warm, self.log, self.S)
        self.assertTrue(ok, out)
        self.assertIn("PASS (0 mismatches over 1120 compared candles)", out)

    def test_changed_event_fails(self):
        r = self.with_events[len(self.with_events) // 2]
        r["events"] = r["events"].replace(":1", ":-1", 1) if ":1" in r["events"] else r["events"].replace(":-1", ":1", 1)
        ok, out = run(self.warm, self.log, self.S)
        self.assertFalse(ok, out)
        self.assertIn("MISMATCH", out)

    def test_dropped_event_fails(self):
        self.with_events[3]["events"] = "-"
        ok, out = run(self.warm, self.log, self.S)
        self.assertFalse(ok, out)

    def test_event_on_unfed_candle_fails(self):
        r = self.log[100]
        r["ind_ok"] = "0"
        r["events"] = "SKIP:E1:1"
        ok, out = run(self.warm, self.log, self.S)
        self.assertFalse(ok, out)
        self.assertIn("not fed (ind_ok 0) but the EA logged events", out)

    def test_no_warmup_is_never_pass(self):
        ok, out = run(self.warm, self.log, self.S, with_warm=False)
        self.assertFalse(ok, out)
        self.assertIn("no warm-up file", out)

    def test_time_backwards_fails(self):
        eur = [r for r in self.log if r["symbol"] == "EURUSD"]
        eur[200]["time"] = eur[100]["time"]
        ok, out = run(self.warm, self.log, self.S)
        self.assertFalse(ok, out)
        self.assertIn("not after", out)

    def test_other_settings_fail(self):
        ok, out = run(self.warm, self.log, Settings(trail_on=False, continuation="off", btf_bars=2))
        self.assertFalse(ok, out)

    def test_inputs_map_to_settings(self):
        s = check_replay.settings_from_inputs(check_replay.parse_inputs(
            "inputs: InpMagic=26060 InpTrailOn=false InpRunnerCap=0.0 InpBridgeBars=5 InpContinuation=b InpRiskPct=2.0"))
        self.assertFalse(s.trail_on)
        self.assertIsNone(s.runner_cap_atr)
        self.assertEqual(s.btf_bars, 5)
        self.assertEqual(s.continuation, "b")
        self.assertEqual(check_replay.settings_from_inputs({"InpRunnerCap": "2"}).runner_cap_atr, 2.0)


if __name__ == "__main__":
    unittest.main()
