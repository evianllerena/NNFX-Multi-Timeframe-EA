# Status

Where the project stands. Update this file in every PR.

Last updated: 2026-10-09.

## Phases

| Phase | State |
| --- | --- |
| 1 Rulebook and spec | Living copies in Claude Docs; snapshots in `docs/` |
| 2 Repo setup | Merged |
| 3 Python answer key | Merged |
| 4 MQL5 rules core | Merged (PR #3) |
| 5 Indicator slots and profiles | Merged: PR #4 (at `58e2994`, before the G1_phase5_1 fixes; see note below) and PR #5 (the reviewed fixes, `0e701dd`) |
| 6 Orders, risk, recovery, guard, news, EA | Plan: gate G2 **PASS** (`G2_phase6_1`), `docs/PLAN_PHASE6.md`; owner decisions OD-1 to OD-21 (OD-3 updated), D6c-1 to D6c-3, D6d-1 to D6d-4 and D-OPS-1 in `docs/DECISIONS.md`. **6a** merged (PR #6). **6b** merged (PR #7). **6c state and recovery** merged (PR #8, `G1_phase6c_2` PASS, merge `016bc3f`). **6d guard:** merged (PR #9, `G1_phase6d_1` PASS, merge `0e542f2`); daily loss account-wide (D6d-5). **6e news:** merged (PR #10, `G1_phase6e_2` PASS, merge `49ddad5`). **6f the EA:** branch `phase-6f-ea` (draft PR #11). Done and passing on d80dd0e: runner `20261006_224137`, planted bugs 12 of 12, two identical 4-month runs, presets, both restart tests, demo crash tests (TP1, pause). The first 1H demo smoke test (from 2026-10-06 22:57) was cut by a PC power loss after 24.0 h (logs PASS up to the cut; in `invalid\`); the EA's restart after that hard stop restored its memory and closed nothing (`demo_ea_powercut_restart_20261007_234154`). The 1H demo smoke test from the start passed (26 h, `demo_ea_smoke_20261008_000411`, `OVERALL: PASS`; its start-up exercised D6f-2 on the open AUDNZD trade). The MT5-offline check (D6b-1) passed on 2026-10-09 with the owner's firewall rule (runner part `20261009_104221`, EA part `demo_ea_offline_20261009_103426`; rule removed). Next, with the owner: the chart buttons clicked by hand; then packet G1_phase6f_1. The MT5-offline check is deferred to the 6f G1 gate (D6b-1).  |
| 7 onward | See `docs/SPEC.md` |

**Note (2026-10-04):** PR #4 was merged at `58e2994` on 2026-10-04 15:47 UTC, 4.5 minutes after review
G1_phase5_1 returned CHANGES REQUESTED and before its fixes. The fix commits `521013b`, `bb4c381` and `6c80511`
were pushed to the merged branch afterwards, so they did not reach `main`. This PR (branch `phase-5-fixes`)
brings them to `main` (merged 2026-10-04 as `0e701dd`). Guards against a repeat: `docs/REVIEW_PROTOCOL.md`, "Merge safety".

## OANDA TMS (candidate live broker, D6c-2)

Read-only EnvCheck on demo 62316800 (`docs/ENVIRONMENT.md`): hedging, EUR account, server GMT+2. Open points:
- **Symbol class: settled. The EA uses the `.pro` symbols on OANDA TMS.** Plain EURUSD/EURGBP are trade mode
  DISABLED (server path `Forex\...`, fixed 2400-point spread, no swaps). `EURUSD.pro` / `EURGBP.pro` are trade mode
  FULL (`PRO\FX\Major\...`, spread 8 at 06:32 server). Re-run `oanda_envcheck_pro_20261006_003214`, read-only.
- **Rollover:** 17:00 New York = 23:00 server on OANDA (D1 opens 00:00 server = 18:00 New York); the 6d rollover block
  is keyed to the real rollover per broker, never to server midnight (`docs/PLAN_PHASE6.md` 6d).
- **Phase 8 input:** real ticks on the `.pro` pairs from 2019 (EURUSD.pro from 2018) in the probe.

## Waiting on the owner

- **After 25 Oct and after 1 Nov 2026 (D6d-4):** the reviewer checks each broker's server time against GMT, to
  confirm the clock-change rules assumed in `tests/fixtures/guard/guard_cases.txt`: OANDA TMS GMT+1 in winter on the
  EU rule, MetaQuotes-Demo GMT+2 in winter on the US rule. Until then they are settings, not facts.
- Tick I-1, I-2, I-3, I-7, I-9 in the living rulebook doc; then refresh the `docs/RULEBOOK.md` snapshot.
- Review D5-1 to D5-5 (`docs/DECISIONS.md`).
- Choose the live broker (`docs/ENVIRONMENT.md`; MetaQuotes-Demo is not a retail broker).
- MT5-offline check (carry-over 1; G1_phase6b_1 F3, D6b-1): **done 2026-10-09**, both parts PASS (`docs/VERIFICATION.md`);
  the firewall rule was added and removed through admin prompts the owner approved.

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
