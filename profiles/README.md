# Indicator profiles

Swapping an indicator means editing one of these files, never the EA's code
(`docs/SPEC.md`, Indicator profiles). The exact file format is fixed in Phase 5;
each profile will hold:

| Field | Example | Why |
| --- | --- | --- |
| Indicator file | `Custom\SSL_Channel.ex5` | Which indicator to load |
| Slot | C1 | Which job it does |
| Input settings | period = 10 | Passed to the indicator in order |
| Signal type | Two-line cross | How its values become long / short / none |
| Line numbers (buffers) | fast = 0, slow = 1 | Which output lines to read; never guessed |
| Centre line | 0, 50, ... | Required for centre-line types; never defaulted to 0 |
| Volume pass rule | Above a level / above own average / line cross | Volume indicators signal differently |
| Warm-up candles | 50 | Earlier values are ignored |
| Source / notes | Where the indicator came from; who checked it | Traceability |

A profile is used only after its values on a fixed sample of candles match MT5's
Data Window, and after the repaint check (V2) passes.
