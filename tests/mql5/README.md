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

Run `NNFX_ExportBars` on any chart (defaults: VP's 5 test pairs, H1, 3000 candles). It writes
`$MT5\MQL5\Files\NNFX\export\<PAIR>_H1.csv`. Then:

```powershell
python "$Repo\tools\check_export.py" (Get-ChildItem "$MT5\MQL5\Files\NNFX\export\*.csv").FullName --replay
```

**Pass line:** `RESULT <file>: PASS` for every pair. The checker recomputes every C1, C2, exit
direction and volume pass in Python from the raw values and must agree with MT5 on every candle.

### 4. Data Window spot check (by eye)

Open an H1 chart of one pair and add MT5's own indicators with the reference settings:
Moving Average (20, Simple, Close), RVI (10), MACD (12, 26, 9, Close), Volumes (Tick).
Open the Data Window (Ctrl+D). For the three sample times `check_export.py` prints, hover over
that candle and compare. **Pass line:** values agree (the Data Window rounds to fewer decimals).

### 5. Repaint check (`NNFX_RepaintCheck`, Strategy Tester, spec V2)

Strategy Tester: Expert `NNFX\NNFX_RepaintCheck`, symbol EURUSD, timeframe H1, model
"1 minute OHLC", a date range of a few months, run. It places no orders. Report:
`$Common\NNFX\reports\Repaint_EURUSD_H1.txt`.
**Pass line:** every profile `PASS` and `RESULT: NO REPAINTING FOUND`.

Not yet confirmed on this PC: that the tester's local agent can read `Common\Files` (the MQL5
docs say `FILE_COMMON` is the folder shared by all terminals). If it can't, the EA stops at start
with "cannot open ... profiles" in the tester Journal; report that and the profiles will be
embedded another way.
