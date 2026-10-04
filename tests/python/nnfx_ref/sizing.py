"""Position sizing (rulebook M2-M5; SPEC, Money, sizing and exposure).

Risk is a percentage of balance (decision S-3), split into two equal halves,
each rounded DOWN to the broker's lot step. If a half is below the minimum lot,
the trade is skipped. Risk is never rounded up.
"""
import math
from dataclasses import dataclass
from typing import Optional

_EPS = 1e-9


@dataclass
class SizeResult:
    half_lots: float
    total_lots: float
    risk_money: float          # money actually at risk with the rounded lots
    target_risk_money: float   # money the risk percentage allows
    skipped: bool
    reason: str = ""


def tick_value_for_sizing(tick_value: float, tick_value_loss: float) -> float:
    """Decision OD-6: the larger of the broker's tick value and its tick value for a
    losing trade, so lots can only come out smaller. 0.0 if neither is > 0 (refuse)."""
    best = max(tick_value, tick_value_loss)
    return best if best > 0 else 0.0


def size_trade(balance: float, risk_pct: float, stop_distance: float, tick_size: float,
               tick_value: float, vol_min: float, vol_step: float,
               vol_max: Optional[float] = None) -> SizeResult:
    """stop_distance is in price units (e.g. 0.0030 for 30 pips on EURUSD).
    tick_value is the account-currency value of one tick for one lot."""
    if min(balance, risk_pct, stop_distance, tick_size, tick_value, vol_min, vol_step) <= 0:
        raise ValueError("all sizing inputs must be > 0")
    target = balance * risk_pct / 100.0
    loss_per_lot = (stop_distance / tick_size) * tick_value
    raw_total = target / loss_per_lot
    raw_half = raw_total / 2.0
    steps = math.floor(raw_half / vol_step + _EPS)
    half = round(steps * vol_step, 8)
    if vol_max is not None and half > vol_max:
        half = round(math.floor(vol_max / vol_step + _EPS) * vol_step, 8)
    if half + _EPS < vol_min:
        return SizeResult(0.0, 0.0, 0.0, target, True, "too small to size")
    total = round(half * 2, 8)
    return SizeResult(half, total, total * loss_per_lot, target, False)
