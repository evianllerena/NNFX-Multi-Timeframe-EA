"""News answer key (Phase 6e; docs/PLAN_PHASE6.md section 6).

RULEBOOK [A]:
  N1  Major news on a currency in the next 24 hours -> no new trade on that currency.
  N2  Elections and referendums -> don't trade that currency at all until settled (a blackout list, OD-19).
  X5  Major news within 24 hours on a currency you hold: exit if losing, or if in profit by less than 1 x ATR.
      I-10: checked at the FIRST candle close inside the 24-hour window.
Owner: D6e-1 (the approved event list, news/news_events.txt), D6e-2 (N1 and X5 unchanged).

The news block (owner rule D6e-3, 2026-10-06; replaces the first build's "t < e <= t + 24 h", review G1_phase6e_1
F1). For each event e:
  news day   the trading day e falls in: 17:00 New York to 17:00 New York (OD-3 update). An event at exactly
             17:00 New York starts a new day. A news day that would end on a Saturday or Sunday ends on Monday.
  start      the EARLIER of (a) 15:00 New York on the previous trading day (the weekday before the news day's close
             date: Monday's is Friday) and (b) 24 hours before e (VP's "24 hours")
  end        the 17:00 New York close that ends the news day; trading resumes at that close
  N1 blocks a pair at the candle close t when either of its currencies has an event with start <= t < end (so an
     event exactly at a candle close is inside its own block), or t is inside an N2 blackout [from, to] (whole days,
     00:00 to 23:59 of 'to', server time).
  X5's flag is true at the first candle close inside an event's block: t inside it and the previous ACTUAL close
     not inside THAT event's block. Two events with different blocks give two flags.
Owner's examples: a Friday 08:30 NFP blocks EUR/USD from Thursday 08:30 New York (24 h before) to the Friday 17:00
close; Australian jobs at 20:30 Wednesday New York block from Tuesday 20:30 to Thursday 17:00.
Candle closes and event times are server times; the block is worked out in New York time and converted with the
broker's clock rule (guard.py).

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


def utc_to_ny(u: datetime) -> datetime:
    s, e = guard.us_dst_dates(u.year)
    edt = datetime(s.year, s.month, s.day, 7) <= u < datetime(e.year, e.month, e.day, 6)
    return u - timedelta(hours=4 if edt else 5)


def ny_to_utc(ny: datetime) -> datetime:
    """A New York wall-clock time (15:00 or 17:00 here, never in the changeover hour) to UTC."""
    s, e = guard.us_dst_dates(ny.year)
    return ny + timedelta(hours=4 if s <= ny.date() < e else 5)


def _weekday_on_or_after(d):
    while d.weekday() >= 5:
        d += timedelta(days=1)
    return d


def _weekday_before(d):
    d -= timedelta(days=1)
    while d.weekday() >= 5:
        d -= timedelta(days=1)
    return d


def block_window(e_server: datetime, broker: "guard.Broker") -> Tuple[datetime, datetime]:
    """D6e-3: the block of one event, as (start, end) in SERVER time; a close t is blocked when start <= t < end."""
    u = guard.server_to_utc(broker, e_server)
    ny = utc_to_ny(u)
    close_date = ny.date() + timedelta(days=1) if ny.hour >= 17 else ny.date()
    close_date = _weekday_on_or_after(close_date)
    prev = _weekday_before(close_date)
    a = ny_to_utc(datetime(prev.year, prev.month, prev.day, 15))
    b = u - WINDOW
    end = ny_to_utc(datetime(close_date.year, close_date.month, close_date.day, 17))
    return guard.utc_to_server(broker, min(a, b)), guard.utc_to_server(broker, end)


def in_block(t: datetime, e: datetime, broker: "guard.Broker") -> bool:
    start, end = block_window(e, broker)
    return start <= t < end


def blocked(sym: str, t: datetime, events: Sequence[Event], broker: "guard.Broker",
            blackouts: Sequence[Blackout] = ()) -> List[str]:
    """N1 and N2 reasons at the candle close t, e.g. ["N1 USD Nonfarm Payrolls 2026.06.05 15:30", "N2 GBP"]."""
    curs = currencies(sym)
    why = []
    for ev in events:
        if ev.currency in curs and in_block(t, ev.time, broker):
            why.append("N1 %s %s %s" % (ev.currency, ev.name, fmt_time(ev.time)))
    for b in blackouts:
        if b.currency in curs and b.start <= t <= b.end:
            why.append("N2 %s" % b.currency)
    return why


def first_close(sym: str, t: datetime, prev_t: Optional[datetime], events: Sequence[Event],
                broker: "guard.Broker") -> bool:
    """X5 / I-10 with D6e-3: true at the first candle close inside some event's block. prev_t is the previous ACTUAL
    candle close (across a weekend that is Friday's last close); None = the first candle seen."""
    curs = currencies(sym)
    return any(ev.currency in curs and in_block(t, ev.time, broker)
               and (prev_t is None or not in_block(prev_t, ev.time, broker)) for ev in events)
