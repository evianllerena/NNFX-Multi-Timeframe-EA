# G2 plan: Phase 6 (orders, risk, recovery, guard, news): version 2

**Version 2 (2026-10-04).** This is `PLAN.md` (attempt 1) with:
- the four required edits from `VERDICT.md` (G2_phase6_1: "PASS, with 4 required edits"):
  - **F1:** new sub-phase 6f, the real EA (section 6f)
  - **F2:** the decision log in 6f
  - **F3:** the stopless test path only under `#ifdef NNFX_TEST_BUILD` (sections 1 and 3)
  - **F4:** the exact "risk ≤ 2%" rule in `check_trades.py` (section 3)
- the owner's answers to OD-1 to OD-21: "accept recommended defaults", meaning the reviewer's recommendations in
  `VERDICT.md` (section 11, now "Decisions")

Inline references to open decisions now name the chosen option. Everything else is unchanged from attempt 1.
Committed as `docs/PLAN_PHASE6.md` in the 6a PR (VERDICT "Next"). The review packet is
`C:\Users\Evision\NNFX-Review\G2_phase6_1\` (`PLAN.md` = attempt 1, `VERDICT.md`).

| Field | Value |
| --- | --- |
| Gate | G2 Plan (before building Phase 6): **PASS** (`G2_phase6_1\VERDICT.md`) |
| Base | `origin/main` = `0e701ddd68c59e78aa39ed9b6c018d376d055406` (merge of PR #5); `evidence\github_state.txt` |
| Date | 2026-10-04 (Sunday) |
| Scope | **Planning only.** No code was written and no branch or PR was opened for this packet |
| Sources read | `docs/SPEC.md` (Architecture; Settings; Money, sizing and exposure; Orders and restart recovery; On/off controls and safety limits; News filter; Verification plan), `docs/RULEBOOK.md` (M, T, X, N, R rules), `docs/DECISIONS.md`, `docs/ENVIRONMENT.md`, `tests/python/nnfx_ref/sizing.py`, `exposure.py` (also `settings.py`, `core.py` and `tests/python/README.md`, for the core's boundary) |
| Prepared by | Local Claude Code on the owner's PC |

Labels on rule-related statements: **A** = VP's own words, **B** = secondary source, **C** = no source / owner's
choice (as in RULEBOOK.md). Quotes are copied from the files at `0e701dd`. "Unverified" marks a fact I could not
confirm. Everything marked unverified is collected in section 13.

---

## 0. How Phase 6 fits on what exists

- **What exists (merged):**
  - The rules core: `RulesCore.mqh` in MQL5 and `core.py` in Python, 47/47 rule cases.
  - The indicator slots and profiles: `Slot.mqh`, `Profile.mqh`, `Signals.mqh`, `BarBuilder.mqh`.
  - `Connection.mqh` (waits for login).
  - Python `sizing.py` and `exposure.py`, with unit tests (`test_units.py`: 6 sizing and 8 exposure tests). They have no MQL5 port yet.
- **The core's boundary is fixed already.** Phase 6 must produce the core's inputs `block` and `news`:
  - From `core.py`: "block — list of reasons new entries are blocked on this candle (news N1, rollover, weekend, master
    switch, drawdown, daily loss, same-currency exposure ...). Decided outside the core."
  - Also: "news — True on the first candle close inside a 24 h window before a major event on one of the pair's
    currencies (X5 check)".
  - The core already contains X5 and the N1 skip (fixtures `N1_blocked_by_news`, `X5_*`).
- **The core is decision-only.** Phase 6 turns its `ENTER` / `EXIT` / `TRAIL` decisions into broker orders and keeps
  the broker's state as the truth.
- **Every sub-phase follows the same process:**
  - its own branch `phase-6x-...` and **draft** PR
  - its own G1 packet with `evidence\github_state.txt`
  - marked ready only after "PASS" and "MERGE OK <commit>" (REVIEW_PROTOCOL.md, "Merge safety")
  - built in order 6a → 6f, each on `main` after the previous one is merged

---

## 1. SAFETY: no orders on a real account

**Rule for all Phase 6 code:** anything that can send, modify or close an order goes through **one** module,
`MQL5/Include/NNFX/Orders.mqh`. Every public function in it first calls `NNFXOrdersAllowed()`.

- `NNFXOrdersAllowed(string &why)` returns true only if:
  - `MQLInfoInteger(MQL_TESTER)` is true (Strategy Tester), **or**
  - `AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO`.
- `ACCOUNT_TRADE_MODE_CONTEST` and `ACCOUNT_TRADE_MODE_REAL` are refused, with the reason logged and an alarm.
- `ACCOUNT_TRADE_MODE_DEMO` is used by the merged `NNFX_EnvCheck.mq5`, which compiles.
- `MQL_TESTER` is a standard MQL5 property, but no code here uses it yet. **Unverified until the first compile.**
- The check runs at `OnInit` and again before **every** `OrderSend`. The account can change while the EA runs
  (the user logs in to another account).
- It is a pure decision function, `NNFXOrdersAllowedFor(long tradeMode, bool inTester)`, plus a thin wrapper that
  reads the two values, so it can be tested without a real account.
- **Out of scope:** any switch that unlocks real-money trading. Lifting the refusal is a later, separate owner
  decision after the demo period (S-9: "Demo for at least 3 months before real money" [C]).

**How it is tested:**

| Test | Where | Pass line |
| --- | --- | --- |
| S1 Decision table | MQL5 script `NNFX_SafetyTest.mq5` and Python `test_safety.py`, the same 6 cases (DEMO, CONTEST, REAL) × (tester, not tester) | `RESULT: 6 passed, 0 failed, 6 total`: only DEMO/any and tester/any allowed |
| S2 Source scan | Python `test_order_calls.py`: every `OrderSend`, `OrderSendAsync`, `CTrade` and `PositionClose` in `MQL5/` is inside `Orders.mqh`, and every public function there calls `NNFXOrdersAllowed` first | `OK`; lists 0 violations |
| S3 Live demo | `NNFX_OrderTest` (6b) on the MetaQuotes-Demo account | Log line `orders allowed: DEMO` |
| S2b Test-only path (F3) | Same `test_order_calls.py`: `NNFXTestOpenWithoutStop()` exists only inside `#ifdef NNFX_TEST_BUILD` in `Orders.mqh`, refuses unless `MQLInfoInteger(MQL_TESTER)` is true, and `NNFX_EA.mq5` never defines `NNFX_TEST_BUILD` | `OK`; lists 0 violations |
| S4 Planted bugs | (a) remove the guard call from one public function; (b) add an `OrderSend` to another file; (c) make the function return true for REAL; (d) move `NNFXTestOpenWithoutStop()` outside the `#ifdef`, or define `NNFX_TEST_BUILD` in `NNFX_EA.mq5` (F3) | S2 catches (a) and (b); S1 catches (c); S2b catches (d) |

A real account can't be used to test the refusal live, and it won't be. S1 covers REAL through the pure function.

---

## 2. Sub-phase 6a: sizing + exposure

**Branch** `phase-6a-sizing-exposure`, draft PR.

### Implements

**RULEBOOK:**
- M2 "Risk 2% of total trading capital per trade (not per sub-account)" **[A]**
- M3 "Stop loss = 1.5 × ATR from entry" **[A]**
- M4 "Position size: risk money ÷ stop distance = value per pip, so every pair carries the same risk" **[A]**
- M5 "The 2% is split into two equal half-orders" **[A]**
- M6 "Never more than one trade at 2% that is long or short the same currency" **[A]**
- M7 "If two signals share a currency: take one at 2%, or both at 1% each, or 1% now and 1% later" **[A]**

**SPEC, Money, sizing and exposure:**
- "1. Risk money = 2% of the account (balance or equity: decision below)."
- "2. Stop distance = 1.5 × ATR of the last closed candle."
- "3. Loss per lot = stop distance converted to money with the broker's own tick size and tick value for that pair."
- "4. Total lots = risk money ÷ loss per lot, split into two equal halves, each rounded down to the broker's lot step."
- "5. If a half is below the broker's minimum lot, the trade is skipped and logged as "too small to size". It is never
  rounded up (this was the old harness's double-risk bug)."
- "Before any new trade, the EA lists every open position on the account: all three EAs, all pairs, and any manual trades."
- "Each position is split into its two currencies with direction (long EUR/USD = long EUR + short USD)."
- "Default: the first signal keeps its 2% and the later one is skipped. Alternative to test: both at 1% (M7)."

**DECISIONS:**
- S-3 "Risk is 2% of balance (not equity)" **[C]**
- S-4 "Same-currency rule counts same-direction exposure only; first signal keeps 2%, later skipped; "both at 1%" also tested" **[A rule / C detail]**
- R-14 **[A]**

**Carry-over 2:** tick value is read at order time (section 8).

### Files and functions

| File | Function | Purpose |
| --- | --- | --- |
| `MQL5/Include/NNFX/Sizing.mqh` (new) | `NNFXSizeTrade(balance, riskPct, stopDist, tickSize, tickValue, volMin, volStep, volMax, NNFXSize &out)` | Port of `size_trade()`: two equal halves, rounded down, skip below the minimum lot, never above target risk |
| | `NNFXSizeForSymbol(sym, riskPct, stopDist, NNFXSize &out)` | Reads balance and the symbol's tick size / tick value / volume limits **now** and calls the above. Tick value = the larger of `SYMBOL_TRADE_TICK_VALUE` and `SYMBOL_TRADE_TICK_VALUE_LOSS` (OD-6 (c)). Refuses if tick value or tick size ≤ 0 |
| `MQL5/Include/NNFX/Exposure.mqh` (new) | `NNFXCurrencies(sym, base, quote)` | Base and quote from a symbol, tolerating suffixes (port of `currencies()`) |
| | `NNFXLegs(sym, dir, legs[])` | Long EURUSD = +EUR, −USD |
| | `NNFXAllocate(openPos[], signals[], riskPct, mode, out[])` | Port of `allocate()`: modes `first` and `split` |
| | `NNFXOpenLegs(legs[])` | Lists **every** open position on the account (all magics, manual trades) as legs |
| `tests/python/nnfx_ref/sizing.py`, `exposure.py` | `exposure.py`: non-FX symbols are ignored with a log line (OD-21 (b)); 3+ signals on one leg stay skipped (OD-4 (a)). `sizing.py` unchanged: it takes the tick value as an input, and the caller picks the larger of the two (OD-6 (c)) | Answer key |
| `tests/fixtures/sizing/sizing_cases.txt` (new) | — | Shared cases: inputs → half lots, total lots, risk money, skipped/reason |
| `tests/fixtures/exposure/exposure_cases.txt` (new) | — | Shared cases: open positions + signals + mode → risk per signal |
| `tests/python/test_sizing_exposure_fixtures.py` (new) | — | Runs both fixture files through the Python answer key |
| `MQL5/Scripts/NNFX/NNFX_SizingTest.mq5` (new) | — | Runs both fixture files through the MQL5 ports and writes a report |

### Shared fixtures (the same cases in Python and MQL5)

- **Sizing, at least these cases:**
  - EURUSD 2% normal case
  - exact minimum lot (0.01 per half, the old double-risk bug)
  - half just below the minimum lot (skip)
  - lot-step edge where floating point would round up (the existing `test_float_step_edge`)
  - volume max cap
  - JPY pair (tick size 0.001)
  - non-USD quote (tick value ≠ 1)
  - zero or negative inputs (rejected)
  - tick value 0 (rejected: carry-over 2)
- **Exposure, at least these cases:**
  - VP's all-short-AUD example
  - an open position blocks the same direction
  - opposite direction allowed (S-4)
  - unrelated pairs
  - suffixed symbols
  - split mode halves simultaneous signals
  - split mode still respects open positions
  - three signals on one leg in split mode: all skipped (OD-4 (a))
  - an open XAUUSD position is ignored, with a log line (OD-21 (b))
  - half 2 running at breakeven still counts until fully closed (OD-20 (a))
  - a manual position counts

### MT5 tests

| Test | Pass line |
| --- | --- |
| `NNFX_SizingTest` (script, via the runner) | `RESULT: <n> passed, 0 failed, <n> total`, where n = the number of sizing + exposure fixture cases (fixed when the fixtures are written) |
| Python | `test_sizing_exposure_fixtures.py` and the existing `test_units.py`: the suite total rises by the new tests, `OK` |
| Live read (demo, script) | `NNFX_SizingTest` also prints, for the 5 pairs, the sizing it **would** use now from live tick values. Information only, labelled "live, not a fixture" |

### Planted bugs (new checker: the MQL5 sizing/exposure ports, checked by the fixtures)

At least 8, one at a time, each restored byte for byte:
- rounding up instead of down
- `<=` vs `<` at the minimum lot
- halves not equal
- tick value read from the docs constant instead of the symbol
- exposure counting only the EA's own magic
- opposite direction counted as a conflict
- split mode not halving
- suffix not stripped

**Pass:** every bug makes `NNFX_SizingTest` report a FAIL.

### Out of scope

- Margin check: decided as OD-5 (a), skip and log; built in 6b at order time (`NNFXOpenTrade`)
- Equity-based risk (S-3 chose balance)
- Netting accounts (S-10; this account is RETAIL_HEDGING per ENVIRONMENT.md)
- Sending any order

---

## 3. Sub-phase 6b: orders

**Branch** `phase-6b-orders`, draft PR. Depends on 6a.

### Implements

**RULEBOOK:**
- T1 "Both halves get the same 1.5×ATR stop. Half 1 gets a take profit at 1 × ATR" **[A]**
- T2 "When half 1 hits TP, move half 2's stop to breakeven (the entry price)" **[A]**
- T3 "Half 2 has no fixed target" **[A]**
- T4 "Trailing stop on half 2: 1.5 × ATR behind price, switched on once price has closed 2 × ATR beyond entry, moved
  once per candle close, never backwards" **[B]**, decision R-1 **[B]**
- T7 runner cap (R-11, off by default) **[C]**
- X1 "Stop loss (1.5 × ATR, then breakeven, then trailing) and TP1 close the trade or half of it" **[A]**
- X2–X4 exits at the close (R-2) **[A/B]**
- R2 "Never add to a winning trade (no scaling in)" **[A]**

**SPEC, Orders and restart recovery:**
- "No position ever exists without a broker-held stop"
- "Every order is sent with its stop loss in the same request. If the broker would reject the stop (closer than its
  minimum stop distance), the trade is not sent and the reason is logged."
- "Half 1: stop + TP1 at 1 × ATR. Half 2: stop, no target (or the runner cap when that setting is on)."
- "When half 1's TP fills, half 2's stop moves to breakeven straight away (T2), not at the next candle close."
- "Trailing (T4) and signal exits (X2–X4) act at candle close."
- "If any position is ever found without a stop, the EA closes it at once and logs an alarm."
- "A failed order is retried a limited number of times. Before every retry the EA checks whether the first attempt
  actually filled, so it can never open a duplicate."
- "Each instance has its own magic number (one per timeframe)."
- "Each trade gets an ID, written into both halves' order comments and into a small state file." The state file is 6c.

**Also:**
- DECISIONS P-5 "Every order carries a broker-held stop loss" **[C]**
- SPEC Architecture: Orders "Opens the two halves with broker-held stops, TP1, breakeven, trailing, exits | Decide trades: never"
- SAFETY (section 1)

### Files and functions

| File | Function | Purpose |
| --- | --- | --- |
| `MQL5/Include/NNFX/Orders.mqh` (new) | `NNFXOrdersAllowed(why)` / `NNFXOrdersAllowedFor(mode, tester)` | Section 1 |
| | `NNFXOpenTrade(sym, dir, atr, NNFXSize &size, magic, tradeId, NNFXTicketPair &out)` | Sends half 1 (SL + TP1) and half 2 (SL, no TP or the runner cap), each with its stop in the same request. Refuses if the stop is closer than `SYMBOL_TRADE_STOPS_LEVEL`. Refuses and logs if the trade needs more than the free margin (OD-5 (a)). Magic numbers 30M = 26030, 1H = 26060, 4H = 26240, fixed in the presets (OD-16) |
| | `NNFXSendWithRetry(request, maxTries, NNFXResult &res)` | Up to 3 retries, 1 s apart (OD-13). Before each retry it searches open positions and history for this trade ID + half, so it never duplicates |
| | `NNFXAfterFill(ticket)` | Takes the actual fill price, recomputes SL/TP1 from it (and the BE price = exactly the fill/entry price, OD-15 (a)), modifies the stop/target if needed, and logs the slippage. No deviation limit: any fill is accepted (OD-14 (c)) |
| | `NNFXMoveStop(ticket, newSl)` | Modifies a stop; never moves it backwards; respects stops and freeze levels |
| | `NNFXCloseRemaining(tradeId, reason)` | Closes whatever is left of a trade (X2–X5, close-all) |
| | `NNFXOnTp1Filled(tradeId)` | Called from `OnTradeTransaction` when half 1 closes at its target: moves half 2 to breakeven straight away (T2) |
| | `NNFXEnforceStops()` | Every tick: any position with one of our magics and no stop → close at once and alarm; a **manual** position without a stop → alarm only, never closed (OD-8 (a)) |
| | `NNFXTradeComment(tradeId, half)` | Builds the comment. The broker's comment length limit is unverified (section 13) |
| `MQL5/Include/NNFX/TradeLog.mqh` (new) | `NNFXLogTrade(...)` | One CSV row per order event: open, TP1, BE, trail, close, with requested vs filled price, lots, stop, the risk at entry in money and %, and the tick value used |
| `MQL5/Experts/NNFX/NNFX_OrderTest.mq5` (new, test EA) | — | Strategy Tester and demo only. Opens scripted trades from a fixture schedule and logs everything. No indicator logic |
| `tests/python/nnfx_ref/orders.py` (new) | `plan_orders(...)`, `breakeven_price(...)`, `trail_stop(...)` | Answer key for prices: SL, TP1, BE and trail levels from entry, ATR and direction. It reuses `core.py`'s numbers so the two never disagree |
| `tests/fixtures/orders/order_cases.txt` (new) | — | Shared: entry, ATR, direction, settings → expected SL, TP1, half-2 TP (cap), BE price, trail sequence |
| `tools/check_trades.py` (new checker) | — | SPEC Check 1c over a trade log: "Every position had a stop from its first moment; actual risk never above 2%; halves equal; TP1, breakeven and trailing at the right prices" |
| `Orders.mqh`, inside `#ifdef NNFX_TEST_BUILD` only (F3) | `NNFXTestOpenWithoutStop(sym, dir, lots)` | Test-only: opens a position with no stop, to prove `NNFXEnforceStops()` closes it. Refuses unless `MQLInfoInteger(MQL_TESTER)` is true. Compiled only into `NNFX_OrderTest`, which defines `NNFX_TEST_BUILD`; never into `NNFX_EA.mq5` |

**"Risk ≤ 2%" in `check_trades.py`, exactly (F4):**
- Planned risk at entry = (half-1 lots + half-2 lots) × (stop distance ÷ tick size) × tick value used. The tick value
  used is the one the trade log recorded at order time.
- It is compared with the target = balance at entry × risk % ÷ 100.
- **Pass** only if planned risk ≤ target, with **no tolerance above it**.
- Realised losses bigger than the planned risk (a gap through the stop) are reported as information only, never as
  a pass or a fail.

### MT5 tests

| Test | Where | Pass line |
| --- | --- | --- |
| `NNFX_OrderMathTest` (script) | MQL5 vs `order_cases.txt` | `RESULT: <n> passed, 0 failed, <n> total` |
| Order run | Strategy Tester: `NNFX_OrderTest`, EURUSD H1, 1 minute OHLC, a fixed schedule of at least 20 trades covering stop-out, TP1 then BE, TP1 then trail, runner cap, signal exit | `check_trades.py`: `RESULT <log>: PASS (0 failures)`. Every trade: stop present from its first deal, halves equal, planned risk ≤ target (F4 definition above), prices match `orders.py` within one tick |
| Same on demo | `NNFX_OrderTest` on MetaQuotes-Demo, weekday, at least 5 trades, minimum lots | Same `check_trades.py` pass line; log shows `orders allowed: DEMO` |
| Missing-stop alarm | Strategy Tester: `NNFX_OrderTest` (built with `NNFX_TEST_BUILD`) calls `NNFXTestOpenWithoutStop()`; tester only, refused elsewhere (F3) | Position closed within the same tick sequence; log line `ALARM missing stop` |
| No duplicate on retry | Tester: inject a "request sent, reply lost" case | Exactly one position per half per trade ID |

### Planted bugs (new checker: `tools/check_trades.py`)

At least 8:
- a position with no stop for its first deal
- halves unequal
- risk 2.01%
- TP1 off by 2 ticks
- breakeven not at entry
- trail moving backwards
- trail before the 2 × ATR close
- a duplicated half
- risk check with a tolerance above target (for example ≤ target × 1.001) (F4)
- realised gap loss counted as a risk failure (F4: must stay information only, so the checker must not FAIL a
  trade whose planned risk was within target)

**Pass:** each makes `check_trades.py` give the wrong answer that its tests detect. Same record format as
`G1_phase5_2\planted_bugs.md`.

### Out of scope

- Entry and exit decisions (the core)
- The state file and restart (6c)
- Guard (6d)
- News (6e)
- Netting half-close (SPEC 1f: "Only if your account is netting"; this account is hedging)
- The full basket EA (6f, per OD-1 (a))

---

## 4. Sub-phase 6c: state + restart recovery

**Branch** `phase-6c-state-recovery`, draft PR. Depends on 6b.

### Implements

**SPEC, Orders and restart recovery:**
- "Some brokers change order comments, so comments are never the only record: the state file and the account's deal history back each other up."
- "On start-up, before doing anything else, the EA rebuilds its memory from what the broker holds."
- The rebuild table, quoted in full in section 9.

**SPEC, Architecture:** State & recovery "Remembers each trade's halves and continuation state; rebuilds them after a restart".

**RULEBOOK, old-code lessons:** "It remembers which positions are the two halves only in memory. After an MT5 or PC
restart it forgets …".

**Continuation state:**
- E6 **[B]**; decisions R-6, R-7 **[B / owner, unverified in writing]**
- I-12 "Continuation is armed only by a standard entry (E1-E4) … disarmed by a close on the other side of the baseline.
  Version (a) is also disarmed once C1 reads against the trend at any close after the original entry."

### Files and functions

| File | Function | Purpose |
| --- | --- | --- |
| `MQL5/Include/NNFX/State.mqh` (new) | `NNFXStateSave(instance, NNFXTradeState &st[])` | Writes the state file after every change, atomically: write a temp file, then rename. Location `MQL5\Files\NNFX\state\` (OD-9 (a)) |
| | `NNFXStateLoad(instance, st[])` | Reads it, and checks a version and a checksum |
| | `NNFXRebuild(instance, magic, st[], NNFXRebuildReport &rep)` | On start: pairs halves from magic + trade ID (comment, state file, deal history); TP1-filled from history; BE/trail stage from half 2's stop; continuation armed/disarmed from price history since entry; last exit direction from history. Logs every source disagreement |
| | `NNFXReconcile()` | Each new candle: the state file vs the broker. A mismatch is logged and the broker's state wins |
| `tests/python/nnfx_ref/recovery.py` (new) | `rebuild(positions, deals, candles, state) -> TradeState` | Answer key for the rebuild from the same inputs |
| `tests/fixtures/recovery/*.json` (new) | — | Shared: snapshots of positions + deals + candles + (state file / no state file / changed comments) → expected rebuilt state |
| `MQL5/Scripts/NNFX/NNFX_RecoveryTest.mq5` (new) | — | Runs the recovery fixtures through `NNFXRebuild`'s pure part. Broker reads are replaced by fixture data through one interface |

### MT5 tests

| Test | Pass line |
| --- | --- |
| `NNFX_RecoveryTest` (script) | `RESULT: <n> passed, 0 failed, <n> total` |
| Restart tests R1–R4 (section 9) | As quoted there |

### Planted bugs (new checkers: `recovery.py` + fixtures, and the restart comparison tool `tools/compare_runs.py`)

At least 8:
- TP1 detected from comments only
- BE stage misread when trailing
- continuation armed after a baseline cross
- last exit direction inverted
- halves paired by symbol only (two trades on one pair)
- state file trusted over the broker
- a corrupted state file accepted
- `compare_runs.py` ignoring one log column

### Out of scope

- Netting accounts
- Rebuilding manual trades (they are counted for exposure in 6a but never managed)

---

## 5. Sub-phase 6d: guard (switches and limits)

**Branch** `phase-6d-guard`, draft PR. Depends on 6a–6c.

### Implements

**SPEC, On/off controls and safety limits:**
- "Turning the EA "off" stops new trades by default; open trades keep being managed … Closing everything is a separate,
  deliberate action." Decision S-2 **[C]**.
- The controls table:
  - "Master switch | All three instances at once | One shared switch in the MT5 terminal (a terminal-wide global variable), plus a button on each chart"
  - "Instance switch | One timeframe | Setting + chart button"
  - "Pair list | One pair in one instance | Preset file"
  - "Close-all | One instance's trades | Chart button with a confirm step; never automatic"
- The limits table:
  - "Drawdown pause | VP, R1 | 10% below the account's peak | No new trades on any instance until you reset it"
  - "Daily loss limit | Not VP (your request) | 3 × risk per trade (6% at 2%) | No new trades until the next trading day"
  - "Max spread | Not VP | Off until spreads are measured | Skip the entry"
  - "Missing stop | This spec | Always on | Close the position at once and alarm" (built in 6b, reported by the guard)
  - "Indicator failure | This spec | Always on | Indicator won't load or returns empty values: no new trades on that pair, alarm"
- Rollover: "Rollover block (decision #10) | 15 min before to 60 min after the daily close"; R-10 **[C window]**, based on M9 **[A]**
  "Spreads are very wide for about an hour after the daily close".
- Weekend: "A setting can block new entries in the last N hours before the weekend close; it is off by default and tested"; S-7 **[C]**.

**RULEBOOK:**
- R1 "Aim for no more than 10% maximum drawdown; 15% is "a lot"; 20% is "Armageddon"" **[A]**
- R-12 **[A]**, S-5 **[C]**, S-6 "10% drawdown pause is reset by hand only" **[C]**

**Fixed processing order:** "When several pairs signal on the same candle, they are processed in a fixed order so every run gives the same result."

### Files and functions

| File | Function | Purpose |
| --- | --- | --- |
| `MQL5/Include/NNFX/Guard.mqh` (new) | `NNFXGuardBlocks(sym, candleTime, NNFXGuardState &g, string &blocks)` | Builds the core's `block` string for one pair and candle: master off, instance off, drawdown pause, daily loss, rollover, weekend, max spread, indicator failure (exposure comes from 6a, news from 6e) |
| | `NNFXDrawdownUpdate(g)` / `NNFXDrawdownReset()` | Tracks the peak of equity, sampled at each candle close (OD-2 (c)), and pauses at −10%. Reset by hand only (S-6), through a chart button with a confirm step or a global variable the owner sets |
| | `NNFXDailyLossUpdate(g)` | Day's loss from closed trades only vs 3 × risk; the day starts at server midnight, i.e. the daily close at 00:00 server (OD-3) |
| | `NNFXInRollover(t, dailyClose)` | 15 min before to 60 min after the daily close. Daily close = 00:00 server time per ENVIRONMENT.md ("EURUSD D1 candle opened 2026.10.02 00:00"; D1 candles open 00:00 server). A setting, not assumed |
| | `NNFXInWeekendBlock(t, hours)` | Off by default |
| | `NNFXMasterOn()` | Reads the terminal global variable (name fixed in code) |
| | `NNFXNotify(text)` | Log + Alert + optional `SendNotification` (push needs a MetaQuotes ID set in MT5; **unverified** on this PC) |
| `MQL5/Include/NNFX/Panel.mqh` (new) | Chart buttons: instance on/off, close-all (with confirm), drawdown reset (with confirm) | — |
| `tests/python/nnfx_ref/guard.py` (new) | `blocks(...)`, `drawdown(...)`, `daily_loss(...)`, `in_rollover(...)` | Answer key |
| `tests/fixtures/guard/guard_cases.txt` (new) | — | Shared: time, balance/equity series, settings → expected block reasons and pause state |
| `MQL5/Scripts/NNFX/NNFX_GuardTest.mq5` (new) | — | Runs the guard fixtures |

### MT5 tests

| Test | Pass line |
| --- | --- |
| `NNFX_GuardTest` (script) | `RESULT: <n> passed, 0 failed, <n> total` |
| Rollover sample (V12) | `NNFX_GuardTest` prints the computed block window for 5 sample days on both sides of a daylight-saving change. Each one must equal the window derived by hand from the server's D1 candle open times (`docs/VERIFICATION.md` row) |
| Master switch | Demo: two charts with the test EA. Set the global variable off → both log `blocked:master` on their next candle; open test trades keep being managed (their trailing/BE log lines continue) |
| Global variables in the tester | Strategy Tester: confirm whether the terminal global variable is visible. **Unverified**: MT5 may keep tester global variables separate (section 13). Pass line is whatever is found, recorded |
| Close-all button | Manual, demo: confirm dialog appears; only this instance's magic is closed; manual trades untouched |

### Planted bugs (new checker: `guard.py` + fixtures)

At least 8:
- rollover window off by one hour
- window end exclusive vs inclusive swapped
- drawdown from balance instead of the chosen base
- pause auto-resets
- daily loss resets at local midnight instead of the trading day
- master switch ignored when the global variable is missing
- weekend block on when it should be off
- the indicator-failure block dropped

### Out of scope

- Dead-market rules T6, D1, D2: "Needs a volatility gauge (VP used EVZ); not built yet" (`tests/python/README.md`)
- Choosing the max-spread value: it needs weekday spread measurements (carry-over 4)

---

## 6. Sub-phase 6e: news (calendar export + N1 / X5 / N2)

**Branch** `phase-6e-news`, draft PR. Depends on 6d (block plumbing).

### Implements

**RULEBOOK:**
- N1 "Major news on a currency in the next 24 hours → no new trade on that currency" **[A]**
- N2 "Elections and referendums → don't trade that currency at all until settled" **[A]**
- N3 "Backtests must include news avoidance, or results are skewed" **[A]**
- X5 "Major news within 24 hours on a currency you hold: exit if losing, or if in profit by less than 1 × ATR;
  otherwise carry on" **[A]**
- VP's event list per currency **[A]**, with R-15 substitutions (roles not names; SNB rate decision instead of CHF Libor) **[C]**
- R-9 **[A]**; I-10 "News exit (X5) is checked at the first candle close inside the 24-hour window; profit is measured
  close vs entry against 1 × the current ATR"

**SPEC, News filter:**
- "MT5's built-in economic calendar works on live charts but not in the Strategy Tester, so backtests need a saved copy of past events."
- "Calendar functions cannot be used in the tester: when trying to call any of them, we get the FUNCTION_NOT_ALLOWED (4014) error."
  (quoted in SPEC from the MQL5 book; not re-checked here)
- "a small export tool runs once on a live chart and saves VP's event list for the test years to a file. Live and tester
  both read events through one module, so the EA behaves the same in both."
- "forum users report a timeout when asking the calendar for more than one month at a time …, so the export goes month by month."
- "N2 | Elections and referendums are entered by hand as a blackout list (currency + dates) in the preset"
- "A test run with the news filter off is also kept"

### Files and functions

| File | Function | Purpose |
| --- | --- | --- |
| `MQL5/Scripts/NNFX/NNFX_CalendarExport.mq5` (new) | — | Live chart only (waits for login via `Connection.mqh`). Month by month, for the 8 currencies: writes the events whose names match VP's list to `Common\Files\NNFX\calendar\events_<from>_<to>.csv` (time, currency, event id, name, importance), plus `_summary.txt` with one line per month (count, errors) and a `RESULT:` line |
| A text file in the repo, for example `profiles/news_events.txt` (new; OD-11 (a); the owner approves the names) | — | VP's list mapped to the calendar's exact event names. **The names in MT5's calendar are not yet known** (ENVIRONMENT.md item 7; SPEC open check 6) |
| `MQL5/Include/NNFX/News.mqh` (new) | `NNFXNewsLoad(path)` / `NNFXNewsCheckAge()` | One interface and one code path: the tester and live both read the CSV. Live, the CSV is refreshed daily by the export script, and there is an alarm if it is older than 24 h (OD-12 (b)) |
| | `NNFXNewsBlocked(sym, t, why)` | N1: either currency has an event in (t, t + 24 h]; also the N2 blackout list from the preset |
| | `NNFXNewsFirstClose(sym, t, prevT)` | The core's `news` flag: true at the first candle close inside the 24 h window (I-10) |
| `tests/python/nnfx_ref/news.py` (new) | `blocked(...)`, `first_close(...)` | Answer key |
| `tests/fixtures/news/news_cases.txt` (new) | — | Shared: event list + candle times (30M / 1H / 4H) → expected N1 block and X5 flag per candle, including window edges and two events close together |
| `tools/check_calendar.py` (new checker) | — | Over an export: no month missing, no duplicate events, every VP event type present at least once a year per currency (or listed as absent), times in one time base |
| `MQL5/Scripts/NNFX/NNFX_NewsTest.mq5` (new) | — | Runs the news fixtures |

### MT5 tests

| Test | Pass line |
| --- | --- |
| `NNFX_NewsTest` (script) | `RESULT: <n> passed, 0 failed, <n> total` |
| Calendar export (live demo, weekday not required) | `_summary.txt` `RESULT: <m> of <m> months exported, 0 errors`; then `check_calendar.py`: `RESULT: PASS` |
| Calendar depth | Recorded, not pass/fail: earliest month with events. **Unknown today** (ENVIRONMENT.md item 7) |
| Tester gives the same block as live | One week replayed in the tester from the CSV vs the same week computed live from the calendar | Identical N1/X5 flags for every candle of the 5 pairs |
| Time base (V12) | 10 sample events checked against their published release times, including one each side of a daylight-saving change | All 10 line up. Whether calendar times are server time is **unverified** |
| End-to-end core | Existing fixtures `N1_blocked_by_news`, `X5_*` still pass, now fed by `News.mqh` output for a constructed event | `NNFX_RulesTest` 47/47 (or the new total) |

### Planted bugs (new checkers: `news.py` + fixtures, and `check_calendar.py`)

At least 8:
- window 24 h measured backwards
- `(t, t+24h]` endpoints swapped
- only the base currency checked
- the X5 flag on every candle in the window instead of the first
- the N2 blackout ignored
- a month silently missing from the export
- a duplicate event accepted
- events in local time instead of the export's time base

### Out of scope

- Dead markets (D1, D2)
- Any news source other than MT5's calendar
- Choosing the elections list contents (owner; the N2 list starts empty, OD-19)

---

## 6f. Sub-phase 6f: the EA (`NNFX_EA.mq5`) and the decision log (verdict F1, F2; OD-1 (a))

**Branch** `phase-6f-ea`, draft PR. Depends on 6a–6e. The test EA (`NNFX_OrderTest`) serves 6b–6e; this step builds
the real one.

### Implements

**SPEC, Architecture:**
- "One shared rules core, run as three instances (30M, 1H, 4H), each loaded with its own preset file."
- "each instance trades a basket of pairs from one chart" (decision S-1 **[C]**)
- "Log | One line per candle per pair (every decision and why) + a trade log" (F2: the decision log is assigned here;
  the trade log is in 6b)

**SPEC, Candle timing and sessions:**
- "Every decision runs once per closed candle, per pair, on the first price update of the new candle (decision #3)." (R-3 **[C]**)
- "Each pair keeps its own clock. In a basket, prices arrive at different moments; a pair is processed when its own new candle exists, so no pair is read mid-candle."
- "Fixed processing order. When several pairs signal on the same candle, they are processed in a fixed order so every run gives the same result."

**SPEC, Settings:** "All three presets start with the same defaults"; `MQL5/Presets/README.md`: `NNFX_M30.set`,
`NNFX_H1.set`, `NNFX_H4.set`, "Each has its own magic number" (30M = 26030, 1H = 26060, 4H = 26240; OD-16).

**SPEC, On/off controls:** chart buttons and the master switch, wired from 6d's `Panel.mqh` and `Guard.mqh`.

### Files and functions

| File | Function | Purpose |
| --- | --- | --- |
| `MQL5/Experts/NNFX/NNFX_EA.mq5` (new) | `OnInit` | `NNFXWaitConnected`; `NNFXOrdersAllowed` (section 1); load the preset, profiles and pair list; `NNFXRebuild` (6c); never defines `NNFX_TEST_BUILD` (F3) |
| | `OnTick` / `OnTimer` | For each pair in the preset's fixed order: if that pair has a new closed candle (its own clock), process it once. If the EA started with an unprocessed closed candle waiting, skip it and wait for the next one (OD-7 (b)) |
| | `ProcessPair(sym, candle)` | BarBuilder → `NNFXBar`; `block` = Guard (6d) + Exposure (6a) + News N1/N2 (6e); `news` = News X5 flag (6e); run the core; send the core's ENTER/EXIT/TRAIL decisions through `Orders.mqh` (6b); save state (6c); write one decision-log row |
| | `OnTradeTransaction` | Hands TP1 fills to `NNFXOnTp1Filled` (T2 straight away) |
| | `OnChartEvent` | Panel buttons (6d) |
| `MQL5/Include/NNFX/DecisionLog.mqh` (new) | `NNFXLogDecision(sym, candle, NNFXBar &in, events[], blocks)` | One CSV row per pair per closed candle: time, the core's inputs (o h l c atr base c1 c2 ex vol), block reasons, news flag, the core's events with rule IDs, and the action sent. Format fixed so Phase 7's bar-by-bar check can replay it |
| `MQL5/Presets/NNFX_M30.set`, `NNFX_H1.set`, `NNFX_H4.set` (new) | — | Saved from MT5's own settings dialog (`MQL5/Presets/README.md`); same defaults; own magic |
| `tools/check_decision_log.py` (new checker) | — | Every pair has exactly one row per closed candle in the run (no gap, no duplicate); pairs in the preset's fixed order within a candle time; every ENTER in the decision log has a matching open in the trade log, and every trade-log open has an ENTER |

### MT5 tests

| Test | Pass line |
| --- | --- |
| EA run (verdict F1) | Strategy Tester: `NNFX_EA` on the 1H preset, the 5 pairs, 1 minute OHLC, at least 3 months. The run completes; `check_trades.py` `RESULT <log>: PASS (0 failures)`; `check_decision_log.py` `RESULT <log>: PASS` |
| Same run twice | Identical decision logs and trade logs (a first look at V14; the full V14 is Phase 8) |
| All three presets start | The 30M, 1H and 4H presets each start in the tester for one week with no errors; each run's trade log carries its own magic |
| Demo smoke test | Weekday, the 1H preset, the 5 pairs, at least one full day: no errors; decision log complete; `orders allowed: DEMO` |

### Planted bugs (new checker: `tools/check_decision_log.py`)

At least 8:
- a missing candle row
- a duplicated row
- pairs out of the fixed order
- an ENTER with no trade-log open
- a trade-log open with no ENTER
- a row written mid-candle (time not on a candle boundary)
- a block reason dropped
- an event's rule ID changed

### Out of scope

- The bar-by-bar comparison with the answer key (Phase 7)
- The shootout (Phase 8)
- Tuning any setting

---

## 7. CARRY-OVERS from the G1_phase5_2 VERDICT

| # | Verdict text (quoted) | Plan |
| --- | --- | --- |
| 1 | "The INVALID/timeout path of `NNFXWaitConnected` has not been exercised, and neither has the runner's "no Python" FAIL path. Phase 6 depends on login state (orders), so its plan should include a test with MT5 offline." | In 6a, see below. Pass lines: EnvCheck `RESULT: INVALID (not connected)`; runner `3 NNFX_EnvCheck FAIL`; and `5 Python unit tests FAIL - no working Python found` with `5 check_export.py` and `5 check_indicators.py` `NOT RUN`. Phase 6: `Orders.mqh` calls `NNFXWaitConnected` before the first order of a session, and the 6b order test repeats the offline case: `NNFX_OrderTest` refuses with `not connected`, 0 orders |
| 2 | "Tick values for non-USD pairs move with exchange rates. Position sizing must read `SYMBOL_TRADE_TICK_VALUE` when the order is placed, never use the values recorded in ENVIRONMENT.md." | 6a `NNFXSizeForSymbol` reads tick value and tick size immediately before sizing, inside the same call that sends the order (6b). The trade log records the tick value used. Planted bug "tick value from a constant" (6a). Decided OD-6 (c): the larger of `SYMBOL_TRADE_TICK_VALUE` and `SYMBOL_TRADE_TICK_VALUE_LOSS`, which can only make lots smaller |
| 3 | "On a weekend the export skips the last closed candle. The plan must state which candle the EA acts on when it starts outside market hours." | See below; decided OD-7 (b) skip and OD-17 (a) act |
| 4 | "Spreads are still weekend readings. Commission is still unknown (ENVIRONMENT.md item 5)." | See below |

**Carry-over 1: how the offline test is run.**
- A runner option `-Offline` makes MT5 start with no connection, and the runner expects EnvCheck to report
  `RESULT: INVALID (not connected)` and counts that step as **PASS-expected-failure**.
- The way to start MT5 offline is **unverified**. Candidates, to be tried in this order:
  - (a) Windows firewall rule blocking `terminal64.exe`, which needs an admin prompt (owner)
  - (b) a `/config` `[Common]` section pointing at a non-existent server
  - (c) network adapter off (owner, by hand)
- "No Python": run the runner with `PATH` stripped of Python and `py`, and `LOCALAPPDATA` pointed at an empty
  folder, in a child process. No code change is needed.

**Carry-over 3: which candle the EA acts on.**
- Per R-3 **[C]** "Act on the first tick of the new candle using the candle that just closed", the EA keeps a
  per-pair "last processed candle time" (6c state file).
- On the first tick after it starts:
  - (i) If the last fully closed candle is newer than the last processed one, there were two options (OD-7). **Decided: (b) skip**, so the EA waits for the next new candle; open trades are still managed after the rebuild:
    - **(a) catch-up:** process only that one most recent closed candle, never older ones
    - **(b) skip:** wait for the next new candle
  - (ii) Over a weekend the "first tick of the new candle" is the Monday (Sunday server) open. So the Friday last
    candle is decided at that open and any entry fills at the Monday open price (gap risk). This matches the
    answer key's "decided at the close, filled at the next open".
- The export's skipping of the last closed candle (it starts at shift 1) is a property of `NNFX_ExportBars`, not of
  the EA. The EA uses "a new candle exists" (bar time change), not "shift 1".
- Test:
  - a tester run that starts mid-week at 10:37 vs one that starts at 10:00 must give the same decisions from the
    first common candle on
  - a demo start on a Saturday must log `waiting: market closed` and no decision until the first Monday tick

**Carry-over 4: spreads and commission.**
- In 6d, `NNFX_EnvCheck` is re-run on a weekday during the London/New York overlap and at the daily close. A new
  `InpSpreadSamples` option takes, for example, 60 samples over 10 minutes per pair and records min / median / max.
- Commission comes from the deal record (`DEAL_COMMISSION`) of the 6b demo order test.
  - This is MetaQuotes-Demo's commission, which is **not** the live broker's.
  - The live broker is still undecided ("Waiting on the owner: Choose the live broker").
- The max-spread guard stays off (SPEC: "Off until spreads are measured") until those readings exist.

---

## 8. Where tick value, ATR and prices come from at order time

So that carry-over 2 holds everywhere:

| Value | Source at order time | Never from |
| --- | --- | --- |
| Balance | `AccountInfoDouble(ACCOUNT_BALANCE)` (S-3) | Cached value |
| Tick size, tick value, volume min/step/max, stops level, freeze level, filling mode | `SymbolInfo*` for that symbol, read in the sizing/order call | `docs/ENVIRONMENT.md` |
| ATR | `BarBuilder` ATR(14) of the last closed candle (M1, M3) | Live candle |
| Entry price | The broker's fill price (`DEAL_PRICE`) | Requested price |
| SL / TP1 / BE / trail | From the **fill** price and the decision candle's ATR (`orders.py` = the same formula) | Requested price |

---

## 9. RESTART TESTS

**SPEC "Rebuilding after a restart", quoted:**

> On start-up, before doing anything else, the EA rebuilds its memory from what the broker holds:
>
> | What it needs | Rebuilt from |
> | --- | --- |
> | Which open positions are halves of the same trade | Magic number + trade ID; state file; deal history |
> | Has TP1 already filled? | Deal history (half 1 closed at its target) |
> | Breakeven / trailing stage | Half 2's current stop compared with entry and ATR |
> | Continuation still allowed? | Price history since the original entry: has price crossed the baseline? |
> | Last exit direction (for continuation) | Deal history |
>
> Pass test: restart MT5 in each state (before TP1, after TP1, trailing, flat but waiting for a continuation). The
> trades and logs afterwards must match a run with no restart.

Also SPEC Verification plan, 1e: "Restart | Restart MT5 in each trade state (section: Orders) | Identical to a run without restart".

| # | State at restart | How it is reached | Pass line |
| --- | --- | --- | --- |
| R1 | Before TP1 (both halves open, original stops) | Tester: scripted trade; demo: a real trade | After the restart: same two tickets paired to one trade ID; TP1 not done; stops unchanged. Afterwards the log matches the no-restart run |
| R2 | After TP1 (half 2 open, stop at breakeven) | Same | Rebuilt: TP1 done (from deal history), BE stage; half 2's stop = entry. Same later trail and exit as the no-restart run |
| R3 | Trailing (half 2, trail active) | Same | Rebuilt: trail active; the next trail move is at the same candle and price as the no-restart run; never backwards |
| R4 | Flat, waiting for a continuation | Same | Rebuilt: armed, the same trend direction, the same `c1_flipped` (version a). The continuation entry happens on the same candle as the no-restart run, or does not happen in both |

**How "a run with no restart" is obtained (OD-10, decided (c) both):**
- **(a) Tester, simulated restart.** A test input `InpRestartAt=<time>` makes the EA, at that time, throw away all
  memory and run `NNFXRebuild` exactly as at start-up. Same price data, so the two runs are directly comparable with
  `tools/compare_runs.py`. **Pass:** `RESULT: IDENTICAL (0 differing rows)` over the trade log and the decision log
  after the restart time.
- **(b) Demo, real restart.** Close and reopen MT5 (or kill `terminal64.exe`) in each state, on a weekday. There is
  no second identical live run, so the comparison is against (i) the saved pre-restart state file and (ii) a Python
  replay of the same candles. **Pass:** rebuilt state = pre-restart state field for field, and no decision differs
  from the replay.
- **Plan:** both. (a) proves "identical to a run without restart" literally. (b) proves the real process restart,
  including the state file, comments as the broker returns them, and `OnInit` order.
- Comment handling: one R2 variant where the state file is deleted before the restart, and one where comments are
  ignored, so each backup source is shown to work alone. SPEC: "comments are never the only record".

---

## 10. Sequence and what each merge proves

| Step | Merged when (G1 pass line) |
| --- | --- |
| 6a | `NNFX_SizingTest` all pass; Python suite OK; planted bugs all caught; offline test done (carry-over 1) |
| 6b | `NNFX_OrderMathTest` all pass; tester order run `check_trades.py` PASS; demo order run PASS; S1–S4 safety tests pass |
| 6c | `NNFX_RecoveryTest` all pass; R1–R4 in the tester (`compare_runs.py` IDENTICAL) and on demo |
| 6d | `NNFX_GuardTest` all pass; rollover samples line up; master switch demo test; weekday spreads recorded |
| 6e | `NNFX_NewsTest` all pass; calendar export PASS; tester = live flags for one week; time-base samples line up |
| 6f | EA tester run on 5 pairs completes; `check_trades.py` PASS; `check_decision_log.py` PASS; two runs identical; three presets start; demo smoke test |

Every step updates `docs/STATUS.md`, `docs/VERIFICATION.md` and `tools/README.md` in its own PR.

---

## 11. DECISIONS (owner, 2026-10-04: "accept recommended defaults")

The owner accepted the reviewer's recommended default for every open decision (`VERDICT.md`, "Open decisions: reviewer's
recommended defaults"). The options and reasons below are copied from there. These become rows in `docs/DECISIONS.md`
in the 6a PR, labelled C (owner's choice) unless stated otherwise.

| ID | Question | Decision | Reviewer's reason |
| --- | --- | --- | --- |
| OD-1 | Which sub-phase builds `NNFX_EA.mq5` | (a) a test EA in 6b–6e; the real EA in **6f** | Each PR stays testable on its own |
| OD-2 | Drawdown peak | (c) **equity, sampled at each candle close** | Protects against open-trade losses; deterministic in the tester |
| OD-3 | Daily loss | **Closed trades only**; the day starts at **server midnight** (the daily close, 00:00 server per ENVIRONMENT.md) | Simple and identical in tester and live |
| OD-4 | Split mode with 3+ signals on one leg | (a) **skip all** (as `exposure.py` does now) | Conservative; VP has no rule |
| OD-5 | Not enough free margin | (a) **skip and log** | Never changes risk silently |
| OD-6 | Tick value for sizing | (c) **the larger of TICK_VALUE and TICK_VALUE_LOSS** | Can only make lots smaller, so risk is never above 2% |
| OD-7 | Start outside market hours / after downtime | (b) **skip**: wait for the next new candle | Never enters late at a worse price; open trades are still managed after the rebuild |
| OD-8 | Missing-stop scope | (a) **our magics are closed; a manual stopless position raises an alarm only** | The EA never closes the owner's manual trades |
| OD-9 | State file location | (a) `MQL5\Files\NNFX\state\` | The tester and live can never share a file |
| OD-10 | "A run with no restart" | (c) **both** (tester simulated restart and demo real restart) | As planned |
| OD-11 | VP's event-name mapping | (a) **a text file in the repo; the owner approves the names** | Versioned and reviewable |
| OD-12 | News source live | (b) **CSV refreshed daily, plus an alarm if it is older than 24 h** | Same code path live and in the tester |
| OD-13 | Retries | **3 retries, 1 s apart, a duplicate check before each** | "Limited" made concrete |
| OD-14 | Slippage | (c) **accept the fill; SL/TP from the fill price; log the slippage** | Risk stays exact (the stop is measured from the fill) |
| OD-15 | Breakeven price | (a) **exactly entry** | T2 is A |
| OD-16 | Magic numbers | **30M = 26030, 1H = 26060, 4H = 26240**, fixed in the presets | Distinct and readable (the reviewer's example values, accepted as given) |
| OD-17 | Weekend: Friday's last candle at the Monday open | (a) **act** | Matches the answer key and backtests |
| OD-18 | CONTEST accounts | (a) **refuse** | Demo or tester only |
| OD-19 | Elections/referendums list (N2) | **Start with an empty list; the owner adds entries** | Format only for now |
| OD-20 | Exposure while half 2 runs at breakeven | (a) **counts until fully closed** | Literal M6; conservative (C label) |
| OD-21 | Non-FX symbols | (b) **ignore non-FX symbols, with a log line** | Out of VP's scope |

**How OD-7 and OD-17 fit together:**
- OD-17 applies while the EA is running through the weekend. The first Monday (Sunday server) tick is the "first
  tick of the new candle", so Friday's last candle is decided then, as R-3 says.
- OD-7 applies only when the EA **starts** (or restarts) with a closed candle it never processed. That candle is
  skipped.
- So the same Friday candle is acted on if the EA ran through the weekend, and skipped if it was started over the
  weekend. Restart test R4 and the carry-over-3 start-time test cover this difference.

**Reviewer's optional suggestion, not covered by "accept recommended defaults":** run `NNFX_CalendarExport` +
`check_calendar.py` early, alongside 6a, as a read-only data step, to learn the calendar depth (U3). The owner made
it optional for 6a (2026-10-04). **Not done in 6a**; it stays in 6e.

---

## 12. What Phase 6 does not include

- The bar-by-bar cross-check (Phase 7)
- The shootout and V1–V14 on real backtests (Phase 8)
- The demo period (Phase 9)
- Dead markets (T6, D1, D2: no volatility gauge yet)
- Netting accounts (S-10; this account is hedging)
- Choosing the live broker
- Real-money trading of any kind (section 1)

---

## 13. Facts I could not confirm (unverified)

| # | Fact | Why it matters | How it will be confirmed |
| --- | --- | --- | --- |
| U1 | `MQLInfoInteger(MQL_TESTER)` returns true in the Strategy Tester (standard MQL5; not used in this repo yet) | Safety rule | First compile and S1/S3 tests |
| U2 | Calendar functions return error 4014 in the tester (quoted in SPEC from the MQL5 book; not re-checked by me) | 6e design | One call from the 6e test EA in the tester; the error code recorded |
| U3 | MT5 calendar depth and VP's event names in it | 6e mapping and test years | Calendar export (6e) |
| U4 | Calendar event times are in trade-server time | N1 window, V12 | 10 sample events (6e test) |
| U5 | The broker keeps order comments unchanged, and the comment length limit | Restart recovery | 6b demo test: read back the comments (ENVIRONMENT.md item 6) |
| U6 | Terminal global variables are shared with / separate from the Strategy Tester | Master switch in backtests | 6d tester test |
| U7 | `SendNotification` works on this PC (needs a MetaQuotes ID in MT5 settings) | Alarms to phone | 6d demo test; owner sets the ID |
| U8 | `SYMBOL_TRADE_TICK_VALUE_LOSS` differs from `SYMBOL_TRADE_TICK_VALUE` on this broker | OD-6 | 6a live read prints both |
| U9 | Filling modes supported by MetaQuotes-Demo (`SYMBOL_FILLING_MODE`) | Orders must use an allowed mode | 6b reads and logs it per symbol |
| U10 | How to start MT5 offline for the carry-over-1 test (firewall / bad server in `/config` / adapter off) | Offline test | Tried in 6a, in the order listed |
| U11 | Commission on MetaQuotes-Demo (and on the eventual live broker) | Costs, V4 | 6b demo deal record; broker terms |
| U12 | `OnTradeTransaction` reports half 1's TP fill in the tester with enough detail to move BE "straight away" | T2 timing | 6b tester run, log of transaction types |
| U13 | `[StartUp]` in a `/config` file can attach an Expert (not only a Script) to a chart, for unattended demo restart tests | Automating R1–R4 on demo | 6c: try once; fallback is by hand |
| U14 | Daylight-saving dates for the server (server − GMT was +3.00 on 2026-10-04; ENVIRONMENT.md item 3) | Rollover window, news times | Re-run EnvCheck after the change |
