# MT5 environment

Facts read from the owner's MT5 terminal. Each line says where it came from.
Anything not yet checked is listed under "Still to check".

## Checked on 2026-10-03 (read-only: terminal log and data-folder listing)

| Fact | Value | Source |
| --- | --- | --- |
| Terminal | MetaTrader 5 x64, build 6235, installed in `C:\Program Files\MetaTrader 5` | Terminal log; `origin.txt` |
| Data folder | `...\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075` | Owner |
| Account | New **demo** account on the **MetaQuotes-Demo** server, opened 2026-10-03 | Terminal log: "new demo account ... opened on MetaQuotes-Demo" |
| Account type | **Hedging** | Terminal log: "trading has been enabled, demo account - hedging mode" |
| PC time zone | GMT-5 (as reported at start-up) | Terminal log |
| Price history on disk | EURUSD, GBPUSD, USDCHF, USDJPY only; yearly files 2024, 2025, 2026 | `bases\MetaQuotes-Demo\history` listing |
| Tick history on disk | None downloaded yet | `bases\MetaQuotes-Demo\ticks` listing |

**What the history listing does not tell us:** MT5 downloads history from the server on
demand, so files on disk show only what has been downloaded so far, not how much the
server holds. Four of VP's five test pairs (AUDNZD, EURGBP, AUDCAD, CHFJPY) have not
been downloaded yet.

**Important for the shootout:** MetaQuotes-Demo is MetaQuotes' own demo server, not a
retail broker. The spec requires testing on the same broker that will be traded live,
because spreads, commission, server time and history all differ by broker. Which broker
will be used live is still an open question.

## Read on 2026-10-04 by `tools/run_phase5_checks.ps1` run `20261004_115428` (after login)

Source: `MQL5\Files\NNFX\checks\20261004_115428\NNFX_EnvCheck.txt`, commit 521013b. The report says
`Connection: connected and logged in, tick value > 0 on every pair (waited 0.8 s)` and ends
`RESULT: VALID (read after login)`. Read on a **Sunday** (market closed).

| Fact | Value |
| --- | --- |
| Terminal build | 6238 |
| Account | MetaQuotes-Demo, DEMO, RETAIL_HEDGING, USD, 1:100, balance 100000.00 |
| Server time vs GMT | +3.00 hours on 2026-10-04 (may change with daylight saving) |
| Daily / 4-hour candle | EURUSD D1 candle opened 2026.10.02 00:00 server; H4 2026.10.02 20:00 |
| Max bars in chart | 100000 (terminal setting) |

| Pair | Digits | Tick size / tick value (USD) | Lot min / step / max | Min stop / freeze (points) | Swap long / short (mode 1) | Server history starts (M1) | Real ticks, mid-January 2016-2026 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EURUSD | 5 | 0.00001 / 1.00000 | 0.01 / 0.01 / 500.00 | 0 / 0 | -0.70 / -1.00 | 1971.01.04 | yes every year |
| AUDNZD | 5 | 0.00001 / 0.56121 | 0.01 / 0.01 / 500.00 | 0 / 0 | -2.50 / -15.20 | 1993.04.05 | yes every year |
| EURGBP | 5 | 0.00001 / 1.32393 | 0.01 / 0.01 / 500.00 | 0 / 0 | -1.20 / -0.40 | 1993.05.03 | yes every year |
| AUDCAD | 5 | 0.00001 / 0.70173 | 0.01 / 0.01 / 500.00 | 0 / 0 | 6.40 / -15.40 | 1993.04.27 | yes every year |
| CHFJPY | 3 | 0.001 / 0.63346 | 0.01 / 0.01 / 500.00 | 0 / 0 | -0.50 / -0.10 | 1992.02.19 | yes every year |

Tick value for a losing trade (`SYMBOL_TRADE_TICK_VALUE_LOSS`), read by `NNFX_SizingTest` in run `20261004_125319`
(Sunday): EURUSD 1.00000, AUDNZD 0.56188, EURGBP 1.32393, AUDCAD 0.70174, CHFJPY 0.63348 USD. It is slightly above
`SYMBOL_TRADE_TICK_VALUE` on AUDNZD, AUDCAD and CHFJPY, so the OD-6 rule (use the larger) changes the lot size. Both
move with exchange rates; sizing reads them when the order is placed, never from here.

Spreads (EURUSD 3, AUDNZD 205, EURGBP 2, AUDCAD 2, CHFJPY 4 points, all floating) were read with the
market closed and are **not representative**. Tick values for pairs not quoted in USD move with
exchange rates; these are the values at the time of reading.

**Not used:** the EnvCheck report from run `20261004_113357` was read before MT5 had logged in
(review G1_phase5_1, F1) and showed netting, balance 0, server - GMT +0 and tick value 0 on three
pairs. None of its numbers are recorded here.

## Read on 2026-10-04 (NNFX_EnvCheck, from the Experts log; superseded by the run above)

The report file was still empty when read (the script was still probing tick history), so
these lines come from the Experts log. `tools/run_phase5_checks.ps1` re-runs the check and
keeps the full report.

| Fact | Value |
| --- | --- |
| Terminal build | 6238 |
| Account | MetaQuotes-Demo, DEMO, RETAIL_HEDGING, USD, 1:100, balance 100,000.00 |
| Server time vs GMT | +3 hours on 2026-10-04 (may change with daylight saving) |
| Daily candle | EURUSD D1 candle opens 00:00 server time |
| Minimum stop distance | 0 points (pairs read) |
| Server history starts (M1 base) | EURUSD 1971.01.04; AUDNZD 1993.04.05; EURGBP 1993.05.03 |
| Real ticks (mid-January probe) | EURUSD: 2016 error 4401, 2017 onward yes; AUDNZD: 2016 onward yes |
| Spreads | Read on a Sunday with the market closed (AUDNZD showed 205 points), so **not representative**; to be re-read during market hours |

## Demo order run facts (MetaQuotes-Demo, 2026-10-05 server time)

From the 6b demo order run `demo_20261004_224606` (`NNFX_OrderTest`, EURUSD M1, minimum lots, 5 trades) and the read-only
`NNFX_DealReport`:

| Fact | Value |
| --- | --- |
| Filling mode of the EA's orders (U9) | FOK (`SYMBOL_FILLING_MODE` allows it; the EA picks FOK first). The server's own SL/TP closes are IOC |
| Commission, swap, fees (U11) | 0.00 on all 20 deals (5 trades x 2 halves, open + close) |
| Comments (U5) | Kept unchanged on opening orders and deals |
| Breakeven after TP1 (U12) | Both breakeven moves made by `OnTradeTransaction` (`via=transaction`); in the tester it was the tick poll |
| Slippage | T0003: fills 3 and 8 points away from the requested price; SL/TP re-set from the fills (MODIFY, OD-14) |
| Algo Trading button | Must be on: a first attempt with it off got retcode 10027 "AutoTrading disabled by client" on every order (kept in `checks\invalid\demo_20261004_171933\`) |

## Still to check

| # | Check | How |
| --- | --- | --- |
| 1 | ~~Server history depth: AUDCAD, CHFJPY~~ | Done: all 5 pairs, run `20261004_115428` (table above) |
| 2 | ~~Real-tick history: EURGBP, AUDCAD, CHFJPY~~ | Done: mid-January probe finds ticks 2016-2026 on all 5 pairs, run `20261004_115428`. A probe is one 3-day window per year, not a full coverage check |
| 3 | Server time offset after the daylight-saving change | `NNFX_EnvCheck` script, re-run after the change |
| 4 | Spread during market hours | `NNFX_EnvCheck` script (runner, on a weekday). Lot step, tick value and swaps: done, run `20261004_115428` |
| 5 | Commission | **MetaQuotes-Demo: 0.00** on all 20 deals of the demo order run (`demo_20261004_224606`, `NNFX_DealReport.txt`; swap and fee also 0.00). The live broker's commission is still unknown (live broker not chosen) |
| 6 | ~~Does the broker keep order comments unchanged?~~ | **Yes on MetaQuotes-Demo**: every opening order and deal kept the EA's comment (`NNFX T0001 h1` ...). Closes made by the server carry the server's own comment (`[sl 1.12007]`, `[tp 1.11902]`). Demo order run `demo_20261004_224606`, `NNFX_DealReport.txt`. To re-check on the live broker |
| 7 | How far back the economic calendar goes | Calendar export tool |
| 8 | ~~Can the tester run from the command line on this PC?~~ | **Yes**: `tools/run_phase5_checks.ps1` step 4 ran the Strategy Tester from a `/config` file (runs `20261004_113357`, `20261004_115428`) |
| 9 | Live broker choice | Owner |
