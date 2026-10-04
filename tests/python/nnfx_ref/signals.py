"""Turn raw indicator values into directions (docs/SPEC.md, Indicator profiles).

Directions: +1 long, -1 short, 0 none. Bad values never become signals:
None, NaN, infinities and MQL5's EMPTY_VALUE all read as 0, as do warm-up candles.
"""
import math
from typing import Optional, Sequence

# MQL5 EMPTY_VALUE is DBL_MAX.
EMPTY_VALUE = 1.7976931348623157e308


def is_bad(value: Optional[float]) -> bool:
    if value is None:
        return True
    try:
        v = float(value)
    except (TypeError, ValueError):
        return True
    return math.isnan(v) or math.isinf(v) or v >= EMPTY_VALUE or v <= -EMPTY_VALUE


def price_line_dir(close: Optional[float], line: Optional[float]) -> int:
    """Baseline: long when the close is above the line, short when below."""
    if is_bad(close) or is_bad(line):
        return 0
    if close > line:
        return 1
    if close < line:
        return -1
    return 0


def two_line_dir(fast: Optional[float], slow: Optional[float]) -> int:
    """Two-line cross: long when fast is above slow, short when below."""
    if is_bad(fast) or is_bad(slow):
        return 0
    if fast > slow:
        return 1
    if fast < slow:
        return -1
    return 0


def centre_line_dir(value: Optional[float], centre: Optional[float]) -> int:
    """Centre-line cross. The centre line must be given; it is never defaulted to 0."""
    if centre is None:
        raise ValueError("centre line must be supplied by the indicator profile")
    if is_bad(value):
        return 0
    if value > centre:
        return 1
    if value < centre:
        return -1
    return 0


def volume_pass(rule: str, value: Optional[float], *, level: Optional[float] = None,
                history: Optional[Sequence[float]] = None, mult: float = 1.0,
                other: Optional[float] = None) -> bool:
    """Volume / volatility pass-fail. Rules (one per profile):
        'level'   - value above a fixed level
        'average' - value at or above mult x the average of `history` (the previous N readings)
        'cross'   - value above another line (`other`)
    Any bad input fails (no trade on bad data).
    """
    if is_bad(value):
        return False
    if rule == "level":
        if level is None:
            raise ValueError("level rule needs a level")
        return value > level
    if rule == "average":
        if not history or any(is_bad(h) for h in history):
            return False
        return value >= mult * (sum(history) / len(history))
    if rule == "cross":
        if is_bad(other):
            return False
        return value > other
    raise ValueError("unknown volume rule: %r" % rule)


def warmed_up(index: int, warmup: int) -> bool:
    """Values on candles before the profile's warm-up count are ignored."""
    return index >= warmup
