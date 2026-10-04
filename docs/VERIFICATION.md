# Verification log

Every check run against the code, newest first. A check is logged with what was run,
where, on which commit, and the exact result. Failed runs are logged too.
Pass lines come from `docs/SPEC.md` (Verification plan).

| Date | Phase / check | Commit | Where | Result |
| --- | --- | --- | --- | --- |
| 2026-10-03 | Phase 4: planted wrong answer (E1_fires_long expected dir changed to -1, MT5 copy only) | 11425d4 | MT5 build 6235, owner PC | `46 passed, 1 failed, 47 total`; the one failure was E1_fires_long, expected -1 got +1, as intended. File restored byte for byte afterwards |
| 2026-10-03 | Phase 4: NNFX_RulesTest (Check 1a in MT5) | 11425d4 | MT5 build 6235, owner PC | `RESULT: 47 passed, 0 failed, 47 total` |
| 2026-10-03 | Phase 4: compile NNFX_RulesTest.mq5 (+ RulesCore.mqh, Settings.mqh) | 11425d4 | MetaEditor, MT5 build 6235 | `0 errors, 0 warnings` |
| 2026-10-03 | Phase 4: Python suite | 11425d4 | Python 3.12.10, owner PC | 28 tests OK (47 fixtures) |
| 2026-10-03 | Phase 3: Python suite | 7f8eaa7 | Python 3.12.10, owner PC | 27 tests OK (45 fixtures) |
| 2026-10-03 | Phase 3: planted-bug check (10 deliberate bugs) | 7f8eaa7 | Python 3.11, cloud session | 10 of 10 caught (after adding one missing case) |
