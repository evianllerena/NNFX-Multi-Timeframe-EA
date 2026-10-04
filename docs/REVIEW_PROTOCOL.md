# Review protocol

The local Claude Code (on the owner's PC) builds, compiles, runs and fixes.
A second Claude session (in the Claude app) reviews independently at each gate.
The owner approves plans and is the only one who merges.

## Gates: stop and wait for a verdict

| Gate | When |
| --- | --- |
| G1 Phase end | Every phase, before the owner merges its PR |
| G2 Plan | Before building Phase 6 (orders, risk) and the backtest shootout |
| G3 Result | Every backtest, shootout or timeframe result, before anything relies on it |

At a gate: write the packet, tell the owner "Ready for review: <packet folder>", and stop.
Do not start the next step until the verdict says PASS.

## Shared folder

`C:\Users\Evision\NNFX-Review\` (not in the repo). One subfolder per packet:
`<gate>_<phase>_<n>`, e.g. `G1_phase5_1`, `G1_phase5_2` after fixes.

## Packet contents

| File | Content |
| --- | --- |
| `PACKET.md` | Gate, phase, branch, commit hash, PR number, date; what changed (one line per file); the claims list (below); anything not done or not verified |
| `claims` (in PACKET.md) | Numbered. Each claim names its evidence file and the exact line to look for, e.g. "C3: NNFX_SignalTest 56/56 - `NNFX_SignalTest.txt`, line `RESULT: 56 passed, 0 failed, 56 total`" |
| `diff.patch` | `git diff main...<branch>` |
| `evidence\` | Every report, compile log, Python output and summary the claims cite, copied unedited. Large raw files (exports, trade logs) may stay where MT5 wrote them; give the full path instead |
| `planted_bugs.md` | For any new checker: the deliberate bugs planted and whether each was caught |

Rules for the packet:
- Copy outputs unedited. Never retype a number.
- A failed or invalid run is included, not left out.
- Evidence is never deleted (G1_phase6b_1 F4; CONTRIBUTING "Nothing is deleted"). A failed or invalid run's raw
  output is moved, unedited, to an `invalid\` subfolder, with a `REASON.txt` of one line saying why it is invalid,
  before anything is re-run. Re-runs write to a new folder; they never overwrite.
- If something was not run, say so in PACKET.md.

## Verdict

The reviewer writes `VERDICT.md` in the same subfolder:

- `PASS`, or `CHANGES REQUESTED` with numbered findings `F1, F2, ...`, each with what is wrong,
  the evidence, and what would settle it.
- The reviewer recomputes what it can from raw data with its own code and says which claims
  it checked independently and which it could only read.

## Applying a verdict

When the owner says "apply review":
1. Read `VERDICT.md`. Do not change anything a finding does not cover.
2. Answer every finding in `RESPONSE.md` in the same subfolder: fixed (how, which commit)
   or not fixed (why, with evidence).
3. Re-run every test and check, then write a new packet (`_n+1`) and stop again.

The owner may override a finding; that is recorded in `docs/DECISIONS.md`.

## Merge safety

Added 2026-10-04 after PR #4 was merged before its review fixes
(`C:\Users\Evision\NNFX-Review\G1_phase5_2\AUDIT_main_merge.md`).

- Every PR is opened with `gh pr create --draft`. It is marked ready (`gh pr ready <n>`) only after
  `VERDICT.md` says PASS and names the head commit.
- The owner merges only when the verdict says "MERGE OK <7-char commit>" and the PR page shows that
  same latest commit.
- Every `PACKET.md` includes, pasted unedited in `evidence\github_state.txt`, the output of
  `git fetch origin`, `git rev-parse origin/main <branch>` and
  `gh pr view <n> --json state,isDraft,mergedAt,headRefOid`, all run when the packet is written.
  No statement about GitHub without it.
- One branch per PR; never push to a branch whose PR is merged.

## Unchanged

Approval before building; branch and PR; never push to `main`; only the owner merges;
every result in `docs/VERIFICATION.md`; facts labelled with their source (CONTRIBUTING.md).
