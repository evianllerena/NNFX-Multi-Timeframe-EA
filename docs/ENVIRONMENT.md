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

## Read on 2026-10-04 (NNFX_EnvCheck, from the Experts log)

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

## Still to check

| # | Check | How |
| --- | --- | --- |
| 1 | Server history depth: AUDCAD, CHFJPY (3 of 5 pairs read above) | `NNFX_EnvCheck` script (runner) |
| 2 | Real-tick history: EURGBP, AUDCAD, CHFJPY | `NNFX_EnvCheck` script (runner) |
| 3 | Server time offset after the daylight-saving change | `NNFX_EnvCheck` script, re-run after the change |
| 4 | Spread during market hours; lot step, tick value, swaps per pair | `NNFX_EnvCheck` script (runner, on a weekday) |
| 5 | Commission | Not exposed as a symbol property in MQL5; read from a demo trade's deal record, or the broker's published terms |
| 6 | Does the broker keep order comments unchanged? | Small demo-account test |
| 7 | How far back the economic calendar goes | Calendar export tool |
| 8 | Can the tester run from the command line on this PC? | `tools/run_phase5_checks.ps1` step 4 |
| 9 | Live broker choice | Owner |
