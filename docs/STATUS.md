# Status

Where the project stands. Update this file in every PR.

Last updated: 2026-10-04.

## Phases

| Phase | State |
| --- | --- |
| 1 Rulebook and spec | Living copies in Claude Docs; snapshots in `docs/` |
| 2 Repo setup | Merged |
| 3 Python answer key | Merged |
| 4 MQL5 rules core | Merged (PR #3) |
| 5 Indicator slots and profiles | Merged: PR #4 (at `58e2994`, before the G1_phase5_1 fixes; see note below) and PR #5 (the reviewed fixes, `0e701dd`) |
| 6 Orders, risk, recovery, guard, news, EA | Plan: gate G2 **PASS** (`G2_phase6_1`), `docs/PLAN_PHASE6.md`; owner decisions OD-1 to OD-21 in `docs/DECISIONS.md`. **6a sizing + exposure:** merged (PR #6, `G1_phase6a_1` PASS). **6b orders:** draft PR #7 from branch `phase-6b-orders`. Review `G1_phase6b_1`: CHANGES REQUESTED (F1-F5). F1 (ABORT, REFUSE stops level, REFUSE margin, MODIFY exercised in the tester), F4 (evidence never deleted) and F5 (BE via) done: run `20261004_164337` OVERALL PASS, planted bugs 15 of 15 and S4 7 of 7. F2 demo order run done (`demo_20261004_224606`, 5 trades, `check_trades.py` PASS; an earlier attempt failed with Algo Trading off and is kept in `checks\invalid\`). F3 (MT5-offline check) deferred to the 6f G1 gate (D6b-1). Re-run and packet `G1_phase6b_2` next. 6c may start on a branch from `phase-6b-orders`. 6d-6f not started |
| 7 onward | See `docs/SPEC.md` |

**Note (2026-10-04):** PR #4 was merged at `58e2994` on 2026-10-04 15:47 UTC, 4.5 minutes after review
G1_phase5_1 returned CHANGES REQUESTED and before its fixes. The fix commits `521013b`, `bb4c381` and `6c80511`
were pushed to the merged branch afterwards, so they did not reach `main`. This PR (branch `phase-5-fixes`)
brings them to `main` (merged 2026-10-04 as `0e701dd`). Guards against a repeat: `docs/REVIEW_PROTOCOL.md`, "Merge safety".

## Waiting on the owner

- Tick I-1, I-2, I-3, I-7, I-9 in the living rulebook doc; then refresh the `docs/RULEBOOK.md` snapshot.
- Review D5-1 to D5-5 (`docs/DECISIONS.md`).
- Choose the live broker (`docs/ENVIRONMENT.md`; MetaQuotes-Demo is not a retail broker).
- MT5-offline check (carry-over 1; G1_phase6b_1 F3): **deferred to the 6f G1 gate** (decision D6b-1): required
  before the real EA is accepted and before any demo forward-test. Then: add the firewall rule in
  `tools/run_offline_check.ps1` (admin PowerShell), run it with MT5 closed (plus the order-path part on a live chart),
  remove the rule.

## Answered by the Phase 5b runs (2026-10-04)

- MT5 runs scripts and the Strategy Tester from a `/config` file on this PC: **yes**
  (runs `20261004_113357` and `20261004_115428`; terminal log "successfully initialized from start config").
- The tester can read `Common\Files\NNFX\profiles`: **yes** (the repaint check loaded all 5 profiles and wrote its report).
- The Phase 5b changes to `NNFX_ExportBars.mq5` and `BarBuilder.mqh` compile with 0 errors, 0 warnings.
- Scripts started from `/config` can begin before MT5 has logged in (G1_phase5_1 F1). Scripts that read
  server data now wait for login (`MQL5/Include/NNFX/Connection.mqh`). The EnvCheck numbers from run
  `20261004_113357` were read before login and are not used.

## Do not use

Files in `C:\Users\Evision\Downloads` other than the phase bundles (`fix*.patch`,
`FIX*_FOR_AGENT.txt`, `FIX6_7_7b_SPEC.txt`, `MASTER_HANDOFF_NNFX.txt`, `POST_RESET_KICKOFF.txt`,
`NNFX_CANONICAL_RULEBOOK_source.txt`, `RULEBOOK_ADDENDUM_NEWS.txt`) were not produced by this
project's process and their origin is unverified. Do not apply them to this repo.
