# Rule fixtures

Hand-built candle sequences, one JSON file per case, each with its known right answer.
`build_fixtures.py` writes them; every expected answer in it was worked out by hand
from the rulebook. The Python answer key (Phase 3) and the MQL5 rules core (Phase 4)
run the same files.

Format: see `tests/python/nnfx_ref/fixtures.py`. Rebuild with
`python tests/fixtures/build_fixtures.py`.

## Phase 5 additions

- `signals/signal_cases.txt`: raw indicator values -> expected direction or volume pass
  (37 cases, including NaN, infinity and EMPTY_VALUE). Run by `test_profiles.py` and `NNFX_SignalTest.mq5`.
- `profiles_bad/`: 14 invalid profiles that both the Python and MQL5 readers must reject.

## Phase 6a additions

- `sizing/sizing_cases.txt`: 20 cases (10 sizings, 5 rejected inputs, 5 tick-value choices for OD-6).
- `exposure/exposure_cases.txt`: 22 cases (15 allocations in modes first/split, 7 symbol readings incl. non-FX).
- Every answer is worked out by hand in the file's comments. Run by `test_sizing_exposure_fixtures.py` and
  `NNFX_SizingTest.mq5`.

## Phase 6b additions

- `orders/order_cases.txt`: 28 cases: 8 price plans (OP), 3 rejected inputs (OE), 8 trail steps (TR), 3 stop
  distances (SD), 6 safety decisions (SF). Run by `test_orders.py`, `NNFX_OrderMathTest.mq5` (OP/OE/TR/SD) and
  `NNFX_SafetyTest.mq5` (SF).
- G1_phase6a_1 verdict note 2: `sizing_cases.txt` gains 3 cases (minimum lot and volume cap with lot step 0.1),
  `exposure_cases.txt` 1 (a second OD-4 case); now 23 + 23 cases.

## Phase 6c additions

- `recovery/recovery_cases.txt`: 22 restart-rebuild cases (broker positions, deals, the state file's trades,
  candles -> the expected TRADE and CONT lines). They cover R1-R4, a deleted state file, comments ignored or changed
  by the broker, a corrupt or stale state file, fallback pairing after an ABORT, TP1 from the deal reason (not the
  comment), and other magics ignored. Every expected line is worked out by hand in the file's comments.
- `recovery/state_files/`: 5 state files (2 valid, 3 corrupt: a changed byte, truncated, wrong version) and
  `index.txt` with each expected reading.
- Run by `test_recovery.py` (answer key `nnfx_ref/recovery.py`) and `NNFX_RecoveryTest.mq5`.
- Deviation from `docs/PLAN_PHASE6.md`: the plan said JSON. These are line-based `.txt` files, like every fixture
  since Phase 5, because MQL5 reads them without a JSON parser.
- G1_phase6c_1 F3: `fallback_pairing_after_abort` now expects the logged fallback IDs
  (`fallback id R31 = positions 31+32`, `fallback id R21 = position 21`).

## Phase 6d additions

- `guard/guard_cases.txt`: 56 cases.
  - 20 trading-day boundaries (17:00 New York in server time, OD-3 update) for two broker clock rules (EU, US).
    They include days in the weeks where US and EU daylight saving differ, in 2026 and 2027, and each change day.
  - 14 rollover windows, 7 weekend blocks, 6 daily-loss days (D6d-2), 3 drawdown series (manual reset, D6d-3) and
    6 block strings (D6d-1: a missing master switch counts as OFF).
  - Every expected value is worked out by hand in the file's comments.
  - Run by `test_guard.py` (answer key `nnfx_ref/guard.py`) and `NNFX_GuardTest.mq5`.
- The broker clock rules in the file are settings, not verified facts (D6d-4: to be checked after 25 Oct and 1 Nov).

## Phase 6e additions

- `news/news_cases.txt`: 13 event-matching cases (incl. a new Fed chair and a new ECB president caught by the role
  pattern only), 13 N1 cases (window edges, quote currency, two events close together, N2 blackout), 14 X5 cases (the
  first close inside each window, 30M/1H/4H, two events close together, the weekend), and 4 UTC-to-server cases.
  Every expected value is worked out by hand in the comments. Run by `test_news.py` and `NNFX_NewsTest.mq5`. The
  event list is the approved `news/news_events.txt` (D6e-1).
- `news/calendar_catalogue_20261006.csv`: the calendar's own event list (1051 events) the mapping was made from.
- G1_phase6e_1 F1 / D6e-3: the N1 and X5 cases now follow the owner's news block (25 N1, 16 X5 cases, worked out by
  hand in New York time with the MetaQuotes clock rule): a Friday NFP from Thu 08:30 NY to the Fri 17:00 close on
  30M/1H/4H, an event at its own candle close, the Fed at a 1H close, an overnight AUD release, a Monday release from
  Fri 15:00 NY, trading resuming at the close.
