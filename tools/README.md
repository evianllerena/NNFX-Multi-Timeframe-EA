# Tools

| Tool | Purpose | Status |
| --- | --- | --- |
| `MQL5/Scripts/NNFX/NNFX_EnvCheck.mq5` | Read-only check of the account and broker: account type, server time, spreads, stop distances, history depth | Compiled 2026-10-04 (build 6238) |
| `MQL5/Scripts/NNFX/NNFX_RulesTest.mq5` | Runs the rule cases through the MQL5 rules core | Compiled; 47/47 (2026-10-03) |
| `MQL5/Scripts/NNFX/NNFX_SignalTest.mq5` | Signal cases + profile accept/reject cases in MT5 (Phase 5) | Compiled; 56/56 (2026-10-04) |
| `MQL5/Scripts/NNFX/NNFX_ExportBars.mq5` | Exports candles, tick volume, raw indicator values and directions to CSV; forces history download; writes `_summary.txt` (Phase 5; reused in Phase 7) | Compiled 2026-10-04; Phase 5b changes not yet compiled |
| `MQL5/Experts/NNFX/NNFX_RepaintCheck.mq5` | Strategy Tester only, no trading: repaint check V2 for every profile | Compiled 2026-10-04; not yet run |
| `tools/check_export.py` | Recomputes every direction and volume pass from an export in Python; checks candles; flags constant indicators; prints sample rows | Tested here (7 tests incl. corruption cases); PASS on 5 exports 2026-10-04 |
| `tools/check_indicators.py` | Recalculates ATR, SMA, RVI, MACD and tick volume from an export with MT5's own formulas; replaces the by-eye Data Window check | Tested here (6 tests incl. corruption cases; planted-bug check 11 of 11) |
| `tools/run_phase5_checks.ps1` | Runs every Phase 5 check unattended (copy, compile, scripts and tester via `/config`, Python checks) and writes `SUMMARY.txt` | Written; **not yet run** (no PowerShell in the cloud session) |
| Calendar export (MQL5 script) | Saves VP's news events, month by month, for backtests | Planned (Phase 6) |
| Result recompute (Python) | Recomputes trades, R and drawdown from raw trade logs (V13) | Planned (Phase 8) |

How to run each MQL5 check: `tests/mql5/README.md`.
