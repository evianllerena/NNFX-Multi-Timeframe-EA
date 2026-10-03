# NNFX Multi-Timeframe EA — Intraday Spec (Phase 1)

Oct 1, 2026 · @Evian

This spec says exactly how the approved rulebook runs on 30M, 1H and 4H, and how every part will be proven before it is trusted. Rule IDs (M1, E6, X3…) refer to the rulebook. No code is written until you approve this.

## Architecture

One shared rules core, run as three instances (30M, 1H, 4H), each loaded with its own preset file. I recommend that each instance trades a **basket of pairs from one chart** rather than one chart per pair: MT5's tester supports multi-currency EAs, and it is the only way to test the same-currency rule (M6) and VP's 5-pair test (P2) in one run.

| Module | Owns | Never does |
| --- | --- | --- |
| Rules core | Every entry/exit decision in the rulebook (E0–E6, X1–X5), from closed-candle values | Places orders, reads indicators, or knows the timeframe |
| Indicator slots | Baseline, C1, C2, Volume, Exit: load the indicator from its profile and turn its values into long / short / none | Decide trades |
| ATR | ATR(14) on the chart's timeframe, closed candle only | — |
| Risk | Lot size from 2% risk and the stop distance; refuses a trade it cannot size safely | Round risk up |
| Exposure | Same-currency check across **every** open position on the account | — |
| Orders | Opens the two halves with broker-held stops, TP1, breakeven, trailing, exits | Decide trades |
| State & recovery | Remembers each trade's halves and continuation state; rebuilds them after a restart | — |
| Guard | On/off switches, drawdown pause, news block, rollover window, max spread | — |
| News source | Live: MT5's calendar. Tester: a saved calendar file | — |
| Log | One line per candle per pair (every decision and why) + a trade log | — |

The rules core has no MT5 trading calls in it, so the same logic can be checked line-for-line against the Python answer key (section: Verification plan).

## Candle timing and sessions

Every decision runs once per closed candle, per pair, on the first price update of the new candle (decision #3). Stops and TP1 sit with the broker, so they can fill mid-candle; everything else waits for the close.

|  | 30M | 1H | 4H |
| --- | --- | --- | --- |
| Decision points per pair per day | 48 | 24 | 6 |
| Entries, exits X2–X4, breakeven, trailing | At candle close | At candle close | At candle close |
| SL and TP1 | Broker-held, any time | Broker-held, any time | Broker-held, any time |
| Rollover block (decision #10) | 15 min before to 60 min after the daily close | Same | Same |

Details:

- **Each pair keeps its own clock.** In a basket, prices arrive at different moments; a pair is processed when its own new candle exists, so no pair is read mid-candle.
- **Daily close time is a setting.** It depends on the broker's server time; it is read from the broker during Phase 1 checks, not assumed.
- **4H candles follow the broker's clock.** Where the 4H candles start depends on the broker's time zone, so results can differ between brokers. The broker used for testing is the broker used live.
- **Weekends.** VP holds daily trades over weekends and has no rule for intraday. Default: hold, same as VP. A setting can block new entries in the last N hours before the weekend close; it is off by default and tested.
- **Fixed processing order.** When several pairs signal on the same candle, they are processed in a fixed order so every run gives the same result.

## Settings

All three presets start with the same defaults, so the shootout compares timeframes, not settings. ATR is always measured on the chart's own timeframe, which scales stops and targets automatically. Values marked "fixed" are VP's A-level rules and are not tuned.

| Setting | Rule | Default | Values the tests try |
| --- | --- | --- | --- |
| ATR period | M1 | 14 | Fixed |
| Risk per trade | M2, decision #14 | 2% | Fixed for the shootout; editable per preset afterwards |
| Stop distance | M3 | 1.5 × ATR | Fixed |
| TP1 distance (half 1) | T1 | 1 × ATR | Fixed |
| Max distance from baseline | E1–E3 | 1 × ATR | Fixed |
| Trailing: switch-on distance | T4, #1 | 2 × ATR close | Off (breakeven only), 1.5, 2, 2.5 |
| Trailing: distance behind price | T4, #1 | 1.5 × ATR | 1, 1.5, 2 |
| Runner cap | T7, #11 | Off | Off, 1, 2, 3, 4 × ATR |
| Exit indicator / C1 flip / baseline exit | X2–X4, #2 | All on | Each on/off |
| One-candle rule | E4, #4 | On | On/off |
| Bridge too far | E5, #5 | On, 7 candles | Off, 7, 14, 28, and the 7-day equivalent |
| Continuation | E6, #6–#7 | Version (a) VP | Off, (a), (b) |
| News block | N1, #9 | On, 24 h | On/off (needs saved calendar in tests) |
| Rollover block | #10 | 15 min before / 60 min after | Fixed |
| Weekend entry block | Section above | Off | Off, 4 h, 8 h |
| Max spread | Guard | Off | Off, then set from measured spreads |
| Drawdown pause | R1, #12 | 10% from peak | Fixed |

Only one or two settings change per test run, with everything else at default, so each result can be traced to a single cause.

## Money, sizing and exposure

The EA may risk less than 2% when lot sizes force it to round, but never more.

**Sizing (M2–M5)**

1. Risk money = 2% of the account (balance or equity: decision below).
2. Stop distance = 1.5 × ATR of the last closed candle.
3. Loss per lot = stop distance converted to money with the broker's own tick size and tick value for that pair.
4. Total lots = risk money ÷ loss per lot, split into two equal halves, each rounded **down** to the broker's lot step.
5. If a half is below the broker's minimum lot, the trade is skipped and logged as "too small to size". It is never rounded up (this was the old harness's double-risk bug).

**Same-currency exposure (M6, M7)**

- Before any new trade, the EA lists every open position on the account: all three EAs, all pairs, and any manual trades.
- Each position is split into its two currencies with direction (long EUR/USD = long EUR + short USD).
- If the new trade would put a second full-risk trade on the same currency in the same direction, it is not opened at 2%. Default: the first signal keeps its 2% and the later one is skipped. Alternative to test: both at 1% (M7).
- On the 30M and 1H charts this check matters more: more signals per day means more overlap.

**Hedging vs netting accounts**

The EA reads the account type from MT5 at start-up (`ACCOUNT_MARGIN_MODE`: retail netting, exchange, or retail hedging).

|  | Hedging account | Netting account |
| --- | --- | --- |
| The two halves | Two separate positions | One position; TP1 is a broker-held order that closes half of it |
| Several EAs on the same pair | Fine, each keeps its own positions | Not allowed: positions on one pair merge, so only one timeframe may trade a given pair |
| Status | Primary target | Supported, but the half-close order must be proven on your broker before use |

## Orders and restart recovery

No position ever exists without a broker-held stop, and a restart must never change what the EA does next.

**Placing and managing orders**

- Every order is sent with its stop loss in the same request. If the broker would reject the stop (closer than its minimum stop distance), the trade is not sent and the reason is logged. This matters most on 30M, where ATR is small.
- Half 1: stop + TP1 at 1 × ATR. Half 2: stop, no target (or the runner cap when that setting is on).
- When half 1's TP fills, half 2's stop moves to breakeven straight away (T2), not at the next candle close.
- Trailing (T4) and signal exits (X2–X4) act at candle close.
- If any position is ever found without a stop, the EA closes it at once and logs an alarm.
- A failed order is retried a limited number of times. Before every retry the EA checks whether the first attempt actually filled, so it can never open a duplicate.

**Knowing which positions are which**

- Each instance has its own magic number (one per timeframe).
- Each trade gets an ID, written into both halves' order comments and into a small state file.
- Some brokers change order comments, so comments are never the only record: the state file and the account's deal history back each other up.

**Rebuilding after a restart**

On start-up, before doing anything else, the EA rebuilds its memory from what the broker holds:

| What it needs | Rebuilt from |
| --- | --- |
| Which open positions are halves of the same trade | Magic number + trade ID; state file; deal history |
| Has TP1 already filled? | Deal history (half 1 closed at its target) |
| Breakeven / trailing stage | Half 2's current stop compared with entry and ATR |
| Continuation still allowed? | Price history since the original entry: has price crossed the baseline? |
| Last exit direction (for continuation) | Deal history |

Pass test: restart MT5 in each state (before TP1, after TP1, trailing, flat but waiting for a continuation). The trades and logs afterwards must match a run with no restart.

## On/off controls and safety limits

Turning the EA "off" stops **new** trades by default; open trades keep being managed, so they are never left half-handled. Closing everything is a separate, deliberate action.

| Control | Scope | How |
| --- | --- | --- |
| Master switch | All three instances at once | One shared switch in the MT5 terminal (a terminal-wide global variable), plus a button on each chart |
| Instance switch | One timeframe | Setting + chart button |
| Pair list | One pair in one instance | Preset file |
| Close-all | One instance's trades | Chart button with a confirm step; never automatic |
| MT5's own Algo Trading button | Every EA in the terminal | Stops all EA activity, including trade management; broker-held stops still protect open trades |

**Safety limits** (each logged and, if enabled, sent as a push notification to your phone through MT5)

| Limit | Source | Default | What happens |
| --- | --- | --- | --- |
| Drawdown pause | VP, R1 | 10% below the account's peak | No new trades on any instance until you reset it |
| Daily loss limit | Not VP (your request) | 3 × risk per trade (6% at 2%) | No new trades until the next trading day |
| Max spread | Not VP | Off until spreads are measured | Skip the entry |
| Missing stop | This spec | Always on | Close the position at once and alarm |
| Indicator failure | This spec | Always on | Indicator won't load or returns empty values: no new trades on that pair, alarm |

The daily loss default is tied to the risk setting, so it scales if you change risk: three full stop-outs in one day is the trigger.

## News filter

MT5's built-in economic calendar works on live charts but **not** in the Strategy Tester, so backtests need a saved copy of past events. This is confirmed in MQL5's own documentation, not assumed.

- **In the tester:** "Calendar functions cannot be used in the tester: when trying to call any of them, we get the FUNCTION\_NOT\_ALLOWED (4014) error." The documented workaround is to save calendar entries to files on a live chart, then load them in the tester ([MQL5 book: Economic calendar](https://www.mql5.com/en/book/advanced/calendar)).
- **Plan:** a small export tool runs once on a live chart and saves VP's event list for the test years to a file. Live and tester both read events through one module, so the EA behaves the same in both.
- **Reported limit:** forum users report a timeout when asking the calendar for more than one month at a time ([forum thread](https://www.mql5.com/en/forum/496980)), so the export goes month by month. How many years back the calendar goes is still to be checked.

How the rules apply on each candle close:

| Rule | Applied as |
| --- | --- |
| N1 | No new trade on a pair if either of its currencies has one of VP's events within the next 24 hours |
| X5 | At the first candle close inside that 24-hour window: exit if losing, or if in profit by less than 1 × ATR; otherwise keep the trade (its stop is at breakeven or trailing) |
| N2 | Elections and referendums are entered by hand as a blackout list (currency + dates) in the preset, because the calendar does not reliably carry them |

The event list is VP's per-currency list from the rulebook, matched by event name. A test run with the news filter off is also kept, to measure what the filter is worth.

## Indicator profiles

Swapping an indicator means editing one small text file, never the EA's code. The EA loads any indicator with its settings while running, using MT5's `IndicatorCreate`.

**What a profile holds**

| Field | Example | Why |
| --- | --- | --- |
| Indicator file | `Custom\SSL_Channel.ex5` | Which indicator to load |
| Slot | C1 | Which job it does |
| Input settings | period = 10 | Passed to the indicator in order |
| Signal type | Two-line cross | How its values become long / short / none |
| Line numbers (buffers) | fast = 0, slow = 1 | Which output lines to read; never guessed |
| Centre line | 0, or 50, etc. | Required for zero-cross types; never defaulted to 0 |
| Volume pass rule | Above a level / above its own average / line cross | Volume indicators signal in different ways |
| Warm-up candles | 50 | Values before this are ignored |

**Signal types**

| Type | Long when | Short when | Allowed in |
| --- | --- | --- | --- |
| Price line | Close above the line | Close below the line | Baseline |
| Two-line cross | Fast above slow | Fast below slow | C1, C2, Exit |
| Centre-line cross | Value above its centre line | Value below it | C1, C2, Exit |
| Pass / fail | — | — | Volume (passes or fails; no direction) |

The old project limited C2 to centre-line types. VP does not require that, so C1, C2 and Exit can each use either type.

**Bad values never become signals.** Empty values, "not a number" and warm-up candles all read as "none". If an indicator fails to load or returns nothing, that pair stops taking new trades and the EA raises an alarm.

**Every new profile is checked before use:** its values on a fixed sample of candles must match MT5's Data Window for the same candles.

## Verification plan

Nothing is trusted on a "tests pass" summary: each check below has a pass line, and every failure is traced to its root cause before moving on.

**Check 1 — The EA does exactly what the rulebook says**

| Step | What | Pass |
| --- | --- | --- |
| 1a Rule cases | Every rule ID gets hand-built candle sequences with a known right answer: at least one where the rule fires and one where it must not | Python answer key and MT5 rules core both 100% |
| 1b Bar-by-bar match | Real candles and real indicator values are exported from MT5; the Python answer key replays them; its decisions are compared with the EA's decision log, every candle, every pair | Zero mismatches over at least one year per timeframe |
| 1c Trade checks | Automatic checks over every test trade in the logs | Every position had a stop from its first moment; actual risk never above 2%; halves equal; TP1, breakeven and trailing at the right prices |
| 1d Visual review | Step through sample trades in the tester's visual mode | You and I agree each trade matches the rules |
| 1e Restart | Restart MT5 in each trade state (section: Orders) | Identical to a run without restart |
| 1f Netting | Only if your account is netting | Half-close works on your broker |

**Check 2 — The rules are VP's**

- A rules are already checked against VP's writing.
- B rules and continuation version (a) stay labelled "unverified" in the rulebook until confirmed from VP's videos. Until then they are settings, tested both ways.

**Check 3 — It works**

- The timeframe shootout below, on data the settings were not tuned on.
- Then a demo account for at least 3 months on the winner. Pass: every demo decision matches a backtest re-run over the same dates, and any profit difference is explained by spread, slippage or commission.

**Check 4 — Every backtest result is valid, not skewed**

A backtest result counts only after it passes every check below. A result that fails one is marked invalid in the log, kept (never deleted), and its cause fixed before re-running.

| # | What can skew a result | Check | Pass |
| --- | --- | --- | --- |
| V1 | **Looking ahead:** a decision uses a candle that hasn't closed yet | Re-run the same test with a different MT5 price model; decisions use closed candles only, so they must not change | Decision logs identical |
| V2 | **Repainting indicators:** an indicator rewrites its past values, so history looks better than it traded | Record each indicator's value as it was at each candle close, then compare with the values recomputed afterwards over the same history | Every value identical; a repainting indicator is rejected |
| V3 | **Bad or missing price data** | Gap report per pair (missing candles, frozen prices, spikes); MT5's history-quality figure in the test report | No unexplained gaps; quality figure recorded with every result |
| V4 | **Missing costs** | Spread, commission and swap must all appear in the test report and match the broker's figures | Costs present and matching; plus a stress run with spreads 50% wider |
| V5 | **Perfect fills** | Re-run with MT5's random execution delay on | Ranking does not flip |
| V6 | **Overfitting:** settings tuned until the past looks good | Forward period never used for tuning; the number of runs tried is logged; a setting must also work at its neighbouring values | Forward result holds up; no cliff when a setting moves one step |
| V7 | **Lucky winner from many tries:** testing many indicators makes a lucky one likely | Every run is logged, not just winners; winners must also pass the forward period | Winner confirmed on untouched data |
| V8 | **Too few trades** | Minimum sample (decision #8) | At least 100 trades in total and 30 in the forward period |
| V9 | **Picking pairs or dates after seeing results** | Pairs (VP's 5) and dates fixed before the first run and written in the log | No change after results are seen |
| V10 | **One pair or one year carries the result** | Results split per pair and per year | Flagged if one pair or year makes most of the profit |
| V11 | **Unrealistic trade sizes** | From the trade log: risk per trade, lot steps, minimum lots, margin used | Never above 2% risk; never above available margin |
| V12 | **Time-zone mistakes:** news, rollover or candles on the wrong hour | Check sample news events and the daily close against their known times, including daylight-saving changes | All samples line up |
| V13 | **MT5's report miscounting** | Recompute the key figures (trades, R, drawdown) from the raw trade log with an independent script | Matches MT5's report |
| V14 | **Can't be repeated** | Run the same test twice | Identical trade logs |

Every result is saved with the conditions that produced it (settings, dates, pairs, price model, costs, EA version), so any number can be re-run and checked later.

## Timeframe shootout

The winner is the timeframe with the best return for its drawdown on data it was never tuned on, among those that stay within VP's 10% drawdown limit. Everything else is held equal.

**Three stages**

1. **Same indicators, three timeframes.** One fixed reference set of indicators on 30M, 1H and 4H. This isolates the effect of the timeframe itself.
2. **Indicator auditions per timeframe.** Swap one slot at a time through the candidate profiles; the rest stay at reference. A daily winner is not assumed to win intraday.
3. **Final comparison.** Each timeframe with its own best set, judged on the forward (untouched) period.

**Test conditions (identical for all three)**

| Item | Setting |
| --- | --- |
| Pairs | VP's 5 test pairs first (EUR/USD, AUD/NZD, EUR/GBP, AUD/CAD, CHF/JPY); all 28 if history allows |
| Dates | The same years for every timeframe; at least 3 years if the broker's history allows |
| Tuning vs forward | Settings chosen on the first two-thirds; the last third is the forward period (MT5's built-in forward mode, 1/3) |
| Price model | "Every tick based on real ticks" (real spreads) if the broker has tick history; otherwise "1 minute OHLC", and the report says so |
| Costs | The broker's real commission, confirmed in the test report |
| Robustness re-run | Same test with MT5's random execution delay switched on |
| News | Saved calendar file, filter on (plus one run with it off) |

**How results are measured**

Pips are not comparable across timeframes, so results are in **R** (1R = the money risked on one trade).

| Measure | Used for |
| --- | --- |
| Max drawdown % | Gate: must stay at or under 10% (VP, R1) |
| Number of trades | Gate: at least the minimum sample (decision below) |
| Return ÷ max drawdown | **Ranking** (computed by the EA and returned to MT5 as a custom score) |
| Expectancy (R per trade), profit factor, win rate, longest losing streak, % of months positive | Reported, not ranked |
| Result per pair | A result carried by one pair alone is flagged |

Tie-break: the timeframe that needed fewer settings changed from the defaults.

## Open checks

These facts are not yet verified, and parts of this spec depend on them. Most can be read from your MT5 with a read-only check script, which needs your approval and access to your MT5 folder.

| # | Check | Affects | How |
| --- | --- | --- | --- |
| 1 | Broker, and hedging or netting account | Two-halves design | Read-only script on your MT5 |
| 2 | Years of 30M, 1H, 4H and real-tick history for the 5 test pairs | Test length, price model | Read-only script |
| 3 | Broker server time zone and daily close time | Rollover block, 4H candle alignment | Read-only script |
| 4 | Commission, typical spread, minimum stop distance per pair | Costs; whether 30M stops are even allowed | Read-only script |
| 5 | Does your broker keep order comments unchanged? | Restart recovery | Small demo-account test |
| 6 | How many years back MT5's calendar goes, and how VP's events are named in it | News filter in backtests | Export tool on a live chart |
| 7 | Can the tester be launched from the command line on your PC? Your old project found it never ran reliably | Automated test runs; fallback is running tests from the MT5 window | Try once; report |
| 8 | VP's videos for the B rules | Upgrading B rules to A | You, if you have the videos or notes |

## Decisions for you

Ten calls, each with my proposed default. As with the rulebook, ticking means "build it this way and test it", not "proven".

- [x] **1. Basket design:** each timeframe instance trades all its pairs from one chart (needed to test M6 and the 5-pair set in one run).
- [x] **2. What "off" means:** stop new trades and keep managing open ones; close-all is a separate button.
- [x] **3. Risk base:** 2% of **balance**, so trade size doesn't swing with other trades' open profit or loss. Alternative: equity.
- [x] **4. Same-currency rule:** only trades in the same direction on a currency count (VP's example is all short AUD). First signal keeps 2%, later one skipped; "both at 1%" is tested too.
- [x] **5. Daily loss limit:** 3 × risk per trade (6% at 2%), then no new trades until the next day.
- [x] **6. Drawdown pause (10%):** you reset it by hand; it never resumes on its own.
- [x] **7. Weekends:** hold trades over the weekend as VP does; the Friday entry block is off by default and tested.
- [x] **8. Minimum sample:** a timeframe needs at least 100 trades over the whole test and 30 in the forward period to be ranked.
- [x] **9. Demo period:** at least 3 months on the winner before any real money.
- [x] **10. Netting accounts:** if your account is netting, each pair is traded by one timeframe only.

## Sources

- *NNFX Multi-Timeframe EA — Rulebook (Phase 0)*: every rule ID used here
- [MQL5 book — Economic calendar](https://www.mql5.com/en/book/advanced/calendar): calendar functions return error 4014 in the tester; save-to-file workaround
- [MQL5 forum — ERR\_CALENDAR\_TIMEOUT over one month](https://www.mql5.com/en/forum/496980): month-by-month export
- [MQL5 forum — Economic Calendar in backtesting](https://www.mql5.com/en/forum/476661): community cache tool for backtests
- [MetaTrader 5 Help — Platform Start for Advanced Users](https://www.metatrader5.com/en/terminal/help/start_advanced/start): tester price models, forward mode (1/2, 1/3, 1/4, custom), random execution delay, custom optimisation score from the EA
- [MetaQuotes — Trading Strategy Tester](https://www.metaquotes.net/en/metatrader5/algorithmic-trading/tester): multi-currency EA testing; real-tick testing
- [MQL5 book — Account type: netting or hedging](https://www.mql5.com/en/book/automation/account/account_netting_hedge): `ACCOUNT_MARGIN_MODE` values
