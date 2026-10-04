# Rule fixtures

Hand-built candle sequences, one JSON file per case, each with its known right answer.
`build_fixtures.py` writes them; every expected answer in it was worked out by hand
from the rulebook. The Python answer key (Phase 3) and the MQL5 rules core (Phase 4)
run the same files.

Format: see `tests/python/nnfx_ref/fixtures.py`. Rebuild with
`python tests/fixtures/build_fixtures.py`.
