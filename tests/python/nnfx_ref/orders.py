"""Order prices and the order safety rule (Phase 6b; docs/PLAN_PHASE6.md sections 1 and 3).

Prices use the same formulas as core.py (_open_position, _manage_open), measured from the
broker's FILL price (decision OD-14), then put on the broker's tick grid:

    stop   SL = fill - dir * sl_atr * ATR (M3, T1), rounded TOWARDS the fill price, so the stop
           distance is never larger than the one the lots were sized for (F4: planned risk is
           never above target)
    TP1    fill + dir * tp1_atr * ATR (T1), rounded to the nearest tick
    TP2    fill + dir * runner_cap_atr * ATR if the runner cap is on (T7), nearest tick
    BE     exactly the half's entry price (T2 [A]; decision OD-15)
    trail  after TP1, on once a close is trail_start_atr ENTRY ATRs beyond entry; then
           close - dir * trail_dist_atr * current ATR, nearest tick, never backwards (T4, I-11)

Safety (section 1): orders only in the Strategy Tester or on a DEMO account (decision OD-18:
CONTEST refused). REAL is always refused.
"""
import math
from typing import Optional, Tuple

_EPS = 1e-9
TRADE_MODES = ("DEMO", "CONTEST", "REAL")


def orders_allowed_for(trade_mode: str, in_tester: bool) -> bool:
    """Section 1: True only in the Strategy Tester or on a DEMO account."""
    if trade_mode not in TRADE_MODES:
        raise ValueError("unknown trade mode %r" % trade_mode)
    return bool(in_tester) or trade_mode == "DEMO"


def _ticks(x: float, tick: float) -> float:
    return x / tick


def round_nearest(price: float, tick: float) -> float:
    return round(math.floor(_ticks(price, tick) + 0.5 + _EPS) * tick, 10)


def round_stop(direction: int, price: float, tick: float) -> float:
    """A stop rounded towards the fill price: up for a long (stop below), down for a short."""
    if direction == 1:
        return round(math.ceil(_ticks(price, tick) - _EPS) * tick, 10)
    return round(math.floor(_ticks(price, tick) + _EPS) * tick, 10)


def plan_prices(direction: int, fill: float, atr: float, tick: float, sl_atr: float = 1.5,
                tp1_atr: float = 1.0, cap_atr: Optional[float] = None) -> Tuple[float, float, Optional[float]]:
    """(SL, TP1, TP2 or None) for a trade filled at `fill`."""
    if direction not in (1, -1):
        raise ValueError("direction must be +1 or -1")
    if min(fill, atr, tick, sl_atr, tp1_atr) <= 0 or (cap_atr is not None and cap_atr <= 0):
        raise ValueError("prices, ATR, tick and multiples must be > 0")
    sl = round_stop(direction, fill - direction * sl_atr * atr, tick)
    tp1 = round_nearest(fill + direction * tp1_atr * atr, tick)
    tp2 = round_nearest(fill + direction * cap_atr * atr, tick) if cap_atr else None
    return sl, tp1, tp2


def breakeven_price(entry: float) -> float:
    """T2 / OD-15: exactly the entry price."""
    return entry


def trail_step(direction: int, entry: float, atr_entry: float, current_sl: float, active: bool,
               close: float, atr: float, tick: float, start_atr: float = 2.0,
               dist_atr: float = 1.5) -> Tuple[float, bool]:
    """One candle close of the T4 trail on half 2 (called only after TP1). Returns (new SL, active)."""
    if not active and (close - entry) * direction >= start_atr * atr_entry - 1e-12:
        active = True
    if not active:
        return current_sl, False
    candidate = round_nearest(close - direction * dist_atr * atr, tick)
    if (candidate - current_sl) * direction > _EPS * tick:
        return candidate, True
    return current_sl, True


def stop_distance_ok(price: float, sl: float, stops_level_points: int, point: float) -> bool:
    """SPEC: a stop closer than the broker's minimum stop distance is not sent."""
    return abs(price - sl) + _EPS * point >= stops_level_points * point


def planned_risk(lots: float, entry: float, sl: float, tick_size: float, tick_value: float) -> float:
    """Money lost if this position's stop is hit exactly: lots x stop distance in ticks x tick value."""
    return lots * (abs(entry - sl) / tick_size) * tick_value
