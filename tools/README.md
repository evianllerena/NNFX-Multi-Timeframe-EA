# Tools

| Tool | Purpose | Status |
| --- | --- | --- |
| `MQL5/Scripts/NNFX/NNFX_EnvCheck.mq5` | Read-only check of the account and broker: account type, server time, spreads, stop distances, history depth | Written, **not yet compiled** |
| `MQL5/Scripts/NNFX/NNFX_RulesTest.mq5` | Runs the rule cases through the MQL5 rules core | Compiled; 47/47 (2026-10-03) |
| `MQL5/Scripts/NNFX/NNFX_SignalTest.mq5` | Signal cases + profile accept/reject cases in MT5 (Phase 5) | Written, **not yet compiled** |
| `MQL5/Scripts/NNFX/NNFX_ExportBars.mq5` | Exports candles, raw indicator values and directions to CSV (Phase 5; reused in Phase 7) | Written, **not yet compiled** |
| `MQL5/Experts/NNFX/NNFX_RepaintCheck.mq5` | Strategy Tester only, no trading: repaint check V2 for every profile | Written, **not yet compiled** |
| `tools/check_export.py` | Recomputes every direction and volume pass from an export in Python; checks candles; flags constant indicators; prints Data Window samples | Tested here (7 tests incl. corruption cases) |
| Calendar export (MQL5 script) | Saves VP's news events, month by month, for backtests | Planned (Phase 6) |
| Result recompute (Python) | Recomputes trades, R and drawdown from raw trade logs (V13) | Planned (Phase 8) |

How to run each MQL5 check: `tests/mql5/README.md`.
