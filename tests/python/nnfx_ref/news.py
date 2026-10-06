"""News answer key (Phase 6e; docs/PLAN_PHASE6.md section 6).

RULEBOOK [A]:
  N1  Major news on a currency in the next 24 hours -> no new trade on that currency.
  N2  Elections and referendums -> don't trade that currency at all until settled (a blackout list, OD-19).
  X5  Major news within 24 hours on a currency you hold: exit if losing, or if in profit by less than 1 x ATR.
      I-10: checked at the FIRST candle close inside the 24-hour window.
Owner: D6e-1 (the approved event list, news/news_events.txt), D6e-2 (N1 and X5 unchanged).

Definitions used here (all times are the broker's server time, as the calendar export writes them):
  an event at time e is "within 24 hours" of a candle close at t when  t < e <= t + 24 h
  N1 blocks a pair at t when either of its currencies has such an event, or is inside an N2 blackout
     [from, to] (whole days, from 00:00 to 23:59 of 'to')
  X5's flag is true at the candle close t when, for some event e of either currency, t is inside e's window and
     the previous candle close (t - period) was not inside THAT event's window: the first close inside it. Two
     events close together give two flags, one at the first close inside each window.

Event matching (D6e-1, R-15 roles not names): an event of currency C matches a list entry of C when its id is one
of the entry's ids OR its name matches the entry's pattern ("*" = any text, e.g. "Fed Chair * Speech"), so a new
chair's speech, with a new id, is still caught.
"""
from dataclasses import dataclass
from datetime import datetime, timedelta
from fnmatch import fnmatchcase
from typing import Iterable, List, Optional, Sequence, Tuple

from . import guard

WINDOW = timedelta(hours=24)


@dataclass(frozen=True)
class Entry:
    currency: str
    vp: str
    pattern: str
    ids: Tuple[str, ...]


@dataclass(frozen=True)
class Event:
    time: datetime
    currency: str
    event_id: str
    name: str


@dataclass(frozen=True)
class Blackout:
    currency: str
    start: datetime   # 00:00 of the first day
    end: datetime     # 23:59 of the last day


def parse_time(s: str) -> datetime:
    return datetime.strptime(s, "%Y.%m.%d %H:%M")


def fmt_time(t: datetime) -> str:
    return t.strftime("%Y.%m.%d %H:%M")


def load_entries(lines: Iterable[str]) -> List[Entry]:
    out = []
    for line in lines:
        line = line.strip()
        if not line.startswith("EVENT|"):
            continue
        _, cur, vp, pattern, ids = line.split("|")
        out.append(Entry(cur, vp, pattern, tuple(x for x in ids.split(",") if x)))
    return out


def match(entries: Sequence[Entry], currency: str, event_id: str, name: str) -> Optional[Entry]:
    for e in entries:
        if e.currency == currency and (event_id in e.ids or fnmatchcase(name, e.pattern)):
            return e
    return None


def load_export(lines: Iterable[str], broker: "guard.Broker") -> List[Event]:
    """The export file stores UTC (the calendar gives history in TODAY's server offset; run
    calendar_export_20261006_181154). Each time becomes the broker's server time for its date (guard.py rule)."""
    out = []
    for ln in lines:
        p = ln.rstrip("\r\n").split("|")
        if ln.startswith("#") or len(p) != 5 or p[0] == "time_utc":
            continue
        out.append(Event(guard.utc_to_server(broker, parse_time(p[0])), p[1], p[2], p[3]))
    return out


def currencies(sym: str) -> Tuple[str, str]:
    s = sym.upper()
    return s[:3], s[3:6]


def parse_blackouts(text: str) -> List[Blackout]:
    """Preset format: "CUR:YYYY.MM.DD-YYYY.MM.DD;CUR:..." ("" = none, OD-19)."""
    out = []
    for item in [x for x in text.split(";") if x.strip()]:
        cur, span = item.strip().split(":")
        a, b = span.split("-")
        start = datetime.strptime(a, "%Y.%m.%d")
        end = datetime.strptime(b, "%Y.%m.%d") + timedelta(hours=23, minutes=59)
        out.append(Blackout(cur.upper(), start, end))
    return out


def in_window(t: datetime, e: datetime) -> bool:
    return t < e <= t + WINDOW


def blocked(sym: str, t: datetime, events: Sequence[Event], blackouts: Sequence[Blackout] = ()) -> List[str]:
    """N1 and N2 reasons at the candle close t, e.g. ["N1 USD Nonfarm Payrolls 2026.06.05 15:30", "N2 GBP"]."""
    curs = currencies(sym)
    why = []
    for ev in events:
        if ev.currency in curs and in_window(t, ev.time):
            why.append("N1 %s %s %s" % (ev.currency, ev.name, fmt_time(ev.time)))
    for b in blackouts:
        if b.currency in curs and b.start <= t <= b.end:
            why.append("N2 %s" % b.currency)
    return why


def first_close(sym: str, t: datetime, prev_t: Optional[datetime], events: Sequence[Event]) -> bool:
    """X5 / I-10: true at the first candle close inside some event's 24-hour window. prev_t is the previous ACTUAL
    candle close (across a weekend that is Friday's last close, not t - period); None = the first candle seen."""
    curs = currencies(sym)
    return any(ev.currency in curs and in_window(t, ev.time) and (prev_t is None or not in_window(prev_t, ev.time))
               for ev in events)
