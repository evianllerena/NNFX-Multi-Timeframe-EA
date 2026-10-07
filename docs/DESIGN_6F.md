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
- **A missing or corrupt state file** (6c status `absent` / `corrupt`): ~~the core starts from the replay~~ **as built
  (section 8.4): the core starts flat**, warmed up over recent candles with entries blocked ("start"), so it never
  invents a position; the same rule holds. A disagreement at start-up is logged and alarmed, never acted on.
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

## 8. As built (2026-10-06): what the build settled

Each item says where it is and how it was checked. **[C]** = my reading, for the reviewer and the owner.

1. **Visits.** Live: every tick and a 1-second timer. Tester: the chart symbol's ticks only (1 minute OHLC gives one
   at least every minute; a 1-second timer would add millions of empty events to a 3-month run). Start-up is "ready"
   when every pair's last closed candle builds (all indicator values present): `AllCalculated`, used by the scripts,
   never becomes true in the tester (run `ea_dbg_start_20261006_*`).
2. **Batches [C].** Each pair keeps its own clock, so a pair whose new candle arrives after the others' (typically
   at the daily rollover) is processed in a later visit. Its decision row's note starts `batch N;`. The fixed order
   holds within each batch, and `check_decision_log.py` checks rows sorted by (batch, place in the preset's list).
   Waiting for every pair before processing a candle time was not chosen: SPEC says no pair waits for another.
3. **Block reasons in the decision log:** the guard's words (master, instance, drawdown, dailyloss, rollover, weekend,
   spread, indicator) + `N1 <cur> <event> <time>` / `N2 <cur>` + `exposure` + `diverge` (below) + `missed` (a candle
   not seen live) + `newsfile` (the event file could not be read: no entry, safe side). `start` is used only for the
   warm-up candles, which are not logged.
4. **Exposure (section 4) as built:** a trial run of each pair's core on a copy (Snapshot/Restore) finds the ENTERs;
   `NNFXAllocate` allocates them over every open position on the account; a signal allocated 0 gets the block reason
   `exposure` and the real core run then SKIPs it, so the decision log's block explains it and Phase 7 can replay it.
   Split mode's half risk is passed to `OpenTrade` and noted on the row.
5. **D6f-1 as built.** After the actions: core flat (no position, or an exit pending at the next open) and the broker
   holds a trade on the pair -> `CloseRemaining`, action `DIVERGE close <id>`, a DIVERGE trade-log row and an alarm.
   Core holding (or entering) and the broker flat -> action `DIVERGE wait` on every such row, one alarm per episode.
   Before the core runs, a pair whose broker trade is open while the core is flat gets the block reason `diverge`,
   so a second trade on that pair can never open (e.g. a D6f-1 close that failed). Seen in the tester: a broker stop
   hit by the spread at the Friday rollover while the core's simulated stop was not (EURGBP 2026-08-07, the 4-month
   H1 run; a 30M case 2026-09-24). Both "wait" episodes ended when the core closed.
6. **Restart as built.** The state file gained one line per pair, `PCORE|<sym>|<last candle it processed>|<core
   snapshot>`, inside the same checksum and atomic write (Python and MQL5 alike; 6c files without PCORE read as
   before; RecoveryTest adds the PCORE files and byte-for-byte rewrites). On start each pair is restored with its own
   clock; the candles it missed, including the one waiting now, are fed to its core with block `missed` and logged
   ("missed while stopped (OD-7 (b))"), never acted on, but **open trades stay managed**: the broker trail
   (`Orders.OnBarClose`) runs for those candles too (S-2; found by the open-trade restart test, which skipped one
   trail step before the fix). More missed candles than `InpWarmupBars` (300): the saved memory is treated as too old
   and the pair starts flat. The same "missed" path is used if a pair ever falls more than one candle behind live.
7. **The cross-check replay** feeds the last 300 closed candles to a separate core with no block except news (it
   cannot know the master switch, the pause, the daily loss or exposure) and is information only: `the replay
   agrees` / `the replay differs: information only` on the start-up row.
8. **A broker trade the core does not know: owner decision D6f-2 (2026-10-07), as built.** After a start WITHOUT saved memory
   (no state file, a corrupt one, or memory too old), the broker may hold a trade the flat core knows nothing about.
   D6f-1 would close it at the first live candle, because the core is "flat" only for lack of memory. As built, that
   trade is left to its broker-held stop, TP1, breakeven and trail (Orders.mqh), and the pair takes no new entry
   while it is open (block `diverge`); the start-up row and an alarm say so. The other choice (close it at once) was not chosen.
9. **Trade IDs** are `T<yymmddhhmm of the decision candle>_<place in the preset's list>`: one entry per pair per
   candle, deterministic, so two runs give the same IDs. Nothing keys on them after a restart (a "deal history only"
   rebuild gives `R<ticket>`; 6c carry-over).
10. **News live: owner decision D6f-3 (2026-10-07), as built.** OD-12 says the CSV is "refreshed daily by the export script". The script cannot be started by
    `/config` while the same terminal runs the EA, so the export code moved into `CalendarExport.mqh` unchanged
    (Aug-Sep 2026 rows byte-identical, run `calendar_export_20261006_205916`) and the EA, live only, runs it at start
    (after login) and once per GMT day into `Common\Files\NNFX\calendar\events_live.txt` (last month to next month),
    then reads that file back through `NNFXNewsLoad`, the tester's path. The 24-hour age alarm and the recency alarm
    (no event in the next 24 hours) run hourly. `InpNewsFile=auto` (the presets) means this; the tester refuses
    `auto` and must name an exported history file. If the file cannot be read, entries are blocked (`newsfile`).
11. **Presets: owner decision D6f-4 (2026-10-07), as written.** The plan says to save them from MT5's settings dialog; an agent cannot click it. They are written
    by `tools/make_presets.py` in the format MT5 itself writes (copied from MT5's own `Profiles\Tester\NNFX_EA.set`),
    every input listed, the EA's defaults, own magic, and proved by loading each in the tester with
    `ExpertParameters=` and no `[TesterInputs]` (`tools/check_presets_mt5.ps1`). The owner may re-save them from the
    dialog at any time.
12. **Carry-overs closed in 6f:** state after every trade event (`OnTradeTransaction`); the Algo Trading pre-check and
    no retry on 10026/10027 (Orders.mqh); the slippage window, approach (b) of G1_phase6b_2 note 3: a forced adverse
    fill in the test EA (`InpAdverseOn`) and the `check_trades.py` window rule "risk with the stop sent <= target +
    the slippage"; the drawdown pause, peak, reset and instance switch flushed to disk on change
    (`GlobalVariablesFlush`), proved by a demo hard kill with the pause on; the master test records and restores
    `NNFX_MASTER`; the test-EA log texts; a second M5 recovery case; the account-flat step in `run_demo_restarts.ps1`
    (judged on this magic and the test magics; the whole account is reported, since the 1H smoke EA's own trades may
    be open on the same demo account [C]); news into the core checked end to end (`check_news_inputs.py`).
