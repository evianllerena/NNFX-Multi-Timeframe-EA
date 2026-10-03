"""Rule settings and their defaults (docs/SPEC.md, Settings table).

Each field names the rule ID it controls. Defaults are the approved defaults;
tests override single fields to exercise one rule at a time.
"""
from dataclasses import dataclass, field, fields
from typing import Optional


@dataclass
class Settings:
    # Money and trade management
    risk_pct: float = 2.0            # M2, decision R-14 / S-3 (percent of balance)
    sl_atr: float = 1.5              # M3: stop distance in ATRs
    tp1_atr: float = 1.0             # T1: half 1 target in ATRs
    max_dist_atr: float = 1.0        # E1-E3: max distance close <-> baseline, in ATRs

    # T4 trailing stop on half 2 (decision R-1)
    trail_on: bool = True
    trail_start_atr: float = 2.0     # switch on once a close is this many entry-ATRs beyond entry
    trail_dist_atr: float = 1.5      # distance behind the close, in current ATRs

    # T7 runner cap on half 2 (decision R-11); None = off (pure NNFX)
    runner_cap_atr: Optional[float] = None

    # Exits (decision R-2)
    exit_on_exit_ind: bool = True    # X2
    exit_on_c1: bool = True          # X3
    exit_on_baseline: bool = True    # X4
    news_exit: bool = True           # X5

    # Entries
    pullback_on: bool = True         # E3
    one_candle: bool = True          # E4 (decision R-4)
    btf_on: bool = True              # E5 (decision R-5)
    btf_bars: int = 7
    continuation: str = "a"          # E6 (decision R-6): "off", "a" (VP per owner) or "b" (Lesson 11)

    @classmethod
    def from_dict(cls, overrides: dict) -> "Settings":
        known = {f.name for f in fields(cls)}
        unknown = set(overrides) - known
        if unknown:
            raise ValueError("Unknown settings: %s" % sorted(unknown))
        return cls(**overrides)

    def validate(self) -> None:
        if self.continuation not in ("off", "a", "b"):
            raise ValueError("continuation must be 'off', 'a' or 'b'")
        for name in ("risk_pct", "sl_atr", "tp1_atr", "max_dist_atr", "trail_start_atr", "trail_dist_atr"):
            if getattr(self, name) <= 0:
                raise ValueError("%s must be > 0" % name)
        if self.btf_bars < 1:
            raise ValueError("btf_bars must be >= 1")
        if self.runner_cap_atr is not None and self.runner_cap_atr <= 0:
            raise ValueError("runner_cap_atr must be > 0 or None")
