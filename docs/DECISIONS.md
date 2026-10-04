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
