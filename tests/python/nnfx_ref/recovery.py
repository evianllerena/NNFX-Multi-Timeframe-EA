"""State file and restart rebuild (Phase 6c; docs/PLAN_PHASE6.md sections 4 and 9).

SPEC, "Rebuilding after a restart": on start-up the EA rebuilds its memory from what the broker holds:
which open positions are halves of one trade (magic + trade ID; state file; deal history), whether TP1
filled (deal history), the breakeven/trailing stage, whether a continuation is still allowed (price
history since the original entry) and the last exit direction (deal history).

Rules used here and in MQL5/Include/NNFX/State.mqh (the same, line for line):

  pairing    each of our entry (IN) deals gets (trade id, half) from, in order: its comment
             "NNFX <id> h<1|2>" (unless comments are ignored), the state file's position map, or a
             fallback: entry deals with the same symbol, second, direction and volume, in deal order,
             are paired as half 1 / half 2 of trade "R<half-1 position>". A comment that disagrees with
             the state file wins (the broker holds it) and the disagreement is noted.
  broker     open/closed halves, entries, lots, half 2's stop and "TP1 filled" (half 1 closed by a
             deal with reason TP) come from the broker only. The state file is never trusted for them.
  state      only for what the broker does not hold: the entry ATR and the runner cap of a trade,
             if the file is present, valid (version + checksum) and has that trade id.
  fallback   entry ATR: the ATR of the decision candle (the last candle that closed at or before the
             entry); runner cap: |TP - entry| / entry ATR from half 2's target, or off (-1).
  trail      on if TP1 filled and a candle from TP1's candle on closed 2 x entry ATR beyond half 2's
             entry (T4, I-11); evaluated only up to the last candle the EA processed.
  continue   per symbol, from the latest trade (open or closed): trend = its direction, armed, C1 not
             flipped; replayed over the candles from its entry candle to the last processed candle:
             while armed, a close on the far side of the baseline disarms it, and C1 against the trend
             sets C1-flipped (core.py, I-12). Last exit direction = the direction of the latest trade
             with every half closed.
"""
import calendar
import re
import time as _time
from dataclasses import dataclass
from typing import Dict, List, Tuple

STATE_VERSION = "1"
_COMMENT = re.compile(r"^NNFX (\S+) h([12])$")


def tparse(text: str) -> int:
    """'YYYY.MM.DD HH:MM[:SS]' -> seconds (naive server time, as MQL5 datetime)."""
    fmt = "%Y.%m.%d %H:%M:%S" if text.count(":") == 2 else "%Y.%m.%d %H:%M"
    return calendar.timegm(_time.strptime(text.strip(), fmt))


def tfmt(sec: int) -> str:
    """seconds -> 'YYYY.MM.DD HH:MM' (MQL5 TimeToString(t, TIME_DATE | TIME_MINUTES))."""
    return _time.strftime("%Y.%m.%d %H:%M", _time.gmtime(sec))


def fnv1a32(text: str) -> int:
    h = 0x811C9DC5
    for b in text.encode("ascii"):
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


@dataclass
class Trade:
    id: str
    sym: str
    dir: int
    pos1: int = 0
    pos2: int = 0
    open1: bool = False
    open2: bool = False
    lots: float = 0.0
    entry1: float = 0.0
    entry2: float = 0.0
    atr_entry: float = 0.0
    cap: float = -1.0
    sl2: float = 0.0
    tp1_done: bool = False
    trail_active: bool = False


@dataclass
class Cont:
    sym: str
    trend_dir: int = 0
    armed: bool = False
    c1_flipped: bool = False
    last_exit_dir: int = 0
    since: int = 0


def num(v: float) -> str:
    return "%.10g" % v


def trade_line(t: Trade) -> str:
    return "TRADE|%s|%s|%d|%d|%d|%d|%d|%s|%s|%s|%s|%s|%s|%d|%d" % (
        t.id, t.sym, t.dir, t.pos1, t.pos2, int(t.open1), int(t.open2), num(t.lots), num(t.entry1),
        num(t.entry2), num(t.atr_entry), num(t.cap), num(t.sl2), int(t.tp1_done), int(t.trail_active))


def cont_line(c: Cont) -> str:
    return "CONT|%s|%d|%d|%d|%d|%s" % (c.sym, c.trend_dir, int(c.armed), int(c.c1_flipped), c.last_exit_dir,
                                        tfmt(c.since))


def serialize(trades: List[Trade], conts: List[Cont]) -> List[str]:
    """Canonical lines: trades sorted by id, then continuation states sorted by symbol."""
    return [trade_line(t) for t in sorted(trades, key=lambda t: t.id)] + \
           [cont_line(c) for c in sorted(conts, key=lambda c: c.sym)]


CORE_FIELDS = 35   # "CORE|1|" + 33 fields: CNNFXPairCore::Snapshot (MQL5/Include/NNFX/RulesCore.mqh, Phase 6f)


def core_line(sym: str, processed: int, snapshot: str) -> str:
    """Phase 6f (DESIGN_6F section 5): one pair's rules-core memory, saved at every candle close, with the open time
    of the last candle that pair processed (each pair keeps its own clock)."""
    return "PCORE|%s|%s|%s" % (sym, tfmt(processed), snapshot)


def state_file_text(instance: str, trades: List[Trade], conts: List[Cont], processed: int,
                    cores: Dict[str, Tuple[int, str]] = None) -> str:
    """cores: symbol -> (last processed candle, core snapshot); 6f EA only, the 6c test EA writes none. PCORE lines
    sorted by symbol."""
    body = ["NNFXSTATE|%s|%s" % (STATE_VERSION, instance), "PROC|%s" % tfmt(processed)] + serialize(trades, conts)
    body += [core_line(s, cores[s][0], cores[s][1]) for s in sorted(cores or {})]
    text = "\n".join(body) + "\n"
    return text + "CHECKSUM|%08x\n" % fnv1a32(text)


def parse_trade(p: List[str]) -> Trade:
    return Trade(p[1], p[2], int(p[3]), int(p[4]), int(p[5]), p[6] == "1", p[7] == "1", float(p[8]), float(p[9]),
                 float(p[10]), float(p[11]), float(p[12]), float(p[13]), p[14] == "1", p[15] == "1")


def parse_state_file(text: str, cores_out: Dict[str, Tuple[int, str]] = None) -> Tuple[str, List[Trade], List[Cont], int, str]:
    """(status, trades, conts, processed, why): status 'present' or 'corrupt'. PCORE lines (6f) go to cores_out
    (symbol -> (last processed candle, snapshot)) if given; their content is checked when the core restores it, not here."""
    lines = text.replace("\r\n", "\n").split("\n")
    while lines and lines[-1] == "":
        lines.pop()
    if not lines or not lines[-1].startswith("CHECKSUM|"):
        return "corrupt", [], [], 0, "no checksum line"
    body = "\n".join(lines[:-1]) + "\n"
    if "%08x" % fnv1a32(body) != lines[-1].split("|")[1].strip().lower():
        return "corrupt", [], [], 0, "checksum mismatch"
    head = lines[0].split("|")
    if len(head) < 2 or head[0] != "NNFXSTATE" or head[1] != STATE_VERSION:
        return "corrupt", [], [], 0, "wrong header or version"
    trades, conts, proc, cores = [], [], 0, {}
    try:
        for ln in lines[1:-1]:
            p = ln.split("|")
            if p[0] == "PROC":
                proc = tparse(p[1])
            elif p[0] == "TRADE" and len(p) == 16:
                trades.append(parse_trade(p))
            elif p[0] == "CONT" and len(p) == 7:
                conts.append(Cont(p[1], int(p[2]), p[3] == "1", p[4] == "1", int(p[5]), tparse(p[6])))
            elif p[0] == "PCORE" and len(p) == 3 + CORE_FIELDS and p[3] == "CORE":
                cores[p[1]] = (tparse(p[2]), "|".join(p[3:]))
            else:
                return "corrupt", [], [], 0, "unreadable line %r" % ln
    except (ValueError, IndexError):
        return "corrupt", [], [], 0, "unreadable number"
    if cores_out is not None:
        cores_out.update(cores)
    return "present", trades, conts, proc, ""


@dataclass
class Position:
    pos: int
    sym: str
    magic: int
    dir: int
    volume: float
    price: float
    sl: float
    tp: float
    comment: str


@dataclass
class Deal:
    deal: int
    time: int
    pos: int
    sym: str
    magic: int
    entry: str      # IN or OUT
    dir: int        # the position's direction
    volume: float
    price: float
    reason: str     # EXPERT, SL, TP, CLIENT, ...
    comment: str


@dataclass
class Candle:
    sym: str
    time: int       # open time
    close: float
    atr: float
    side: int       # close vs baseline: +1 above, -1 below, 0 on it
    c1: int         # C1 direction


def rebuild(positions: List[Position], deals: List[Deal], state_status: str, state_trades: List[Trade],
            candles: List[Candle], period: int, magic: int, upto: int,
            ignore_comments: bool = False) -> Tuple[List[Trade], List[Cont], List[str]]:
    """Rebuilt (open trades, continuation states, notes). upto: open time of the last processed candle."""
    notes = ["state file: %s" % state_status]
    st_ok = state_status == "present"
    st_by_pos: Dict[int, Tuple[str, int]] = {}
    st_by_id: Dict[str, Trade] = {}
    if st_ok:
        for t in state_trades:
            st_by_id[t.id] = t
            st_by_pos[t.pos1] = (t.id, 1)
            if t.pos2:
                st_by_pos[t.pos2] = (t.id, 2)

    ins = sorted([d for d in deals if d.magic == magic and d.entry == "IN"], key=lambda d: (d.time, d.deal))
    keyed: Dict[int, Tuple[str, int]] = {}
    unresolved: List[Deal] = []
    for d in ins:
        m = None if ignore_comments else _COMMENT.match(d.comment or "")
        from_state = st_by_pos.get(d.pos)
        if m:
            keyed[d.pos] = (m.group(1), int(m.group(2)))
            if from_state and from_state != keyed[d.pos]:
                notes.append("disagree position %d: comment %s h%d, state %s h%d; comment used"
                             % (d.pos, keyed[d.pos][0], keyed[d.pos][1], from_state[0], from_state[1]))
        elif from_state:
            keyed[d.pos] = from_state
        else:
            unresolved.append(d)
    # fallback: same symbol, second, direction and volume, in deal order. The trade ID is "R" + half 1's position
    # ticket (the first IN deal of the pair): deterministic, the same on every rebuild of the same history (G1_phase6c_1
    # F3). The note logs each mapping: "fallback id R31 = positions 31+32" (a lone half: "= position 21").
    groups: Dict[Tuple, List[Deal]] = {}
    for d in unresolved:
        groups.setdefault((d.sym, d.time, d.dir, round(d.volume, 8)), []).append(d)
    for g in groups.values():
        for k in range(0, len(g), 2):
            tid = "R%d" % g[k].pos
            keyed[g[k].pos] = (tid, 1)
            if k + 1 < len(g):
                keyed[g[k + 1].pos] = (tid, 2)
        notes.append("fallback pairing: %s" % ",".join(str(d.pos) for d in g))
        for k in range(0, len(g), 2):
            if k + 1 < len(g):
                notes.append("fallback id R%d = positions %d+%d" % (g[k].pos, g[k].pos, g[k + 1].pos))
            else:
                notes.append("fallback id R%d = position %d" % (g[k].pos, g[k].pos))

    open_pos = {p.pos: p for p in positions if p.magic == magic}
    outs: Dict[int, Deal] = {}
    for d in sorted(deals, key=lambda d: (d.time, d.deal)):
        if d.magic == magic and d.entry == "OUT":
            outs[d.pos] = d
    by_trade: Dict[str, Dict[int, Deal]] = {}
    for d in ins:
        tid, half = keyed[d.pos]
        by_trade.setdefault(tid, {})[half] = d

    sym_candles: Dict[str, List[Candle]] = {}
    for c in sorted(candles, key=lambda c: c.time):
        if c.time <= upto:
            sym_candles.setdefault(c.sym, []).append(c)

    out_trades: List[Trade] = []
    all_trades: List[Tuple[int, str, int, bool, int]] = []   # (entry time, sym, dir, fully closed, last out time)
    for tid, halves in by_trade.items():
        h1, h2 = halves.get(1), halves.get(2)
        first = h1 or h2
        t = Trade(tid, first.sym, first.dir)
        if h1:
            t.pos1, t.entry1, t.lots = h1.pos, h1.price, h1.volume
            t.open1 = h1.pos in open_pos
        if h2:
            t.pos2, t.entry2 = h2.pos, h2.price
            t.lots = t.lots or h2.volume
            t.open2 = h2.pos in open_pos
        o1 = outs.get(t.pos1) if h1 else None
        t.tp1_done = bool(o1 and o1.reason == "TP")
        closed = not t.open1 and not t.open2
        last_out = max([outs[p].time for p in (t.pos1, t.pos2) if p and p in outs] or [0])
        all_trades.append((first.time, t.sym, t.dir, closed, last_out))
        if closed:
            continue
        if t.open2:
            t.sl2 = open_pos[t.pos2].sl
        st = st_by_id.get(tid)
        if st:
            t.atr_entry, t.cap = st.atr_entry, st.cap
            for name in ("open1", "open2", "sl2", "tp1_done"):
                if getattr(st, name) != getattr(t, name):
                    notes.append("disagree %s %s: state %s, broker %s; broker used"
                                 % (tid, name, getattr(st, name), getattr(t, name)))
        else:
            dec = [c for c in sym_candles.get(t.sym, []) if c.time + period <= first.time]
            t.atr_entry = dec[-1].atr if dec else 0.0
            if not dec:
                notes.append("%s: no decision candle for the entry ATR" % tid)
            if t.open2 and open_pos[t.pos2].tp != 0 and t.atr_entry > 0:
                t.cap = round(abs(open_pos[t.pos2].tp - t.entry2) / t.atr_entry, 2)
            else:
                t.cap = -1.0
        if t.tp1_done and t.open2 and t.atr_entry > 0:
            start = o1.time - o1.time % period
            for c in sym_candles.get(t.sym, []):
                if c.time >= start and (c.close - t.entry2) * t.dir >= 2.0 * t.atr_entry - 1e-12:
                    t.trail_active = True
                    break
        out_trades.append(t)

    conts: List[Cont] = []
    for sym in sorted({a[1] for a in all_trades}):
        mine = sorted([a for a in all_trades if a[1] == sym])
        last = mine[-1]
        c = Cont(sym, last[2], True, False, 0, last[0] - last[0] % period)
        for cd in sym_candles.get(sym, []):
            if cd.time < c.since or not c.armed:
                continue
            if cd.side == -c.trend_dir:
                c.armed = False
            if cd.c1 == -c.trend_dir:
                c.c1_flipped = True
        done = [a for a in mine if a[3]]
        if done:
            c.last_exit_dir = max(done, key=lambda a: (a[4], a[0]))[2]
        conts.append(c)
    return out_trades, conts, notes
