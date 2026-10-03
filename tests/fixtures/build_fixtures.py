"""Builds the JSON rule fixtures in this folder.

Every expectation below was worked out by hand from docs/RULEBOOK.md and the
interpretations in tests/python/README.md, NOT copied from the engine's output.
The JSON files are what both the Python answer key and (Phase 4) the MQL5 test
scripts run, so the two are checked against identical cases.

Run:  python tests/fixtures/build_fixtures.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ALL = ["ENTER", "EXIT", "SKIP", "PENDING", "OPEN", "CLOSE",
       "SL", "TP1", "MOVE_BE", "BE_SL", "TRAIL", "TRAIL_SL", "TP2"]
DEC = ["ENTER", "EXIT", "SKIP", "PENDING"]

FIXTURES = []


def b(c, c1=0, c2=0, ex=0, vol=True, base=100.0, atr=1.0, o=None, h=None, l=None,
      block=None, news=False):
    """One closed candle. Default range is +/-0.05 around the close, so stops and
    targets are only touched where a fixture says so."""
    o = c if o is None else o
    h = max(o, c) + 0.05 if h is None else h
    l = min(o, c) - 0.05 if l is None else l
    if not (l <= min(o, c) and h >= max(o, c)):
        raise ValueError("impossible candle o=%s h=%s l=%s c=%s" % (o, h, l, c))
    return {"o": o, "h": h, "l": l, "c": c, "atr": atr, "base": base,
            "c1": c1, "c2": c2, "ex": ex, "vol": vol, "block": block or [], "news": news}


def fx(name, rule, description, bars, expect, check=None, settings=None, expect_r=None):
    for i, bar in enumerate(bars):
        bar["t"] = i
    item = {"name": name, "rule": rule, "description": description,
            "settings": settings or {}, "check": check or DEC, "bars": bars, "expect": expect}
    if expect_r is not None:
        item["expect_r"] = expect_r
    FIXTURES.append(item)


# A long trade opened by E1: decided at bar 1, opened at bar 2's open (100.5).
# Stop 99.0 (1.5 ATR), TP1 101.5 (1 ATR).
def long_entry():
    return [b(100.3, c1=-1, c2=1), b(100.4, c1=1, c2=1), b(100.5, c1=1, c2=1)]


ENTRY_EV = [[1, "ENTER", "E1", 1], [2, "OPEN", "E1", 1]]

# ---------------------------------------------------------------- E0 / warm-up
fx("E0_first_candle_is_warmup", "E0",
   "No signal can be fresh on the first candle: C1 and C2 long, price above baseline, nothing happens.",
   [b(100.3, c1=1, c2=1), b(100.3, c1=1, c2=1)], [])

# ---------------------------------------------------------------- E1
fx("E1_fires_long", "E1", "C1 turns long, price above baseline within 1 ATR, C2 long, volume passes.",
   long_entry(), ENTRY_EV, check=DEC + ["OPEN"])
fx("E1_fires_short", "E1", "Mirror of E1_fires_long.",
   [b(99.7, c1=1, c2=-1), b(99.6, c1=-1, c2=-1), b(99.5, c1=-1, c2=-1)],
   [[1, "ENTER", "E1", -1], [2, "OPEN", "E1", -1]], check=DEC + ["OPEN"])
fx("E1_two_failures_skip", "E1", "C1 turns long but C2 disagrees and volume fails: skipped.",
   [b(100.3, c1=-1, c2=-1), b(100.4, c1=1, c2=-1, vol=False)],
   [[1, "SKIP", "E1", 1]])
fx("E1_vs_E2_priority", "E2",
   "Baseline cross and C1 signal on the same candle count as a baseline (E2) entry with C1 age 0.",
   [b(99.7, c1=-1, c2=1), b(100.3, c1=1, c2=1)],
   [[1, "ENTER", "E2", 1]])

# ---------------------------------------------------------------- E2 / E5
fx("E2_fires_long", "E2", "Close crosses above the baseline; C1 already long for 1 candle; C2 long.",
   [b(99.7, c1=1, c2=1), b(100.3, c1=1, c2=1), b(100.4, c1=1, c2=1)],
   [[1, "ENTER", "E2", 1], [2, "OPEN", "E2", 1]], check=DEC + ["OPEN"])
fx("E2_c1_and_c2_disagree_skip", "E2", "Close crosses above the baseline but C1 and C2 are short: skipped.",
   [b(99.7, c1=-1, c2=-1), b(100.3, c1=-1, c2=-1)],
   [[1, "SKIP", "E2", 1]])
fx("E5_bridge_too_far_7", "E5", "C1 long on the 7 candles before the cross: skipped.",
   [b(99.7, c1=1, c2=1) for _ in range(7)] + [b(100.3, c1=1, c2=1)],
   [[7, "SKIP", "E5", 1]])
fx("E5_boundary_6_enters", "E5", "C1 long on only 6 candles before the cross: entered.",
   [b(99.7, c1=1, c2=1) for _ in range(6)] + [b(100.3, c1=1, c2=1)],
   [[6, "ENTER", "E2", 1]])
fx("E5_off", "E5", "Bridge-too-far switched off: the 7-candle case enters.",
   [b(99.7, c1=1, c2=1) for _ in range(7)] + [b(100.3, c1=1, c2=1)],
   [[7, "ENTER", "E2", 1]], settings={"btf_on": False})

# ---------------------------------------------------------------- E3
fx("E3_pullback_enters", "E3", "Cross closes 1.4 ATR from baseline: wait; next close back within 1 ATR: enter.",
   [b(99.7, c1=1, c2=1), b(101.4, c1=1, c2=1), b(100.8, c1=1, c2=1)],
   [[1, "PENDING", "E3", 1], [2, "ENTER", "E3", 1]])
fx("E3_pullback_expires", "E3", "Next close still 1.2 ATR away: the wait expires.",
   [b(99.7, c1=1, c2=1), b(101.4, c1=1, c2=1), b(101.2, c1=1, c2=1)],
   [[1, "PENDING", "E3", 1], [2, "SKIP", "E3", 1]])
fx("E3_off", "E3", "Pullback rule off: a cross beyond 1 ATR is skipped.",
   [b(99.7, c1=1, c2=1), b(101.4, c1=1, c2=1)],
   [[1, "SKIP", "E2", 1]], settings={"pullback_on": False})

# ---------------------------------------------------------------- E4
fx("E4_c2_lags_then_enters", "E4", "C1 turns long, C2 still short: wait one candle; C2 agrees next candle: enter.",
   [b(100.3, c1=-1, c2=-1), b(100.4, c1=1, c2=-1), b(100.5, c1=1, c2=1)],
   [[1, "PENDING", "E4", 1], [2, "ENTER", "E4", 1]])
fx("E4_expires", "E4", "C2 still disagrees on the next candle: the wait expires.",
   [b(100.3, c1=-1, c2=-1), b(100.4, c1=1, c2=-1), b(100.5, c1=1, c2=-1)],
   [[1, "PENDING", "E4", 1], [2, "SKIP", "E4", 1]])
fx("E4_needs_within_atr", "E4", "Decision R-4: volume passes next candle but price is 1.3 ATR away: skipped.",
   [b(100.3, c1=-1, c2=1), b(100.4, c1=1, c2=1, vol=False), b(101.3, c1=1, c2=1)],
   [[1, "PENDING", "E4", 1], [2, "SKIP", "E4", 1]])
fx("E4_baseline_lags_then_enters", "E4",
   "C1 turns long while price is just below baseline: wait; price closes above baseline next candle: E4 entry.",
   [b(99.7, c1=-1, c2=1), b(99.8, c1=1, c2=1), b(100.3, c1=1, c2=1)],
   [[1, "PENDING", "E4", 1], [2, "ENTER", "E4", 1]])
fx("E4_off", "E4", "One-candle rule off: a single lagging indicator means skip.",
   [b(100.3, c1=-1, c2=-1), b(100.4, c1=1, c2=-1)],
   [[1, "SKIP", "E1", 1]], settings={"one_candle": False})

# ---------------------------------------------------------------- blocks (N1 etc.)
bars = long_entry()
bars[1]["block"] = ["news"]
fx("N1_blocked_by_news", "N1", "A valid E1 entry on a candle blocked by the news filter is skipped.",
   bars, [[1, "SKIP", "E1", 1]])

# ---------------------------------------------------------------- exits X2-X4
fx("X3_exit_on_c1_flip", "X3", "Open long; C1 turns short: exit decided at the close, closed at the next open.",
   long_entry() + [b(100.5, c1=-1, c2=1), b(100.4, c1=-1, c2=1)],
   ENTRY_EV + [[3, "EXIT", "X3", 1], [4, "CLOSE", "X3", 1]], check=DEC + ["OPEN", "CLOSE"])
fx("X2_exit_on_exit_indicator", "X2", "Open long; exit indicator turns short: exit.",
   long_entry() + [b(100.5, c1=1, c2=1, ex=-1), b(100.5, c1=1, c2=1, ex=-1)],
   ENTRY_EV + [[3, "EXIT", "X2", 1], [4, "CLOSE", "X2", 1]], check=DEC + ["OPEN", "CLOSE"])
fx("X4_exit_on_baseline", "X4", "Open long; price closes below the baseline: exit.",
   long_entry() + [b(99.8, c1=1, c2=1), b(99.8, c1=1, c2=1)],
   ENTRY_EV + [[3, "EXIT", "X4", 1], [4, "CLOSE", "X4", 1]], check=DEC + ["OPEN", "CLOSE"])
fx("X2_off", "X2", "Exit-indicator exit switched off: no exit.",
   long_entry() + [b(100.5, c1=1, c2=1, ex=-1)],
   ENTRY_EV, check=DEC + ["OPEN", "CLOSE"], settings={"exit_on_exit_ind": False})
fx("X4_needs_a_close_below", "X4", "Price dips below the baseline inside the candle but closes above it: no exit.",
   long_entry() + [b(100.2, c1=1, c2=1, o=100.5, h=100.6, l=99.6)],
   ENTRY_EV, check=DEC + ["OPEN", "CLOSE"])
fx("X4_close_exactly_on_baseline", "X4", "A close exactly on the baseline is not the other side: no exit.",
   long_entry() + [b(100.0, c1=1, c2=1, o=100.5, h=100.6, l=99.9)],
   ENTRY_EV, check=DEC + ["OPEN", "CLOSE"])
fx("X3_off", "X3", "C1-flip exit switched off: no exit.",
   long_entry() + [b(100.5, c1=-1, c2=1)],
   ENTRY_EV, check=DEC + ["OPEN", "CLOSE"], settings={"exit_on_c1": False})

# ---------------------------------------------------------------- X5 news
fx("X5_news_exit_when_losing", "X5", "First candle in a news window while the trade is losing: exit.",
   long_entry() + [b(100.3, c1=1, c2=1, news=True), b(100.3, c1=1, c2=1)],
   ENTRY_EV + [[3, "EXIT", "X5", 1], [4, "CLOSE", "X5", 1]], check=DEC + ["OPEN", "CLOSE"])
fx("X5_news_exit_small_profit", "X5", "In profit by 0.5 ATR (< 1 ATR): exit.",
   long_entry() + [b(101.0, c1=1, c2=1, news=True), b(101.0, c1=1, c2=1)],
   ENTRY_EV + [[3, "EXIT", "X5", 1], [4, "CLOSE", "X5", 1]], check=DEC + ["OPEN", "CLOSE"])
fx("X5_news_keep_when_1atr_profit", "X5", "In profit by 1.1 ATR: keep the trade.",
   long_entry() + [b(101.6, c1=1, c2=1, o=100.5, h=101.65, l=100.45, news=True)],
   ENTRY_EV, check=DEC + ["OPEN", "CLOSE"])

# ---------------------------------------------------------------- stops and targets
fx("M3_stop_loss", "M3",
   "Stop at 99.0 is hit; the close below baseline is also a short cross, but C1 and C2 are long: skipped.",
   long_entry() + [b(99.2, c1=1, c2=1, o=100.5, h=100.6, l=98.9)],
   ENTRY_EV + [[3, "SL", "M3", 1], [3, "SKIP", "E2", -1]], check=ALL, expect_r=[-1.0])
fx("M3_stop_gap_fills_at_open", "M3", "Candle opens at 98.5, below the 99.0 stop: filled at 98.5 (-1.333R).",
   long_entry() + [b(98.6, c1=1, c2=1, o=98.5, h=98.7, l=98.4)],
   ENTRY_EV + [[3, "SL", "M3", 1], [3, "SKIP", "E2", -1]], check=ALL, expect_r=[-1.333333])
fx("T1_T2_tp1_then_breakeven", "T2",
   "TP1 at 101.5 fills, stop moves to entry 100.5; next candle comes back to 100.4: breakeven exit.",
   long_entry() + [b(101.2, c1=1, c2=1, o=100.5, h=101.6, l=100.45),
                   b(100.6, c1=1, c2=1, o=101.2, h=101.3, l=100.4)],
   ENTRY_EV + [[3, "TP1", "T1", 1], [3, "MOVE_BE", "T2", 1], [4, "BE_SL", "T2", 1]],
   check=ALL, expect_r=[0.333333])
fx("T1_tp1_closes_half_only", "T1", "TP1 at 101.5 closes half 1; half 2 stays open with no target.",
   long_entry() + [b(101.2, c1=1, c2=1, o=100.5, h=101.6, l=100.45)],
   ENTRY_EV + [[3, "TP1", "T1", 1], [3, "MOVE_BE", "T2", 1]], check=ALL)
fx("T2_no_breakeven_before_tp1", "T2",
   "Price returns to entry before TP1: the stop stays at 99.0 (no breakeven exit) and the trade stays open.",
   long_entry() + [b(101.2, c1=1, c2=1, o=100.5, h=101.4, l=100.45),
                   b(100.4, c1=1, c2=1, o=101.2, h=101.25, l=100.3)],
   ENTRY_EV, check=ALL)
fx("SL_and_TP1_same_candle", "M3", "One candle reaches both 98.9 and 101.6: the stop is assumed first.",
   long_entry() + [b(100.2, c1=1, c2=1, o=100.5, h=101.6, l=98.9)],
   ENTRY_EV + [[3, "SL", "M3", 1]], check=ALL, expect_r=[-1.0])

TRAIL_BARS = long_entry() + [
    b(101.4, c1=1, c2=1, o=100.5, h=101.6, l=100.45),   # 3: TP1
    b(102.6, c1=1, c2=1, o=101.4, h=102.65, l=101.35),   # 4: close 2.1 ATR beyond entry -> trail to 101.1
    b(103.0, c1=1, c2=1, o=102.6, h=103.05, l=102.5),   # 5: trail to 101.5
    b(102.7, c1=1, c2=1, o=103.0, h=103.05, l=102.6),   # 6: 101.2 would be backwards: no move
    b(101.6, c1=1, c2=1, o=102.7, h=102.75, l=101.4),   # 7: trailing stop 101.5 hit
]
fx("T4_trailing_stop", "T4", "Trail switches on after a close 2 ATR beyond entry, moves at closes, never backwards.",
   TRAIL_BARS,
   ENTRY_EV + [[3, "TP1", "T1", 1], [3, "MOVE_BE", "T2", 1], [4, "TRAIL", "T4", 1],
               [5, "TRAIL", "T4", 1], [7, "TRAIL_SL", "T4", 1]],
   check=ALL, expect_r=[0.666667])
fx("T4_off", "T4", "Trailing off: the stop stays at breakeven, so the same candles leave the runner open.",
   json.loads(json.dumps(TRAIL_BARS)),
   ENTRY_EV + [[3, "TP1", "T1", 1], [3, "MOVE_BE", "T2", 1]],
   check=ALL, settings={"trail_on": False})
fx("T7_runner_cap_2atr", "T7", "Runner cap at 2 ATR (102.5) fills on candle 4: whole trade = +1.0R.",
   json.loads(json.dumps(TRAIL_BARS[:5])),
   ENTRY_EV + [[3, "TP1", "T1", 1], [3, "MOVE_BE", "T2", 1], [4, "TP2", "T7", 1]],
   check=ALL, settings={"runner_cap_atr": 2.0}, expect_r=[1.0])

fx("T7_runner_cap_not_reached", "T7", "Runner cap at 4 ATR (104.5) is never reached: no TP2; trail exits instead.",
   json.loads(json.dumps(TRAIL_BARS)),
   ENTRY_EV + [[3, "TP1", "T1", 1], [3, "MOVE_BE", "T2", 1], [4, "TRAIL", "T4", 1],
               [5, "TRAIL", "T4", 1], [7, "TRAIL_SL", "T4", 1]],
   check=ALL, settings={"runner_cap_atr": 4.0}, expect_r=[0.666667])

# ---------------------------------------------------------------- E6 continuation
def cont_bars(b4, b5):
    """Long E1 trade exited by the exit indicator (X2) at bar 3, closed at bar 4's open."""
    return long_entry() + [b(100.5, c1=1, c2=1, ex=-1), b4, b5]


CONT_PRE = [[1, "ENTER", "E1", 1], [3, "EXIT", "X2", 1]]
fx("E6a_continuation_fires", "E6", "Version (a): C2 dips short, then turns long again while C1 never flipped: re-enter.",
   cont_bars(b(100.5, c1=1, c2=-1, ex=-1), b(100.6, c1=1, c2=1, ex=-1)),
   CONT_PRE + [[5, "ENTER", "E6", 1]])
fx("E6a_ignores_volume_and_distance", "E6", "Continuation still fires with volume failing and price 1.6 ATR away.",
   cont_bars(b(100.5, c1=1, c2=-1, ex=-1), b(101.6, c1=1, c2=1, ex=-1, vol=False)),
   CONT_PRE + [[5, "ENTER", "E6", 1]])
fx("E6a_blocked_after_c1_flip", "E6",
   "Exit was a C1 flip (X3), so version (a) can't fire later. C1's return is itself an E1 signal but C2 and volume fail.",
   long_entry() + [b(100.5, c1=-1, c2=1), b(100.5, c1=1, c2=-1, vol=False), b(100.6, c1=1, c2=1)],
   [[1, "ENTER", "E1", 1], [3, "EXIT", "X3", 1], [4, "SKIP", "E1", 1]])
fx("E6_disarmed_by_baseline_cross", "E6",
   "After the exit, price closes below the baseline: continuation is off. That close is a short cross with one "
   "indicator lagging, so it waits one candle and expires.",
   cont_bars(b(99.8, c1=1, c2=-1, ex=-1), b(99.9, c1=1, c2=1, ex=-1)),
   CONT_PRE + [[4, "PENDING", "E4", -1], [5, "SKIP", "E4", -1]])
fx("E6b_continuation_fires", "E6", "Version (b): the exit indicator turns long again with C1 and C2 long: re-enter.",
   cont_bars(b(100.5, c1=1, c2=1, ex=-1), b(100.6, c1=1, c2=1, ex=1)),
   CONT_PRE + [[5, "ENTER", "E6", 1]], settings={"continuation": "b"})
fx("E6_off", "E6", "Continuation off: the E6a case does not re-enter.",
   cont_bars(b(100.5, c1=1, c2=-1, ex=-1), b(100.6, c1=1, c2=1, ex=-1)),
   CONT_PRE, settings={"continuation": "off"})


MQL5_DIR = os.path.join(HERE, "mql5")


def _num(x):
    return repr(float(x))


def _val(v):
    if v is None:
        return "none"
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, (int, float)):
        return _num(v)
    return str(v)


def to_mql5_text(item):
    """Line format for the MQL5 test script (MQL5 has no built-in JSON reader).
    Same data as the JSON file; tests/python/test_fixture_formats.py proves it."""
    lines = ["NAME|" + item["name"], "RULE|" + item["rule"]]
    for k in sorted(item["settings"]):
        lines.append("SET|%s|%s" % (k, _val(item["settings"][k])))
    lines.append("CHECK|" + ",".join(item["check"]))
    for bar in item["bars"]:
        lines.append("BAR|" + "|".join([
            str(bar["t"]), _num(bar["o"]), _num(bar["h"]), _num(bar["l"]), _num(bar["c"]),
            _num(bar["atr"]), _num(bar["base"]), str(bar["c1"]), str(bar["c2"]), str(bar["ex"]),
            "1" if bar["vol"] else "0", ";".join(bar["block"]), "1" if bar["news"] else "0"]))
    for i, ev, rule, d in item["expect"]:
        lines.append("EXP|%d|%s|%s|%d" % (i, ev, rule, d))
    for r in item.get("expect_r", []):
        lines.append("EXPR|" + _num(r))
    lines.append("END")
    return "\n".join(lines) + "\n"


def main():
    os.makedirs(MQL5_DIR, exist_ok=True)
    for folder, ext in ((HERE, ".json"), (MQL5_DIR, ".txt")):
        for old in os.listdir(folder):
            if old.endswith(ext):
                os.remove(os.path.join(folder, old))
    names = set()
    for item in FIXTURES:
        if item["name"] in names:
            raise SystemExit("duplicate fixture name " + item["name"])
        names.add(item["name"])
        with open(os.path.join(HERE, item["name"] + ".json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(item, f, indent=1)
            f.write("\n")
        with open(os.path.join(MQL5_DIR, item["name"] + ".txt"), "w", encoding="ascii", newline="\n") as f:
            f.write(to_mql5_text(item))
    print("wrote %d fixtures (JSON + MQL5 text)" % len(FIXTURES))


if __name__ == "__main__":
    main()
