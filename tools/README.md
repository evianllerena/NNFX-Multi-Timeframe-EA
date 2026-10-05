# Tools

| Tool | Purpose | Status |
| --- | --- | --- |
| `MQL5/Scripts/NNFX/NNFX_EnvCheck.mq5` | Read-only check of the account and broker: account type, server time, spreads, stop distances, history depth. Waits for login first; a report read before login ends `RESULT: INVALID (not connected)` | Compiled 2026-10-04 (build 6238); valid run `20261004_115428` |
| `MQL5/Scripts/NNFX/NNFX_RulesTest.mq5` | Runs the rule cases through the MQL5 rules core | Compiled; 47/47 (2026-10-03, again 2026-10-04) |
| `MQL5/Scripts/NNFX/NNFX_SignalTest.mq5` | Signal cases + profile accept/reject cases in MT5 (Phase 5) | Compiled; 56/56 (2026-10-04) |
| `MQL5/Scripts/NNFX/NNFX_ExportBars.mq5` | Exports candles, tick volume, raw indicator values and directions to CSV; forces history download; waits for login; writes `_summary.txt` (Phase 5; reused in Phase 7) | Compiled 2026-10-04 (build 6238); 5 of 5 pairs complete (run `20261004_115428`) |
| `MQL5/Experts/NNFX/NNFX_RepaintCheck.mq5` | Strategy Tester only, no trading: repaint check V2 for every profile | Compiled 2026-10-04; `NO REPAINTING FOUND` on EURUSD H1, 2026.06.01-2026.10.01 (runs `20261004_113357`, `20261004_115428`) |
| `tools/check_export.py` | Recomputes every direction and volume pass from an export in Python; checks candles; flags constant indicators; prints sample rows | Tested here (7 tests incl. corruption cases); PASS on 5 exports 2026-10-04 |
| `tools/check_indicators.py` | Recalculates ATR, SMA, RVI, MACD and tick volume from an export with MT5's own formulas; replaces the by-eye Data Window check | Tested here (6 tests incl. corruption cases); planted-bug checks 11 of 11 (author) and 14 of 14 (independent, owner PC); PASS on 5 exports 2026-10-04 |
| `MQL5/Scripts/NNFX/NNFX_SizingTest.mq5` | Phase 6a: shared sizing and exposure cases through `Sizing.mqh` and `Exposure.mqh`; plus a LIVE read (tick values, OD-6 choice, sizing for a 1.5 x ATR stop), information only | Compiled 2026-10-04 (build 6238); 42/42 (run `20261004_125319`); planted bugs 12 of 12 |
| `tools/run_phase5_checks.ps1` | Runs every Phase 5 check, and the Phase 6a SizingTest, unattended (copy, compile, scripts and tester via `/config`, Python checks) and writes `SUMMARY.txt`; finds a working Python itself; `-PythonOnly` runs only the Python step | Runs on the owner PC; OVERALL PASS (run `20261004_125319`) |
| `MQL5/Scripts/NNFX/NNFX_SafetyTest.mq5` | Phase 6b, S1: the order safety decision on all 6 (trade mode x tester) cases | Compiled 2026-10-04; 6/6 (run `20261004_162607`) |
| `MQL5/Scripts/NNFX/NNFX_OrderMathTest.mq5` | Phase 6b: SL/TP1/TP2/BE, trail steps and stop distances against `order_cases.txt` | Compiled 2026-10-04; 22/22 (run `20261004_162607`) |
| `MQL5/Experts/NNFX/NNFX_OrderTest.mq5` | Phase 6b TEST EA (defines `NNFX_TEST_BUILD`): scripted trades through `Orders.mqh`, trade log for `check_trades.py`; orders only in the tester or on DEMO | Compiled 2026-10-04; tester run 154 trades, `check_trades.py` PASS (run `20261004_162607`); demo run pending |
| `tools/check_trades.py` | SPEC Check 1c over a trade log: stop from the first moment, equal halves, planned risk <= target (F4, 1e-6 float bound), SL/TP/BE/trail prices, test alarms, ABORT closes half 1, REFUSE sends nothing; `--require`, `--require-note` | Tested here (27 tests incl. corruption cases); planted bugs 15 of 15; PASS on the tester order run (run `20261004_164337`) |
| `MQL5/Scripts/NNFX/NNFX_DealReport.mq5` | Read-only: one magic's orders and deals from the account history (filling mode, comments, commission, swap, fee, reason) | Compiled 2026-10-04; run after the demo order run `demo_20261004_224606` |
| `tools/run_offline_check.ps1` | Carry-over 1: `-NoPython` proves the runner FAILs with no Python; `-Mt5Offline` proves EnvCheck and ExportBars FAIL with `RESULT: INVALID (not connected)` while an owner-added firewall rule blocks MT5 | `-NoPython` PASS 2026-10-04; `-Mt5Offline` not run yet (needs the owner's firewall rule) |
| Calendar export (MQL5 script) | Saves VP's news events, month by month, for backtests | Planned (Phase 6) |
| Result recompute (Python) | Recomputes trades, R and drawdown from raw trade logs (V13) | Planned (Phase 8) |

How to run each MQL5 check: `tests/mql5/README.md`.
