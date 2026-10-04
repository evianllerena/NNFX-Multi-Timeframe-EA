"""Indicator profiles (profiles/README.md): parse, validate, and turn raw values
into a direction. The MQL5 parser (MQL5/Include/NNFX/Profile.mqh) applies the same
rules; tests/python/test_profiles.py covers them.
"""
import re
from dataclasses import dataclass, field
from typing import List, Optional, Sequence

from . import signals

SLOTS = ("BASELINE", "C1", "C2", "EXIT", "VOLUME")
SOURCES = ("builtin", "custom")
BUILTINS = ("MA", "RVI", "MACD", "VOLUMES", "MOMENTUM")
SIGNALS = ("price_line", "two_line", "centre_line", "volume")
VOL_RULES = ("level", "average", "cross")
INPUT_TYPES = ("int", "double", "bool", "string", "enum")
ENUMS = ("MODE_SMA", "MODE_EMA", "MODE_SMMA", "MODE_LWMA",
         "PRICE_CLOSE", "PRICE_OPEN", "PRICE_HIGH", "PRICE_LOW", "PRICE_MEDIAN",
         "PRICE_TYPICAL", "PRICE_WEIGHTED", "VOLUME_TICK", "VOLUME_REAL")
ALLOWED = {"BASELINE": ("price_line",), "C1": ("two_line", "centre_line"),
           "C2": ("two_line", "centre_line"), "EXIT": ("two_line", "centre_line"),
           "VOLUME": ("volume",)}
KEYS = ("name", "slot", "source", "indicator", "input", "signal", "buf_main", "buf_fast",
        "buf_slow", "centre", "vol_rule", "vol_level", "vol_period", "vol_mult", "buf_other",
        "warmup", "notes")


class ProfileError(ValueError):
    pass


@dataclass
class Profile:
    name: str = ""
    slot: str = ""
    source: str = ""
    indicator: str = ""
    inputs: List[tuple] = field(default_factory=list)   # (type, text value)
    signal: str = ""
    buf_main: Optional[int] = None
    buf_fast: Optional[int] = None
    buf_slow: Optional[int] = None
    centre: Optional[float] = None
    vol_rule: Optional[str] = None
    vol_level: Optional[float] = None
    vol_period: Optional[int] = None
    vol_mult: Optional[float] = None
    buf_other: Optional[int] = None
    warmup: Optional[int] = None
    notes: str = ""

    def buffers(self) -> List[int]:
        """Output lines this profile reads, in a fixed order."""
        if self.signal == "two_line":
            return [self.buf_fast, self.buf_slow]
        if self.signal == "volume" and self.vol_rule == "cross":
            return [self.buf_main, self.buf_other]
        return [self.buf_main]


def _int(key, text):
    if not re.fullmatch(r"-?\d+", text):
        raise ProfileError("%s must be a whole number, got %r" % (key, text))
    return int(text)


# Same number grammar as the MQL5 reader (Profile.mqh NNFXIsNumber): optional sign, digits with
# at most one '.', optional exponent. (Python's float() alone would also accept "1_0" or "inf".)
_NUM = re.compile(r"[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?")


def _num(key, text):
    if not _NUM.fullmatch(text):
        raise ProfileError("%s must be a number, got %r" % (key, text))
    v = float(text)
    if signals.is_bad(v):
        raise ProfileError("%s must be a finite number" % key)
    return v


def parse(text: str) -> Profile:
    p = Profile()
    seen = set()
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ProfileError("line %d: expected key=value" % n)
        key, value = (s.strip() for s in line.split("=", 1))
        if key not in KEYS:
            raise ProfileError("line %d: unknown key %r" % (n, key))
        if key != "input":
            if key in seen:
                raise ProfileError("line %d: %s given twice" % (n, key))
            seen.add(key)
        if key == "input":
            if ":" not in value:
                raise ProfileError("line %d: input must be type:value" % n)
            t, v = value.split(":", 1)
            if t not in INPUT_TYPES:
                raise ProfileError("line %d: unknown input type %r" % (n, t))
            if t == "int":
                _int("input", v)
            elif t == "double":
                _num("input", v)
            elif t == "bool" and v not in ("true", "false"):
                raise ProfileError("line %d: bool input must be true or false" % n)
            elif t == "enum" and v not in ENUMS:
                raise ProfileError("line %d: unknown enum %r" % (n, v))
            p.inputs.append((t, v))
        elif key in ("buf_main", "buf_fast", "buf_slow", "buf_other", "vol_period", "warmup"):
            setattr(p, key, _int(key, value))
        elif key in ("centre", "vol_level", "vol_mult"):
            setattr(p, key, _num(key, value))
        else:
            setattr(p, key, value)
    validate(p)
    return p


def validate(p: Profile) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_]+", p.name or ""):
        raise ProfileError("name is required (letters, digits, _)")
    if p.slot not in SLOTS:
        raise ProfileError("slot must be one of %s" % (SLOTS,))
    if p.source not in SOURCES:
        raise ProfileError("source must be builtin or custom")
    if not p.indicator:
        raise ProfileError("indicator is required")
    if p.source == "builtin" and p.indicator not in BUILTINS:
        raise ProfileError("unknown builtin indicator %r" % p.indicator)
    if p.signal not in SIGNALS:
        raise ProfileError("signal must be one of %s" % (SIGNALS,))
    if p.signal not in ALLOWED[p.slot]:
        raise ProfileError("slot %s cannot use signal %s" % (p.slot, p.signal))
    if p.warmup is None or p.warmup < 0:
        raise ProfileError("warmup is required and must be >= 0")
    if p.signal == "two_line":
        if p.buf_fast is None or p.buf_slow is None:
            raise ProfileError("two_line needs buf_fast and buf_slow")
        if p.buf_fast == p.buf_slow:
            raise ProfileError("buf_fast and buf_slow must differ")
    else:
        if p.buf_main is None:
            raise ProfileError("%s needs buf_main" % p.signal)
    if p.signal == "centre_line" and p.centre is None:
        raise ProfileError("centre_line needs centre (never defaulted to 0)")
    if p.signal == "volume":
        if p.vol_rule not in VOL_RULES:
            raise ProfileError("volume needs vol_rule: level, average or cross")
        if p.vol_rule == "level" and p.vol_level is None:
            raise ProfileError("vol_rule=level needs vol_level")
        if p.vol_rule == "average":
            if p.vol_period is None or p.vol_period < 1:
                raise ProfileError("vol_rule=average needs vol_period >= 1")
            if p.vol_mult is None or p.vol_mult <= 0:
                raise ProfileError("vol_rule=average needs vol_mult > 0")
        if p.vol_rule == "cross" and p.buf_other is None:
            raise ProfileError("vol_rule=cross needs buf_other")
    for b in p.buffers():
        if b is None or b < 0:
            raise ProfileError("buffer numbers must be >= 0")


def load(path: str) -> Profile:
    with open(path, encoding="ascii") as f:
        return parse(f.read())


def direction(p: Profile, values: Sequence[Optional[float]], close: Optional[float] = None) -> int:
    """Direction for a direction slot. values = raw readings of p.buffers() in order.
    price_line also needs the candle's close."""
    if p.signal == "price_line":
        return signals.price_line_dir(close, values[0])
    if p.signal == "two_line":
        return signals.two_line_dir(values[0], values[1])
    if p.signal == "centre_line":
        return signals.centre_line_dir(values[0], p.centre)
    raise ProfileError("%s is not a direction signal" % p.signal)


def volume_passes(p: Profile, value: Optional[float], history: Sequence[float] = (),
                  other: Optional[float] = None) -> bool:
    """history = the previous vol_period readings (average rule only)."""
    if p.signal != "volume":
        raise ProfileError("not a volume profile")
    return signals.volume_pass(p.vol_rule, value, level=p.vol_level, history=list(history),
                               mult=p.vol_mult if p.vol_mult is not None else 1.0, other=other)
