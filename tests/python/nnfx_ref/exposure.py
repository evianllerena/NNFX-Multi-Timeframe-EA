"""Same-currency exposure (rulebook M6, M7; decision S-4).

Each position is split into its two currencies with direction:
long EUR/USD = long EUR + short USD. Only same-direction exposure on a currency
counts (S-4). A currency may carry one full-risk trade per direction.

Modes for new signals on the same candle:
    'first' - signals are taken in a fixed order; a signal that would add a second
              same-direction trade on a currency is skipped (default).
    'split' - signals that conflict only with each other (not with an open position)
              are each taken at half risk (VP's "1% on each"). A conflict with an
              open position is still skipped. Three or more signals on one leg are
              all skipped (decision OD-4).

Open positions on symbols that are not a pair of two of the 8 major currencies
(rulebook P1), such as XAUUSD, are ignored with a log line (decision OD-21). A trade
counts until it is fully closed, a breakeven runner included (decision OD-20): the
caller lists every open position, whatever its stop.
"""
from typing import Dict, List, Optional, Sequence, Tuple

Leg = Tuple[str, int]  # (currency, direction)

# The 8 majors whose 28 pairs VP trades (rulebook P1).
MAJORS = ("USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "NZD")


def currencies(symbol: str) -> Tuple[str, str]:
    """Base and quote currency from a symbol such as 'EURUSD' or 'EURUSD.m'.
    Brokers add suffixes; the first six letters are used."""
    letters = "".join(ch for ch in symbol if ch.isalpha()).upper()
    if len(letters) < 6:
        raise ValueError("cannot read currencies from %r" % symbol)
    return letters[:3], letters[3:6]


def is_fx(symbol: str) -> bool:
    """True if the symbol is a pair of two different major currencies (OD-21)."""
    try:
        base, quote = currencies(symbol)
    except ValueError:
        return False
    return base in MAJORS and quote in MAJORS and base != quote


def legs(symbol: str, direction: int) -> List[Leg]:
    if direction not in (1, -1):
        raise ValueError("direction must be +1 or -1")
    base, quote = currencies(symbol)
    return [(base, direction), (quote, -direction)]


def allocate(open_positions: Sequence[Tuple[str, int]], signals: Sequence[Tuple[str, int]],
             risk_pct: float, mode: str = "first", log: Optional[List[str]] = None) -> List[float]:
    """Return the risk percentage for each new signal (0.0 = skipped), in signal order.
    open_positions: (symbol, direction) of every open position on the account.
    log: if given, a line is appended for every open position that is ignored."""
    if mode not in ("first", "split"):
        raise ValueError("mode must be 'first' or 'split'")
    for sym, _ in signals:
        if not is_fx(sym):
            raise ValueError("signal on a non-FX symbol: %r" % sym)
    held = set()
    for sym, d in open_positions:
        if not is_fx(sym):
            if log is not None:
                log.append("exposure: ignored non-FX position %s" % sym)
            continue
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
