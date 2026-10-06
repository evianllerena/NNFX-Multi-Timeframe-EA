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
