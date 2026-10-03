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

## Still to check

| # | Check | How |
| --- | --- | --- |
| 1 | Server history depth per pair and timeframe (30M, 1H, 4H) | `NNFX_EnvCheck` script |
| 2 | Real-tick history: from which year | `NNFX_EnvCheck` script |
| 3 | Broker server time offset and daily close time | `NNFX_EnvCheck` script |
| 4 | Spread, minimum stop distance, lot step, tick value, swaps per pair | `NNFX_EnvCheck` script |
| 5 | Commission | Not exposed as a symbol property in MQL5; read from a demo trade's deal record, or the broker's published terms |
| 6 | Does the broker keep order comments unchanged? | Small demo-account test |
| 7 | How far back the economic calendar goes | Calendar export tool |
| 8 | Can the tester run from the command line on this PC? | Try once |
| 9 | Live broker choice | Owner |
