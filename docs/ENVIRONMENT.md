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

## OANDA TMS (candidate live broker)

Owner decision D6c-2. Read-only `NNFX_EnvCheck` on the OANDA TMS **demo** account, compiled with OANDA's own
MetaEditor; no orders on OANDA. Run `oanda_envcheck_20261005_222410` (report in the OANDA data folder
`...\Terminal\47AEB69EDDAD4D73097816C71FB25856\MQL5\Files\NNFX\checks\oanda_envcheck_20261005_222410\`), started
Monday 2026-10-05 22:24 EDT = **Tuesday 04:24 server time (Asian session)**. `RESULT: VALID (read after login)`.

| Fact | Value |
| --- | --- |
| Terminal | OANDA TMS MT5 Terminal, build 6241, `C:\Program Files\OANDA TMS MT5 Terminal` |
| Account | OANDATMS-MT5, login 62316800, OANDA TMS Brokers S.A., DEMO, **RETAIL_HEDGING**, **currency EUR**, 1:100, balance 50000.00 |
| Server time vs GMT | **+2.00 hours** on 2026-10-06 (MetaQuotes-Demo was +3); D1 candle opens 00:00 server, H4 on 00/04/08... |
| Symbol names | AUDNZD, AUDCAD, CHFJPY exist only as **`.pro`** (`AUDNZD.pro`, `AUDCAD.pro`, `CHFJPY.pro`). EURUSD and EURGBP were found under the plain name (see the warning below) |

| Pair (as found) | Digits | Spread at 04:24 server | Stops / freeze | Lot min / step / max | Tick size / value (EUR) | Swap long / short (mode) | History starts (M1) | Real ticks, mid-January probe |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EURUSD | 5 | **2400 (fixed)** | 0 / 0 | 0.01 / 0.01 / 50 | 0.00001 / 0.88216 | 0.00 / 0.00 (mode 0) | 1971.01.03 | 2016 error 4401; 2017-2026 yes |
| AUDNZD.pro | 5 | 17 (floating) | 0 / 0 | 0.01 / 0.01 / 50 | 0.00001 / 0.49938 | 0.82 / -2.71 (mode 5) | 1993.04.04 | 2016 error 4401; 2017, 2018 no; 2019-2026 yes |
| EURGBP | 5 | **2400 (fixed)** | 0 / 0 | 0.01 / 0.01 / 50 | 0.00001 / 1.16183 | 0.00 / 0.00 (mode 0) | 1993.05.02 | 2016 error 4401; 2017-2021 yes; 2022, 2023 no; 2024-2026 yes |
| AUDCAD.pro | 5 | 21 (floating) | 0 / 0 | 0.01 / 0.01 / 50 | 0.00001 / 0.62516 | 1.25 / -3.14 (mode 5) | 1993.04.26 | 2016 error 4401; 2017, 2018 no; 2019-2026 yes |
| CHFJPY.pro | 3 | 45 (floating) | 0 / 0 | 0.01 / 0.01 / **25** | 0.001 / 0.56468 | -2.28 / 0.26 (mode 5) | 1992.02.18 | 2016 error 4401; 2017, 2018 no; 2019-2026 yes |

**Symbol class (owner, 2026-10-05): do NOT use plain EURUSD / EURGBP on OANDA TMS until this is settled.**
Plain EURUSD and EURGBP show a FIXED 2400-point spread and swap mode 0 (no swaps); AUDNZD, AUDCAD and CHFJPY exist only
as `.pro`. A read-only re-run of `NNFX_EnvCheck` for `EURUSD.pro` and `EURGBP.pro` (with each symbol's path on the
server and trade mode) is to decide which symbol class the EA uses; result below when run.

**Daily close and rollover on OANDA TMS (server GMT+2, read 2026-10-06):** the D1 candle opens at 00:00 server
= 22:00 GMT = **18:00 New York** (EDT, UTC-4). The 17:00 New York rollover is **23:00 server**. (On MetaQuotes-Demo,
GMT+3, both are 00:00 server.) The rollover block must use 23:00 server here, not server midnight (PLAN_PHASE6 6d).
Both offsets change at daylight-saving changes (US and the broker's own); to re-read after each change.

**Real ticks, Phase 8 input:** on the three `.pro` pairs the mid-January probe found real ticks from **2019** on
(2017 and 2018 "no", 2016 error 4401). The probe reads one 3-day window per year, so "no" means none in that window,
not proven none all year. A backtest on OANDA "every tick based on real ticks" would start in 2019 at the earliest
(SPEC: "at least 3 years if the broker's history allows").

**Warning, not verified: the plain-name EURUSD and EURGBP readings are probably not the tradable instruments.**
Both show a fixed 2400-point spread and zero swaps (swap mode 0), unlike the three `.pro` pairs. EnvCheck takes the
requested name first if it exists, so it never looked for `EURUSD.pro` / `EURGBP.pro`. To re-check with those names
(another ~15 minutes with the OANDA terminal closed) before any OANDA number is relied on.

Also: the account currency is **EUR** (MetaQuotes-Demo is USD), so tick values are in EUR; spreads were read in the
Asian session, not at the London/New York overlap; commission is still unknown (not a symbol property; it needs a
deal record, and no orders are placed on OANDA under D6c-2, or the broker's published terms).

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
