# Changelog

Newest first.

## 2026-10-04 — Phase 6a: sizing and exposure

- `docs/PLAN_PHASE6.md`: the Phase 6 plan (gate G2 PASS) with the verdict's edits F1-F4; `docs/DECISIONS.md`:
  owner decisions OD-1 to OD-21.
- `MQL5/Include/NNFX/Sizing.mqh`, `Exposure.mqh`: MQL5 ports of `sizing.py` and `exposure.py`. No orders.
- `tests/fixtures/sizing/`, `tests/fixtures/exposure/`: 42 shared cases with hand-worked answers;
  `tests/python/test_sizing_exposure_fixtures.py`; `MQL5/Scripts/NNFX/NNFX_SizingTest.mq5` (42/42 in MT5).
- `nnfx_ref`: `exposure.is_fx` and non-FX handling (OD-21); `sizing.tick_value_for_sizing` (OD-6).
- Runner: SizingTest added; `-PythonOnly`. `tools/run_offline_check.ps1` (carry-over 1): no-Python path PASS;
  MT5-offline path waits for the owner's firewall rule.
- Planted-bug check on the MQL5 ports: 12 of 12 caught. 50 Python tests pass.

## 2026-10-04 — Phase 5: review G1_phase5_1 fixes

- F1: `MQL5/Include/NNFX/Connection.mqh` (new). `NNFX_EnvCheck` and `NNFX_ExportBars` wait until MT5
  is connected, logged in and has a tick value above 0 for every pair before reading anything;
  otherwise they write `RESULT: INVALID (not connected)`, which the runner counts as FAIL. The earlier
  EnvCheck numbers (run `20261004_113357`) were read before login and are not used.
- F2: `docs/STATUS.md`, `docs/VERIFICATION.md`, `docs/ENVIRONMENT.md`, `tools/README.md`,
  `tests/mql5/README.md`, `MQL5/Include/NNFX/README.md` and file headers brought in line with the runs.
- F3: independent planted-bug check of `tools/check_indicators.py` on the owner PC: 14 of 14 caught.
- F4: `tools/run_phase5_checks.ps1` finds a working Python itself, prints it in `SUMMARY.txt`, and
  writes Python's stderr without PowerShell's `NativeCommandError` wrapper.
- `tools/run_phase5_checks.ps1` run `20261004_115428`: OVERALL PASS. 46 Python tests pass.

## 2026-10-04 — Phase 5b: automated verification

- `tools/run_phase5_checks.ps1`: one command runs every Phase 5 check with MT5 closed: copy, compile
  (must be 0 errors, 0 warnings), each script through MT5's `/config` start-up file, the repaint
  check in the Strategy Tester, and the Python checks. Writes `SUMMARY.txt` and keeps every report
  and log in `MQL5\Files\NNFX\checks\<date-time>\`. **Not yet run.**
- `tools/check_indicators.py` + 6 tests: recalculates ATR, SMA, RVI, MACD and tick volume from the
  export using MT5's own source formulas. Replaces the by-eye Data Window check.
- `NNFX_ExportBars`: makes MT5 download enough history first, waits until every indicator has
  calculated, adds a `tickvol` column and writes `_summary.txt`. `BarBuilder.AllCalculated()` added.
- All scripts: no input dialog (so nothing waits for a click in an unattended run).
- `docs/VERIFICATION.md`: Phase 5 results; `docs/ENVIRONMENT.md`: first NNFX_EnvCheck facts.
- 46 Python tests pass.
- Working method: `docs/REVIEW_PROTOCOL.md` (local Claude Code builds and runs; a second Claude
  session reviews at each gate), `docs/STATUS.md`, and a pointer to both in `CLAUDE.md`.

## 2026-10-04 — Phase 5: indicator slots and profiles

- `profiles/`: profile format (README) and five reference profiles built from MT5 standard
  indicators (20 SMA, RVI 10, MACD main vs 0, MACD cross, tick volume vs 20-candle average).
  Pipeline references only, not chosen for performance.
- `MQL5/Include/NNFX/`: `Signals.mqh`, `Profile.mqh`, `Slot.mqh`, `BarBuilder.mqh`. **Not yet compiled.**
- `MQL5/Scripts/NNFX/NNFX_SignalTest.mq5`, `NNFX_ExportBars.mq5`; `MQL5/Experts/NNFX/NNFX_RepaintCheck.mq5`
  (Strategy Tester only, no trading). **Not yet compiled.**
- `tests/python/nnfx_ref/profiles.py` + `test_profiles.py`, `tests/fixtures/signals/signal_cases.txt` (37 cases),
  `tests/fixtures/profiles_bad/` (14 profiles that must be rejected), `tools/check_export.py` + tests.
  40 Python tests pass; planted-bug check 9 of 9 caught.
- `docs/VERIFICATION.md`: verification log, starting with the Phase 3 and 4 results.
- Phase 4 file headers now record the compile and 47/47 result.

## 2026-10-03 — Phase 4: MQL5 rules core

- `MQL5/Include/NNFX/Settings.mqh`, `RulesCore.mqh`: the rules core in MQL5, a function-for-function
  port of the Python answer key. No trading or indicator calls. **Not yet compiled.**
- `MQL5/Scripts/NNFX/NNFX_RulesTest.mq5`: runs all rule cases in MT5 and writes a pass/fail report.
  **Not yet compiled.**
- `tests/fixtures/mql5/`: the same 45 rule cases in a line format MQL5 can read;
  `tests/python/test_fixture_formats.py` proves they match the JSON exactly.
- Pass line: 47 of 47 in MT5, the same as Python.
- I-14 fix (owner-approved): if a regular entry is refused or only waiting, the continuation is
  still checked. Changed in both `core.py` and `RulesCore.mqh`; two new fixtures (47 total).
- Interpretations reviewed: I-4, 5, 6, 8, 10, 11, 12, 13, 14 approved; I-1, 2, 3, 7, 9 reworded
  for intraday and awaiting a tick; the old I-15 is now a checker note.
- `docs/RULEBOOK.md` snapshot is behind the living doc; it will be refreshed once I-1, 2, 3, 7, 9 are ticked.

## 2026-10-03 — Phase 3: Python answer key

- `tests/python/nnfx_ref/`: rules engine (E0-E6, X1-X5, T1-T7), signals, sizing, exposure, settings.
- `tests/fixtures/`: 45 hand-built rule cases (JSON) plus the generator that writes them;
  the same JSON files will drive the MQL5 tests in Phase 4.
- `tests/python/test_fixtures.py`, `test_units.py`: 27 tests, all passing. A planted-bug check
  (10 deliberate bugs) caught all 10 after one missing case was added.
- `docs/DECISIONS.md`: interpretations I-1 to I-15, pending owner approval.
- No MT5 or trading code.

## 2026-10-03 — Phase 2: repo setup

- Folder structure for the EA, profiles, tests, tools and results.
- `docs/RULEBOOK.md` and `docs/SPEC.md`: snapshots of the approved Claude Docs.
- `docs/DECISIONS.md`, `docs/ENVIRONMENT.md`, this changelog.
- `CONTRIBUTING.md` (working rules), `CLAUDE.md` (notes for AI sessions), `.gitignore`.
- `MQL5/Scripts/NNFX/NNFX_EnvCheck.mq5`: read-only environment check script. **Not yet compiled.**
- No trading code yet.
