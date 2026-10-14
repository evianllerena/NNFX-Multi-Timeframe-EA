# Phase 8 plan amendments: the timeframe shootout (DRAFT for gate G2)

Status: **approved by the owner 2026-10-14 ("all A", DECISIONS OWN-2 (b)); broker OANDA TMS `.pro` (OWN-2 (a)). The G2 verdict is still needed before the first run.** Originally drafted under OWN-1. Every row is a proposal with a default;
the owner decides, the reviewer checks it at gate G2 (`REVIEW_PROTOCOL.md`), and only then does the first shootout run
happen. Rows marked **reopens** change a decision that is already approved (CLAUDE.md: say so when reopening).

Source: the four-reviewer brief (`OPUS_REVIEW_BRIEF.md`, section E) as checked in `docs/REVIEW_OPUS_2026-10-14.md`
(E1-E3 CONFIRMED, E4 PARTLY, the V-check gaps CONFIRMED). The SPEC's shootout (`docs/SPEC.md`, "Timeframe shootout")
stays the frame; these rows change how it is measured. All labels are C (no VP source: these are test design).

## 1. What is wrong with the plan as written (from the review check)

| # | Problem | Why it matters (numbers labelled C, from the review's own simulation) |
| --- | --- | --- |
| E1 | S-8's 30 forward trades per timeframe cannot rank three systems | With R per trade s.d. 1.5-2R, the expectancy's standard error at n = 30 is 0.27-0.37R: a "winner" by less than that is noise, and picking the best of 3 inflates it |
| E2 | The forward window is used twice | Stage 2 confirms indicator sets on it, stage 3 then ranks timeframes on the same window; after that the only clean out-of-sample data is the demo |
| E3 | Return / max drawdown on one short path is the noisiest common metric | At 2% risk and a 40-45% win rate, a 10% drawdown inside 100 trades happens by luck most of the time (simulated P = 0.86-0.99), so the R1 gate admits or kills timeframes on streak luck |
| E4 | Costs come from the wrong broker | Everything so far ran on MetaQuotes-Demo; 30M vs 4H is decided by spread, commission and swap; SPEC says the testing broker is the live broker, which is not chosen |

## 2. Proposed amendments

| ID | Proposal (default) | Alternatives | Reopens |
| --- | --- | --- | --- |
| P8-1 | **Broker first.** The shootout runs on the chosen live broker's history with real ticks ("Every tick based on real ticks", SPEC price model). Default candidate: **OANDA TMS, `.pro` symbols** (hedging, real ticks from 2019, EURUSD.pro from 2018; `docs/ENVIRONMENT.md`). Before the first run: a read-only EnvCheck of commission, swap and spread on the 5 `.pro` pairs, recorded | MetaQuotes-Demo (no retail broker; E4 stays open) | No (SPEC already says so) |
| P8-2 | **Windows.** The whole history 2019.01-2026.09 is split once, before any run: **in-sample 2019.01.01-2024.03.01** (P7-3's window), **forward 2024.03.01-2026.10.01**. Stage 1 and stage 2 use only the in-sample, with a walk-forward inside it (yearly folds: choose on the years before, score on the next year); **stage 3 uses the forward window once**, for the final ranking only | Keep MT5's single 2/3-1/3 forward mode | Yes: SPEC "Tuning vs forward" (one split, used by stages 2 and 3) |
| P8-3 | **Sample.** A timeframe is ranked only with **at least 200 forward trades** (expectancy SE about 0.1R at s.d. 1.5R). If 4H cannot reach it on 5 pairs, the basket grows to more pairs (SPEC: "all 28 if history allows") for every timeframe alike, and the report says so | Keep 30 (S-8) and report the CI so the reader sees the noise | Yes: S-8 (30 forward trades) |
| P8-4 | **Ranking metric.** Rank on **forward expectancy in R per trade, with a bootstrap 90% interval** (10 000 resamples of the trade list). Return / max DD, profit factor, win rate, streaks, % of months positive stay as reported figures | R-Sharpe (mean / s.d. of R per trade) with the same interval | Yes: SPEC "Return / max drawdown: Ranking" |
| P8-5 | **The 10% drawdown gate (R1).** Judged as **P(max drawdown > 10%)** from 10 000 reshuffles of the forward trade sequence at 2% risk, reported with the one real path; a timeframe **fails R1 when that probability is above 50%** | Keep the one real path; or report only | Yes: SPEC "Max drawdown: Gate" (one path) |
| P8-6 | **Many tries.** Every run is already logged (V6/V7); the final report gives the number of configurations tried per timeframe and a **deflated** figure (the expectancy interval widened for that number of tries, Bonferroni on the 90% level) | Report the count only | No |
| P8-7 | **Pre-registered outcomes**, written into DECISIONS before stage 1: (a) the metric (P8-4); (b) **all fail** = no demo; the next step is new indicator candidates, not looser gates; (c) **winners not distinguishable** (90% intervals overlap) = prefer the higher timeframe (fewer trades, lower cost share), then SPEC's tie-break | Split risk across the overlapping timeframes | No (adds) |
| P8-8 | **V15 portfolio risk** (new): from the three instances' trade logs merged in time, the peak **simultaneous open risk** across 30M/1H/4H on one account (M6/M7 limit identical currencies only; correlated pairs stack). Reported; FLAG above 6% (3 x 2%) | Cap it in the EA (a new rule: owner + RULEBOOK) | No (adds) |
| P8-9 | **V16 gap / weekend stress** (new): the realised loss beyond the planned risk per stopped trade (check_trades already lists it as information) summarised per timeframe; plus one re-run with **spreads 50% wider** (SPEC V4 already asks) | - | No (adds) |
| P8-10 | **Calendar completeness**: the event file 2019.01-2026.09 checked against an independent schedule for NFP, CPI and the central-bank rate decisions of the 8 currencies (counts per month), and the unexplained **NFP 2025-11-20 07:30** row explained or fixed, before any run with the news filter | - | No |
| P8-11 | **Costs present** (V4): `summarize_trades.py` FLAGs a run whose commission and swap are both zero; on the chosen broker a run with both zero is invalid | - | No |

## 3. What already exists for this (Phase 7, this branch)

- `tools/check_replay.py`: Check 1b on every continuous tester run (the EA's decisions = the answer key's, every candle).
- `tools/summarize_trades.py`: R per trade from the trade log, money from the tester report, V8 / V10 / V11 / V13 and the
  V4 cost flag. Not yet: the bootstrap interval (P8-4), the reshuffled drawdown (P8-5), V15, V16 - small additions once
  the rows above are decided.
- `tools/run_backtest_set.ps1`: the three timeframes in one go, each checked and summarised.
- `InpTesterDdPause` (P7-2): a backtest measured over its whole window; the first R-12 pause date is reported.

## 4. Order once approved

1. Owner: broker (P8-1); the windows, sample, metric and gate rows (P8-2 to P8-5); pre-registration (P8-7).
2. EnvCheck on the chosen broker (read-only); calendar check (P8-10).
3. Gate G2 packet `G2_phase8_1` with this file as decided; verdict PASS.
4. Stage 1 (reference set, 3 timeframes, in-sample walk-forward) -> G3 packet; stage 2 auditions -> G3; stage 3 forward,
   once -> G3; then the demo (S-9).
