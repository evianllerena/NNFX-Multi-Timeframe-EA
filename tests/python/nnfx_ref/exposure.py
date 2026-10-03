"""Same-currency exposure (rulebook M6, M7; decision S-4).

Each position is split into its two currencies with direction:
long EUR/USD = long EUR + short USD. Only same-direction exposure on a currency
counts (S-4). A currency may carry one full-risk trade per direction.

Modes for new signals on the same candle:
    'first' - signals are taken in a fixed order; a signal that would add a second
              same-direction trade on a currency is skipped (default).
    'split' - signals that conflict only with each other (not with an open position)
              are each taken at half risk (VP's "1% on each"). A conflict with an
              open position is still skipped.
"""
from typing import Dict, List, Sequence, Tuple

Leg = Tuple[str, int]  # (currency, direction)


def currencies(symbol: str) -> Tuple[str, str]:
    """Base and quote currency from a symbol such as 'EURUSD' or 'EURUSD.m'.
    Brokers add suffixes; the first six letters are used."""
    letters = "".join(ch for ch in symbol if ch.isalpha()).upper()
    if len(letters) < 6:
        raise ValueError("cannot read currencies from %r" % symbol)
    return letters[:3], letters[3:6]


def legs(symbol: str, direction: int) -> List[Leg]:
    if direction not in (1, -1):
        raise ValueError("direction must be +1 or -1")
    base, quote = currencies(symbol)
    return [(base, direction), (quote, -direction)]


def allocate(open_positions: Sequence[Tuple[str, int]], signals: Sequence[Tuple[str, int]],
             risk_pct: float, mode: str = "first") -> List[float]:
    """Return the risk percentage for each new signal (0.0 = skipped), in signal order.
    open_positions: (symbol, direction) of every open position on the account."""
    if mode not in ("first", "split"):
        raise ValueError("mode must be 'first' or 'split'")
    held = set()
    for sym, d in open_positions:
        held.update(legs(sym, d))

    if mode == "first":
        taken = set(held)
        out = []
        for sym, d in signals:
            my = set(legs(sym, d))
            if my & taken:
                out.append(0.0)
            else:
                out.append(risk_pct)
                taken |= my
        return out

    # split
    out = [0.0] * len(signals)
    eligible = []
    for i, (sym, d) in enumerate(signals):
        if not (set(legs(sym, d)) & held):
            eligible.append(i)
    counts: Dict[Leg, int] = {}
    for i in eligible:
        for leg in legs(*signals[i]):
            counts[leg] = counts.get(leg, 0) + 1
    for i in eligible:
        shared = max(counts[leg] for leg in legs(*signals[i]))
        if shared == 1:
            out[i] = risk_pct
        elif shared == 2:
            out[i] = risk_pct / 2.0
        else:
            out[i] = 0.0  # three or more on one leg: not covered by VP's rule; skip
    return out
