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

## Review fixes, first set (2026-10-14, branch `review-fixes-1`)

From the independent review checked in `docs/REVIEW_OPUS_2026-10-14.md`. The owner asked for this set on 2026-10-14
("GitHub is connected", after the proposed first set: A10, A4, A7, B3 and the trail setting). Built, awaiting review.

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| RV-A7 | Orders need a **hedging** account, tester included (`NNFXHedgingOk`, `orders.py hedging_ok`): both halves are separate positions on one symbol (S-10, RULEBOOK line 206); on netting the second fill merges into the first. Part of `NNFXOrdersAllowed`, so every order method refuses on netting | C | Built, awaiting review |
| RV-B3 | Refusals a retry 1 s later cannot clear are **not retried** (OD-13 still retries the rest): INVALID, INVALID_VOLUME, INVALID_STOPS, TRADE_DISABLED, MARKET_CLOSED, NO_MONEY, INVALID_FILL, SERVER/CLIENT_DISABLES_AT, ONLY_REAL, LIMIT_ORDERS/VOLUME/POSITIONS, INVALID_ORDER, POSITION_CLOSED, HEDGE_PROHIBITED, FIFO_CLOSE, INVALID_EXPIRATION, INVALID_CLOSE_VOLUME, CLOSE_ORDER_EXIST, LONG_ONLY, SHORT_ONLY, CLOSE_ONLY. Any other code (incl. one MT5 adds later) is retried as before. The list is a judgment (C); the order cases name MT5's constants, never numbers | C | Built, awaiting review |
| RV-A10 | A candle whose ATR is 0 or less is **not usable** (`BarBuilder::Raw`, why `ATR:bad`), the same rule `check_export.py` already applied. `NNFXIsBad` is unchanged: 0 is a real value for zero-line indicators | C | Built, awaiting review |
| RV-A4 | A half's fill price unknown at readback is 0, never uninitialised; at TP1 it is read from half 2's position if that is still open; if still unknown, no BE move (ALARM instead) and no trail | C | Built, awaiting review |
| RV-T4 | `InpTrailOn=false` now also stops the **order side** trailing (it used to trail at the broker while the core did not; found in the review check, N-1). `check_trades.py --trail-off` fails any TRAILON/TRAIL row | C | Built, awaiting review |

## Owner instruction: work through steps 1-6 unattended (2026-10-14)

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| OWN-1 | Owner, 2026-10-14: "go from 1-6 do everything as automated as possible i dont want to interfere here , get as ready to comletion as possible" (steps 1-6 of the plan given that day: close Phase 6, first backtest look, Phase 7, live-safety fixes, broker + Phase 8 plan, demo). Applied as: the work continues on **stacked branches** (each PR's base is the branch before it, never `main`), a review packet is written at every gate as `REVIEW_PROTOCOL.md` says, but the next step starts **without waiting** for the verdict. Unchanged: drafts only, never merged, never marked ready, nothing on a live account, the owner's own steps (merges, verdicts, chart buttons, broker choice) are left to the owner | A (owner's words) | Applied |

## Review fixes, second set (2026-10-14, branch `review-fixes-2`, base `review-fixes-1`)

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| RV-A7b | The A7 hedging check runs **after login**: `Init` skips it only when live and not logged in (before login `ACCOUNT_MARGIN_MODE` reads 0 = netting), the start-up (`ReadyToStart`) refuses to start on a non-hedging account (Alert once), every order method keeps the full check. Found while writing G1_review1_1; a normal cold start did not show the problem (`coldstart_20261014_160124`: OnInit already saw hedging), so this covers a start without connection | C | Built, awaiting review |
| RV-A1 | A refused breakeven move is **tried again** from `Poll` (every tick): every 5 s for the first 5 failures, then every 60 s (`NNFXPendingDue`); a RETRY row per refusal, an ALARM and an Alert at the 5th. If the price half 2 would close at has already reached or passed breakeven against the trade, a breakeven stop would be hit at once and the broker refuses it, so **half 2 is closed at market** instead (`NNFXBeAction` 2; EXIT row "BE price already passed") | C | Built, awaiting review |
| RV-A8 | Closes read and check the price first (no send on a failed `SymbolInfoTick`); a refusal that can clear (`NNFXRetcodeRetryable`) is retried up to 3 times 1 s apart; a close that still fails (ABORT's half 1, exits, close-all) goes **pending** and is tried again from `Poll` on the same schedule as RV-A1 | C | Built, awaiting review |
| RV-TOOLS2 | `run_ea_tester.ps1` passes `--trail-off` to `check_trades.py` when `InpTrailOn=false` (G1_review1_1: planted bug M3 passed the runner without it); `tools/run_coldstart_check.ps1` starts MT5 with NNFX_EA attached on the demo (test magic 26991, master switch untouched) | C | Built, awaiting review |

## Phase 7: bar-by-bar cross-check and the first backtest look (2026-10-14, branch `phase-7-crosscheck`)

Under OWN-1. Built, awaiting review.

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| P7-1 | Check 1b replays **the EA's own logged inputs** through the answer key (`tools/check_replay.py`; every pair, every candle, events compared exactly). For an exact replay the decision log writes `atr` and `base` with 17 significant digits (prices stay at the symbol's digits, on the tick grid): with `%.10g` / digits + 2, run `ea_trailoff_h1_4m_20261014_152457` replayed EURGBP 2026.09.24 13:00 as "close on the baseline" (the logged base 0.8597400 equalled the close) where the EA had the close a hair below it. The EA also writes its flat warm-up's candles to `<log>_warmup.csv` (a new file at each start), so the replay starts where the core did. A replay without the warm-up file is never a PASS. `run_ea_tester.ps1` runs it on every continuous run. Whether the logged inputs themselves are right (indicator values from the candles) stays with `check_indicators.py` / `check_export.py` (Phase 5) | C | Built, awaiting review |
| P7-2 | Tester-only input `InpTesterDdPause` (default 1 = R-12 as approved). 0 = the drawdown pause is computed and logged once ("TESTER: not blocking") but does not block, so a multi-year backtest is measured over its whole window; the result reports when R-12 would first have paused. Refused outside the tester (INIT_PARAMETERS_INCORRECT); the presets hold 1 (`test_presets.py`). Reason: at 2% risk R-12 trips after a 5R dip, which over 100+ trades is near certain (brief E3), and the tester cannot reset it by hand (S-6). **Owner to confirm** | C | Built, awaiting owner |
| P7-3 | **Exploratory backtest, fixed before the first run (V9).** Purpose: a first look at where the system stands; it is not the Phase 8 shootout and decides nothing. MetaQuotes-Demo history (not the live broker: E4), Strategy Tester model 1 (1 minute OHLC, not real ticks: stated with every number), the presets as they are (reference indicator set, defaults) on **M30, H1 and H4**, VP's 5 pairs, chart EURUSD, the tester's deposit. Window **2019.01.01 to 2024.03.01** = the first two-thirds (62 of 93 months) of 2019.01-2026.09; **2024.03.01-2026.10.01 is not run** and stays untouched for Phase 8's forward period (E2). `InpTesterDdPause=0` (P7-2). Each run is checked by `check_trades`, `check_decision_log`, `check_news_inputs`, `check_replay` (P7-1) and summarised by `tools/summarize_trades.py` (V8, V10, V11, V13; R per trade from the trade log, money from the tester report). No setting is changed after seeing a result; any further run is logged | C | Fixed 2026-10-14, before any run |
| P7-4 | **Changed after a partial result (stated as such):** the P7-3 runs use a tester **deposit of 1 000 000** instead of the tester's 10 000. The first M30 run (`checks\invalid\ea_explore1_M30_20261014_163756`, stopped, REASON.txt) lost 98.6% by 2019-12 (balance 142.09); from there 2% of the balance is below the minimum lot, so trades are refused and four of the five years would add almost no sample. The deposit changes no rule and no setting: R per trade does not depend on it and returns and drawdowns in % are the same at 2% compounding; only the lot-size floor stops binding. The 10 000 result is kept and reported. `check_replay.py --trades-out` also writes the answer key's own simulated trades (R from candles, no costs) as a second view | C | Applied 2026-10-14, before the re-run |

## Review 2026-10-13, section C: the record fixed (2026-10-14, branch `docs-c-phase8-plan`)

Under OWN-1. C1 is fixed in `docs/PLAN_PHASE6.md` (OD-3 row marked superseded). C2 and C3 concern the snapshots of the
owner's living documents: listed in `docs/SNAPSHOT_SYNC_2026-10-14.md` for the owner to apply there first (CLAUDE.md:
the living copies are the source). C4 and C8 are in `docs/STATUS.md`. The rows below need the owner.

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| DOC-C5 | Dead-market rules T6, D1, D2 (A, "Dead Markets") are **not in the backtests**: D1 is VP's EVZ < 8, and EVZ is not in MT5's history (it is a CBOE index), so no backtest here can apply it as written. Proposal: say so in every result (as N3 does for news), run the shootout without them, and look at an in-MT5 proxy (EURUSD ATR percentile) only after the shootout, as its own decision | C | **Proposed, owner to decide** |
| DOC-C6 | T5 (A: the exit indicator "competes with" the trailing stop, alternatives to test) becomes three settings variants in Phase 8 stage 2, all already settings: **both** (default: X2 on, T4 on), **exit indicator only** (`InpTrailOn=false`), **trail only** (`InpExitOnExitInd=false`) | C | **Proposed, owner to decide** |
| DOC-C7 | I-13 (b)'s "with C1 and C2 agreeing" is a **tightening** that RULEBOOK E6 / Lesson 11 do not state: label **C** (interpretation), kept as built until the owner confirms or drops it. E6 (a) has no volume filter and no 1 x ATR limit, which is what RULEBOOK line 178 asks ("the volume filter and the 1 x ATR limit do not apply") | C | Labelled; owner to confirm (b) |

## Review fixes, third set (2026-10-14, branch `review-fixes-3`, base `docs-c-phase8-plan`)

Under OWN-1. Built, awaiting review.

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| RV-A5 | An open order **accepted without a position yet** (PLACED, or DONE before the position shows) is waited for up to 5 s (the position by comment, else the order's state) and **never sent again while unresolved** (ALARM + Alert; the trade is not opened, a late fill is found by Reconcile, with its own stop). Only an order that will never fill (cancelled, rejected, expired) may be re-sent. The duplicate check runs right before each re-send (after the 1 s pause) and also covers pending orders with the same comment (`NNFXOrderStateOutcome`, `orders.py order_state_outcome`) | C | Built, awaiting review |
| RV-A2 | The restart rebuild replays the trail switch-on with the **T4 setting** (`trail_start_atr`), not the constant 2.0; when the trade is in the state file, its **saved `trail_active` is used** and the candle replay is a cross-check (a difference is a note "disagree ... trail_active ... state used"). `recovery.rebuild(..., trail_start_atr)` in lockstep | C | Built, awaiting review |
| RV-A3 | Live, the rebuild's deal history starts a day before the **oldest open position of this magic** (or 30 days back, whichever is earlier), so an older runner is never rebuilt as no trade. If half 1's deals are still missing, `tp1_done` comes from the state file (note). An open position of this magic that no rebuilt trade owns is named in a note at start-up | C | Built, awaiting review |

## Owner decisions, 2026-10-14 (branch `owner-decisions-1`, base `review-fixes-3`)

The owner's answer to the five questions put that day (each with option A as the recommendation): **"all A"**.

| ID | Decision | Label | Status |
| --- | --- | --- | --- |
| OWN-2 (a) | **Live broker: OANDA TMS, `.pro` symbols** (hedging, EUR account, real ticks from 2019; `docs/ENVIRONMENT.md`, D6c-2). Phase 8 runs on its history and costs (P8-1). Settles STATUS "choose the live broker" | A (owner) | Approved |
| OWN-2 (b) | **The Phase 8 plan `docs/PLAN_PHASE8.md` approved as drafted** (P8-1 to P8-11), including the rows that reopen S-8 (30 forward trades -> at least 200), the SPEC ranking (-> forward expectancy with bootstrap intervals), the single forward split (-> walk-forward in-sample, forward used once) and the single-path R1 gate (-> P(maxDD > 10%) <= 50%). The G2 verdict (`G2_phase8_1`) is still needed before the first shootout run | A (owner) | Approved; awaiting G2 verdict |
| OWN-2 (c) | **P7-2 confirmed**: the tester-only `InpTesterDdPause` stays (refused live; presets at 1) | A (owner) | Approved |
| OWN-2 (d) | **OD-5 gets a 5% buffer**: an entry needs the margin of both halves plus 5% free (`NNFXMarginOk`, `orders.py margin_ok`, MB cases). Updates OD-5 | A (owner) | Built, awaiting review |
| OWN-2 (e) | **Blanket approval** of I-1, I-2, I-3, I-7, I-9 (Phase 3 interpretations, "awaiting tick") and D5-1 to D5-5 (Phase 5 design choices, "pending review"), as built and tested; closes the review's C4. The living rulebook doc still needs the ticks for the snapshot to be refreshed (`docs/SNAPSHOT_SYNC_2026-10-14.md`) | A (owner) | Approved |
| OWN-2 (also) | DOC-C5, DOC-C6 and DOC-C7 were not among the five questions: still proposals for the owner | - | Open |
