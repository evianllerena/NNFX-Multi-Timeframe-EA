# Design note: 6f, the EA (`NNFX_EA.mq5`)

Written before the build (2026-10-06) so the reviewer can check the design, not only the result. Rule and decision
references as elsewhere; **[C]** marks my reading where neither the plan nor an owner decision says it.

## 1. One instance, a basket of pairs (S-1, SPEC Architecture)

One EA instance per timeframe (30M / 1H / 4H presets, magic 26030 / 26060 / 26240, OD-16) trades the preset's pair
list from one chart. Per pair it holds:
- a `CNNFXBarBuilder` (5 indicator slots + ATR, closed candles only);
- a `CNNFXPairCore` (the rules core, the port of `core.py`, **unaltered**);
- its own clock: the open time of the last candle it processed.

## 2. Candle timing (SPEC "Candle timing", R-3, OD-7 (b))

- On every tick and on a 1-second timer, the pairs are visited in the preset's **fixed order**.
- A pair is processed when its own new candle exists: `iTime(pair, tf, 0)` has moved past the last processed
  candle. It is processed once, from shift 1 (the candle that just closed). No pair is read mid-candle.
- At start, a closed candle that is waiting is NOT acted on (OD-7 (b)); the first decision is at the next new candle.
  The waiting candle is still fed to the core during the warm-up replay (section 5) so its memory is right.

## 3. Processing one pair at one candle close

1. **The core's inputs.** BarBuilder gives `NNFXBar` (o h l c, ATR, baseline, C1, C2, exit, volume).
   - `block` = Guard (6d: master, instance, drawdown, daily loss, rollover, weekend, spread, indicator failure)
     + Exposure (6a, M6/M7/OD-4) + News N1/N2 (6e, D6e-3).
   - `news` = the X5 first-close flag (6e).
   - An indicator failure (`raw.ok` false) blocks entries on that pair ("indicator") and is logged.
2. **The core runs** (`OnBar`). Its events for this candle are read: ENTER, EXIT, TRAIL, SKIP, OPEN, SL, TP1, ...
3. **Actions at the broker** (`Orders.mqh`, the only order sender; the safety rule of section 1):
   - ENTER (the core fills at the next open) -> `OpenTrade` now, at the open of the new candle;
   - EXIT -> `CloseRemaining`;
   - TP1, breakeven and trailing stay with `Orders.mqh` (broker-held, T1-T4, from the fill), as in 6b.
4. **D6f-1, aligning core and broker.** For each pair, after the core has run: the core's position (open / flat) vs
   the broker's trade for that pair.
   - Core flat, broker open: close the broker trade at market (owner, option A).
   - Core open, broker flat: no action; no new entry until the core's own simulation closes.
   - Both are logged as a `DIVERGE` row in the decision log.
5. **State** is saved after every trade event, not only at the candle (G1_phase6c_2 note 1).
6. **One decision-log row** per pair per candle (section 6).

## 4. Exposure across the basket (6a)

The pairs' ENTER decisions at one candle time are collected in the fixed order. `NNFXAllocate` gives each its risk
share (mode first/split, OD-4) using every open position on the account. A signal allocated 0 becomes a SKIP with
"exposure". [C] The allocation is per candle time across the pairs processed at that tick; pairs whose candle arrives
on a later tick are allocated with the positions then open.

## 5. Restart: broker rebuild plus core replay [C]

- **The broker side** is 6c unchanged: `Orders.mqh`'s trade map is rebuilt from the broker, the state file and the
  candles (`NNFXRebuildPure`). It waits until MT5 is connected and logged in, +3 s (6c carry-over). Nothing trades
  before that.
- **The core side** is new. The core's memory (previous candle, C1 run, E3/E4 waits, continuation, its simulated
  position) is not in the state file. After the broker rebuild, each pair's core is **replayed** over the closed
  candles from a start point to the last closed candle, with no orders sent. The core is deterministic, so this
  restores the memory an uninterrupted run would have.
- **Start point:** the decision candle of the oldest open trade of that pair minus a warm-up of 50 candles, or a
  warm-up of 300 candles when flat.
- If the replayed core still disagrees with the broker, that is a `DIVERGE` handled as in section 3.4. It is logged,
  never silent.

## 6. Decision log (`DecisionLog.mqh`, F2, for Phase 7)

One CSV row per pair per closed candle, in `Common\Files\NNFX\decisions\<preset>_<mode>.csv`:

`time, symbol, tf, o, h, l, c, atr, base, c1, c2, ex, vol, ind_ok, block, news, events, action, note`

- `events` = the core's events for this candle, `EV:RULE:DIR` joined by ";" (e.g. `ENTER:E1:1`).
- `action` = what was sent to the broker (`OPEN T0007`, `CLOSE T0007`, `DIVERGE close`, ...) or "-".
- The time is the closed candle's open time, so it is always on a candle boundary.
- Phase 7 replays the same inputs through the Python core and compares `events`.

`tools/check_decision_log.py` checks:
- one row per pair per candle (no gap, no duplicate);
- the fixed pair order within a candle time;
- each time on a candle boundary;
- every ENTER that was acted on matches an OPEN in the trade log, and every trade-log OPEN has its ENTER;
- the events well-formed.

## 7. What stays out (plan)

Bar-by-bar comparison with the answer key (Phase 7), the shootout (Phase 8), tuning.
