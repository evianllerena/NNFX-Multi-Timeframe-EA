# Presets

One MT5 settings file per timeframe: `NNFX_M30.set`, `NNFX_H1.set`, `NNFX_H4.set`.
They are created in Phase 6, once the EA's settings exist, by saving them from MT5's
own settings dialog (so the format is exactly what MT5 expects). All three start with
the same defaults (`docs/SPEC.md`, Settings). Each has its own magic number.
