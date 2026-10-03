# NNFX Multi-Timeframe EA

A MetaTrader 5 Expert Advisor that trades the No Nonsense Forex (NNFX) method on
the 30M, 1H and 4H charts. One shared rules core runs as three instances (one per
timeframe); the timeframe that performs best on untouched test data is the one
taken forward.

**Status: Phase 2 (repo setup). No trading code exists yet.**
Nothing in this repo is proven. Every rule and every result must pass the checks
in `docs/SPEC.md` (Verification plan) before it is trusted.

## Where things are

| Path | What it holds |
| --- | --- |
| `docs/RULEBOOK.md` | The NNFX rules, each with its source and a confidence label (A / B / C). Source of truth for *what* the EA does |
| `docs/SPEC.md` | How the rules run on 30M / 1H / 4H, the modules, safety limits, and the verification and shootout plan. Source of truth for *how* |
| `docs/DECISIONS.md` | Every decision taken, when, and why |
| `docs/ENVIRONMENT.md` | Facts read from the MT5 terminal (account type, history on disk) |
| `docs/CHANGELOG.md` | What changed in the repo, by date |
| `MQL5/` | Mirrors MT5's own `MQL5` folder: `Experts/NNFX`, `Include/NNFX`, `Scripts/NNFX`, `Presets` |
| `profiles/` | Indicator profile files: swapping an indicator means editing one of these, never the code |
| `tests/` | Python answer key, hand-built rule cases, MT5 test scripts |
| `tools/` | Support tools (environment check, calendar export, independent result recomputation) |
| `results/` | The register of every test run, valid or not |

## Build phases

| Phase | Output | Gate |
| --- | --- | --- |
| 0 Rulebook | `docs/RULEBOOK.md` | Approved 2026-10-01 |
| 1 Intraday spec | `docs/SPEC.md` | Approved 2026-10-03 |
| 2 Repo setup | This structure | Your review of the pull request |
| 3 Python answer key | `tests/python` + rule cases | 100% of rule cases pass |
| 4 MQL5 rules core | `MQL5/Include/NNFX` | Same rule cases pass in MT5 |
| 5 Indicator slots + profiles | `profiles/`, slot modules | Values match MT5's Data Window |
| 6 Orders, risk, recovery | Execution modules | Trade checks and restart tests pass |
| 7 Bar-by-bar cross-check | EA vs answer key | Zero mismatches |
| 8 Shootout | `results/` | Validity checks V1–V14 pass |
| 9 Demo, then small live | Demo log | Demo matches backtest |

## Working rules

See `CONTRIBUTING.md`. In short: branch, then pull request, then merge; never
push straight to `main`; nothing is changed without approval; facts are checked,
never assumed.
