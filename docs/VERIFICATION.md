# Verification log

Every check run against the code, newest first. A check is logged with what was run,
where, on which commit, and the exact result. Failed runs are logged too.
Pass lines come from `docs/SPEC.md` (Verification plan).

| Date | Phase / check | Commit | Where | Result |
| --- | --- | --- | --- | --- |
| 2026-10-04 | Phase 5, G1 F1/F4 fixes: `tools/run_phase5_checks.ps1` run `20261004_115428` (no `-Python`; found `Python312\python.exe`, 3.12.10) | 521013b | MT5 build 6238, owner PC | `OVERALL: PASS`. Compile 5 of 5 `0 errors, 0 warnings`; RulesTest `47 passed, 0 failed, 47 total`; SignalTest `56 passed, 0 failed, 56 total`; EnvCheck `RESULT: VALID (read after login)` (waited 0.8 s; RETAIL_HEDGING, balance 100000.00, tick value > 0 on all 5 pairs); ExportBars `5 of 5 pairs complete`; repaint `NO REPAINTING FOUND (0 changed values)`; 46 Python tests OK; check_export 5 of 5 PASS; check_indicators 5 of 5 PASS |
| 2026-10-04 | Phase 5, G1 F3: independent planted-bug check on `tools/check_indicators.py` (13 bugs + 1 variant: ATR true range, ATR window x2, SMA window, SMA period, RVI window, RVI denominator, MACD signal as EMA, EMA burn-in 0 and 1500, tolerance x1000, missing values ignored, volume tolerance 1.0, minimum count off) | 521013b (file unchanged since 2e91d1e) | Python 3.12.10, owner PC | 14 of 14 caught. One (ATR window shifted onto the empty first true range) was caught by a crash, so a non-crashing variant was added; it was caught by the value comparison. File restored byte for byte (same SHA-256) |
| 2026-10-04 | Phase 5b: `tools/run_phase5_checks.ps1` run `20261004_113357` (with `-Python`) | 58e2994 | MT5 build 6238, owner PC | `OVERALL: PASS`, but **NNFX_EnvCheck numbers invalid**: the script read the account at 11:34:20.68, before MT5 logged in at 11:34:21.21 (netting, balance 0, tick value 0 on 3 pairs). Found in review G1_phase5_1 (F1). All other results in this run stand |
| 2026-10-04 | Phase 5b: planted-bug check on `tools/check_indicators.py` (wrong true range, wrong ATR divisor, RVI weights, RVI signal divisor, EMA factor, MACD signal period, loose tolerance, missing values ignored, no EMA burn-in, volume compared to itself, volume skipped) | Phase 5b commit | Python 3.11, cloud session | 11 of 11 caught. One more change (skipping the first ATR candle) was not caught; it only compares one candle fewer, so it is not a wrong answer |
| 2026-10-04 | Phase 5b: Python suite | Phase 5b commit | Python 3.11, cloud session | 46 tests OK |
| 2026-10-04 | Phase 5: check_export.py on EURUSD, AUDNZD, EURGBP, AUDCAD, CHFJPY H1 exports | 9690106 | MT5 build 6238 export, owner PC | PASS on all 5, 0 failures, 0 warnings. EURUSD 3,000 candles; the other four had only about 2 weeks of history downloaded, so they are re-run in Phase 5b with forced history download |
| 2026-10-04 | Phase 5: NNFX_RulesTest re-run | 9690106 | MT5 build 6238, owner PC | `RESULT: 47 passed, 0 failed, 47 total` |
| 2026-10-04 | Phase 5: NNFX_SignalTest | 9690106 | MT5 build 6238, owner PC | `RESULT: 56 passed, 0 failed, 56 total` |
| 2026-10-04 | Phase 5: compile Signals/Profile/Slot/BarBuilder via NNFX_SignalTest, NNFX_ExportBars, NNFX_RepaintCheck, NNFX_RulesTest, NNFX_EnvCheck | 9690106 | MetaEditor, MT5 build 6238 | all 5: `0 errors, 0 warnings` |
| 2026-10-04 | Phase 5: Python suite | 9690106 | Python 3.12.10, owner PC | 40 tests OK |
| 2026-10-04 | Phase 5: planted-bug check (9 deliberate bugs in profiles.py / check_export.py) | 9690106 | Python 3.11, cloud session | 9 of 9 caught |
| 2026-10-04 | Phase 5: repaint check (V2) and Data Window comparison | - | - | Not run at this point. Done later the same day by `tools/run_phase5_checks.ps1` (rows above); the by-eye Data Window step is replaced by `tools/check_indicators.py` |
| 2026-10-03 | Phase 4: planted wrong answer (E1_fires_long expected dir changed to -1, MT5 copy only) | 11425d4 | MT5 build 6235, owner PC | `46 passed, 1 failed, 47 total`; the one failure was E1_fires_long, expected -1 got +1, as intended. File restored byte for byte afterwards |
| 2026-10-03 | Phase 4: NNFX_RulesTest (Check 1a in MT5) | 11425d4 | MT5 build 6235, owner PC | `RESULT: 47 passed, 0 failed, 47 total` |
| 2026-10-03 | Phase 4: compile NNFX_RulesTest.mq5 (+ RulesCore.mqh, Settings.mqh) | 11425d4 | MetaEditor, MT5 build 6235 | `0 errors, 0 warnings` |
| 2026-10-03 | Phase 4: Python suite | 11425d4 | Python 3.12.10, owner PC | 28 tests OK (47 fixtures) |
| 2026-10-03 | Phase 3: Python suite | 7f8eaa7 | Python 3.12.10, owner PC | 27 tests OK (45 fixtures) |
| 2026-10-03 | Phase 3: planted-bug check (10 deliberate bugs) | 7f8eaa7 | Python 3.11, cloud session | 10 of 10 caught (after adding one missing case) |
