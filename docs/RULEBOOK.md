# NNFX Multi-Timeframe EA — Rulebook (Phase 0)

Sep 28, 2026 · @Evian

This is the source of truth for the EA's rules. Every rule shows where it comes from and how sure we are; anything not confirmed by VP himself is listed as a decision for you. No code is written until you approve this.

**Status: approved for building, not proven.** All 15 decisions were accepted on Oct 1, 2026 as the defaults to build and test. No rule is trusted until it passes three checks: the EA matches this rulebook exactly (test cases and a bar-by-bar cross-check), each B rule is confirmed against VP's videos, and backtests plus a demo period show it works.

## How to read this

Every rule carries one of three labels. Most of VP's detailed rules were taught in videos, not written down, so many rules land at B.

| Label | Meaning | What we do with it |
| --- | --- | --- |
| **A — VP, written** | VP's own words on nononsenseforex.com, or in the posts you supplied (*the\_trading\_truth.docx*) | Build as stated |
| **B — Secondary** | Community write-ups of VP's videos (flow charts, lesson sites, testing tools). They agree with each other but are not VP's own words | Build as a setting with the stated default; you confirm |
| **C — No source** | Not found anywhere reliable, or sources disagree | Your decision, recorded in DECISIONS.md |

## Money management

Money management is the best-sourced part of NNFX: nearly all of it is in VP's own words.

| # | Rule | Label | Source |
| --- | --- | --- | --- |
| M1 | ATR period is 14, left at default | A | ATR post (your doc) |
| M2 | Risk 2% of **total** trading capital per trade (not per sub-account) | A | [Risk Management guide](https://nononsenseforex.com/trade-management/forex-risk-management/), [Don't Split Your Risk](https://nononsenseforex.com/forex-q-and-a-podcast/dont-split-your-risk/) |
| M3 | Stop loss = 1.5 × ATR from entry | A | Risk Management guide; Backtesting Ep. 21 (your doc) |
| M4 | Position size: risk money ÷ stop distance = value per pip, so every pair carries the same risk | A | Risk Management guide; ATR post (your doc) |
| M5 | The 2% is split into two equal half-orders | A | [Scaling Out](https://nononsenseforex.com/trade-management/forex-money-management-scaling-out/): "Make TWO HALF TRADES with that new number" |
| M6 | Never more than one trade at 2% that is long or short the **same currency** (e.g. EUR/AUD long + AUD/USD short = double AUD exposure) | A | Risk Management guide |
| M7 | If two signals share a currency: take one at 2%, or both at 1% each, or 1% now and 1% later | A | Risk Management guide |
| M8 | Read the ATR about 30 minutes before the candle closes, once the candle has made its range | A | ATR post (your doc) |
| M9 | Spreads are very wide for about an hour after the daily close | A | ATR post (your doc) |

**For the EA:** M6 and M7 mean the EA must look across **all** open trades (all three EAs and all pairs) before opening a new one. That makes a shared exposure check a required module, not an extra.

## Trade management

The split, TP1 and breakeven are VP's own words; the trailing stop's exact mechanics are only in secondary sources.

| # | Rule | Label | Source |
| --- | --- | --- | --- |
| T1 | Both halves get the same 1.5×ATR stop. Half 1 gets a take profit at 1 × ATR | A | [Scaling Out](https://nononsenseforex.com/trade-management/forex-money-management-scaling-out/) |
| T2 | When half 1 hits TP, move half 2's stop to breakeven (the entry price) | A | Scaling Out |
| T3 | Half 2 has no fixed target: "let that baby run" | A | Scaling Out |
| T4 | Trailing stop on half 2: 1.5 × ATR behind price, switched on once price has **closed** 2 × ATR beyond entry, moved once per candle close, never backwards | B | [No Nonsense Trader — Trailing Stop](https://nononsensetrader.com/trailing-stop/) |
| T5 | The exit indicator "competes with" the trailing stop (they are alternatives to test against each other) | A | Backtesting Ep. 21 (your doc) |
| T6 | In a dead market, take the whole trade off at TP1 instead of scaling out | A | Dead Markets (your doc) |
| T7 | Runner take-profit cap (your option 3): a setting, **off by default** so the EA stays true to NNFX; backtests decide | Your decision | This conversation |

**Conflict on T4:** the [Rui Silva flow chart](https://nononsensetrader.com/wp-content/uploads/2021/02/No-Nonsense-FOREX-Flow-Charts.pdf) describes the trail moving in 0.5 × ATR steps, while the lesson site says it is moved each day at 1.5 × ATR. Both are secondary. The EA will make activation distance, trail distance and step size settings, defaulting to the lesson site's version, until you confirm from VP's trailing-stop video.

**Every order always has a broker-held stop.** No NNFX rule removes a stop, so this matches your "always a stop loss" requirement with no conflict.

## Algorithm structure

VP's own post (Dec 2018) lists six slots: 1 ATR, 2 ???, 3 Confirmation, 4 ???, 5 Volume, 6 Exit. Slots 2 and 4 were revealed later in videos; secondary sources agree they are the Baseline and a second confirmation (C2).

| Slot | Role | Label | Source |
| --- | --- | --- | --- |
| 1 — ATR | Trade management (sizing, stop, target) | A | Volume post (your doc) |
| 2 — Baseline | Filters losses; price crossing it is also an entry trigger | B | Flow charts; [NNFX Algo Tester modes](https://help.nnfxalgotester.com/knowledgebase.php?article=86) |
| 3 — C1 | "The one real vehicle for trade entry" | A | Volume post (your doc) |
| 4 — C2 | Filters losses from C1 | A (role) / B (name) | Volume post: "2, 4, and 5 … take the losses your Confirmation Indicator gives you, and attempts to eliminate most of them" |
| 5 — Volume / volatility | Pass/fail filter; volume and volatility indicators are "the same family" | A | Volume post (your doc) |
| 6 — Exit | Trade management: closes the trade | A | Volume post (your doc) |
| Extra — Continuation | Not a separate slot in VP's version (C2 gives the re-entry signal); one community author uses the exit indicator instead | B | [Lesson 11](https://nononsensetrader.com/lesson-11-continuation-trades/) |

Other A-level principles that shape the indicator slots:

- Currencies are never "overbought" or "oversold", so no overbought/oversold levels anywhere; signals are line crosses or zero/centre-line crosses (Reversal Trading post, your doc).
- Test indicators on default settings first, then try other settings (Backtesting Ep. 21, your doc).
- Avoid the "Dirty Dozen" (RSI, Stochastics, CCI, Bollinger Bands, MA crossovers, and so on) as signals (Big Banks post, your doc).

**For the EA:** each slot is a swappable module fed by an indicator profile file. This matches your modular goal and needs no NNFX rule to be bent.

## Entry rules

Only the timing of entries is in VP's own writing; every entry pattern below comes from secondary sources, which agree on the shape but not every detail.

| # | Rule | Label | Source |
| --- | --- | --- | --- |
| E0 | Decide once per candle, shortly before it closes, using that candle's values (VP checks 30 minutes before the daily close and executes then) | A | Best Time Frame Ep. 3 and ATR post (your doc) |
| E1 | **Standard entry (C1 triggers):** C1 gives a signal; price is on the same side of the baseline; price is within 1 × ATR of the baseline; C2 agrees; volume passes | B | [Flow charts](https://nononsensetrader.com/wp-content/uploads/2021/02/No-Nonsense-FOREX-Flow-Charts.pdf) |
| E2 | **Baseline entry (baseline triggers):** price crosses the baseline (opens one side, closes the other); C1 agrees and its signal was fewer than 7 candles ago; within 1 × ATR; C2 and volume agree | B | Flow charts; [Algo Tester modes](https://help.nnfxalgotester.com/knowledgebase.php?article=86) |
| E3 | **1 × ATR / pullback:** if price is more than 1 × ATR from the baseline, don't enter. If the next candle closes back within 1 × ATR and everything still agrees, enter then | B | Flow charts; [backtestd rules](https://github.com/stfl/backtestd-doc/blob/master/NNFX%20Algo/Algorithm%20Rules.org) |
| E4 | **One-candle rule:** if one indicator lags the signal, wait at most one candle for it to agree | B (details unclear) | Flow charts; backtestd rules |
| E5 | **Bridge too far (7 candles):** if C1's signal started 7 or more candles before the baseline cross, skip the trade | B (counting unclear) | [No Nonsense Trader — Bridge Too Far](https://nononsensetrader.com/bridge-too-far/); flow charts |
| E6 | **Continuation:** after an exit, re-enter in the same direction if price has not crossed the baseline since the original entry. Two versions, tested against each other: (a) VP (per you, from his videos): C2 flips back in the trade's direction while C1 never flipped against it; (b) Lesson 11 author's own choice: the exit indicator doubles as the continuation signal. Both ignore the volume filter and the 1 × ATR rule; money management is unchanged | B | Flow charts; [Lesson 11](https://nononsensetrader.com/lesson-11-continuation-trades/) |

Open details, each a setting until you decide (listed again under Decisions):

- **E0 for an EA:** VP enters just before the close. An EA can do the same (for example 1–2 minutes before close on 30M) or act on the first tick of the next candle. The second is simpler and is how backtests are normally scored.
- **E4:** sources don't say whether the one-candle rule also requires price to stay within 1 × ATR on the second candle.
- **E5:** sources differ on whether the candle count includes the cross candle. One lesson site also argues the rule clashes with E4.
- **E6:** version (a) comes from you, from VP's videos; I could not find it in writing. Version (b) is the Lesson 11 author's own design ("I made the continuation indicator the same as the exit indicator"), not VP's.

## Exit rules

There is one exit indicator (slot 6), confirmed in VP's writing. VP also implies that an opposite C1 signal means you should already be out; the baseline-cross exit is secondary only.

| # | Rule | Label | Source |
| --- | --- | --- | --- |
| X1 | Stop loss (1.5 × ATR, then breakeven, then trailing) and TP1 close the trade or half of it | A | Scaling Out; Risk Management guide |
| X2 | Exit indicator signals against the trade → close what is left | A (slot) / B (mechanics) | Volume post (your doc); flow charts |
| X3 | C1 gives an opposite signal → close what is left. VP: "If your own Confirmation Indicator is giving you a short signal before your Exit Indicator tells you to abort … Why are you still in the trade?" | A (implied) | [Scaling In Ep. 25](https://nononsenseforex.com/forex-q-and-a-podcast/scaling-in/) |
| X4 | Price closes on the other side of the baseline → close what is left | B | Flow charts; Algo Tester (optional there) |
| X5 | Major news within 24 hours on a currency you hold: exit if losing, or if in profit by less than 1 × ATR; otherwise carry on (the stop is at breakeven or trailing) | A | [Forex News Trading](https://nononsenseforex.com/forex-basics/forex-news-trading/) |

**Proposed default:** exit on whichever comes first of X1–X4, with X2, X3 and X4 each a setting (on by default) so the backtests can measure each one. This keeps one exit indicator as you asked, and treats C1 flip and baseline cross as safety exits alongside it.

## News, dead markets, pairs and drawdown

All of these are in VP's own writing (label A). The news rule is the one that most affects the build.

| # | Rule | Source |
| --- | --- | --- |
| N1 | Major news on a currency in the next 24 hours → no new trade on that currency | [Forex News Trading](https://nononsenseforex.com/forex-basics/forex-news-trading/) |
| N2 | Elections and referendums → don't trade that currency at all until settled | Forex News Trading |
| N3 | Backtests must include news avoidance, or results are skewed | Back Testing Ep. 47 (your doc) |
| D1 | Dead market (low volume): don't trade. VP watches the EUR/USD volatility index (EVZ); his own threshold was 8 | Dead Markets (your doc) |
| D2 | In a dead market, avoid USD pairs and take the whole trade off at TP1 | Dead Markets (your doc) |
| P1 | Trade all 28 combinations of the 8 majors (EUR/CHF was excluded, later added back) | Currency Pairs Ep. 4 (your doc) |
| P2 | Quick test on 5 pairs first: EUR/USD, AUD/NZD, EUR/GBP, AUD/CAD, CHF/JPY. If it fails there, it likely fails on the rest | Back Testing Ep. 47 (your doc) |
| R1 | Aim for no more than 10% maximum drawdown; 15% is "a lot"; 20% is "Armageddon" | Drawdown Ep. 52 (your doc) |
| R2 | Never add to a winning trade (no scaling in) | [Scaling In Ep. 25](https://nononsenseforex.com/forex-q-and-a-podcast/scaling-in/) |

VP's list of major events per currency:

| Currency | Events |
| --- | --- |
| USD | Interest rates, Non-Farm Payrolls, CPI, FOMC speech by the Fed chair |
| EUR | Interest rates, ECB president speech |
| GBP | Interest rates (incl. MPC votes), GDP |
| CAD | Interest rates, employment, CPI, retail sales |
| AUD | Interest rates, employment |
| NZD | Interest rate, GDP, GDT, employment |
| JPY | Interest rate |
| CHF | Libor rate (see note below) |

**For the EA:** R1 gives the safety limits a sourced basis: a max-drawdown stop around 10% fits VP's guidance. News avoidance needs a calendar feed. MT5 has a built-in economic calendar, but I will verify whether it works inside the Strategy Tester before relying on it; if not, backtests need a saved list of past event dates.

**My substitutions, not VP's words:** VP named people ("Jay Powell", "Mario Draghi"); I wrote the roles (Fed chair, ECB president) so the list stays current. He named the Libor rate for CHF, which has since been retired; I suggest the SNB rate decision instead. Both are for you to approve.

## Timeframes: 30M, 1H and 4H

VP says the system works on any timeframe but best on the Daily, and ranks 4H as the next best after the Weekly. So running NNFX on 30M/1H/4H is allowed by his teaching, but expected to perform worse than Daily, which is exactly what the shootout will measure.

What VP wrote (all A, your doc):

- "The Daily time frame. And it's not even close." He tested every indicator on every timeframe except 1-minute (Best Time Frame Ep. 3).
- "Everything I do here works on every time frame … They just all perform better on the Daily time frame" (Ep. 3).
- "I would say the 4 hr is the next best after the Weekly, but it's a pain in the ass to trade, and I don't recommend it." Earlier in his testing, 4H and 1H outperformed the Weekly (Ep. 3).
- Lower timeframes bring "more news, sessions, the way the Big Banks handle intraday moves" (Dead Markets).

What that means for the EA (my analysis, not VP's words):

| Topic | Daily NNFX | Intraday effect | Proposed handling |
| --- | --- | --- | --- |
| Stop and target | 1.5 / 1 × daily ATR | ATR on the chart's timeframe shrinks them automatically | No change to the rules |
| Trading costs | Spread is tiny next to daily ATR | Spread and commission are a much bigger share of a small stop | Every backtest uses real spread and commission; optional max-spread filter |
| Rollover | Spreads blow out \~1 hour after the daily close (M9) | Several intraday candles close inside that hour | No entries in a set window around rollover (setting) |
| News (N1) | 24 hours = one candle | 24 hours = 6 (4H) to 48 (30M) candles | Keep VP's 24-hour clock rule (setting) |
| 7-candle rule (E5) | 7 days | 7 hours on 1H | Count candles, as written (setting) |
| Same-currency limit (M6) | Few open trades | Three EAs can open overlapping trades | One shared exposure check across all EAs |
| Test length | 2–3 years (Ep. 21, 47) | Same years, far more candles | Same date range for all three; confirm broker history first |

## Decisions for you

Fifteen points need your call. Each becomes a setting with the default shown, so it can be tested either way; tick each one you accept, or comment with a change.

- [x] **1. Trailing stop (T4):** switch on after a close 2 × ATR beyond entry, trail 1.5 × ATR, move at each candle close.
- [x] **2. Exits (X2–X4):** exit indicator, C1 flip and baseline cross all on; whichever comes first closes the trade.
- [x] **3. Entry timing (E0):** act on the first tick of the new candle, using the candle that just closed.
- [x] **4. One-candle rule (E4):** price must still be within 1 × ATR of the baseline on the second candle.
- [x] **5. Bridge too far (E5):** a setting (on/off + number of candles), counted back from the candle before the baseline cross. 7 candles is 7 days on Daily but only \~28 hours on 4H, 7 hours on 1H and 3.5 hours on 30M, so each timeframe is tested at 7 and at larger values; the results set the number.
- [x] **6. Continuation versions (E6):** two versions as one setting, both backtested; the better one becomes the default. (a) VP (per you): C2 flips back in the trade's direction while C1 never flipped against it. (b) Lesson 11 author: the exit indicator doubles as the continuation signal.
- [x] **7. Continuation conditions (E6):** in both versions, price must not have crossed the baseline since the original entry; the volume filter and the 1 × ATR limit do not apply; money management is unchanged.
- [x] **8. Baseline cross:** the close is on the other side of the baseline from the previous close. The flow chart's wording ("opens one side, closes the other") only differs when price gaps across the baseline between candles, which my version still counts.
- [x] **9. News (N1):** no new trades on a currency within 24 hours before its major events; apply the open-trade rule (X5).
- [x] **10. Rollover:** no new entries from 15 minutes before to 60 minutes after the daily close.
- [x] **11. Runner cap (T7):** off by default (pure NNFX). Backtests also run caps of 1×, 2×, 3× and 4× ATR on the chart's timeframe, since intraday moves often stall between sessions. VP himself takes the whole trade at TP1 in dead markets, which equals a 1× cap.
- [x] **12. Drawdown safety limit (R1):** stop opening new trades at 10% drawdown from the account's peak; open trades keep their stops.
- [x] **13. Pairs (P1/P2):** start with VP's 5 test pairs; widen to all 28 once the broker's history is confirmed.
- [x] **14. Risk:** 2% default, editable per timeframe preset.
- [x] **15. Substitutions:** use roles instead of names in the news list, and the SNB rate decision instead of CHF Libor.

## Where the old code differs

This section compares the code from your earlier scanner project (`nnfx_engine.py` and `NNFXHarness.mq5`) with this rulebook, so the new EA doesn't inherit its gaps. That code passes its own 39 tests, but it covers only part of NNFX. It is a lesson, not a starting point.

- **Entries.** The old code only opens a trade on the candle where price crosses the baseline. It misses three other entries:
  - C1 flips while price is already on the right side of the baseline (E1).
  - Price crosses the baseline but closes more than 1 × ATR away; if the next candle closes back within 1 × ATR, you enter then (E3). The old code skips the trade for good.
  - Everything agrees except one indicator, which agrees one candle later (E4). The old code never waits that candle.
- **Exits.** The old code exits only when C1 flips. The rulebook exits on whichever comes first: exit indicator, C1 flip, or a close on the wrong side of the baseline. When the old code did test an exit indicator, it judged long/short by "above or below 0", which breaks the rule that an indicator's own centre line is never assumed to be 0.
- **Trailing stop.** Both trail the runner 1.5 × ATR behind price. The old code starts right after TP1, so the stop begins rising once price closes 1.5 × ATR past entry. The rulebook waits until price has closed 2 × ATR past entry. The rulebook version gives the runner more room.
- **News and exposure.** The old code has neither of VP's safety rules: no new trade before major news on that currency (N1, X5), and never two 2% trades on the same currency (M6).
- **Volume.** The old code tested every volume indicator the same way: pass if today's reading is at or above its own 20-candle average. Its README called that a placeholder. In the new EA, each indicator's profile says how it signals a pass. This is a design choice, not a VP rule.
- **Continuation.** The old code triggered continuation on a new C1 signal. The rulebook tests VP's version (C2 flips back while C1 never flipped) against the Lesson 11 version (E6).
- **MT5 plumbing bugs (five).**
  - Daily candles are hardcoded, so it cannot run on 30M, 1H or 4H.
  - When the risk works out to exactly the broker's minimum lot (for example 0.01), each half is rounded back up to 0.01, so it trades 0.02: double the intended risk.
  - The volume average is always read from output line 0, even when today's value comes from another line, so it can compare two different lines.
  - It remembers which positions are the two halves only in memory. After an MT5 or PC restart it forgets, so it cannot move the runner to breakeven, trail it or exit it on a signal (the broker still holds the original stop and TP).
  - It needs a hedging account (two separate positions). A netting account merges them into one and breaks the two-halves logic.

The new EA is built to avoid each of these from the start, and each one gets its own test (Phases 4–6).

## Sources

**VP's own writing (label A)**

- *the\_trading\_truth.docx* (supplied by you): 12 VP posts, including The ATR Is The World's Best Forex Indicator; How Many Currency Pairs (Ep. 4); Reversal or Trend Trading; Best Time Frame (Ep. 3); Beware The Big Banks; Forex Volume Indicator; Forex Backtesting Step By Step (Ep. 21); Dead Markets; Back Testing A Forex Trading System (Ep. 47); Forex Drawdown (Ep. 52); Forex Automated Trading; Our Forex Technical Analysis
- [Forex Risk Management — The Definitive Guide](https://nononsenseforex.com/trade-management/forex-risk-management/)
- [Forex Money Management — Scaling Out Is A Must](https://nononsenseforex.com/trade-management/forex-money-management-scaling-out/)
- [Don't Split Your Risk (Ep. 72)](https://nononsenseforex.com/forex-q-and-a-podcast/dont-split-your-risk/)
- [Scaling In (Ep. 25)](https://nononsenseforex.com/forex-q-and-a-podcast/scaling-in/)
- [Forex News Trading](https://nononsenseforex.com/forex-basics/forex-news-trading/)
- [Other Time Frames Than The Daily (Ep. 30)](https://nononsenseforex.com/forex-q-and-a-podcast/other-time-frames/)

**Secondary (label B)**

- [No Nonsense FOREX Flow Charts](https://nononsensetrader.com/wp-content/uploads/2021/02/No-Nonsense-FOREX-Flow-Charts.pdf) (Rui Silva, "NNFX WAY — Developed by VP")
- [No Nonsense Trader — Trailing Stop](https://nononsensetrader.com/trailing-stop/), [Bridge Too Far](https://nononsensetrader.com/bridge-too-far/), [Lesson 9](https://nononsensetrader.com/lesson-9-basic-entry-rules/), [Lesson 11](https://nononsensetrader.com/lesson-11-continuation-trades/)
- [NNFX Algo Tester — Operation Modes](https://help.nnfxalgotester.com/knowledgebase.php?article=86)
- [backtestd — Algorithm Rules](https://github.com/stfl/backtestd-doc/blob/master/NNFX%20Algo/Algorithm%20Rules.org)

**Not reachable:** VP's YouTube videos (baseline, C2, trailing stop, continuation, one-candle) can't be read from here. They are the primary source for every B rule; if you have notes or transcripts, they would upgrade those rules to A.
