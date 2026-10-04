# Python answer key

An independent Python version of the rulebook. In later phases the MQL5 EA must make
exactly the same decisions as this code, candle by candle (`docs/SPEC.md`, Check 1).
Standard library only: no packages to install.

## Run the tests

From the repo root (Python 3.8 or newer):

```
python -m unittest discover -s tests/python -v
```

To rebuild the rule cases after editing `tests/fixtures/build_fixtures.py`:

```
python tests/fixtures/build_fixtures.py
```

## What is here

| File | What it does |
| --- | --- |
| `nnfx_ref/settings.py` | Every rule setting with its approved default |
| `nnfx_ref/signals.py` | Turns indicator values into long / short / none; bad values never become signals |
| `nnfx_ref/core.py` | The rules engine for one pair: entries E0-E6, exits X1-X5, trade management T1-T7 |
| `nnfx_ref/sizing.py` | Lot size from 2% of balance and the stop distance; never rounds risk up |
| `nnfx_ref/exposure.py` | Same-currency check (M6, M7) |
| `nnfx_ref/fixtures.py` | Loads and runs the JSON rule cases |
| `test_fixtures.py` | Runs every rule case; checks every required rule has a "fires" and a "must not fire" case |
| `test_units.py` | Signals, sizing, exposure and settings |

## How the tests were checked (not just "they pass")

1. Every expected answer in `tests/fixtures/build_fixtures.py` was worked out by hand from the
   rulebook, before running the engine.
2. Full event traces were read for key cases (trailing stop prices, R results, continuation).
3. **Planted-bug check:** 10 deliberate bugs were put into a copy of the engine, one at a time.
   The first run caught 9. The missed one (a close exactly on the baseline treated as a
   baseline exit) exposed a gap in the cases; a case was added, and all 10 are now caught.

## Interpretations (pending owner approval)

The rulebook says *what* each rule does; code needs it exact. Each point below is my
interpretation, listed so it can be checked. They are also in `docs/DECISIONS.md` (I-1 to I-14, plus a checker note), with their approval status.

| ID | Interpretation | Rule |
| --- | --- | --- |
| I-1 | Decisions are made at a candle's close and acted on at the next candle's open. The first candle is warm-up: no signal can be "fresh" on it | E0, R-3 |
| I-2 | A signal is "fresh" when its direction differs from the previous candle's. A baseline cross is a close on one side after a close on the other side or exactly on the line | E1, E2, R-8 |
| I-3 | If price crosses the baseline and C1 turns on the same candle, it is a baseline entry (E2) with C1 age 0 | E1, E2 |
| I-4 | Bridge too far counts the consecutive candles C1 was already in the trade's direction before the cross candle; 7 or more = skip. Applies to baseline entries (E2) only | E5, R-5 |
| I-5 | Pullback (E3) applies when everything agrees except distance. Next candle: price on the right side and within 1 ATR, and C1, C2 and volume all still agree | E3 |
| I-6 | One-candle rule (E4) applies when exactly one item lags (C2, volume, C1 for a baseline entry, or the baseline side for a C1 entry) and price is within 1 ATR. Next candle: everything must agree and price within 1 ATR. Distance plus one lagging item = skip | E4, R-4 |
| I-7 | When a waiting trade expires, a new signal on that same candle is still evaluated | E3, E4 |
| I-8 | The exit indicator exits when it *reads* against the trade at a close (not only on the candle it flips). Based on Lesson 11's description of an exit indicator "still saying exit" | X2 |
| I-9 | If several exits fire on one close, the trade closes once, at the next open; the logged reason is the first of X5, X2, X3, X4 | X2-X5 |
| I-10 | News exit (X5) is checked at the first candle close inside the 24-hour window; profit is measured close vs entry against 1 × the current ATR | X5 |
| I-11 | Trailing starts only after TP1. The switch-on distance uses the ATR at entry; the trailing distance uses the latest closed candle's ATR | T4 |
| I-12 | Continuation is armed only by a standard entry (E1-E4) and needs the previous trade to have been in the same direction. It is disarmed by a close on the other side of the baseline. Version (a) is also disarmed once C1 reads against the trend at any close after the original entry. Continuations can repeat | E6 |
| I-13 | Version (a) fires on a fresh C2 signal in the trend direction. Version (b) fires on a fresh exit-indicator signal in the trend direction with C1 and C2 agreeing | E6, R-6 |
| I-14 | One trade per candle per pair. A regular entry that can open beats a continuation; if the regular entry is refused or only waiting, the continuation is checked and can open (the regular signal is then logged as SKIP "continuation taken instead") | E6 |
| note | Candle-only fill assumptions (answer key only; not a trading rule; real fills come from MT5): stop and target in one candle = stop first; after TP1 fills, the breakeven stop is checked from the next candle; a stop gapped through fills at the open | M3, T1, T2 |

## Not in the core (and where it lives instead)

| Rule | Where |
| --- | --- |
| News block N1, rollover, weekend, drawdown pause, daily loss, same-currency block | Decided outside the core and passed in as a "blocked" list per candle (Phase 6 guard) |
| Dead markets (T6, D1, D2) | Needs a volatility gauge (VP used EVZ); not built yet |
| Sizing and exposure | `sizing.py`, `exposure.py` (separate from the per-pair core) |
