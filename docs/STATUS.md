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
| 5 Indicator slots and profiles | PR #4 open, branch `phase-5-slots-profiles`. Gate G1: `G1_phase5_1` returned CHANGES REQUESTED (F1-F5); fixes applied, `tools/run_phase5_checks.ps1` OVERALL PASS on the fixes (run `20261004_115428`, `docs/VERIFICATION.md`). **Next:** final run on the PR's last commit, then packet `G1_phase5_2` for review |
| 6 Orders, risk, recovery, guard, calendar export | Not started. Needs owner approval, then gate G2 plan review |
| 7 onward | See `docs/SPEC.md` |

## Waiting on the owner

- Tick I-1, I-2, I-3, I-7, I-9 in the living rulebook doc; then refresh the `docs/RULEBOOK.md` snapshot.
- Review D5-1 to D5-5 (`docs/DECISIONS.md`).
- Choose the live broker (`docs/ENVIRONMENT.md`; MetaQuotes-Demo is not a retail broker).

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
