# Modules

One file per module, as set out in `docs/SPEC.md` (Architecture).

Built so far:

| File | Phase | Status |
| --- | --- | --- |
| `Settings.mqh` | 4 | Compiled; rule settings and defaults |
| `RulesCore.mqh` | 4 | Compiled; 47/47 in MT5. Function-for-function port of `tests/python/nnfx_ref/core.py` |
| `Signals.mqh` | 5 | Compiled 2026-10-04 (build 6238); SignalTest 56/56. Mirrors `signals.py` |
| `Profile.mqh` | 5 | Compiled 2026-10-04; SignalTest 56/56. Reads and validates profiles (same rules as `profiles.py`) |
| `Slot.mqh` | 5 | Compiled 2026-10-04. One indicator per profile via `IndicatorCreate`; closed candles only |
| `BarBuilder.mqh` | 5 | Compiled 2026-10-04. Five slots + ATR(14) -> the rules core's input for one candle |
| `Connection.mqh` | 5 (G1 F1) | Compiled 2026-10-04 (run `20261004_115428`). Waits until MT5 is logged in before a script reads server data |
| `Sizing.mqh` | 6a | Compiled 2026-10-04; SizingTest 42/42. Port of `sizing.py`: two equal halves rounded down, skip below the minimum lot; tick value = the larger of TICK_VALUE and TICK_VALUE_LOSS read now (OD-6) |
| `OrderMath.mqh` | 6b | Compiled 2026-10-04; OrderMathTest 22/22, SafetyTest 6/6. Pure order prices (SL towards the fill, TP1/TP2, BE, trail) and the safety decision |
| `Orders.mqh` | 6b, 6c | Compiled 2026-10-04 (6c additions 2026-10-05). The only module that sends orders; every public method checks `NNFXOrdersAllowed` first (tester or DEMO only). Tester order run: 154 trades, `check_trades.py` PASS. 6c: `ExportTrades`, `ImportTrades` and `Reconcile` (the broker's stop wins; unknown positions are logged as RECONCILE) |
| `TradeLog.mqh` | 6b, 6c | Compiled 2026-10-04. One CSV row per order event in `Common\Files\NNFX\trades\`; 6c: `Open(name, append)` keeps the log across a real restart |
| `State.mqh` | 6c | Compiled 2026-10-05 (build 6238); RecoveryTest 30/30. State file (version, FNV-1a checksum, atomic write via `.tmp` + `FileMove`) and the pure restart rebuild `NNFXRebuildPure` (port of `recovery.py`). The broker wins for open halves, lots, half 2's stop and TP1 (deal reason); the file adds only the entry ATR and the runner cap. No trading calls |
| `Guard.mqh` | 6d | Compiled 2026-10-06 (build 6241); GuardTest 56/56; planted bugs 9 of 9. Port of `guard.py`: trading day boundary (17:00 New York, per-broker clock rule), rollover and weekend blocks, daily loss (D6d-2), drawdown pause with a manual, logged reset (D6d-3), master switch (missing = OFF, D6d-1), block string. Never `TimeLocal` (D6d-4). No trading calls |
| `Panel.mqh` | 6d | Compiled 2026-10-06. Chart buttons: instance on/off, close-all and drawdown reset (each with a confirm step). Never trades: the EA acts and logs. Test path (custom chart events) only under `NNFX_TEST_BUILD` |
| `News.mqh` | 6e | Compiled 2026-10-06 (build 6241); NewsTest 47/47; planted bugs 7 of 7. Port of `news.py`: event matching by id or role pattern (D6e-1), N1 (t, t+24h], N2 blackout, X5 first close (I-10), the exported file read in UTC and converted to server time per date (Guard.mqh clock rule). No trading calls |
| `Exposure.mqh` | 6a | Compiled 2026-10-04; SizingTest 42/42. Port of `exposure.py`: same-currency exposure over every open position; modes first/split; non-FX ignored (OD-21) |

| Module | Owns | Never does | Phase |
| --- | --- | --- | --- |
| Rules core | Every entry/exit decision (E0-E6, X1-X5) from closed-candle values | Place orders, read indicators, know the timeframe | 4 |
| Indicator slots | Baseline, C1, C2, Volume, Exit: load from a profile, return long / short / none | Decide trades | 5 |
| ATR | ATR(14) on the chart's timeframe, closed candle only | | 5 |
| Risk | Lot size from 2% of balance and the stop distance; skips a trade it can't size | Round risk up | 6 |
| Exposure | Same-currency check across every open position on the account | | 6 |
| Orders | Two halves with broker-held stops, TP1, breakeven, trailing, exits | Decide trades | 6 |
| State and recovery | Each trade's halves and continuation state; rebuilt after a restart | | 6 |
| Guard | On/off switches, drawdown pause, daily loss limit, news block, rollover window, max spread | | 6 |
| News source | Live: MT5 calendar. Tester: saved calendar file | | 6 |
| Log | One line per candle per pair (every decision and why) + trade log | | 4-6 |
