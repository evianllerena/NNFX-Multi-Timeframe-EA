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
CONTEST refused). REAL is always refused. Orders also need a HEDGING account, tester included:
two positions per trade on one symbol is the design (S-10), and on a netting account the second
half would merge into the first (review fix A7, 2026-10-14).

Retries (OD-13): a refused request is sent again only when the refusal can clear by itself
(requote, price moved, timeout, connection...). Refusals that cannot clear on a retry 1 s later
(no money, invalid stops/volume/fill, market closed, trading disabled, Algo Trading off) are not
retried (review fix B3, 2026-10-14).
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


MARGIN_MODES = ("HEDGING", "NETTING", "EXCHANGE")


def hedging_ok(margin_mode: str) -> bool:
    """A7: True only on a hedging account (ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)."""
    if margin_mode not in MARGIN_MODES:
        raise ValueError("unknown margin mode %r" % margin_mode)
    return margin_mode == "HEDGING"


# B3: the refusals that a retry 1 s later can clear. Names are MT5's TRADE_RETCODE_* without the prefix.
RETRYABLE = ("REQUOTE", "REJECT", "ERROR", "TIMEOUT", "INVALID_PRICE", "PRICE_CHANGED", "PRICE_OFF",
             "TOO_MANY_REQUESTS", "LOCKED", "FROZEN", "CONNECTION")
NOT_RETRYABLE = ("INVALID", "INVALID_VOLUME", "INVALID_STOPS", "TRADE_DISABLED", "MARKET_CLOSED", "NO_MONEY",
                 "INVALID_FILL", "SERVER_DISABLES_AT", "CLIENT_DISABLES_AT", "ONLY_REAL", "LIMIT_ORDERS",
                 "LIMIT_VOLUME", "LIMIT_POSITIONS", "INVALID_ORDER", "POSITION_CLOSED", "HEDGE_PROHIBITED",
                 "FIFO_CLOSE", "INVALID_EXPIRATION", "INVALID_CLOSE_VOLUME", "CLOSE_ORDER_EXIST", "LONG_ONLY",
                 "SHORT_ONLY", "CLOSE_ONLY")


def retcode_retryable(retcode: str) -> bool:
    """B3: True if a refused request with this retcode is worth sending again (OD-13).
    Anything not on either list (a code added to MT5 later) is retried, as before this fix."""
    return retcode not in NOT_RETRYABLE


# A5 (review fixes set 3): MT5's ORDER_STATE_* names without the prefix.
ORDER_STATES = ("STARTED", "PLACED", "CANCELED", "PARTIAL", "FILLED", "REJECTED", "EXPIRED", "REQUEST_ADD",
                "REQUEST_MODIFY", "REQUEST_CANCEL")


def order_state_outcome(state: str) -> int:
    """A5: 1 = filled (any fill, OD-14), -1 = will never fill (a re-send is safe), 0 = not resolved: never re-send."""
    if state not in ORDER_STATES:
        raise ValueError("unknown order state %r" % state)
    if state in ("FILLED", "PARTIAL"):
        return 1
    if state in ("CANCELED", "REJECTED", "EXPIRED"):
        return -1
    return 0


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


def be_action(direction: int, entry2: float, broker_sl: float, bid: float, ask: float, tick: float) -> int:
    """A1 (review fixes set 2): after TP1, what half 2's stop at the broker needs.
    0 = nothing (at breakeven or better), 1 = move to breakeven, 2 = close half 2 at market (the price is already at
    or beyond breakeven against the trade, so a breakeven stop would be hit at once; label C, decision RV-A1)."""
    if direction not in (1, -1):
        raise ValueError("direction must be +1 or -1")
    be = breakeven_price(entry2)
    if (be - broker_sl) * direction <= tick * 0.5:
        return 0
    exit_price = bid if direction > 0 else ask
    if (exit_price - be) * direction <= 0.0:
        return 2
    return 1


PENDING_FAST_S, PENDING_SLOW_S, PENDING_FAST_N = 5, 60, 5


def pending_due(fails: int, seconds_since_last: int) -> bool:
    """A1/A8 (review fixes set 2): a failed breakeven move or close is tried again every 5 s for the first
    5 failures, then every 60 s, without end."""
    if fails <= 0:
        return True
    return seconds_since_last >= (PENDING_FAST_S if fails < PENDING_FAST_N else PENDING_SLOW_S)


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
