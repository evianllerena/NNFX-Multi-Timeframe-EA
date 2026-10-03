# Changelog

Newest first.

## 2026-10-03 — Phase 4: MQL5 rules core

- `MQL5/Include/NNFX/Settings.mqh`, `RulesCore.mqh`: the rules core in MQL5, a function-for-function
  port of the Python answer key. No trading or indicator calls. **Not yet compiled.**
- `MQL5/Scripts/NNFX/NNFX_RulesTest.mq5`: runs all rule cases in MT5 and writes a pass/fail report.
  **Not yet compiled.**
- `tests/fixtures/mql5/`: the same 45 rule cases in a line format MQL5 can read;
  `tests/python/test_fixture_formats.py` proves they match the JSON exactly.
- Pass line: 45 of 45 in MT5, the same as Python.

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
