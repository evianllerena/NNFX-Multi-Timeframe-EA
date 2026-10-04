# MQL5 rule tests (Phase 4)

`MQL5/Scripts/NNFX/NNFX_RulesTest.mq5` runs every rule case through the MQL5 rules core
(`MQL5/Include/NNFX/RulesCore.mqh`) and compares each result with the expected answer.
The cases are `tests/fixtures/mql5/*.txt`: the same cases the Python answer key passes,
in a line format MQL5 can read (a Python test proves the two formats hold identical data).

**Pass line (SPEC Check 1a):** `RESULT: 47 passed, 0 failed, 47 total`, the same as Python.

## Run it (PowerShell)

```powershell
$MT5  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$Repo = "C:\Users\Evision\NNFX-Multi-Timeframe-EA"

# 1. Copy the code and the fixtures into MT5
New-Item -ItemType Directory -Force "$MT5\MQL5\Include\NNFX", "$MT5\MQL5\Scripts\NNFX", "$MT5\MQL5\Files\NNFX\fixtures" | Out-Null
Copy-Item "$Repo\MQL5\Include\NNFX\*.mqh" "$MT5\MQL5\Include\NNFX\" -Force
Copy-Item "$Repo\MQL5\Scripts\NNFX\NNFX_RulesTest.mq5" "$MT5\MQL5\Scripts\NNFX\" -Force
Copy-Item "$Repo\tests\fixtures\mql5\*.txt" "$MT5\MQL5\Files\NNFX\fixtures\" -Force

# 2. Compile (or open the file in MetaEditor and press F7)
& "C:\Program Files\MetaTrader 5\MetaEditor64.exe" /compile:"$MT5\MQL5\Scripts\NNFX\NNFX_RulesTest.mq5" /log:"$MT5\MQL5\Scripts\NNFX\NNFX_RulesTest.log"
Start-Sleep 5
Get-Content "$MT5\MQL5\Scripts\NNFX\NNFX_RulesTest.log"
```

3. In MT5: Navigator, Scripts, NNFX, drag **NNFX_RulesTest** onto any chart, click OK.
4. Read the report:

```powershell
Get-Content "$MT5\MQL5\Files\NNFX_RulesTest.txt"
```

A failing case prints what was expected, what happened, and the full event trace.
