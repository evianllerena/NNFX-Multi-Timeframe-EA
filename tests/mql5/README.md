# MQL5 checks

All paths below assume:

```powershell
$MT5    = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$Common = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files"
$Repo   = "C:\Users\Evision\NNFX-Multi-Timeframe-EA"
$ME     = "C:\Program Files\MetaTrader 5\MetaEditor64.exe"
```

## Phase 4: rules core (`NNFX_RulesTest`)

Runs every rule case (`tests/fixtures/mql5/*.txt`, the same cases the Python answer key passes)
through `MQL5/Include/NNFX/RulesCore.mqh`.
**Pass line:** `RESULT: 47 passed, 0 failed, 47 total`. Passed 2026-10-03 (`docs/VERIFICATION.md`).

```powershell
New-Item -ItemType Directory -Force "$MT5\MQL5\Include\NNFX", "$MT5\MQL5\Scripts\NNFX", "$MT5\MQL5\Files\NNFX\fixtures" | Out-Null
Copy-Item "$Repo\MQL5\Include\NNFX\*.mqh" "$MT5\MQL5\Include\NNFX\" -Force
Copy-Item "$Repo\MQL5\Scripts\NNFX\NNFX_RulesTest.mq5" "$MT5\MQL5\Scripts\NNFX\" -Force
Copy-Item "$Repo\tests\fixtures\mql5\*.txt" "$MT5\MQL5\Files\NNFX\fixtures\" -Force
& $ME /compile:"$MT5\MQL5\Scripts\NNFX\NNFX_RulesTest.mq5" /log:"$MT5\MQL5\Scripts\NNFX\NNFX_RulesTest.log"
```

Run `NNFX_RulesTest` on any chart; report: `$MT5\MQL5\Files\NNFX_RulesTest.txt`.

## Phase 5: slots and profiles

### Automatic run (use this)

Close MetaTrader 5 first (File > Exit), then:

```powershell
powershell -ExecutionPolicy Bypass -File "$Repo\tools\run_phase5_checks.ps1"
```

It copies, compiles, runs every script below through MT5's `/config` start-up file, runs the
repaint check in the Strategy Tester, runs the Python checks, and writes everything to
`$MT5\MQL5\Files\NNFX\checks\<date-time>\` with a `SUMMARY.txt`. No clicking, and no reading
values by eye: `tools/check_indicators.py` recalculates every standard indicator value from the
exported prices instead of the old Data Window comparison.

A step marked `NOT RUN (automation did not engage)` means MT5 did not run that step from the
command line on this PC; then do that step by hand as below and report it.

`NNFX_EnvCheck` and `NNFX_ExportBars` wait (up to 120 s) until MT5 is logged in before reading
anything. If it never logs in they write `RESULT: INVALID (not connected)` and the runner marks the
step FAIL. The runner finds a working Python itself (`-Python <path>` overrides) and prints which
one it used in `SUMMARY.txt`.

### Manual steps (fallback only)

### 1. Copy and compile

```powershell
New-Item -ItemType Directory -Force "$MT5\MQL5\Include\NNFX", "$MT5\MQL5\Scripts\NNFX", "$MT5\MQL5\Experts\NNFX",
  "$MT5\MQL5\Files\NNFX\signals", "$MT5\MQL5\Files\NNFX\profiles_bad", "$MT5\MQL5\Files\NNFX\export",
  "$Common\NNFX\profiles", "$Common\NNFX\reports" | Out-Null
Copy-Item "$Repo\MQL5\Include\NNFX\*.mqh" "$MT5\MQL5\Include\NNFX\" -Force
Copy-Item "$Repo\MQL5\Scripts\NNFX\*.mq5" "$MT5\MQL5\Scripts\NNFX\" -Force
Copy-Item "$Repo\MQL5\Experts\NNFX\*.mq5" "$MT5\MQL5\Experts\NNFX\" -Force
Copy-Item "$Repo\tests\fixtures\signals\signal_cases.txt" "$MT5\MQL5\Files\NNFX\signals\" -Force
Copy-Item "$Repo\tests\fixtures\profiles_bad\*.txt" "$MT5\MQL5\Files\NNFX\profiles_bad\" -Force
Copy-Item "$Repo\profiles\*.txt" "$Common\NNFX\profiles\" -Force

foreach ($f in "Scripts\NNFX\NNFX_RulesTest", "Scripts\NNFX\NNFX_SignalTest", "Scripts\NNFX\NNFX_ExportBars",
               "Scripts\NNFX\NNFX_EnvCheck", "Experts\NNFX\NNFX_RepaintCheck") {
  & $ME /compile:"$MT5\MQL5\$f.mq5" /log:"$MT5\MQL5\$f.log" | Out-Null
  Get-Content "$MT5\MQL5\$f.log" | Select-String "Result:|error"
}
```

**Pass line:** every file `0 errors`.

### 2. Signal and profile test (`NNFX_SignalTest`)

Run it on any chart. Report: `$MT5\MQL5\Files\NNFX_SignalTest.txt`.
**Pass line:** `RESULT: 56 passed, 0 failed, 56 total`
(37 signal cases + 5 reference profiles load + 14 bad profiles rejected), the same answers
the Python tests give. Re-run `NNFX_RulesTest` too: still 47 of 47.

### 3. Export and check (`NNFX_ExportBars` + `tools/check_export.py`)

Run `NNFX_ExportBars` on any chart (defaults: VP's 5 test pairs, H1, 3000 candles). It first makes
MT5 download enough history, and writes `_summary.txt` (pass line `RESULT: 5 of 5 pairs complete`). It writes
`$MT5\MQL5\Files\NNFX\export\<PAIR>_H1.csv`. Then:

```powershell
python "$Repo\tools\check_export.py" (Get-ChildItem "$MT5\MQL5\Files\NNFX\export\*.csv").FullName --replay
```

**Pass line:** `RESULT <file>: PASS` for every pair. The checker recomputes every C1, C2, exit
direction and volume pass in Python from the raw values and must agree with MT5 on every candle.

### 4. Indicator values recalculated (`tools/check_indicators.py`)

```powershell
python "$Repo\tools\check_indicators.py" (Get-ChildItem "$MT5\MQL5\Files\NNFX\export\*.csv").FullName
```

Recalculates ATR(14), the 20 SMA, RVI(10) main and signal, MACD(12, 26, 9) main and signal and
tick volume from the exported prices, using the formulas in MT5's own example source files.
**Pass line:** `RESULT <file>: PASS` for every pair (at least 1,000 candles compared per value).

### 5. Repaint check (`NNFX_RepaintCheck`, Strategy Tester, spec V2)

Strategy Tester: Expert `NNFX\NNFX_RepaintCheck`, symbol EURUSD, timeframe H1, model
"1 minute OHLC", a date range of a few months, run. It places no orders. Report:
`$Common\NNFX\reports\Repaint_EURUSD_H1.txt`.
**Pass line:** every profile `PASS` and `RESULT: NO REPAINTING FOUND`.

Confirmed on this PC (2026-10-04, runs `20261004_113357` and `20261004_115428`): the tester's
local agent reads `Common\Files\NNFX\profiles` and writes its report to `Common\Files\NNFX\reports`.
If that ever fails, the EA stops at start with "cannot open ... profiles" in the tester Journal.
