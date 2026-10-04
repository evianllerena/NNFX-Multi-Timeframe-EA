# Verification log

Every check run against the code, newest first. A check is logged with what was run,
where, on which commit, and the exact result. Failed runs are logged too.
Pass lines come from `docs/SPEC.md` (Verification plan).

| Date | Phase / check | Commit | Where | Result |
| --- | --- | --- | --- | --- |
| 2026-10-04 | Phase 5b: planted-bug check on `tools/check_indicators.py` (wrong true range, wrong ATR divisor, RVI weights, RVI signal divisor, EMA factor, MACD signal period, loose tolerance, missing values ignored, no EMA burn-in, volume compared to itself, volume skipped) | Phase 5b commit | Python 3.11, cloud session | 11 of 11 caught. One more change (skipping the first ATR candle) was not caught; it only compares one candle fewer, so it is not a wrong answer |
| 2026-10-04 | Phase 5b: Python suite | Phase 5b commit | Python 3.11, cloud session | 46 tests OK |
| 2026-10-04 | Phase 5: check_export.py on EURUSD, AUDNZD, EURGBP, AUDCAD, CHFJPY H1 exports | 9690106 | MT5 build 6238 export, owner PC | PASS on all 5, 0 failures, 0 warnings. EURUSD 3,000 candles; the other four had only about 2 weeks of history downloaded, so they are re-run in Phase 5b with forced history download |
| 2026-10-04 | Phase 5: NNFX_RulesTest re-run | 9690106 | MT5 build 6238, owner PC | `RESULT: 47 passed, 0 failed, 47 total` |
| 2026-10-04 | Phase 5: NNFX_SignalTest | 9690106 | MT5 build 6238, owner PC | `RESULT: 56 passed, 0 failed, 56 total` |
| 2026-10-04 | Phase 5: compile Signals/Profile/Slot/BarBuilder via NNFX_SignalTest, NNFX_ExportBars, NNFX_RepaintCheck, NNFX_RulesTest, NNFX_EnvCheck | 9690106 | MetaEditor, MT5 build 6238 | all 5: `0 errors, 0 warnings` |
| 2026-10-04 | Phase 5: Python suite | 9690106 | Python 3.12.10, owner PC | 40 tests OK |
| 2026-10-04 | Phase 5: planted-bug check (9 deliberate bugs in profiles.py / check_export.py) | 9690106 | Python 3.11, cloud session | 9 of 9 caught |
| 2026-10-04 | Phase 5: repaint check (V2) and Data Window comparison | - | - | **Not yet run.** Phase 5b replaces the by-eye Data Window step with `tools/check_indicators.py` and runs everything through `tools/run_phase5_checks.ps1` |
| 2026-10-03 | Phase 4: planted wrong answer (E1_fires_long expected dir changed to -1, MT5 copy only) | 11425d4 | MT5 build 6235, owner PC | `46 passed, 1 failed, 47 total`; the one failure was E1_fires_long, expected -1 got +1, as intended. File restored byte for byte afterwards |
| 2026-10-03 | Phase 4: NNFX_RulesTest (Check 1a in MT5) | 11425d4 | MT5 build 6235, owner PC | `RESULT: 47 passed, 0 failed, 47 total` |
| 2026-10-03 | Phase 4: compile NNFX_RulesTest.mq5 (+ RulesCore.mqh, Settings.mqh) | 11425d4 | MetaEditor, MT5 build 6235 | `0 errors, 0 warnings` |
| 2026-10-03 | Phase 4: Python suite | 11425d4 | Python 3.12.10, owner PC | 28 tests OK (47 fixtures) |
| 2026-10-03 | Phase 3: Python suite | 7f8eaa7 | Python 3.12.10, owner PC | 27 tests OK (45 fixtures) |
| 2026-10-03 | Phase 3: planted-bug check (10 deliberate bugs) | 7f8eaa7 | Python 3.11, cloud session | 10 of 10 caught (after adding one missing case) |
