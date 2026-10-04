"""Per-pair rules engine (docs/RULEBOOK.md; docs/SPEC.md).

Input: one closed candle at a time, with indicator values already turned into
directions by the slot layer (signals.py):

    t     candle time (any sortable label)
    o h l c  open, high, low, close
    atr   ATR(14) of this candle (chart timeframe)
    base  baseline value
    c1 c2 ex   directions (+1 / -1 / 0) of C1, C2 and the exit indicator
    vol   volume / volatility filter passes (bool)
    block list of reasons new entries are blocked on this candle
          (news N1, rollover, weekend, master switch, drawdown, daily loss,
           same-currency exposure ...). Decided outside the core.
    news  True on the first candle close inside a 24 h window before a major
          event on one of the pair's currencies (X5 check)

Timing (decision R-3): decisions are made at a candle's close and acted on at the
OPEN of the next candle. Broker-held stops and targets (SL, TP1, breakeven,
trailing stop, runner cap) can fill inside any candle.

Candle-only fill assumptions (used only to know whether a test trade is still
open; real fills come from MT5's tick data):
    * if a candle reaches both the stop and a target, the stop is assumed first;
    * after TP1 fills inside a candle, the new breakeven stop is checked from the
      next candle (whether price came back to entry after TP1 inside the same
      candle can't be known from OHLC);
    * a stop gapped through at the open fills at the open; targets fill at their price.

Every operational interpretation is listed in tests/python/README.md.
"""
from dataclasses import dataclass
from typing import Dict, List, Optional

from .settings import Settings


@dataclass
class Position:
    dir: int
    entry: float
    atr_entry: float
    sl: float
    tp1: float
    tp2: Optional[float]
    rule: str
    h1_open: bool = True
    h2_open: bool = True
    tp1_done: bool = False
    trail_active: bool = False
    r_result: float = 0.0       # realised result in R (1R = initial stop distance, whole trade)


def _sign(x: float) -> int:
    return 1 if x > 0 else (-1 if x < 0 else 0)


class PairCore:
    def __init__(self, symbol: str, settings: Optional[Settings] = None):
        self.symbol = symbol
        self.s = settings or Settings()
        self.s.validate()
        self.i = -1
        self.events: List[Dict] = []
        # previous closed candle
        self.prev_side: Optional[int] = None
        self.prev_c1: Optional[int] = None
        self.prev_c2: Optional[int] = None
        self.prev_ex: Optional[int] = None
        # C1 run: consecutive candles (up to the previous candle) holding run_dir
        self.c1_run_dir = 0
        self.c1_run_len = 0
        # position and orders
        self.pos: Optional[Position] = None
        self.pending_action: Optional[Dict] = None     # acted on at next open
        self.pending_entry: Optional[Dict] = None      # E3 / E4 wait-one-candle
        # continuation tracking (E6)
        self.trend_dir = 0
        self.armed = False
        self.c1_flipped = False
        self.last_exit_dir = 0
        self.closed_trades: List[Dict] = []

    # ------------------------------------------------------------------ events
    def _emit(self, bar: Dict, event: str, rule: str = "", direction: int = 0,
              price: Optional[float] = None, note: str = "") -> None:
        self.events.append({"i": self.i, "t": bar.get("t", self.i), "event": event, "rule": rule,
                            "dir": direction, "price": price, "note": note})

    # ------------------------------------------------------------------ fills
    def _open_position(self, bar: Dict, act: Dict) -> None:
        d, atr = act["dir"], act["atr"]
        entry = bar["o"]
        sl = entry - d * self.s.sl_atr * atr
        tp1 = entry + d * self.s.tp1_atr * atr
        tp2 = entry + d * self.s.runner_cap_atr * atr if self.s.runner_cap_atr else None
        self.pos = Position(d, entry, atr, sl, tp1, tp2, act["rule"])
        self._emit(bar, "OPEN", act["rule"], d, entry)

    def _close_half(self, half: int, price: float) -> None:
        p = self.pos
        risk = self.s.sl_atr * p.atr_entry
        p.r_result += 0.5 * (price - p.entry) * p.dir / risk
        if half == 1:
            p.h1_open = False
        else:
            p.h2_open = False

    def _finish_if_flat(self, bar: Dict) -> None:
        p = self.pos
        if p and not p.h1_open and not p.h2_open:
            self.closed_trades.append({"rule": p.rule, "dir": p.dir, "entry": p.entry,
                                       "r": round(p.r_result, 6), "closed_i": self.i})
            self.last_exit_dir = p.dir
            self.pos = None

    def _close_all(self, bar: Dict, price: float, event: str, rule: str) -> None:
        p = self.pos
        if p.h1_open:
            self._close_half(1, price)
        if p.h2_open:
            self._close_half(2, price)
        self._emit(bar, event, rule, p.dir, price)
        self._finish_if_flat(bar)

    def _intrabar(self, bar: Dict) -> None:
        p = self.pos
        d, o, h, l = p.dir, bar["o"], bar["h"], bar["l"]
        fav = h if d > 0 else l        # best price reached
        adv = l if d > 0 else h        # worst price reached

        def reached(level: float, extreme: float, favourable: bool) -> bool:
            return (extreme - level) * d >= 0 if favourable else (level - extreme) * d >= 0

        sl_hit = reached(p.sl, adv, False)
        tp1_hit = p.h1_open and reached(p.tp1, fav, True)
        tp2_hit = p.h2_open and p.tp2 is not None and reached(p.tp2, fav, True)

        if sl_hit:
            # Gap through the stop at the open fills at the open; otherwise at the stop.
            fill = o if (p.sl - o) * d > 0 else p.sl
            if p.tp1_done:
                kind, rule = ("TRAIL_SL", "T4") if p.trail_active else ("BE_SL", "T2")
            else:
                kind, rule = "SL", "M3"
            self._close_all(bar, fill, kind, rule)
            return
        if tp1_hit:
            self._close_half(1, p.tp1)
            p.tp1_done = True
            self._emit(bar, "TP1", "T1", d, p.tp1)
            p.sl = p.entry                              # T2: breakeven at once
            self._emit(bar, "MOVE_BE", "T2", d, p.sl)
            # The breakeven stop is checked from the next candle: whether this candle
            # came back to entry after reaching TP1 can't be known from OHLC.
            if tp2_hit:
                self._close_half(2, p.tp2)
                self._emit(bar, "TP2", "T7", d, p.tp2)
                self._finish_if_flat(bar)
            return
        if tp2_hit:
            self._close_half(2, p.tp2)
            self._emit(bar, "TP2", "T7", d, p.tp2)
            self._finish_if_flat(bar)

    # ------------------------------------------------------------------ main
    def on_bar(self, bar: Dict) -> List[Dict]:
        """Process one closed candle. Returns the events emitted for it."""
        self.i += 1
        start = len(self.events)
        s = self.s

        # 1. Actions decided at the previous close are filled at this open.
        if self.pending_action:
            act, self.pending_action = self.pending_action, None
            if act["kind"] == "enter":
                self._open_position(bar, act)
            elif act["kind"] == "exit" and self.pos:
                self._close_all(bar, bar["o"], "CLOSE", act["rule"])

        # 2. Broker-held stops and targets inside the candle.
        if self.pos:
            self._intrabar(bar)

        # 3. Decisions at the close.
        c, base, atr = bar["c"], bar["base"], bar["atr"]
        c1, c2, ex, vol = bar["c1"], bar["c2"], bar["ex"], bool(bar["vol"])
        side = _sign(c - base)
        warm = self.prev_side is not None
        cross = side if (warm and side != 0 and side != self.prev_side) else 0
        c1_fresh = c1 if (warm and c1 != 0 and c1 != self.prev_c1) else 0
        c2_fresh = c2 if (warm and c2 != 0 and c2 != self.prev_c2) else 0
        ex_fresh = ex if (warm and ex != 0 and ex != self.prev_ex) else 0
        within = abs(c - base) <= s.max_dist_atr * atr + 1e-12
        blocks = list(bar.get("block") or [])

        # Continuation tracking (E6): disarm on a close on the far side of the baseline;
        # version (a) also needs C1 never to have flipped against the trend.
        if self.armed and self.trend_dir:
            if side == -self.trend_dir:
                self.armed = False
            if c1 == -self.trend_dir:
                self.c1_flipped = True

        if self.pos:
            self._manage_open(bar, c, atr, c1, ex, side)
            self.pending_entry = None
        elif not self.pending_action:
            self._decide_entry(bar, side, cross, c1, c2, c1_fresh, c2_fresh, ex_fresh,
                               vol, within, blocks)

        # 4. Remember this candle.
        if c1 != 0 and c1 == self.c1_run_dir:
            self.c1_run_len += 1
        else:
            self.c1_run_dir, self.c1_run_len = c1, (1 if c1 != 0 else 0)
        self.prev_side, self.prev_c1, self.prev_c2, self.prev_ex = side, c1, c2, ex
        return self.events[start:]

    # ------------------------------------------------------------------ open trade
    def _manage_open(self, bar: Dict, c: float, atr: float, c1: int, ex: int, side: int) -> None:
        p, s = self.pos, self.s
        d = p.dir
        # T4 trailing stop (half 2, after TP1), at the close, never backwards.
        if s.trail_on and p.tp1_done and p.h2_open:
            if not p.trail_active and (c - p.entry) * d >= s.trail_start_atr * p.atr_entry - 1e-12:
                p.trail_active = True
            if p.trail_active:
                new_sl = c - d * s.trail_dist_atr * atr
                if (new_sl - p.sl) * d > 1e-12:
                    p.sl = new_sl
                    self._emit(bar, "TRAIL", "T4", d, new_sl)
        # X5: first candle inside the news window.
        if s.news_exit and bar.get("news"):
            gain = (c - p.entry) * d
            if gain < 0 or gain < 1.0 * atr:
                self._decide_exit(bar, "X5")
                return
        # X2-X4 signal exits; the first in this fixed order is the logged reason.
        if s.exit_on_exit_ind and ex == -d:
            self._decide_exit(bar, "X2")
        elif s.exit_on_c1 and c1 == -d:
            self._decide_exit(bar, "X3")
        elif s.exit_on_baseline and side == -d:
            self._decide_exit(bar, "X4")

    def _decide_exit(self, bar: Dict, rule: str) -> None:
        self.pending_action = {"kind": "exit", "rule": rule}
        self._emit(bar, "EXIT", rule, self.pos.dir)

    # ------------------------------------------------------------------ flat
    def _enter(self, bar: Dict, d: int, rule: str, atr: float, blocks: List[str]) -> bool:
        if blocks:
            self._emit(bar, "SKIP", rule, d, note="blocked:" + ",".join(blocks))
            return False
        self.pending_action = {"kind": "enter", "dir": d, "rule": rule, "atr": atr}
        self._emit(bar, "ENTER", rule, d)
        if rule != "E6":
            self.trend_dir, self.armed, self.c1_flipped = d, True, False
        return True

    def _decide_entry(self, bar, side, cross, c1, c2, c1_fresh, c2_fresh, ex_fresh,
                      vol, within, blocks) -> None:
        s = self.s
        atr = bar["atr"]

        # a) A trade waiting one candle (E3 pullback or E4 one-candle rule).
        pe, self.pending_entry = self.pending_entry, None
        if pe:
            d = pe["dir"]
            ok = side == d and c1 == d and c2 == d and vol and within
            if ok:
                self._enter(bar, d, pe["rule"], atr, blocks)
                return
            self._emit(bar, "SKIP", pe["rule"], d, note="expired")
            # fall through: this candle may carry its own new signal

        # b) New standard signal: baseline cross (E2) takes priority over C1 signal (E1).
        #    Work out what the regular signal would do; only an immediate entry is
        #    acted on here (I-14: a regular entry beats a continuation).
        outcome = None   # (event, rule, dir, note, wait_rule) for a refused or waiting signal
        trig, rule = 0, ""
        if cross:
            trig, rule = cross, "E2"
        elif c1_fresh:
            trig, rule = c1_fresh, "E1"
        if trig:
            d = trig
            age = self.c1_run_len if self.c1_run_dir == d else 0
            if rule == "E2" and s.btf_on and age >= s.btf_bars:
                outcome = ("SKIP", "E5", d, "C1 signal %d candles old" % age, None)
            else:
                fails = []
                if rule == "E2" and c1 != d:
                    fails.append("c1")
                if rule == "E1" and side != d:
                    fails.append("baseline")
                if c2 != d:
                    fails.append("c2")
                if not vol:
                    fails.append("volume")
                if not fails and within:
                    self._enter(bar, d, rule, atr, blocks)
                    return
                if not fails and not within and s.pullback_on:
                    outcome = ("PENDING", "E3", d, "beyond 1xATR", "E3")
                elif len(fails) == 1 and within and s.one_candle:
                    outcome = ("PENDING", "E4", d, "waiting: " + fails[0], "E4")
                else:
                    why = fails + ([] if within else ["distance"])
                    outcome = ("SKIP", rule, d, ",".join(why), None)

        # c) Continuation (E6): flat after a trade, trend still armed, same direction.
        #    Checked whenever no regular entry opened on this candle (I-14).
        if s.continuation != "off" and self.armed and self.trend_dir and self.last_exit_dir == self.trend_dir:
            d = self.trend_dir
            if s.continuation == "a":
                fire = c2_fresh == d and not self.c1_flipped
            else:
                fire = ex_fresh == d and c1 == d and c2 == d
            if fire:
                if outcome:
                    self._emit(bar, "SKIP", outcome[1], outcome[2], note="continuation taken instead")
                self._enter(bar, d, "E6", atr, blocks)
                return

        # d) Log the regular signal's outcome (refused, or waiting one candle).
        if outcome:
            event, orule, d, note, wait_rule = outcome
            if wait_rule:
                self.pending_entry = {"dir": d, "rule": wait_rule}
            self._emit(bar, event, orule, d, note=note)
