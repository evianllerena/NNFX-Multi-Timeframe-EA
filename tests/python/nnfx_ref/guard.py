"""Guard answer key (Phase 6d; docs/PLAN_PHASE6.md section 5).

The switches and limits that block NEW entries (open trades keep being managed, S-2):

  master     terminal-wide switch (a global variable). Missing = OFF (D6d-1)
  instance   this instance's switch
  drawdown   equity <= 90% of the peak equity, sampled at each candle close (R-12 [A], OD-2); reset by hand only (S-6)
  dailyloss  the trading day's closed-trade P/L <= -3 x risk % of the day's starting balance (S-5, OD-3 + update)
  rollover   15 min before to 60 min after the trading day boundary (R-10, M9 [A]); end exclusive
  weekend    the last N hours before the Friday boundary; N = 0 (off) by default (S-7)
  spread     spread > the max spread; max 0 = off (not set until spreads are measured)
  indicator  an indicator failed to load or returned empty values on this pair

The block string lists the reasons in that fixed order, comma separated ("" = not blocked).

The trading day boundary (OD-3 update, owner 2026-10-06): 17:00 New York, the real rollover, in the broker's server
time. New York follows US daylight saving: 17:00 EDT = 21:00 UTC (2nd Sunday of March to the 1st Sunday of
November), 17:00 EST = 22:00 UTC otherwise. The server's offset follows the broker's own rule, a setting:
  Broker(winter_offset_hours, dst) with dst "none", "EU" (last Sunday of March 01:00 UTC to the last Sunday of
  October 01:00 UTC) or "US" (2nd Sunday of March 07:00 UTC to the 1st Sunday of November 06:00 UTC).
The two daylight-saving calendars are separate: in the weeks where they differ the boundary moves by an hour on a
broker that follows the EU rule. Never "server midnight".
All times here are naive datetimes; "server" times are the broker's clock, "utc" times are UTC.
"""
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from typing import Iterable, List, Optional, Sequence, Tuple

ORDER = ("master", "instance", "drawdown", "dailyloss", "rollover", "weekend", "spread", "indicator")
ROLL_BEFORE = timedelta(minutes=15)
ROLL_AFTER = timedelta(minutes=60)
DD_PAUSE = 0.10            # R-12: 10% below the peak
DAILY_LOSS_X = 3.0         # S-5: 3 x risk per trade


@dataclass(frozen=True)
class Broker:
    name: str
    winter_offset: int     # hours east of UTC outside daylight saving
    dst: str               # "none", "EU" or "US"


def _nth_sunday(year: int, month: int, n: int) -> date:
    d = date(year, month, 1)
    d += timedelta(days=(6 - d.weekday()) % 7)
    return d + timedelta(days=7 * (n - 1))


def _last_sunday(year: int, month: int) -> date:
    d = date(year + (month == 12), month % 12 + 1, 1) - timedelta(days=1)
    return d - timedelta(days=(d.weekday() - 6) % 7)


def us_dst_dates(year: int) -> Tuple[date, date]:
    return _nth_sunday(year, 3, 2), _nth_sunday(year, 11, 1)


def eu_dst_dates(year: int) -> Tuple[date, date]:
    return _last_sunday(year, 3), _last_sunday(year, 10)


def _dst_active(rule: str, utc: datetime) -> bool:
    if rule == "none":
        return False
    if rule == "EU":
        s, e = eu_dst_dates(utc.year)
        return datetime(s.year, s.month, s.day, 1) <= utc < datetime(e.year, e.month, e.day, 1)
    if rule == "US":
        s, e = us_dst_dates(utc.year)
        return datetime(s.year, s.month, s.day, 7) <= utc < datetime(e.year, e.month, e.day, 6)
    raise ValueError("unknown daylight-saving rule %r" % rule)


def server_offset(b: Broker, utc: datetime) -> timedelta:
    return timedelta(hours=b.winter_offset + (1 if _dst_active(b.dst, utc) else 0))


def server_to_utc(b: Broker, t: datetime) -> datetime:
    for h in (b.winter_offset + 1, b.winter_offset):
        u = t - timedelta(hours=h)
        if server_offset(b, u) == timedelta(hours=h):
            return u
    return t - timedelta(hours=b.winter_offset)   # the skipped hour of a spring change


def utc_to_server(b: Broker, utc: datetime) -> datetime:
    return utc + server_offset(b, utc)


def ny_close_utc(d: date) -> datetime:
    """17:00 New York on New York date d, in UTC."""
    s, e = us_dst_dates(d.year)
    return datetime(d.year, d.month, d.day, 21 if s <= d < e else 22)


def trading_day_start(b: Broker, t: datetime) -> datetime:
    """The latest 17:00 New York at or before server time t, in server time."""
    u = server_to_utc(b, t)
    c = ny_close_utc(u.date())
    if c > u:
        c = ny_close_utc(u.date() - timedelta(days=1))
    return utc_to_server(b, c)


def next_boundary(b: Broker, t: datetime) -> Tuple[datetime, date]:
    """The first 17:00 New York strictly after server time t: (server time, its New York date)."""
    u = server_to_utc(b, t)
    d = u.date() - timedelta(days=1)
    while ny_close_utc(d) <= u:
        d += timedelta(days=1)
    return utc_to_server(b, ny_close_utc(d)), d


def in_rollover(b: Broker, t: datetime) -> bool:
    start = trading_day_start(b, t + ROLL_BEFORE)
    return start - ROLL_BEFORE <= t < start + ROLL_AFTER


def in_weekend_block(b: Broker, t: datetime, hours: float) -> bool:
    if hours <= 0:
        return False
    nb, nyd = next_boundary(b, t)
    return nyd.weekday() == 4 and t >= nb - timedelta(hours=hours)


def daily_loss(b: Broker, t: datetime, balance_now: float, risk_pct: float,
               closed: Iterable[Tuple[datetime, float]]) -> Tuple[float, float, bool]:
    """(today's net closed P/L, the limit as a negative amount, blocked). Closed trades only (OD-3); the day starts
    at the trading day boundary (OD-3 update). Limit = 3 x risk % of the day's starting balance, which is the
    balance now minus today's closed P/L; exactly the limit blocks (D6d-2)."""
    start = trading_day_start(b, t)
    pl = sum(p for (ct, p) in closed if start <= ct <= t)
    day_start_balance = balance_now - pl
    limit = -DAILY_LOSS_X * risk_pct / 100.0 * day_start_balance
    return pl, limit, pl <= limit + 1e-9


@dataclass
class Drawdown:
    peak: float = 0.0
    paused: bool = False

    def sample(self, equity: float) -> None:
        """At each candle close (OD-2): the peak of equity; pause at 10% below it. Never resets itself (S-6)."""
        self.peak = max(self.peak, equity)
        if equity <= self.peak * (1.0 - DD_PAUSE) + 1e-9:
            self.paused = True

    def reset(self, equity: float) -> None:
        """By hand only (S-6, D6d-3): the pause ends and the peak restarts from the equity now; logged by the caller."""
        self.paused = False
        self.peak = equity


def blocks(master: Optional[bool], instance_on: bool, dd_paused: bool, dl_blocked: bool, rollover: bool,
           weekend: bool, spread: float, max_spread: float, indicator_ok: bool) -> str:
    """master None = the global variable is missing (counts as off)."""
    on = {
        "master": master is not True,
        "instance": not instance_on,
        "drawdown": dd_paused,
        "dailyloss": dl_blocked,
        "rollover": rollover,
        "weekend": weekend,
        "spread": max_spread > 0 and spread > max_spread,
        "indicator": not indicator_ok,
    }
    return ",".join(k for k in ORDER if on[k])


def parse_time(s: str) -> datetime:
    return datetime.strptime(s, "%Y.%m.%d %H:%M")


def fmt_time(t: datetime) -> str:
    return t.strftime("%Y.%m.%d %H:%M")


def run_drawdown(tokens: Sequence[str]) -> List[Tuple[int, float]]:
    """Tokens "E:<equity>/<balance>" (a candle-close sample) or "R" (a reset by hand). Returns (paused, peak) after each."""
    dd, out, last = Drawdown(), [], 0.0
    for tok in tokens:
        if tok == "R":
            dd.reset(last)
        else:
            eq = float(tok[2:].split("/")[0])
            last = eq
            dd.sample(eq)
        out.append((1 if dd.paused else 0, dd.peak))
    return out
