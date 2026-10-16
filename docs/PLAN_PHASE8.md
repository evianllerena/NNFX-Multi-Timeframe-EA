# Phase 8 plan amendments: the timeframe shootout (DRAFT for gate G2)

Status: **approved by the owner 2026-10-14 ("all A", DECISIONS OWN-2 (b)) as drafted then; broker OANDA TMS `.pro`
(OWN-2 (a)). Corrected 2026-10-16 after gate G2 (`G2_phase8_1`: F1 the numbers now come from this system's own trades,
F2 the drawdown gate has a fixed horizon, F3 the forward window): the corrected rows P8-2, P8-3 and P8-5 differ from what
was approved and go back to the owner; the G2 verdict on them (`G2_phase8_2`) is still needed before the first run.**
Originally drafted under OWN-1. Every row is a proposal with a default;
the owner decides, the reviewer checks it at gate G2 (`REVIEW_PROTOCOL.md`), and only then does the first shootout run
happen. Rows marked **reopens** change a decision that is already approved (CLAUDE.md: say so when reopening).

Source: the four-reviewer brief (`OPUS_REVIEW_BRIEF.md`, section E) as checked in `docs/REVIEW_OPUS_2026-10-14.md`
(E1-E3 CONFIRMED, E4 PARTLY, the V-check gaps CONFIRMED). The SPEC's shootout (`docs/SPEC.md`, "Timeframe shootout")
stays the frame; these rows change how it is measured. All labels are C (no VP source: these are test design).

## 1. What is wrong with the plan as written (from the review check)

Numbers (label C) from this system's own trades: the three exploratory runs of P7-3 (`RESULTS_EXPLORE_2026-10-14.md`),
R per trade as `summarize_trades.py` (each half's (exit - entry) x dir / (1.5 x entry ATR), x 1/2), computed by
`tools/gate_numbers.py` (4 000 bootstrap paths, seed 1). *Corrected 2026-10-16 (G2_phase8_1 F1):* the first draft used
the brief's R s.d. of 1.5-2R; the measured s.d. is **0.64R (M30), 0.62R (H1), 0.54R (H4)**.

| # | Problem | Why it matters |
| --- | --- | --- |
| E1 | S-8's 30 forward trades per timeframe cannot rank three systems | At the measured s.d. the expectancy's standard error at n = 30 is 0.10-0.12R (0.27-0.37R in the first draft): a "winner" by less than that is noise, and picking the best of 3 inflates it |
| E2 | The forward window is used twice | Stage 2 confirms indicator sets on it, stage 3 then ranks timeframes on the same window; after that the only clean out-of-sample data is the demo |
| E3 | Return / max drawdown on one short path is the noisiest common metric | At 2% risk a 10% drawdown is a 5R dip. P(it happens within 100 trades) is 0.57-0.71 with no edge and 0.08-0.20 with a real +0.10R edge (the first draft said 0.86-0.99, from s.d. 1.5-2R), and it grows with the number of trades (+0.10R edge, M30: 0.20 at 100, 0.40 at 200, 0.65 at 400). One path decides the R1 gate partly on luck and partly on how many trades the path has |
| E4 | Costs come from the wrong broker | Everything so far ran on MetaQuotes-Demo; 30M vs 4H is decided by spread, commission and swap; SPEC says the testing broker is the live broker, which is not chosen |

## 2. Proposed amendments

| ID | Proposal (default) | Alternatives | Reopens |
| --- | --- | --- | --- |
| P8-1 | **Broker first.** The shootout runs on the chosen live broker's history with real ticks ("Every tick based on real ticks", SPEC price model). Default candidate: **OANDA TMS, `.pro` symbols** (hedging, real ticks from 2019, EURUSD.pro from 2018; `docs/ENVIRONMENT.md`). Before the first run: a read-only EnvCheck of commission, swap and spread on the 5 `.pro` pairs, recorded | MetaQuotes-Demo (no retail broker; E4 stays open) | No (SPEC already says so) |
| P8-2 | **Windows.** The whole history 2019.01-2026.09 is split once, before any run: **in-sample 2019.01.01-2024.03.01** (P7-3's window), **forward 2024.03.01-2026.06.01**. Stage 1 and stage 2 use only the in-sample, with a walk-forward inside it (yearly folds: choose on the years before, score on the next year); **stage 3 uses the forward window once**, for the final ranking only. *Corrected 2026-10-16 (G2_phase8_1 F3):* 2026.06.01-2026.10.01 is **not clean**: every engineering tester run so far (runners, restarts, plants, order runs) used it with the reference set and its results were seen (no setting was tuned on them). Default: the scored forward period **ends at 2026.06.01** (27 months), and 2026.06-2026.10 stays the engineering window | (b) keep the forward period to 2026.10.01 and move every engineering run to an in-sample window from now on (the 4 months already seen stay seen); (c) MT5's single 2/3-1/3 forward mode | Yes: SPEC "Tuning vs forward" (one split, used by stages 2 and 3) |
| P8-3 | **Sample, from a stated target** (*corrected 2026-10-16, G2_phase8_1 F1*; the first draft's 200 was sized for s.d. 1.5R). Target: tell a **+0.10R edge from none at 90% power** (two-sided 5%): at the measured s.d. that needs **311 (H4) to 430 (M30) trades**, so a timeframe is judged only with **at least 430 forward trades** (the largest, the same for all). Telling two timeframes apart by 0.10R at 90% power (two-sided 5%/3, Bonferroni over the 3 pairs of timeframes) needs **800-1 105 trades each**: a ranking is claimed only when the difference is larger than the one detectable at the actual numbers (reported), otherwise P8-7 (c) applies. At the in-sample rates on 5 pairs (about 620 / 480 / 112 trades per 12 months on M30 / H1 / H4) the 27-month forward window gives about 1 400 / 1 080 / 250: 4H cannot reach 430 on 5 pairs, so the basket grows to more pairs (SPEC: "all 28 if history allows") for every timeframe alike, and the report says so | Target 0.15R (fewer trades); or keep 30 (S-8) and report the CI so the reader sees the noise | Yes: S-8 (30 forward trades) |
| P8-4 | **Ranking metric.** Rank on **forward expectancy in R per trade, with a bootstrap 90% interval** (10 000 resamples of the trade list). Return / max DD, profit factor, win rate, streaks, % of months positive stay as reported figures | R-Sharpe (mean / s.d. of R per trade) with the same interval | Yes: SPEC "Return / max drawdown: Ranking" |
| P8-5 | **The 10% drawdown gate (R1), over a fixed horizon** (*corrected 2026-10-16, G2_phase8_1 F2*: over "the forward trade sequence" the probability grows with the number of trades, so the same system would pass at 200 trades and fail at 400). Judged as **P(max drawdown > 10% within 12 months of trading)**, each timeframe at its own trade rate (trades in the forward window / its months), from 10 000 bootstrap paths of its forward trades at 2% risk compounded, reported with the one real path; a timeframe **fails R1 when that probability is above 50%**. Pre-registered with P8-7. What it means at the measured numbers (+0.10R edge): 12 months is about 620 / 480 / 112 trades and P = **0.81 / 0.69 / 0.11** (M30 / H1 / H4): at 2% risk the lower timeframes would fail R1 on calendar risk even with a real edge. That is the owner's risk per year, not path length, but the owner should see it before choosing | (b) a fixed N trades for all timeframes (N = 100: P = 0.20 / 0.18 / 0.08 at +0.10R; it then measures risk per trade, not per year); (c) keep the one real path; or report only | Yes: SPEC "Max drawdown: Gate" (one path) |
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
3. Gate G2 packet (`G2_phase8_1`, CHANGES REQUESTED; `G2_phase8_2` after the corrections) with this file as decided;
   verdict PASS.
4. Stage 1 (reference set, 3 timeframes, in-sample walk-forward) -> G3 packet; stage 2 auditions -> G3; stage 3 forward,
   once -> G3; then the demo (S-9).
