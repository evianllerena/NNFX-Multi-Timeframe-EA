# Notes for Claude sessions on this repo

Read before doing anything:

1. `CONTRIBUTING.md`: the working rules. Above all: nothing is built or changed without the
   owner's approval; branch, then PR; never push to `main`; never state an unverified fact as true.
2. `docs/RULEBOOK.md`: what the EA does. Rule IDs (M1, T4, E6, X3, N1, R1...) are used everywhere.
3. `docs/SPEC.md`: how it runs on 30M / 1H / 4H, and the verification plan (Checks 1-4, V1-V14).
4. `docs/DECISIONS.md`: what has been decided and when. Do not reopen a decision without saying so.

The living copies of the rulebook and spec are Claude Docs owned by the repo owner;
the files in `docs/` are snapshots. If they disagree, ask which is current.

Label every rule-related statement A (VP's own words), B (secondary source) or C (no source).

## Review gates (owner's standing instruction)

5. `docs/STATUS.md`: where the project stands. Read it at the start of every session; update it in every PR.
6. `docs/REVIEW_PROTOCOL.md`: a second Claude session reviews independently. At every gate
   (phase end, the Phase 6 and shootout plans, every backtest result) write a review packet to
   `C:\Users\Evision\NNFX-Review\`, tell the owner, and **stop until the verdict is PASS**.
   Never merge; only the owner merges.
