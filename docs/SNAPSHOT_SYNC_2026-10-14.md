# Snapshot sync list (2026-10-14)

`docs/SPEC.md` and `docs/RULEBOOK.md` are snapshots of the owner's living Claude Docs (CLAUDE.md). The review of
2026-10-13 (C2, C3; checked in `docs/REVIEW_OPUS_2026-10-14.md`) found text in them that approved decisions have
overtaken. Nothing below was changed in either snapshot: the owner applies it to the living documents first, then the
snapshots are refreshed from them (the sync step the review's D3 asks for). Each line gives the place, what it says,
and what the approved decision says.

## C2: SPEC text older than its decisions

| Place (`docs/SPEC.md`) | Says | Approved since | Suggested text |
| --- | --- | --- | --- |
| News filter table, N1 row (line ~166) | "No new trade on a pair if either of its currencies has one of VP's events within the next 24 hours" | **D6e-3** (2026-10-06): the block runs from the EARLIER of 15:00 New York on the previous trading day and 24 h before the event, until the 17:00 New York close that ends the news day; an event exactly at a candle close is inside | "No new trade on a pair with that currency from the earlier of 15:00 New York the previous trading day and 24 h before the event, until the 17:00 New York close ending the news day (D6e-3)" |
| News filter table, X5 row | "At the first candle close inside that 24-hour window" | D6e-3: X5 applies at the first candle close **inside the block** | "At the first candle close inside the N1 block" |
| Settings table, News block row (line ~63) | "On, 24 h" | D6e-3 | "On (D6e-3 block)" |
| Candle timing, line ~35 and Settings line ~64: rollover block "15 min before to 60 min after the daily close"; line ~40 "Daily close time is a setting" | the daily close as a broker setting | **OD-3 update** (2026-10-06): one trading-day boundary = **17:00 New York**, converted per broker; never "server midnight" | "15 min before to 60 min after 17:00 New York (the real rollover; OD-3 update), converted to the broker's server time" |

## C3: "decision #n" is ambiguous

RULEBOOK decisions #1-#15 are `R-1`-`R-15` in DECISIONS.md; SPEC decisions #1-#10 are `S-1`-`S-10`. Inline "#n"
cannot say which list it means. Suggested replacements in `docs/SPEC.md`:

| Line | Now | Means | Write |
| --- | --- | --- | --- |
| ~28 | decision #3 | rulebook #3 (act on the first tick of the new candle) | R-3 |
| ~35 | decision #10 | rulebook #10 (rollover window) | R-10 |
| ~52 | decision #14 | rulebook #14 (risk 2%) | R-14 |
| ~56, ~57 | #1 | rulebook #1 (trailing stop) | R-1 |
| ~58 | #11 | rulebook #11 (runner cap) | R-11 |
| ~59 | #2 | rulebook #2 (exits) | R-2 |
| ~60 | #4 | rulebook #4 (one-candle rule) | R-4 |
| ~61 | #5 | rulebook #5 (bridge too far) | R-5 |
| ~62 | #6-#7 | rulebook #6, #7 (continuation) | R-6, R-7 |
| ~63 | #9 | rulebook #9 (news) | R-9 |
| ~64 | #10 | rulebook #10 (rollover) | R-10 |
| ~67 | #12 | rulebook #12 (drawdown pause) | R-12 |
| ~245 (V8) | decision #8 | **SPEC** #8 (minimum sample) | S-8 |

Also open from the review: D3 (no sync since 2026-10-03). Proposed habit: every PR that changes a decision lists the
living-document edits it needs in its description; the snapshot is refreshed in the same PR once the owner has made them.
