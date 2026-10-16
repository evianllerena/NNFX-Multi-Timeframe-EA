# Exploratory backtest, 2026-10-14 (P7-3, P7-4): where the reference system stands

**Exploratory. It decides nothing** (P7-3): not the Phase 8 shootout, not on the live broker's data, not on real ticks.
It answers one question: does the EA as built, with the reference indicator set and the default settings, show an edge
over 2019-2024 on VP's 5 pairs? **Answer: no, on any of the three timeframes.** Gate G3 packets: `G3_explore_1`, then
`G3_explore_2` after its corrections (2026-10-16: refusals by reason, the DIVERGE rows, a matched-trade comparison of
broker and core, swap in R, P7-4 text; G3_explore_1 F1, F2, note 2). **The conclusion is unchanged.**

## Conditions (fixed before the first run: DECISIONS P7-3; deposit changed once, P7-4)

| Item | Value |
| --- | --- |
| Code | branch `phase-7-crosscheck`, commit `a73ed56` (M30, H1) and `be5c0dc` (H4 re-run; no MQL5 change between them) |
| Data | MetaQuotes-Demo history (not the live broker), MT5 build 6246 / 6259 (MT5 updated itself during the set), history quality 100% |
| Model | Strategy Tester model 1, **1 minute OHLC** (not real ticks); spread as the tester applies it; commission 0 (none on this broker); swap applied |
| Window | **2019.01.01 to 2024.03.01**, the first two-thirds of 2019.01-2026.09. 2024.03-2026.09 **not run** (kept for Phase 8's forward period) |
| System | presets as they are: reference indicators (SMA 20, RVI 10, MACD main, MACD cross, tick volume 20), all defaults, 2% risk, runner cap off, news filter on |
| Pairs | EURUSD, AUDNZD, EURGBP, AUDCAD, CHFJPY, chart EURUSD |
| Deposit | 1 000 000 (P7-4: at 10 000 the M30 account was at 142 by 2019-12 and then most orders were below the minimum lot) |
| R-12 | the 10% drawdown pause computed and logged but not blocking (`InpTesterDdPause=0`, P7-2) |

## Results

R per trade: each half's (exit - entry) x direction / (1.5 x entry ATR), x 1/2 (1R = the initial stop of the whole
trade). "Broker" = the trades the EA actually made in the tester (spread, swap, real fills of model 1). "Core" = the
answer key's own simulation of every signal from the same candles (no costs, candle-only fill assumptions; the EA's
decisions matched it on every candle, below).

| | M30 | H1 | H4 |
| --- | --- | --- | --- |
| Broker trades (ABORT) | 3 205 (0) | 2 482 (1) | 578 (0) |
| Win rate | 36.7% | 42.4% | 42.2% |
| **Expectancy, broker** | **-0.157R** | **-0.094R** | **-0.063R** |
| **Expectancy, core (no costs)** | **-0.020R** (5 330 signals) | **-0.014R** (2 501) | **-0.010R** (578) |
| Total, broker | -504.1R | -232.7R | -36.5R |
| Max drawdown (R, broker) | 505.2R | 232.8R | 38.5R |
| Longest losing streak | 26 | 13 | 12 |
| Months positive | 7% | 21% | 29% |
| Money (deposit 1 000 000) | -100.0% | -99.3% | -57.4% |
| Swap total | -354.71 | -7 234.48 | -50 360.14 |
| R-12 pause would have started | **2019.01.14** | **2019.01.28** | **2019.02.25** |
| Orders refused, by reason (`tools/explore_breakdown.py`) | 2 125: 2 034 below the minimum lot ("too small to size", once the account shrank), 89 OD-5 margin, 2 "half N not opened" | 18: all OD-5 margin | 0 |
| DIVERGE rows (D6f-1), by kind | 2 345: 2 285 "core holds a trade, broker none" (entries skipped, mostly after a refusal), 60 "core flat, broker trade closed" | 172: 134 entries skipped, 38 broker trades closed | 25: 16 entries skipped, 9 broker trades closed |
| R of the broker trades closed by a DIVERGE, against the rest | -0.143R (60) vs -0.158R | +0.001R (38) vs -0.095R | -0.073R (9) vs -0.063R |
| Matched trades: broker - core (same pair and direction, entry within 3 ticks) | -0.125R (2 139 matched) | -0.075R (1 610) | -0.070R (324) |
| Swap in R (closing deals matched to their trade, / that trade's 1R) | -0.6R (-0.0002R per trade) | -4.2R (-0.0017R) | -4.0R (-0.0069R) |
| Every year negative (broker; a trade's year = the year it CLOSED) | yes (2019-2024) | yes | yes (2024: -0.003R on 28 trades) |
| Every pair negative (broker) | yes | yes | yes |

What it says (label C, from these numbers):
1. **No edge before costs.** The core's expectancy is -0.01R to -0.02R on every timeframe: the reference indicators,
   as a set, are at best a coin flip. Per pair, the best core results are AUDCAD (H1 +0.006R, H4 +0.026R), CHFJPY
   (H4 +0.019R) and EURUSD (M30 +0.005R): within noise.
2. **Costs make the loss larger; they are not all of the gap.** *Corrected 2026-10-16 (G3_explore_1 F2).* The broker
   and core trade sets differ: refused orders and DIVERGE rows (above) change which trades the broker takes, and on
   H1 the 38 broker trades closed by a DIVERGE averaged +0.001R against -0.095R for the rest. Compared like for like,
   on the trades both made (matched by pair, direction and entry within 3 ticks; 56-67% of the broker trades), the
   broker is worse than the core by 0.125R per trade on M30, 0.075R on H1, 0.070R on H4. That matched gap is the
   costs (spread at the fill, the fill itself, swap) plus model 1's fill assumptions; it grows as the timeframe
   shrinks and AUDNZD is the worst pair on every timeframe (M30 -0.254R, H1 -0.161R, H4 -0.143R). Swap is small in R
   (H4 -0.0069R per trade; the -50 360 on H4 is money at the 1 000 000 deposit). Label C for "costs" as the cause:
   the comparison shows the size of the gap, not its parts.
3. **The 10% drawdown rule (R-12) stops every timeframe within its first two months.** With this system, R1 fails
   long before any sample is collected.
4. Nothing here says the EA is wrong: it says this indicator set has no edge on this data. Phase 8's indicator auditions,
   on the live broker's real ticks and costs, are the step that can find one (or show there is none).

## The checks on these runs

| Check | M30 | H1 | H4 |
| --- | --- | --- | --- |
| **Check 1b replay** (`check_replay`, every candle, every pair) | **PASS, 0 mismatches / 319 129** | **PASS, 0 / 160 613** | **PASS, 0 / 40 203** |
| check_trades | PASS | PASS | PASS |
| check_news_inputs (with `--warmup`) | PASS (1 628 news flags, 37 X5 exits) | PASS | PASS |
| check_decision_log (with `--bars` and the late-row rules) | PASS | PASS | PASS |
| summarize_trades V13 (net, balance DD, trade count vs the report) | agree | agree | agree |

Found by these long runs and fixed in the checkers (not in the EA), each with tests for the FAIL side:
- **History gaps** (Christmas, New Year, a few hours in June 2021): the checker took every missing candle for an EA
  fault; with the broker's own candles (`NNFX_ExportBars`, `bars_long_20261014_175831`, from 2017) every gap is proved
  to be a gap in the history (M30: 154 gaps or missing rows over 5 pairs).
- **The first row after a gap**: `check_news_inputs` assumed the candle before was there; the EA's flag was right
  (AUDNZD 2019.01.02 06:00 after the New Year gap).
- **Late rows**: in the tester the pairs are visited on the chart symbol's ticks; a pair still trading while EURUSD is
  closed (Christmas) is processed when EURUSD reopens, as a stall catch-up row (fed, never acted on): 34 / 19 / 3 rows,
  0.01% of rows, **none carried an ENTER or EXIT**. Live, a 1 s timer visits the pairs, so this is a tester-only effect.
- **An ABORT logged as `REFUSE <id>`** in the decision log (H1, T1903151800_1: half 2 refused "No money", half 1
  closed at once by the ABORT, as designed).

Open points for the owner (not changed):
- **OD-5 margin pre-check has no buffer**: it checks the margin of both halves against the free margin, but half 1's
  spread cost lowers the free margin before half 2 is sent, so near full use half 2 can be refused (the H1 ABORT above).
  A small buffer would change OD-5: owner decision. *Corrected 2026-10-16 (G3_explore_1 F1):* this is partly an
  artefact of the deposit: at 1 000 000 the positions are large enough for OD-5 to bind at all (all 18 H1 refusals and
  89 on M30 are OD-5); the same 4-month window at 10 000 has no OD-5 refusal.
- The 1 000 000 deposit (P7-4) was set after the first M30 partial result. *Corrected 2026-10-16 (G3_explore_1 F1):*
  it changes no rule, but it does change which trades are taken (the OD-5 refusals above). The effect is small (H1:
  18 of 2 501 signals; M30: 89 of 5 330) and the core's expectancy does not depend on it.
- **The forward window is not untouched by other runs** (G2_phase8_1 F3): these backtests did not run 2024.03-2026.09,
  but every engineering tester run so far (runners, restarts, plants, order runs) used 2026.06.01-2026.10.01 with this
  reference set, and their results have been seen. No setting was tuned on them. Phase 8's plan says how that window
  is treated (P8-2).

## Files

Run folders under `<MT5 data>\MQL5\Files\NNFX\checks\`: `ea_explore2_M30_20261014_165013`,
`ea_explore2_M30_H1_20261014_172116` (the H1 run; the folder name repeats M30 because of a variable-name slip in
`run_backtest_set.ps1`, since fixed), `ea_explore2h4_H4_20261014_175559`; set summaries `backtest_explore2_20261014_165012`,
`backtest_explore2h4_20261014_175558`; bar export `bars_long_20261014_175831`. Kept in `checks\invalid\` with
REASON.txt: the 10 000-deposit M30 run (stopped) and the first H4 attempt (MT5 LiveUpdate shut the terminal).
