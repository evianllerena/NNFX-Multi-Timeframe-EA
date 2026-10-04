# Indicator profiles

Swapping an indicator means editing or adding one of these files, never the EA's code
(`docs/SPEC.md`, Indicator profiles). The MQL5 slot layer (`MQL5/Include/NNFX/Profile.mqh`)
and the Python answer key (`tests/python/nnfx_ref/profiles.py`) read the same files with
the same validation rules.

## Where MT5 reads them

Copy the `.txt` files to the **common** MT5 files folder:
`%APPDATA%\MetaQuotes\Terminal\Common\Files\NNFX\profiles\`

The common folder is used because the Strategy Tester runs in its own sandbox; the
common folder is the one place both the terminal and the tester can read
(MQL5 docs, `FileOpen`: `FILE_COMMON` = "a shared folder for all client terminals").

## Format

Plain text, one `key=value` per line. Lines starting with `#` and blank lines are ignored.
Unknown keys are rejected (so a typo can't silently change behaviour).

| Key | Required | Values | Meaning |
| --- | --- | --- | --- |
| `name` | yes | letters, digits, `_` | Profile name used in logs and reports |
| `slot` | yes | `BASELINE`, `C1`, `C2`, `EXIT`, `VOLUME` | Which job the indicator does |
| `source` | yes | `builtin`, `custom` | MT5 standard indicator, or a custom `.ex5` |
| `indicator` | yes | builtin: `MA`, `RVI`, `MACD`, `VOLUMES`, `MOMENTUM`; custom: path under `MQL5\Indicators` without `.ex5` (e.g. `Custom\SSL_Channel`) | What to load |
| `input` | no, repeatable | `int:10`, `double:1.5`, `bool:true`, `string:abc`, `enum:MODE_SMA` | Indicator inputs, **in the indicator's own order** |
| `signal` | yes | `price_line`, `two_line`, `centre_line`, `volume` | How values become long / short / none |
| `buf_main` | price_line, centre_line, volume | integer | Output line (buffer) to read |
| `buf_fast`, `buf_slow` | two_line | integers | The two lines compared |
| `centre` | centre_line | number | The indicator's own centre line. **Never defaulted to 0** |
| `vol_rule` | volume | `level`, `average`, `cross` | Pass rule (see below) |
| `vol_level` | vol_rule=level | number | Pass when value > level |
| `vol_period`, `vol_mult` | vol_rule=average | integer, number | Pass when value >= mult x average of the previous `vol_period` readings |
| `buf_other` | vol_rule=cross | integer | Pass when value > this other line |
| `warmup` | yes | integer >= 0 | The first `warmup` candles of history are ignored |
| `notes` | no | text | Where it came from, who checked it |

Allowed slot / signal pairs: BASELINE = `price_line`; C1, C2, EXIT = `two_line` or `centre_line`;
VOLUME = `volume`. (The old scanner project limited C2 to centre-line types; VP doesn't, so this doesn't.)

Enum names allowed in `enum:` inputs: `MODE_SMA`, `MODE_EMA`, `MODE_SMMA`, `MODE_LWMA`,
`PRICE_CLOSE`, `PRICE_OPEN`, `PRICE_HIGH`, `PRICE_LOW`, `PRICE_MEDIAN`, `PRICE_TYPICAL`,
`PRICE_WEIGHTED`, `VOLUME_TICK`, `VOLUME_REAL`. They are written by name so no numeric
value is ever assumed; the MQL5 compiler supplies the real value.

## The reference set (`ref_*.txt`)

Five profiles built only from MT5 standard indicators. **They exist to prove the pipeline
works, not because they trade well.** None was chosen for performance.

| File | Slot | Indicator | Read as | Buffer source |
| --- | --- | --- | --- | --- |
| `ref_baseline_sma20.txt` | BASELINE | Moving Average, 20, simple, close | Close above / below the line | MA has one buffer (0) |
| `ref_c1_rvi10.txt` | C1 | RVI, 10 | Main (0) above / below signal (1) | MQL5 docs, iRVI: "0 - MAIN_LINE, 1 - SIGNAL_LINE" |
| `ref_c2_macd_main.txt` | C2 | MACD 12/26/9, close | Main line (0) above / below 0 | MQL5 docs, iMACD: "0 - MAIN_LINE, 1 - SIGNAL_LINE"; MACD main = fast EMA - slow EMA, so its centre is 0 by definition |
| `ref_exit_macd_cross.txt` | EXIT | MACD 12/26/9, close | Main (0) above / below signal (1) | as above |
| `ref_volume_ticks20.txt` | VOLUME | Volumes, tick volume | Value >= its own 20-candle average | MQL5 docs, iVolumes: buffer 0 = value, buffer 1 = colour |

The 20-candle-average volume rule is the old project's placeholder, kept only for the
reference set; real volume indicators get their own rule in their own profile.

## Before a profile is used

1. Its values on sample candles match MT5's Data Window (`NNFX_ExportBars` + `tools/check_export.py`).
2. It passes the repaint check (`NNFX_RepaintCheck`, spec check V2).
