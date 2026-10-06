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

## Phase 6a: sizing and exposure (`NNFX_SizingTest`)

Runs the shared cases `tests/fixtures/sizing/sizing_cases.txt` and `tests/fixtures/exposure/exposure_cases.txt`
(copied to `$MT5\MQL5\Files\NNFX\sizing\` and `...\exposure\` by the runner) through `Sizing.mqh` and
`Exposure.mqh`. Run by `tools/run_phase5_checks.ps1`; report `$MT5\MQL5\Files\NNFX_SizingTest.txt`.
**Pass line:** `RESULT: 42 passed, 0 failed, 42 total`. The `LIVE` lines after it (tick values, the OD-6 choice,
the sizing for a 1.5 x ATR(14) H1 stop) are information only and never counted.

## Phase 6b: orders (`NNFX_SafetyTest`, `NNFX_OrderMathTest`, `NNFX_OrderTest`)

All three run from the runner. **Pass lines:** `RESULT: 6 passed, 0 failed, 6 total` (SafetyTest),
`RESULT: 22 passed, 0 failed, 22 total` (OrderMathTest); step 4b runs the test EA `NNFX_OrderTest` in the Strategy
Tester (EURUSD H1, 1 minute OHLC) and step 5 checks its trade log with `tools/check_trades.py --min-trades 20
--require SL,TP1,BE,TRAILON,TRAIL,TP2,EXIT,RETRY,TESTSTOPLESS,ABORT,REFUSE,MODIFY --require-note "free margin"
--require-note "minimum distance" --require-note "via="`: `RESULT OrderTest_EURUSD_tester.csv: PASS (0 failures)`.
The test EA forces, in the tester only, an ABORT (trade 7), a REFUSE for the stops level (9) and for free margin
(11, OD-5), and a MODIFY (13, SL/TP planned off the fill) through `#ifdef NNFX_TEST_BUILD` hooks in `Orders.mqh`.

Demo order run (weekday, by hand): attach `NNFX\NNFX_OrderTest` to a EURUSD H1 chart on the demo account with
`InpMinLots=true`, `InpMaxTrades=5`; the stopless and lost-reply tests are tester-only and are refused on demo.
Then `python tools\check_trades.py "...\Common\Files\NNFX\trades\OrderTest_EURUSD_demo.csv"`.

Offline checks (carry-over 1): `tools/run_offline_check.ps1 -NoPython` (no owner action) and `-Mt5Offline`
(needs the firewall rule described in that script's header, added and removed by the owner).

## Phase 6c: state and recovery (`NNFX_RecoveryTest`, restart tests)

`NNFX_RecoveryTest` runs from the runner. It reads the fixtures copied to `$MT5\MQL5\Files\NNFX\recovery\`: 3 FNV-1a
vectors, the 5 state files and the 22 rebuild cases, run through `State.mqh`.
**Pass line:** `RESULT: 30 passed, 0 failed, 30 total`.

Restart test (a), in the tester: `powershell -ExecutionPolicy Bypass -File tools\run_restart_tests.ps1`. One base
run of `NNFX_OrderTest`, then one run per restart state (R1-R4, R2 with the state file deleted, R2 with comments
ignored). Each run is restarted inside the tester at the picked time.
**Pass lines:** for each run, `RESULT: IDENTICAL (0 differing rows, n compared)` and `RESULT: REBUILDS MATCH`.

Restart test (b), real restarts on the demo (weekday): `powershell -ExecutionPolicy Bypass -File
tools\run_demo_restarts.ps1`. It needs MetaQuotes MT5 closed at the start and Algo Trading on, and nobody needs to
watch it. MT5 opens and closes by itself; if MT5 relaunches or is closed, the driver handles it (D6c-3).
**Pass lines:** `R1`-`R4` each restarted, `RESULT: REBUILDS MATCH (n of n)`, and `OVERALL: PASS`.
