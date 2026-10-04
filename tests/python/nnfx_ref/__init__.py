"""nnfx_ref: the Python answer key for the NNFX Multi-Timeframe EA.

An independent implementation of docs/RULEBOOK.md, used to check the MQL5 EA
(docs/SPEC.md, Verification plan, Check 1). Standard library only.

Modules:
    settings  - every rule setting with its default (SPEC, Settings table)
    signals   - turn raw indicator values into long / short / none (SPEC, Indicator profiles)
    core      - per-pair rules engine: entries E0-E6, exits X1-X5, trade management T1-T7
    sizing    - lot size from risk and stop distance (M2-M5)
    exposure  - same-currency check across positions (M6, M7)
    fixtures  - load and run the JSON rule fixtures in tests/fixtures
"""

__version__ = "0.1.0"
