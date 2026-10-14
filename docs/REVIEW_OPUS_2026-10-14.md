# Independent review of 2026-10-13: claims checked against the code

The brief `OPUS_REVIEW_BRIEF.md` (owner's PC, repo root, not committed) listed findings by four reviewers on
`phase-6f-ea`. Each claim was checked against the code at `bcb5f31` on 2026-10-14 (code reading, label C).
Verdicts: **CONFIRMED**, **PARTLY** (part of the claim is wrong), **NOT CONFIRMED**, **PLATFORM** (needs a
live broker to settle), **DECIDED** (fixing it would reopen an approved decision).

## Found in this check, not in the brief

| ID | Finding | Evidence |
| --- | --- | --- |
| N-1 | `InpTrailOn=false` turned off the core's trail only: `Orders.mqh` never received the setting and trailed half 2 at the broker anyway | `NNFX_EA.mq5` Init calls (no trail_on); `Orders.mqh` `OnBarClose` unconditional. **Fixed in PR review-fixes-1** |
| N-2 | A stall of more than 300 candles skips the oldest candles without a log row (`ClosedSince` caps at 300), unlike Start's too-old check | `NNFX_EA.mq5` ~497, ~814 |

## Section A

| ID | Verdict | Notes (corrections to the brief) |
| --- | --- | --- |
| A1 | CONFIRMED | BE is tried once (`Orders.mqh` Poll TP1 branch). Correction: the trail still takes over once a close is 2 ATR beyond entry; until then half 2 keeps the 1.5 ATR stop, and the core (which always simulates BE) and the broker disagree silently |
| A2 | CONFIRMED (latent) | `State.mqh` ~684 hardcodes `2.0`; `trail_active` is parsed, never used. `recovery.py` has the same constant (lockstep). All presets use 2.0. With start > 2 the rebuild can switch the trail on early |
| A3 | CONFIRMED | `NNFX_EA.mq5` ~593 `from = now - 30 days`, hardcoded. Effect: lost trailing (not doubled risk); an IN deal outside the window leaves an orphan position (no BE/trail, a core EXIT cannot close it, a new entry on the pair is allowed). Tester uses `from = 0`, so no tester test covers it |
| A4 | PARTLY | `entries[2]` uninitialised: real. It could not drive BE or the trail (both need half 2's position); it reached log rows and possibly the state file. **Fixed in PR review-fixes-1** |
| A5 | PLATFORM, race worse than stated | The duplicate check runs BEFORE the 1 s sleep and the re-send has no second check; open orders are never checked |
| A6 | PARTLY | Exact comment match only weakens the retry duplicate guard. Reconcile matches by position id; rebuild pairing uses comment, then state file, and the same-second fallback only without a state file. Comments are ~21 chars |
| A7 | CONFIRMED | No margin-mode check; contradicts `SPEC.md` line 92. **Fixed in PR review-fixes-1** |
| A8 | PARTLY | Tick read unchecked: real. Core-exit closes are re-tried once per candle by D6f-1; stopless closes every tick. Gap: a failed ABORT close is never retried |
| A9 | NOT CONFIRMED as stated | Both callers wait for a connection first. Residual: an export after a mid-session disconnect |
| A10 | PARTLY | ATR 0 passed `Raw`: real. `Orders.mqh` already refuses ATR <= 0, so no order could go out; only E6 could fire in the core (inf R). Fix belongs in `BarBuilder`, not `NNFXIsBad` (0 is a real oscillator value). `check_export.py` already failed an ok row with ATR <= 0. **Fixed in PR review-fixes-1** |
| A11 | PARTLY | MessageBox blocks this instance only, with the owner at the screen. The Instance toggle's missing confirm is by design (SPEC line 140) |

## Section B

| ID | Verdict | Notes |
| --- | --- | --- |
| B1 | PARTLY | Only "EUR/USD"-style symbols; `.pro` suffixes parse correctly. `news.py` is positional too (lockstep) |
| B2 | CONFIRMED | Low likelihood |
| B3 | CONFIRMED | **Fixed in PR review-fixes-1** |
| B4 | PARTLY | TP2 not checked against the stops level: real. cap <= tp1 does not by itself force an ABORT |
| B5 | PARTLY | Compacted at every restart; per-tick cost negligible |
| B6 | CONFIRMED, DECIDED | GV names set by D6d-1 / D6d-3: renaming needs the owner |
| B7 | CONFIRMED, DECIDED | Exactly D6d-2's approved definition |
| B8 | CONFIRMED (cosmetic) | ~1e-10 relative; lockstep with `recovery.py` and fixtures |
| B9 | CONFIRMED (low) | The path is already per magic; PCORE matches by symbol only |
| B10 | PARTLY | Only `last_exit_dir` could be wrong, and the 6f EA discards rebuilt conts |
| B11 | CONFIRMED (harmless today) | Used only by `NNFX_RulesTest` |
| B12 | PARTLY | Deliberate (`RulesCore.mqh` ~513), but no decision row records the risk |
| B13 | PARTLY | `buf_other == buf_main` accepted: real. A bad buffer index fails closed and visibly (EA never starts) |
| B14 | NOT CONFIRMED for 6f | The 6f EA discards rebuilt conts; affects the 6c test EA only |
| B15 | CONFIRMED | Contradicts DESIGN_6F ("run hourly") and D6f-3 |
| B16 | CONFIRMED | Plus N-2 above |
| B17 | PARTLY DOCUMENTED | In `core.py` and DECISIONS; not in VERIFICATION.md |
| B18 | CONFIRMED | D5-4 covers "never fed", not this consequence |
| B19 | CONFIRMED (minor) | Also: OUT_BY is never matched, so a manual close-by leaves the half "open" in memory |

## Sections C to E

| ID | Verdict | Notes |
| --- | --- | --- |
| C1 | CONFIRMED | Only the PLAN_PHASE6 section 11 table (line ~738) is stale |
| C2 | CONFIRMED (news), PARTLY (rollover) | Rollover text is outdated, not contradictory |
| C3 | CONFIRMED | e.g. SPEC "decision #3" means rulebook #3, "decision #8" means SPEC #8 |
| C4 | CONFIRMED | No blanket approval recorded |
| C5 | PARTLY | Deferred in PLAN_PHASE6 (~777) and tests README, but no DECISIONS row |
| C6 | CONFIRMED | |
| C7 | PARTLY | E6(b) tightening unlabelled: confirmed. E6(a) "no volume filter" is what the rulebook asks |
| C8 | CONFIRMED | Also STATUS line 16's last sentence is stale |
| D1 | CONFIRMED | No `.github/`, no branch protection |
| D3 | PARTLY | A sync rule exists (on living-doc change), not followed since 2026-10-03 |
| E1 | CONFIRMED | SE at n=30: 0.27-0.37R for sd 1.5-2R |
| E2 | CONFIRMED | V7 screens on the forward window, stage 3 ranks on it again |
| E3 | CONFIRMED | Simple simulation (label C: 100 trades, 2% risk, 40-45% wins at 1.5-2R, -1R losses): P(maxDD > 10%) 0.86-0.99 |
| E4 | PARTLY | Broker undecided: confirmed. MetaQuotes-Demo swaps are not zero (ENVIRONMENT.md); commission is |
| E (V-checks) | CONFIRMED | No portfolio-risk check across instances; V5 is latency only |

No Phase 8 plan exists yet beyond the SPEC outline; its G2 gate has not happened.
