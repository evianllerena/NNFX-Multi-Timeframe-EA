# Status

Where the project stands. Update this file in every PR.

Last updated: 2026-10-16.

## Phases

| Phase | State |
| --- | --- |
| 1 Rulebook and spec | Living copies in Claude Docs; snapshots in `docs/` |
| 2 Repo setup | Merged |
| 3 Python answer key | Merged |
| 4 MQL5 rules core | Merged (PR #3) |
| 5 Indicator slots and profiles | Merged: PR #4 (at `58e2994`, before the G1_phase5_1 fixes; see note below) and PR #5 (the reviewed fixes, `0e701dd`) |
| 6 Orders, risk, recovery, guard, news, EA | Plan: gate G2 **PASS** (`G2_phase6_1`), `docs/PLAN_PHASE6.md`; owner decisions OD-1 to OD-21 (OD-3 updated), D6c-1 to D6c-3, D6d-1 to D6d-4 and D-OPS-1 in `docs/DECISIONS.md`. **6a** merged (PR #6). **6b** merged (PR #7). **6c state and recovery** merged (PR #8, `G1_phase6c_2` PASS, merge `016bc3f`). **6d guard:** merged (PR #9, `G1_phase6d_1` PASS, merge `0e542f2`); daily loss account-wide (D6d-5). **6e news:** merged (PR #10, `G1_phase6e_2` PASS, merge `49ddad5`). **6f the EA:** branch `phase-6f-ea` (draft PR #11). Done and passing on d80dd0e: runner `20261006_224137`, planted bugs 12 of 12, two identical 4-month runs, presets, both restart tests, demo crash tests (TP1, pause). The first 1H demo smoke test (from 2026-10-06 22:57) was cut by a PC power loss after 24.0 h (logs PASS up to the cut; in `invalid\`); the EA's restart after that hard stop restored its memory and closed nothing (`demo_ea_powercut_restart_20261007_234154`). The 1H demo smoke test from the start passed (26 h, `demo_ea_smoke_20261008_000411`, `OVERALL: PASS`; its start-up exercised D6f-2 on the open AUDNZD trade). The MT5-offline check (D6b-1) passed on 2026-10-09 with the owner's firewall rule (runner part `20261009_104221`, EA part `demo_ea_offline_20261009_103426`; rule removed). Next, with the owner: the chart buttons clicked by hand; then packet G1_phase6f_1. (C8, 2026-10-14: the MT5-offline check is done, see below.) |
| Review 2026-10-13 | Every claim checked against the code: `docs/REVIEW_OPUS_2026-10-14.md`. **First fix set** (A7 hedging only, B3 no pointless retries, A10 ATR 0 refused, A4 fill price initialised, N-1 trail setting reaches the order side) on branch `review-fixes-1` (into `phase-6f-ea`, draft PR #12): Python 201 tests OK, 4/4 Python planted bugs caught. On the owner PC 2026-10-14 (3feaaf7, MT5 build 6246): compiled 18 of 18 with 0 errors, 0 warnings, `run_phase5_checks.ps1` run `20261014_151945` `OVERALL: PASS` (SafetyTest 43/43, OrderMathTest 22/22); 4-month H1 tester run with `InpTrailOn=false` (`ea_trailoff_h1_4m_20261014_152457`) PASS, `check_trades.py --trail-off` PASS (no TRAILON/TRAIL, BE 22); 3 of 3 MT5 planted bugs caught (`planted_rf1_20261014_152606`). **Gate: packet `G1_review1_1`, waiting for the verdict.** Next fix sets proposed (not started): A1 + A8 (pending-action retries), A5, then A2 + A3 restart fixes with `recovery.py` in lockstep |
| Review fixes set 2 | Branch `review-fixes-2` (base `review-fixes-1`), under OWN-1 (owner, 2026-10-14: steps 1-6 unattended; stacked branches, never merged by Claude). RV-A7b (hedging check after login), RV-A1 (breakeven retried; half 2 closed at market if the price has passed it), RV-A8 (closes price-checked and retried, failed ones pending). On 2738a0f: runner `20261014_161353` OVERALL PASS (OrderMathTest 41/41; both retry paths seen in the order run), restart test `restart_20261014_162207` PASS, 6f planted bugs 12 of 12, cold start on the demo PASS. `G1_review2_1`: CHANGES REQUESTED (F1 breakeven not restored after a restart or a TP1 while stopped; F2 a pending close after a restart). Applied 2026-10-16 ("apply review"): MaintainBreakeven checks every trade after TP1; a rebuilt lone half 1 (ABORT leftover) is closed; restart cases R5/R6; every tester ini pins Deposit=10000 / Leverage=1:100 (G1_phase7_1 F1). On 8447d33: runner `20261016_142931` PASS (deposit 10 000, 89 trades, 0 REFUSE), restart `restart_20261016_144100` PASS (R5, R6 included), planted 4 of 4 new + 5 of 5 set 2 + 12 of 12 6f, cold start PASS. **Gate: packet `G1_review2_2`.** |
| 7 Bar-by-bar cross-check (Check 1b) | Branch `phase-7-crosscheck` (base `review-fixes-2`), under OWN-1. `tools/check_replay.py` replays the EA's logged inputs through the answer key: **0 mismatches** over 10 555 (4-month H1), 319 129 (M30), 160 613 (H1) and 40 203 (H4, 5 years) candles; 3 of 3 planted bugs caught. `tools/summarize_trades.py` (V8, V10, V11, V13). **First backtest look** (exploratory, 2019-2024.02, MetaQuotes data, 1 min OHLC): the reference indicator set has **no edge** (before costs -0.01 to -0.02R per trade on every timeframe; after costs -0.16R M30, -0.09R H1, -0.06R H4): `docs/RESULTS_EXPLORE_2026-10-14.md`. `G1_phase7_1`: CHANGES REQUESTED (F1: `-Deposit` leaked 1 000 000 into every later tester run); `G3_explore_1`: CHANGES REQUESTED, write-up only, "the conclusion stands" (F1 refusals mislabelled, F2 DIVERGE rows not reported). Applied 2026-10-16 ("apply review"): every tester ini pins the deposit and leverage and the report is read back; the write-up splits refusals by reason, reports DIVERGE rows and a matched-trade comparison (broker - core -0.125 / -0.075 / -0.070R), swap in R; P7-2 and P7-4 texts corrected. On 788ea18: runner `20261016_150525` PASS (deposit 10 000, 89 trades, replay 0 / 10 555), planted 3 of 3. **Gates: `G1_phase7_2` and `G3_explore_2`.** |
| 8 Timeframe shootout | **Plan amendments drafted** (`docs/PLAN_PHASE8.md`, P8-1 to P8-11, answering the review's section E: the live broker first, walk-forward windows, 200+ forward trades, expectancy with bootstrap intervals, the R1 gate as a probability, V15 portfolio risk, V16 gap stress). Nothing approved. `G2_phase8_1`: CHANGES REQUESTED (F1 numbers not this system's, F2 no fixed horizon for the drawdown gate, F3 forward window used by engineering runs); corrected 2026-10-16 on "apply review": measured R s.d. 0.54-0.64R (`tools/gate_numbers.py`), P8-3 from a stated target (430 forward trades per timeframe), P8-5 over 12 months of trading, forward period ending 2026.06.01 by default. **Gate: `G2_phase8_2`.** |
| 7 onward | See `docs/SPEC.md` |

**Note (2026-10-04):** PR #4 was merged at `58e2994` on 2026-10-04 15:47 UTC, 4.5 minutes after review
G1_phase5_1 returned CHANGES REQUESTED and before its fixes. The fix commits `521013b`, `bb4c381` and `6c80511`
were pushed to the merged branch afterwards, so they did not reach `main`. This PR (branch `phase-5-fixes`)
brings them to `main` (merged 2026-10-04 as `0e701dd`). Guards against a repeat: `docs/REVIEW_PROTOCOL.md`, "Merge safety".

## OANDA TMS (candidate live broker, D6c-2)

Read-only EnvCheck on demo 62316800 (`docs/ENVIRONMENT.md`): hedging, EUR account, server GMT+2. Open points:
- **Symbol class: settled. The EA uses the `.pro` symbols on OANDA TMS.** Plain EURUSD/EURGBP are trade mode
  DISABLED (server path `Forex\...`, fixed 2400-point spread, no swaps). `EURUSD.pro` / `EURGBP.pro` are trade mode
  FULL (`PRO\FX\Major\...`, spread 8 at 06:32 server). Re-run `oanda_envcheck_pro_20261006_003214`, read-only.
- **Rollover:** 17:00 New York = 23:00 server on OANDA (D1 opens 00:00 server = 18:00 New York); the 6d rollover block
  is keyed to the real rollover per broker, never to server midnight (`docs/PLAN_PHASE6.md` 6d).
- **Phase 8 input:** real ticks on the `.pro` pairs from 2019 (EURUSD.pro from 2018) in the probe.

## Waiting on the owner

- **After 25 Oct and after 1 Nov 2026 (D6d-4):** the reviewer checks each broker's server time against GMT, to
  confirm the clock-change rules assumed in `tests/fixtures/guard/guard_cases.txt`: OANDA TMS GMT+1 in winter on the
  EU rule, MetaQuotes-Demo GMT+2 in winter on the US rule. Until then they are settings, not facts.
- **Review verdicts, oldest first** (each PR is a draft stacked on the one before; merge in this order once PASS):
  `G1_review1_1` (#12), `G1_review2_1` (#13), `G1_phase7_1` + `G3_explore_1` (#14), `G2_phase8_1` (#15, the
  Phase 8 plan and the section-C records), `G1_review3_1` (#16). `G1_phase6f_1` (#11) still needs the chart buttons
  clicked by hand first.
- **Decisions only the owner can take** (all proposals, nothing applied without you): the Phase 8 plan rows P8-1 to
  P8-11 (`docs/PLAN_PHASE8.md`), above all **the live broker** (P8-1: OANDA TMS `.pro` proposed); P7-2
  (`InpTesterDdPause`, tester only); DOC-C5 (dead-market rules left out of backtests); DOC-C6 (T5 as three variants);
  DOC-C7 (keep or drop I-13 (b)'s "C1 and C2 agreeing"); the OD-5 margin buffer (`docs/RESULTS_EXPLORE_2026-10-14.md`).
- **Phase 8 choices raised by `G2_phase8_1`** (defaults in `docs/PLAN_PHASE8.md`): where the forward period ends (P8-2:
  2026.06.01, or keep 2026.10.01 and move the engineering runs in-sample); the detection target behind the sample size
  (P8-3: 0.10R); the drawdown gate's horizon (P8-5: 12 months, or a fixed N trades; at 2% risk M30 and H1 would fail
  12 months even with a +0.10R edge). Reviewer's notes, not added to the plan: record the first real-tick date per
  `.pro` pair in the P8-1 EnvCheck; report R per year beside R per trade (P8-4).
- **C4 (review 2026-10-13): the approval gap.** I-1, I-2, I-3, I-7, I-9 still "awaiting tick" and D5-1 to D5-5
  "pending review", while the code built on them is merged since Phase 4/5. Either tick them in the living rulebook doc
  (then the `docs/RULEBOOK.md` snapshot is refreshed) or record one blanket approval in DECISIONS.
- **The snapshot sync list** `docs/SNAPSHOT_SYNC_2026-10-14.md` (C2, C3): edits for the living SPEC/RULEBOOK docs.
- Choose the live broker (`docs/ENVIRONMENT.md`; MetaQuotes-Demo is not a retail broker): P8-1 above.

## Done since the last review (moved here, C8)

- MT5-offline check (carry-over 1; G1_phase6b_1 F3, D6b-1): **done 2026-10-09**, both parts PASS (`docs/VERIFICATION.md`);
  the firewall rule was added and removed through admin prompts the owner approved.

## Answered by the Phase 5b runs (2026-10-04)

- MT5 runs scripts and the Strategy Tester from a `/config` file on this PC: **yes**
  (runs `20261004_113357` and `20261004_115428`; terminal log "successfully initialized from start config").
- The tester can read `Common\Files\NNFX\profiles`: **yes** (the repaint check loaded all 5 profiles and wrote its report).
- The Phase 5b changes to `NNFX_ExportBars.mq5` and `BarBuilder.mqh` compile with 0 errors, 0 warnings.
- Scripts started from `/config` can begin before MT5 has logged in (G1_phase5_1 F1). Scripts that read
  server data now wait for login (`MQL5/Include/NNFX/Connection.mqh`). The EnvCheck numbers from run
  `20261004_113357` were read before login and are not used.

## Do not use

Files in `C:\Users\Evision\Downloads` other than the phase bundles (`fix*.patch`,
`FIX*_FOR_AGENT.txt`, `FIX6_7_7b_SPEC.txt`, `MASTER_HANDOFF_NNFX.txt`, `POST_RESET_KICKOFF.txt`,
`NNFX_CANONICAL_RULEBOOK_source.txt`, `RULEBOOK_ADDENDUM_NEWS.txt`) were not produced by this
project's process and their origin is unverified. Do not apply them to this repo.
