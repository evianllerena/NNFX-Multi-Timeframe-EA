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

## 5. Restart: broker rebuild plus saved core memory [C]

(Revised after the reviewer's note on the first draft, 2026-10-06. A replay alone cannot reproduce past block inputs:
the master switch, the drawdown pause, the daily loss, news and exposure. It could rebuild a different core position,
and D6f-1 would then close a live trade on a restart.)

- **The broker side** is 6c unchanged: `Orders.mqh`'s trade map is rebuilt from the broker, the state file and the
  candles (`NNFXRebuildPure`). It waits until MT5 is connected and logged in, +3 s (6c carry-over). Nothing trades
  before that.
- **The core side: saved, not re-derived.** At every candle close, each pair's core memory is written into the state
  file, with the same atomic write and checksum as 6c (`NNFXSTATE`, FNV-1a). The memory covers: the previous candle's
  signals, the C1 run, E3/E4 waits, the order pending for the next open, continuation, and the simulated position.
  On start, it is restored from there (`CNNFXPairCore::Snapshot` / `Restore`).
- **The replay is a cross-check only.** After the restore, each pair's core is also replayed over recent closed
  candles in a separate copy, with no orders sent. If the replayed copy, the restored memory or the broker disagree,
  that is logged.
- **At start-up a disagreement never closes a broker trade.** It is logged as `DIVERGE` with an alarm (`NNFXNotify`).
  D6f-1 applies only from the **first live candle after the restart**, using the restored memory.
- **A missing or corrupt state file** (6c status `absent` / `corrupt`): the core starts from the replay, and the same
  rule holds. A disagreement at start-up is logged and alarmed, never acted on.
- **Test:** restart with the master switch having blocked an entry earlier. The restored core and the broker agree
  (no trade), nothing is closed, and the replay cross-check shows the difference it would have made, logged as
  information.

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
