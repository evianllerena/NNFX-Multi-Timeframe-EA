# Modules

One file per module, as set out in `docs/SPEC.md` (Architecture). Nothing here yet.

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
