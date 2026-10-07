# Decision log

Every decision that shapes the EA, with its date and where it came from. Ticking a
decision means "build it this way and test it", not "proven". Backtest results can
reopen any B or C decision; reopening one adds a new row here, it never edits an old one.

Labels: **A** = VP's own words · **B** = secondary source · **C** = no source / owner's choice.

## Project setup (2026-09-28)

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| P-1 | One shared rules core, run as three instances (30M, 1H, 4H) with one preset each, rather than three separate EAs | C | Approved |
| P-2 | Runner take-profit is a setting, off by default (option 3); backtests decide | C | Approved |
| P-3 | Risk default 2% per trade, editable per timeframe preset | A (VP's 2%) | Approved |
| P-4 | One exit indicator slot | A | Approved |
| P-5 | Every order carries a broker-held stop loss | C (owner requirement) | Approved |
| P-6 | Safety limits added, sized from account and risk | C (owner requirement) | Approved; see S-5, S-6 |
| P-7 | Build from zero; the old scanner-repo code is reference only | C | Approved 2026-09-28 |

## Rulebook decisions (approved 2026-10-01; #5 and #11 on 2026-10-03)

| ID | Decision | Rule | Label | Status |
| --- | --- | --- | --- | --- |
| R-1 | Trailing stop: on after a close 2×ATR beyond entry, trail 1.5×ATR, move at each candle close | T4 | B | Approved, to test |
| R-2 | Exit indicator, C1 flip and baseline cross all on; first one closes the trade | X2–X4 | A/B | Approved, to test |
| R-3 | Act on the first tick of the new candle using the candle that just closed | E0 | C | Approved |
| R-4 | One-candle rule: price must still be within 1×ATR of the baseline on the second candle | E4 | C | Approved, to test |
| R-5 | Bridge too far: setting (on/off + candle count), counted from the candle before the cross; tested at 7 and larger values per timeframe | E5 | B | Approved, to test |
| R-6 | Continuation: two versions, both tested. (a) VP per owner: C2 flips back while C1 never flipped. (b) Lesson 11: exit indicator doubles as the signal | E6 | (a) owner from VP videos, unverified in writing; (b) B | Approved, to test |
| R-7 | Continuation conditions: baseline not crossed since the original entry; volume and 1×ATR rules don't apply | E6 | B | Approved |
| R-8 | Baseline cross = close on the other side from the previous close | E2 | C | Approved |
| R-9 | No new trades on a currency within 24 h before its major events; open-trade rule X5 applies | N1, X5 | A | Approved |
| R-10 | No new entries from 15 min before to 60 min after the daily close | M9 | C (window) | Approved |
| R-11 | Runner cap off by default; tested at 1×, 2×, 3×, 4× ATR | T7 | C | Approved, to test |
| R-12 | Stop opening new trades at 10% drawdown from peak | R1 | A | Approved |
| R-13 | Start with VP's 5 test pairs; widen to 28 once broker history is confirmed | P1, P2 | A | Approved |
| R-14 | Risk 2% default, editable per preset | M2 | A | Approved |
| R-15 | News list uses roles not names; SNB rate decision replaces CHF Libor | N1 | C (substitution) | Approved |

## Spec decisions (approved 2026-10-03)

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| S-1 | Each timeframe instance trades a basket of pairs from one chart | C | Approved |
| S-2 | "Off" stops new trades and keeps managing open ones; close-all is a separate button | C | Approved |
| S-3 | Risk is 2% of balance (not equity) | C | Approved |
| S-4 | Same-currency rule counts same-direction exposure only; first signal keeps 2%, later skipped; "both at 1%" also tested | A (rule) / C (detail) | Approved, to test |
| S-5 | Daily loss limit 3 × risk per trade (6% at 2%) | C | Approved |
| S-6 | 10% drawdown pause is reset by hand only | C | Approved |
| S-7 | Hold over weekends; Friday entry block off by default and tested | C | Approved, to test |
| S-8 | Minimum sample: 100 trades in total and 30 in the forward period | C | Approved |
| S-9 | Demo for at least 3 months before real money | C | Approved |
| S-10 | On a netting account, each pair is traded by one timeframe only | C | Approved |
| S-11 | Every backtest passes validity checks V1–V14 before it counts | C (owner requirement) | Approved 2026-10-03 |

## Phase 3 interpretations (reviewed by owner 2026-10-03)

Exact logic the answer key and the MQL5 core use where the rulebook leaves room. The owner-facing
wording, with an intraday example for each, is in the living rulebook doc ("Exact-logic
interpretations"); technical detail is in `tests/python/README.md`. "One candle" always means one
candle of the chart's timeframe (30 min, 1 h or 4 h).

| ID | Interpretation (short) | Rule | Status |
| --- | --- | --- | --- |
| I-1 | Read indicators only on a closed candle; act at that same moment (start of the next candle) | E0 | Reworded; awaiting tick |
| I-2 | A signal = baseline cross or C1 switching; a trade also needs baseline, C1, C2 and volume to agree | E1, E2 | Reworded; awaiting tick |
| I-3 | A trade opens only on a candle with a signal AND full agreement within 1 ATR; cross + C1 switch on one candle = baseline-cross entry | E1, E2 | Reworded; awaiting tick |
| I-4 | 7-candle rule counts C1 candles before the cross; baseline-cross entries only | E5 | Approved |
| I-5 | Pullback: wait one candle; enter if within 1 ATR and all agree | E3 | Approved |
| I-6 | One-candle rule: exactly one late indicator, within 1 ATR; wait one candle | E4 | Approved |
| I-7 | A dropped wait doesn't block a different valid signal on the same candle | E3, E4 | Reworded (intraday example); awaiting tick |
| I-8 | Exit indicator exits while it reads against the trade, not only on its switch | X2 | Approved |
| I-9 | Any exit reason at a close closes the trade straight away; several reasons = one close | X2-X5 | Reworded; awaiting tick |
| I-10 | News exit at first close within 24 h; close if losing or up < 1 ATR | X5 | Approved |
| I-11 | Trail after TP1 once a close is 2 ATR past entry; 1.5 ATR behind latest close; never back | T4 | Approved |
| I-12 | Continuation: same direction, baseline not crossed since original entry, (a) C1 never against; can repeat | E6 | Approved |
| I-13 | (a) C2 switches back; (b) exit indicator switches back with C1 and C2 agreeing | E6 | Approved |
| I-14 | One trade per candle per pair; a regular entry beats a continuation, but if the regular entry is refused or only waiting, the continuation can open | E6 | Approved; code changed 2026-10-03 (fixtures E6_after_regular_refused, E6_regular_entry_wins) |
| (note) | Answer-key fill assumptions (stop before target in one candle; breakeven from next candle; gapped stop fills at open). Checker-only, not a trading rule | M3, T1, T2 | No decision needed |

## Phase 5 design choices (2026-10-04, for owner review)

| ID | Choice | Label | Status |
| --- | --- | --- | --- |
| D5-1 | Profiles live in MT5's shared `Common\Files\NNFX\profiles` so the terminal and the Strategy Tester read the same files | C | Pending review |
| D5-2 | Reference set from MT5 standard indicators (20 SMA, RVI 10, MACD, tick volume) to prove the pipeline; not chosen for performance | C | Pending review |
| D5-3 | C1, C2 and exit may each be two-line or centre-line (the old project limited C2 to centre-line; VP doesn't) | C | Pending review |
| D5-4 | A candle with any missing or warm-up value is never fed to the rules core (logged with the reason instead) | C | Pending review |
| D5-5 | Volume average reads the previous N readings of the profile's own buffer (fixes the old harness reading buffer 0) | C | Pending review |

## Phase 6 plan decisions (approved 2026-10-04)

From review `G2_phase6_1` (PASS). The owner accepted the reviewer's recommended default for every open decision
("accept recommended defaults"; changes: none). Options and reasons are in `docs/PLAN_PHASE6.md`, section 11.
Label C (owner's choice) unless stated.

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| OD-1 | A test EA (`NNFX_OrderTest`) in 6b-6e; the real EA `NNFX_EA.mq5` in sub-phase 6f | C | Approved |
| OD-2 | Drawdown pause measured from the peak of equity, sampled at each candle close | C | Approved |
| OD-3 | Daily loss counts closed trades only; the day starts at server midnight (the daily close, 00:00 server) | C | Approved |
| OD-4 | Split mode (M7): three or more signals on one currency leg are all skipped | C | Approved |
| OD-5 | Not enough free margin for the sized trade: skip and log | C | Approved |
| OD-6 | Sizing uses the larger of `SYMBOL_TRADE_TICK_VALUE` and `SYMBOL_TRADE_TICK_VALUE_LOSS`, read at order time | C | Approved |
| OD-7 | On start or restart with an unprocessed closed candle: skip it and wait for the next new candle | C | Approved |
| OD-8 | A stopless position with our magic is closed at once with an alarm; a manual stopless position raises an alarm only | C | Approved |
| OD-9 | State file in `MQL5\Files\NNFX\state\` (per terminal, never shared with the tester) | C | Approved |
| OD-10 | Restart tests: both a tester simulated restart and a demo real restart | C | Approved |
| OD-11 | VP's event-name mapping is a text file in the repo; the owner approves the names | C | Approved |
| OD-12 | Live news from a CSV refreshed daily by the export script, with an alarm if older than 24 h | C | Approved |
| OD-13 | Order retries: 3, 1 s apart, a duplicate check before each | C | Approved |
| OD-14 | Accept any fill; SL/TP from the fill price; log the slippage | C | Approved |
| OD-15 | Breakeven is exactly the entry price | A (T2) | Approved |
| OD-16 | Magic numbers 30M = 26030, 1H = 26060, 4H = 26240, fixed in the presets | C | Approved |
| OD-17 | Running through a weekend: Friday's last candle is acted on at the Monday open | C | Approved |
| OD-18 | CONTEST accounts are refused (orders only on DEMO or in the Strategy Tester) | C | Approved |
| OD-19 | Elections/referendums blackout list (N2) starts empty; the owner adds entries | C | Approved |
| OD-20 | A trade counts for same-currency exposure (M6) until fully closed, including a breakeven runner | C | Approved |
| OD-21 | Non-FX symbols are ignored for exposure, with a log line | C | Approved |

## Phase 6b review decisions

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| D6b-1 | The MT5-offline check (carry-over 1; G1_phase6a_1 note 3; G1_phase6b_1 F3) is **deferred** from the 6b gate to the **6f G1 gate**: it must pass before the real EA (`NNFX_EA.mq5`) is accepted and before any demo forward-test. It covers EnvCheck `RESULT: INVALID (not connected)` and the EA/order path refusing with "not connected" and opening 0 orders, run on a live chart (the tester skips the wait) | C (owner, 2026-10-04) | Approved |

## Phase 6c owner decisions (2026-10-05)

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| D6c-1 | Process safety with another MT5 installed: the "MT5 must be closed" check matches ONLY the terminal being tested, by full path; any other `terminal64.exe` is listed in SUMMARY.txt as "other terminal running (ignored)" and never touched; anything that closes MT5 acts only on the process id it started (source-scan test `test_process_safety.py`, plus one planted bug); the run stops if the tested terminal's data folder (origin.txt) or account (EnvCheck Login/Server vs `-ExpectLogin`/`-ExpectServer`) is not the expected one | C (owner) | Approved |
| D6c-2 | Candidate live broker: OANDA TMS Brokers S.A. A read-only check on its DEMO account 62316800 (terminal `C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe`, data folder `...\Terminal\47AEB69EDDAD4D73097816C71FB25856`): only `NNFX_EnvCheck` and its include are copied there and compiled with OANDA's MetaEditor; results go to `docs/ENVIRONMENT.md` "OANDA TMS (candidate live broker)". **No orders on OANDA, demo or live.** The owner closes the OANDA terminal only for the minutes the check runs | C (owner) | Approved |
| D6c-3 | Extends D6c-1 for unattended demo runs. MT5 can end the process the driver started: LiveUpdate (build 6238 -> 6241, run `demo_restart_20261006_000708`) came back under a new PID, and a window closed by hand (run `demo_restart_20261006_001959`). Both runs are kept in `checks\invalid\`. The driver now handles this without the owner. It adopts a relaunched process ONLY if that process has the tested terminal's full path AND this run's own `/config` file on its command line. With no such relaunch, it starts MT5 again itself (an unplanned restart; its REBUILD row is checked like the others; at most 5, then STOP). Any other `terminal64.exe` is still never touched. Owner: "you need to figure out how to close it becasue it will affect the preocess i cant be always" | C (owner, 2026-10-06) | Approved |
| D6c-3 (confirmed) | The owner confirmed D6c-3 as recorded (2026-10-06, after review G1_phase6c_1 F4a): "I confirm D6c-3 as recorded." | A (owner, 2026-10-06) | Approved |
| D-OPS-1 | Standing approvals for test operations (owner, 2026-10-06). (1) The agent may start, close, restart or adopt ONLY `C:\Program Files\MetaTrader 5\terminal64.exe` for its own test runs, without asking. (2) It may close its own leftover TEST positions (magic 26990-26999) on MetaQuotes-Demo 113593254 only, through `Orders.mqh`, logged. (3) It schedules demo tests around market hours and MT5 updates itself; the owner is never asked to watch. (4) While a review is pending, the next sub-phase starts on a NEW branch stacked on the pending one (draft PR, base = that branch until it is merged, then re-targeted to main). The agent STOPS and asks ONLY for: merging; real money or any OANDA account other than demo 62316800 (read-only); changes to rulebook rules, risk settings or any OD/D decision; anything that would delete evidence | A (owner, 2026-10-06) | Approved |
| OD-3 (update) | **Replaces OD-3's day start** ("the day starts at server midnight"). One shared **trading day boundary** = 17:00 New York (the real rollover), set per broker and converted to that server's time; used by the rollover block (R-10), the daily-loss reset (still closed trades only) and the logs' trading day. New York follows US daylight saving (2026: 8 Mar - 1 Nov), the broker's server offset follows the broker's own rule (often EU: 2026: 29 Mar - 25 Oct); the two are handled separately and tested on days in the weeks where they differ (2026: 8-28 Mar and 25-31 Oct). Never "server midnight" (on OANDA TMS, GMT+2, server midnight is 18:00 New York) | C (owner, 2026-10-06) | Approved |
| D6d-1 | Master switch (terminal global variable `NNFX_MASTER`): **missing = OFF**. No new entries until the owner sets it to 1; open trades keep being managed (S-2) | A (owner, 2026-10-06) | Approved |
| D6d-2 | Daily loss limit = 6% (3 x risk at 2%, S-5) of the **trading day's starting balance** (balance now minus the day's closed P/L; the day from the 17:00 New York boundary, OD-3 update). A day's loss of **exactly 6% blocks** new entries | A (owner, 2026-10-06) | Approved |
| D6d-3 | A drawdown reset sets the peak to the **current equity**. Condition: the reset is **manual only** (owner input: the `NNFX_DD_RESET` global variable or the chart button with a confirm step), **never automatic**, and **every reset is logged** (old peak, new peak, equity). Enforced: `NNFXDrawdownReset` is called only from `NNFXDrawdownResetRequested` (source scan in `test_guard_rules.py`) | A (owner, 2026-10-06) | Approved, with conditions |
| D6d-4 | The per-broker clock-change rule (winter offset + EU/US/none; settings, unverified) will be verified by the reviewer against the servers' times after 25 Oct and 1 Nov 2026. **The EA must never use `TimeLocal()`** (this PC's clock): enforced by a source scan in `test_guard_rules.py` (only `NNFX_EnvCheck`'s read-only report line may print it) | A (owner, 2026-10-06) | Approved |
| D6d-5 | The daily loss limit (S-5, D6d-2) counts the **whole account**, all magics: a bad day on one instance stops new entries on all of them. It matches the drawdown pause, which is account-wide too. Consequence: the account must be used only by this EA, since any other trades on it would count (G1_phase6d_1 verdict, O1) | A (owner, 2026-10-06) | Approved |
| D6e-1 | OD-11 approval: VP's news events mapped to MT5 calendar names in `profiles/news_events.txt`, **simplified to VP's own words, one entry per item he names, no extra events** (no press conferences, no testimony, no deposit-rate decision, one headline release per figure; GDT kept because VP names it; the BoE MPC votes kept under interest rates). 21 entries; role patterns for people's names (R-15). Owner: option C | A (owner, 2026-10-06) | Approved |
| D6e-2 | News rules unchanged: **N1** (no new trade on a currency with major news in the next 24 h) **and X5** (an open trade, at the first candle close inside those 24 h: exit if losing or up less than 1 x ATR, otherwise keep it) stay as in the rulebook. Owner: "just news 24hrs before no trade, simple" = keep both, no extra events or complications | A (owner, 2026-10-06) | Approved |
| D6e-3 | **The news block (N1), replacing "t < e <= t + 24 h"** (review G1_phase6e_1 F1: an event exactly at a candle close did not block). For each news event, take the trading day it falls in (17:00-to-17:00 New York, OD-3 update). Block new entries on every pair with that currency from the **EARLIER** of (a) 15:00 New York on the previous trading day and (b) **24 hours before the event** (VP's 24 hours), until the **17:00 New York close that ends the news day**; trading resumes at that close. An event exactly at a candle close is inside the block. X5 applies at the first candle close inside the block. Owner, option A: "EUR/USD stops taking new trades Thursday at 8:30 am, 24 hours before NFP, and resumes at the Friday 5 pm close ... Overnight news, like Australian jobs at 8:30 pm Wednesday New York time, blocks from Tuesday 8:30 pm until Thursday 5 pm. As long as we dont trade the pair on the day of the news we are good." Edge rules worked out from "the trading day it falls in" [C]: an event at exactly 17:00 New York starts a new trading day; Monday's previous trading day is Friday; a news day ending on a weekend ends on Monday | A (owner, 2026-10-06) | Approved |
| D6f-1 | **The rules core and the broker disagree (6f).** The core (the port of `core.py`) runs unaltered on candle data, so Phase 7 can replay it bar by bar; orders go to the broker through `Orders.mqh`. At each candle close the EA compares the core's view of each pair (position open or flat) with the broker's and logs every difference as a `DIVERGE` row. (1) **The core says the trade is closed (e.g. its stop was touched on the candle) but the broker trade is still open: the EA closes the broker trade at market**, so the EA and its rules stay in step (option A). (2) The broker trade closed but the core still holds a position: no new trade on that pair until the core's own simulation closes it. Owner: "A" (after the choice was explained: A keeps one picture and the rulebook's exits; B would leave a trade the rules no longer watch) | A (owner, 2026-10-06) | Approved |
| D6f-2 | **An unknown broker trade after a restart without memory (6f, DESIGN_6F 8.8).** After a start with no usable saved core memory (no state file, a corrupt one, or memory too old), a broker trade of this EA that the flat core does not know is **left on its broker-held stops** (stop, TP1, breakeven, trail by `Orders.mqh`); the pair takes **no new trade until it closes** (block `diverge`); it is logged (start-up row and alarm) and **never closed at start-up**. Owner: "Q1 A" | A (owner, 2026-10-07) | Approved |
| D6f-3 | **Live news (6f, DESIGN_6F 8.10; OD-12).** The EA runs the calendar export itself (`CalendarExport.mqh`, the same code as `NNFX_CalendarExport`) at start and once a day into `events_live.txt`, and reads it back like the tester. The **24-hour news-age alarm and the recency warning must be live**. Owner: "Q2 A" | A (owner, 2026-10-07) | Approved |
| D6f-4 | **Presets (6f, DESIGN_6F 8.11).** The preset files as written by `tools/make_presets.py` in MT5's own format (not re-saved from the dialog). The review packet must show each preset's key values: **risk, timeframe, magic, pair list**. Owner: "Q3 A" | A (owner, 2026-10-07) | Approved |
