# Changelog

Newest first.

## 2026-10-06 — Phase 6c: state and recovery

- `MQL5/Include/NNFX/State.mqh`: the state file (`NNFXSTATE|1`, FNV-1a checksum, atomic write via `.tmp` and
  `FileMove`, per instance in `MQL5\Files\NNFX\state\`, OD-9) and the pure restart rebuild `NNFXRebuildPure`. The
  broker wins for open halves, lots, half 2's stop and TP1 (deal reason TP). The file adds only the entry ATR and the
  runner cap, with fallbacks from the candles. Pairing: order comment, then the file's position map, then
  same-second fallback. No trading calls.
- `Orders.mqh`: `ExportTrades`, `ImportTrades`, `Reconcile` (guard first). `TradeLog.mqh`: append mode.
- Answer key `nnfx_ref/recovery.py` with `tests/fixtures/recovery/` (22 cases, 5 state files; `.txt`, not the
  plan's JSON) and `test_recovery.py`; `NNFX_RecoveryTest.mq5` (30 checks).
- `NNFX_OrderTest`: STATE rows, the state file, simulated restarts in the tester (`InpRestartAt`, delete state,
  ignore comments) and real restarts (PRESTOP/REBUILD rows).
- `tools/compare_runs.py`, `pick_restart_times.py`, `run_restart_tests.ps1` (test a, tester) and
  `run_demo_restarts.ps1` (test b, real restarts on the demo). Tester runs list every input.
- Runner: RecoveryTest, the DealReport compile, D6c-1 (only the tested terminal by full path; account check).
  `test_process_safety.py` checks that nothing closes MT5 by name.
- Owner decisions: D6c-1, D6c-2 (OANDA TMS read-only; `.pro` symbols settled), D6c-3 (the demo driver handles its
  own MT5 relaunch or restart), OD-3 update (one trading day boundary at 17:00 New York; PLAN 6d).
- Results: restart test (a) PASS; restart test (b) on the demo PASS (`demo_restart_20261006_002457`, REBUILDS
  MATCH 5 of 5); planted bugs 11 of 11. Five failed or invalid runs are kept in `invalid\` with `REASON.txt`.

## 2026-10-04 — Phase 6b: review G1_phase6b_1 fixes (F1, F4, F5)

- F1: test-only hooks in `Orders.mqh` (inside `#ifdef NNFX_TEST_BUILD`, refusing outside the tester):
  `TestFailNextHalf2` (ABORT), `TestStopsLevelOverride` and `TestFreeMarginOverride` (REFUSE, OD-5),
  `TestFillOffset` (MODIFY, OD-14). ABORT logs half 1's OPEN and CLOSE. `check_trades.py`: ABORT must close half 1,
  REFUSE must send nothing, `--require-note`; no breakeven required when half 2 closed in TP1's tick.
  `test_order_calls.py` knows the hooks (S2b).
- F4: `docs/REVIEW_PROTOCOL.md`: failed or invalid runs move to `invalid\` with `REASON.txt`, never deleted.
- F5: breakeven rows note `via=transaction|tick` (in the tester: all via the tick poll).
- Run `20261004_164337` OVERALL PASS; planted bugs 15 of 15, S4 7 of 7.
- F2: demo order run on MetaQuotes-Demo (EURUSD M1, 5 trades): `check_trades.py` PASS; `NNFX_DealReport.mq5`
  (read-only) records FOK fills, comments kept, commission 0.00. A first attempt failed (Algo Trading off), kept in
  `invalid\`. `NNFX_OrderTest`: `InpStopWhenDone`. F3 (offline check) pending.

## 2026-10-04 — Phase 6b: orders

- `MQL5/Include/NNFX/Orders.mqh`: the only module that sends orders; every public method checks
  `NNFXOrdersAllowed` first (orders only in the tester or on DEMO; OD-18). Two halves with the stop in the same
  request, SL/TP from the fill (OD-14), stops-level and free-margin checks (OD-5), 3 retries 1 s apart with a
  duplicate check (OD-13), TP1 -> breakeven at once (T2, OD-15), trail at closes (T4), stopless positions closed
  with an alarm, manual ones alarm only (OD-8). Test-only paths under `#ifdef NNFX_TEST_BUILD` (F3).
- `OrderMath.mqh`, `TradeLog.mqh`; test EA `NNFX_OrderTest.mq5`; `NNFX_SafetyTest.mq5` (S1), `NNFX_OrderMathTest.mq5`.
- `nnfx_ref/orders.py`, `tests/fixtures/orders/order_cases.txt` (28 cases); `tools/check_trades.py` (Check 1c,
  F4 with a 1e-6 float bound) and `test_check_trades.py`; `test_order_calls.py` (S2, S2b).
- 6a verdict note 2: second fixture cases for the minimum lot, the volume cap and OD-4.
- Runner: SafetyTest, OrderMathTest, the tester order run (step 4b) and `check_trades.py`.
- Tester order run: 154 trades, `check_trades.py` PASS. Planted bugs: 13 of 13 (check_trades), 6 of 6 (S4).
  75 Python tests pass. Demo order run and the MT5-offline check are still pending.

## 2026-10-04 — Phase 6a: sizing and exposure

- `docs/PLAN_PHASE6.md`: the Phase 6 plan (gate G2 PASS) with the verdict's edits F1-F4; `docs/DECISIONS.md`:
  owner decisions OD-1 to OD-21.
- `MQL5/Include/NNFX/Sizing.mqh`, `Exposure.mqh`: MQL5 ports of `sizing.py` and `exposure.py`. No orders.
- `tests/fixtures/sizing/`, `tests/fixtures/exposure/`: 42 shared cases with hand-worked answers;
  `tests/python/test_sizing_exposure_fixtures.py`; `MQL5/Scripts/NNFX/NNFX_SizingTest.mq5` (42/42 in MT5).
- `nnfx_ref`: `exposure.is_fx` and non-FX handling (OD-21); `sizing.tick_value_for_sizing` (OD-6).
- Runner: SizingTest added; `-PythonOnly`. `tools/run_offline_check.ps1` (carry-over 1): no-Python path PASS;
  MT5-offline path waits for the owner's firewall rule.
- Planted-bug check on the MQL5 ports: 12 of 12 caught. 50 Python tests pass.

## 2026-10-04 — Phase 5: review G1_phase5_1 fixes

- F1: `MQL5/Include/NNFX/Connection.mqh` (new). `NNFX_EnvCheck` and `NNFX_ExportBars` wait until MT5
  is connected, logged in and has a tick value above 0 for every pair before reading anything;
  otherwise they write `RESULT: INVALID (not connected)`, which the runner counts as FAIL. The earlier
  EnvCheck numbers (run `20261004_113357`) were read before login and are not used.
- F2: `docs/STATUS.md`, `docs/VERIFICATION.md`, `docs/ENVIRONMENT.md`, `tools/README.md`,
  `tests/mql5/README.md`, `MQL5/Include/NNFX/README.md` and file headers brought in line with the runs.
- F3: independent planted-bug check of `tools/check_indicators.py` on the owner PC: 14 of 14 caught.
- F4: `tools/run_phase5_checks.ps1` finds a working Python itself, prints it in `SUMMARY.txt`, and
  writes Python's stderr without PowerShell's `NativeCommandError` wrapper.
- `tools/run_phase5_checks.ps1` run `20261004_115428`: OVERALL PASS. 46 Python tests pass.

## 2026-10-04 — Phase 5b: automated verification

- `tools/run_phase5_checks.ps1`: one command runs every Phase 5 check with MT5 closed: copy, compile
  (must be 0 errors, 0 warnings), each script through MT5's `/config` start-up file, the repaint
  check in the Strategy Tester, and the Python checks. Writes `SUMMARY.txt` and keeps every report
  and log in `MQL5\Files\NNFX\checks\<date-time>\`. **Not yet run.**
- `tools/check_indicators.py` + 6 tests: recalculates ATR, SMA, RVI, MACD and tick volume from the
  export using MT5's own source formulas. Replaces the by-eye Data Window check.
- `NNFX_ExportBars`: makes MT5 download enough history first, waits until every indicator has
  calculated, adds a `tickvol` column and writes `_summary.txt`. `BarBuilder.AllCalculated()` added.
- All scripts: no input dialog (so nothing waits for a click in an unattended run).
- `docs/VERIFICATION.md`: Phase 5 results; `docs/ENVIRONMENT.md`: first NNFX_EnvCheck facts.
- 46 Python tests pass.
- Working method: `docs/REVIEW_PROTOCOL.md` (local Claude Code builds and runs; a second Claude
  session reviews at each gate), `docs/STATUS.md`, and a pointer to both in `CLAUDE.md`.

## 2026-10-04 — Phase 5: indicator slots and profiles

- `profiles/`: profile format (README) and five reference profiles built from MT5 standard
  indicators (20 SMA, RVI 10, MACD main vs 0, MACD cross, tick volume vs 20-candle average).
  Pipeline references only, not chosen for performance.
- `MQL5/Include/NNFX/`: `Signals.mqh`, `Profile.mqh`, `Slot.mqh`, `BarBuilder.mqh`. **Not yet compiled.**
- `MQL5/Scripts/NNFX/NNFX_SignalTest.mq5`, `NNFX_ExportBars.mq5`; `MQL5/Experts/NNFX/NNFX_RepaintCheck.mq5`
  (Strategy Tester only, no trading). **Not yet compiled.**
- `tests/python/nnfx_ref/profiles.py` + `test_profiles.py`, `tests/fixtures/signals/signal_cases.txt` (37 cases),
  `tests/fixtures/profiles_bad/` (14 profiles that must be rejected), `tools/check_export.py` + tests.
  40 Python tests pass; planted-bug check 9 of 9 caught.
- `docs/VERIFICATION.md`: verification log, starting with the Phase 3 and 4 results.
- Phase 4 file headers now record the compile and 47/47 result.

## 2026-10-03 — Phase 4: MQL5 rules core

- `MQL5/Include/NNFX/Settings.mqh`, `RulesCore.mqh`: the rules core in MQL5, a function-for-function
  port of the Python answer key. No trading or indicator calls. **Not yet compiled.**
- `MQL5/Scripts/NNFX/NNFX_RulesTest.mq5`: runs all rule cases in MT5 and writes a pass/fail report.
  **Not yet compiled.**
- `tests/fixtures/mql5/`: the same 45 rule cases in a line format MQL5 can read;
  `tests/python/test_fixture_formats.py` proves they match the JSON exactly.
- Pass line: 47 of 47 in MT5, the same as Python.
- I-14 fix (owner-approved): if a regular entry is refused or only waiting, the continuation is
  still checked. Changed in both `core.py` and `RulesCore.mqh`; two new fixtures (47 total).
- Interpretations reviewed: I-4, 5, 6, 8, 10, 11, 12, 13, 14 approved; I-1, 2, 3, 7, 9 reworded
  for intraday and awaiting a tick; the old I-15 is now a checker note.
- `docs/RULEBOOK.md` snapshot is behind the living doc; it will be refreshed once I-1, 2, 3, 7, 9 are ticked.

## 2026-10-03 — Phase 3: Python answer key

- `tests/python/nnfx_ref/`: rules engine (E0-E6, X1-X5, T1-T7), signals, sizing, exposure, settings.
- `tests/fixtures/`: 45 hand-built rule cases (JSON) plus the generator that writes them;
  the same JSON files will drive the MQL5 tests in Phase 4.
- `tests/python/test_fixtures.py`, `test_units.py`: 27 tests, all passing. A planted-bug check
  (10 deliberate bugs) caught all 10 after one missing case was added.
- `docs/DECISIONS.md`: interpretations I-1 to I-15, pending owner approval.
- No MT5 or trading code.

## 2026-10-03 — Phase 2: repo setup

- Folder structure for the EA, profiles, tests, tools and results.
- `docs/RULEBOOK.md` and `docs/SPEC.md`: snapshots of the approved Claude Docs.
- `docs/DECISIONS.md`, `docs/ENVIRONMENT.md`, this changelog.
- `CONTRIBUTING.md` (working rules), `CLAUDE.md` (notes for AI sessions), `.gitignore`.
- `MQL5/Scripts/NNFX/NNFX_EnvCheck.mq5`: read-only environment check script. **Not yet compiled.**
- No trading code yet.
