# Working rules

These rules apply to every change, whoever makes it.

## Process

1. **Approval first.** Nothing is built, changed or deleted without the owner's approval.
2. **Branch, then pull request, then merge.** Never push straight to `main`.
3. **Prove on one before scaling.** One pair, then a few, then a pilot, then everything.
4. **Additive changes.** Add new files and settings rather than rewriting working parts.
   Re-run every existing test after any change.

## Truth

1. **Facts are checked, never assumed.** Anything about MT5, the broker, or VP's rules
   carries its source. If it can't be verified, it is marked unverified.
2. **The rulebook is the source of truth for rules.** A rule change starts as an edit to
   `docs/RULEBOOK.md` with its source and label, plus a line in `docs/DECISIONS.md`.
3. **Trust data, not summaries.** "All tests pass" is not enough: read the actual
   decision logs and trade logs. Bugs in this kind of system are usually silent
   (wrong buffer, one-candle shift, warm-up values read as real).
4. **Every test run is recorded** in `results/`, including failed and invalid ones.
   Nothing is deleted.

## Trading safety

1. Every order carries a broker-held stop loss from the moment it is sent.
2. Risk is never rounded up. A trade that can't be sized within the risk limit is skipped.
3. No real-money use until the demo period in `docs/SPEC.md` has passed.

## Code

1. The rules core contains no MT5 trading calls, so it can be checked against the
   Python answer key line for line.
2. Indicators are configured in `profiles/`, never hardcoded.
3. MQL5 code is compiled in MetaEditor on the owner's PC. Code that has not been
   compiled there is labelled "not yet compiled".
