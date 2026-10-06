<#
run_phase5_checks.ps1 - runs every Phase 5 check with no clicking, and writes one summary.

What it does, in order (each step's result goes in SUMMARY.txt):
  1. Copies the repo's MQL5 files, fixtures and profiles into MT5.
  2. Compiles all five MQL5 programs; each must report 0 errors, 0 warnings.
  3. Starts MT5 once per script with a /config file ([StartUp] Script=..., ShutdownTerminal=1):
       NNFX_RulesTest   pass line  RESULT: 47 passed, 0 failed, 47 total
       NNFX_SignalTest  pass line  RESULT: 56 passed, 0 failed, 56 total
       NNFX_SizingTest  pass line  RESULT: 46 passed, 0 failed, 46 total   (Phase 6a; its LIVE lines
                        are information only)
       NNFX_SafetyTest  pass line  RESULT: 6 passed, 0 failed, 6 total     (Phase 6b, S1)
       NNFX_OrderMathTest pass line RESULT: 22 passed, 0 failed, 22 total  (Phase 6b)
       NNFX_RecoveryTest pass line RESULT: 30 passed, 0 failed, 30 total   (Phase 6c)
       NNFX_GuardTest   pass line  RESULT: 56 passed, 0 failed, 56 total   (Phase 6d)
       NNFX_EnvCheck    information only, but must be read after login: "RESULT: VALID ..."
                        ("RESULT: INVALID (not connected)" is a FAIL)
       NNFX_ExportBars  pass line  RESULT: 5 of 5 pairs complete
     A report only counts if it was written during this run.
  4. Starts the Strategy Tester with a /config file ([Tester] Expert=NNFX\NNFX_RepaintCheck ...)
       pass line  RESULT: NO REPAINTING FOUND
     4b. The Phase 6b order run: Expert=NNFX\NNFX_OrderTest on EURUSD H1 (orders in the tester only);
       its trade log is checked in step 5 by tools/check_trades.py (at least 20 trades and every
       order path: SL, TP1, BE, TRAILON, TRAIL, TP2, EXIT, RETRY, TESTSTOPLESS, ABORT, REFUSE for the
       stops level and for free margin, MODIFY; BE rows note which poll moved the stop, "via=")
  5. Runs the Python tests, tools/check_export.py --replay and tools/check_indicators.py on the
     exports written in step 3. Python is found automatically (-Python if given, then `py -3`,
     then `python`, then the newest %LOCALAPPDATA%\Programs\Python\Python3*\python.exe); each
     candidate must run `--version`. The one used is printed in SUMMARY.txt.

Everything (reports, compile logs, MT5 logs, Python output, SUMMARY.txt) is copied to
  <MT5 data folder>\MQL5\Files\NNFX\checks\<date-time>\
so it can be read back as-is.

MT5 must be CLOSED before running: what /config does when the terminal is already open is not
documented, so the script refuses to start rather than guess. Owner decision D6c-1: only the terminal
being tested counts, matched by its full path ($Install\terminal64.exe); any other terminal64.exe (another
broker's MT5) is listed in SUMMARY.txt as "other terminal running (ignored)" and never touched. Anything
this script closes is closed by the process id it started. The run stops if the data folder does not
belong to the tested install (origin.txt) or EnvCheck reports another account than -ExpectLogin/-ExpectServer.

If a step cannot be automated on this PC (MT5 starts but no fresh report appears), the step is
marked "NOT RUN (automation did not engage)" and the manual steps in tests/mql5/README.md apply.

-PythonOnly skips steps 1-4 (no MT5 needed, MT5 may be open) and runs only step 5. Used by
tools/run_offline_check.ps1 to prove the "no working Python" path FAILs.

Usage (PowerShell, from anywhere):
  powershell -ExecutionPolicy Bypass -File C:\Users\Evision\NNFX-Multi-Timeframe-EA\tools\run_phase5_checks.ps1
#>
param(
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Common  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [string]$Python  = "",          # empty = find a working Python (see step 5)
    [string]$TesterFrom = "2026.06.01",
    [string]$TesterTo   = "2026.10.01",
    [switch]$SkipTester,
    [switch]$PythonOnly,
    [long]$ExpectLogin = 113593254,          # D6c-1: the account this runner may run against
    [string]$ExpectServer = "MetaQuotes-Demo"
)

# "Continue": in Windows PowerShell 5.1, "Stop" turns any text a program writes to stderr
# (python unittest writes its progress there) into an error. Steps that must not fail use -ErrorAction Stop.
$ErrorActionPreference = "Continue"
$Terminal = Join-Path $Install "terminal64.exe"
$ME       = Join-Path $Install "MetaEditor64.exe"
$Stamp    = Get-Date -Format "yyyyMMdd_HHmmss"
$Out      = Join-Path $MT5 "MQL5\Files\NNFX\checks\$Stamp"
$Summary  = New-Object System.Collections.Generic.List[string]
$AllPass  = $true
$script:OrderLogThisRun = $null

function Say([string]$text) { Write-Host $text; $script:Summary.Add($text) }
function Step([string]$name, [string]$status, [string]$detail) {
    if ($status -ne "PASS" -and $status -ne "INFO") { $script:AllPass = $false }
    Say (("{0,-34} {1}" -f $name, $status) + $(if ($detail) { "  - $detail" } else { "" }))
}
function Fresh([string]$path, [datetime]$since) {
    return (Test-Path $path) -and ((Get-Item $path).LastWriteTime -ge $since) -and ((Get-Item $path).Length -gt 0)
}
function ReadText([string]$path) { return (Get-Content -LiteralPath $path -Raw) }

# ---------------------------------------------------------------- 0. preconditions
foreach ($p in @($Repo, $MT5, $Terminal, $ME)) {
    if (-not (Test-Path $p)) { Write-Host "STOP: not found: $p"; exit 2 }
}
# D6c-1: only the tested terminal (full path) blocks the run; others are listed and never touched.
$running = @(Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path })
$tested = @($running | Where-Object { $_.Path -ieq $Terminal })
$others = @($running | Where-Object { $_.Path -ine $Terminal })
if (-not $PythonOnly -and $tested.Count -gt 0) {
    Write-Host "STOP: the tested MetaTrader 5 ($Terminal) is open. Close it (File > Exit) and run this again."
    exit 2
}
# D6c-1: the data folder must belong to the tested install (MT5 writes the install path to origin.txt).
$origin = Join-Path $MT5 "origin.txt"
if (-not $PythonOnly) {
    $originPath = if (Test-Path $origin) { (Get-Content -LiteralPath $origin -Raw -Encoding Unicode).Trim([char]0, " ", "`r", "`n") } else { "" }
    if ($originPath -ine $Install) {
        Write-Host "STOP: data folder $MT5 belongs to '$originPath', not to the tested install '$Install'."
        exit 2
    }
}
New-Item -ItemType Directory -Force $Out | Out-Null
Say "NNFX Phase 5 checks  $Stamp"
Say "Repo:   $Repo  (commit $(& git -C $Repo rev-parse --short HEAD 2>$null))"
Say "MT5:    $MT5"
Say "Tested terminal: $Terminal (data folder origin.txt matches); expected account $ExpectLogin on $ExpectServer"
foreach ($o in $others) { Say ("other terminal running (ignored): pid {0} {1}" -f $o.Id, $o.Path) }
Say ""

if ($PythonOnly) {
    Step "1-4 MT5 steps" "NOT RUN" "skipped with -PythonOnly"
} else {
    # ---------------------------------------------------------------- 1. copy
    New-Item -ItemType Directory -Force "$MT5\MQL5\Include\NNFX", "$MT5\MQL5\Scripts\NNFX", "$MT5\MQL5\Experts\NNFX",
        "$MT5\MQL5\Files\NNFX\fixtures", "$MT5\MQL5\Files\NNFX\signals", "$MT5\MQL5\Files\NNFX\profiles_bad",
        "$MT5\MQL5\Files\NNFX\export", "$MT5\MQL5\Files\NNFX\sizing", "$MT5\MQL5\Files\NNFX\exposure",
        "$MT5\MQL5\Files\NNFX\orders", "$MT5\MQL5\Files\NNFX\recovery\state_files", "$MT5\MQL5\Files\NNFX\guard", "$Common\NNFX\profiles",
        "$Common\NNFX\reports", "$Common\NNFX\trades" | Out-Null
    $ErrorActionPreference = "Stop"
    Copy-Item "$Repo\MQL5\Include\NNFX\*.mqh" "$MT5\MQL5\Include\NNFX\" -Force
    Copy-Item "$Repo\MQL5\Scripts\NNFX\*.mq5" "$MT5\MQL5\Scripts\NNFX\" -Force
    Copy-Item "$Repo\MQL5\Experts\NNFX\*.mq5" "$MT5\MQL5\Experts\NNFX\" -Force
    Copy-Item "$Repo\tests\fixtures\mql5\*.txt" "$MT5\MQL5\Files\NNFX\fixtures\" -Force
    Copy-Item "$Repo\tests\fixtures\signals\signal_cases.txt" "$MT5\MQL5\Files\NNFX\signals\" -Force
    Copy-Item "$Repo\tests\fixtures\profiles_bad\*.txt" "$MT5\MQL5\Files\NNFX\profiles_bad\" -Force
    Copy-Item "$Repo\tests\fixtures\sizing\sizing_cases.txt" "$MT5\MQL5\Files\NNFX\sizing\" -Force
    Copy-Item "$Repo\tests\fixtures\exposure\exposure_cases.txt" "$MT5\MQL5\Files\NNFX\exposure\" -Force
    Copy-Item "$Repo\tests\fixtures\orders\order_cases.txt" "$MT5\MQL5\Files\NNFX\orders\" -Force
    Copy-Item "$Repo\tests\fixtures\recovery\recovery_cases.txt" "$MT5\MQL5\Files\NNFX\recovery\" -Force
    Copy-Item "$Repo\tests\fixtures\recovery\state_files\*.txt" "$MT5\MQL5\Files\NNFX\recovery\state_files\" -Force
    Copy-Item "$Repo\tests\fixtures\guard\guard_cases.txt" "$MT5\MQL5\Files\NNFX\guard\" -Force
    Copy-Item "$Repo\profiles\*.txt" "$Common\NNFX\profiles\" -Force
    $ErrorActionPreference = "Continue"
    Step "1 copy files" "PASS" ""

    # ---------------------------------------------------------------- 2. compile
    $programs = @("Scripts\NNFX\NNFX_RulesTest", "Scripts\NNFX\NNFX_SignalTest", "Scripts\NNFX\NNFX_ExportBars",
                  "Scripts\NNFX\NNFX_EnvCheck", "Experts\NNFX\NNFX_RepaintCheck", "Scripts\NNFX\NNFX_SizingTest",
                  "Scripts\NNFX\NNFX_SafetyTest", "Scripts\NNFX\NNFX_OrderMathTest", "Experts\NNFX\NNFX_OrderTest",
                  "Scripts\NNFX\NNFX_RecoveryTest", "Scripts\NNFX\NNFX_DealReport", "Scripts\NNFX\NNFX_GuardTest")
    $compileOk = $true
    foreach ($f in $programs) {
        $src = "$MT5\MQL5\$f.mq5"; $log = "$MT5\MQL5\$f.log"; $ex5 = "$MT5\MQL5\$f.ex5"
        if (Test-Path $log) { Remove-Item $log -Force }
        $t0 = Get-Date
        Start-Process -FilePath $ME -ArgumentList "/compile:`"$src`"", "/log:`"$log`"" -Wait -WindowStyle Hidden
        $name = Split-Path $f -Leaf
        Copy-Item $log "$Out\$name.compile.log" -ErrorAction SilentlyContinue
        $text = if (Test-Path $log) { ReadText $log } else { "" }
        $m = [regex]::Match($text, "Result:\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?")
        if ($m.Success -and $m.Groups[1].Value -eq "0" -and $m.Groups[2].Value -eq "0" -and (Fresh $ex5 $t0)) {
            Step "2 compile $name" "PASS" "0 errors, 0 warnings"
        } else {
            $compileOk = $false
            $why = if ($m.Success) { "$($m.Groups[1].Value) errors, $($m.Groups[2].Value) warnings" } else { "no Result line in compile log" }
            Step "2 compile $name" "FAIL" $why
        }
    }
    if (-not $compileOk) {
        Say ""; Say "OVERALL: FAIL (compile). Nothing was run. Compile logs are in $Out"
        $Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
        exit 1
    }

    # ---------------------------------------------------------------- 3. scripts via /config
    function Run-Terminal([string]$iniPath, [int]$timeoutMin) {
        $p = Start-Process -FilePath $Terminal -ArgumentList "/config:`"$iniPath`"" -PassThru
        if (-not $p.WaitForExit($timeoutMin * 60 * 1000)) {
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            return "timeout after $timeoutMin min (MT5 was closed by this script)"
        }
        Start-Sleep -Seconds 2
        return ""
    }
    function Run-Script([string]$script, [int]$timeoutMin) {
        $ini = "$Out\run_$script.ini"
        @("[StartUp]", "Script=NNFX\$script", "Symbol=EURUSD", "Period=H1", "ShutdownTerminal=1") |
            Set-Content -LiteralPath $ini -Encoding ASCII
        return (Run-Terminal $ini $timeoutMin)
    }

    $scripts = @(
        @{ Name = "NNFX_RulesTest";  Report = "$MT5\MQL5\Files\NNFX_RulesTest.txt";        Pass = "RESULT: 47 passed, 0 failed, 47 total"; Min = 5 },
        @{ Name = "NNFX_SignalTest"; Report = "$MT5\MQL5\Files\NNFX_SignalTest.txt";       Pass = "RESULT: 56 passed, 0 failed, 56 total"; Min = 5 },
        @{ Name = "NNFX_SizingTest"; Report = "$MT5\MQL5\Files\NNFX_SizingTest.txt";       Pass = "RESULT: 46 passed, 0 failed, 46 total"; Min = 5 },
        @{ Name = "NNFX_SafetyTest"; Report = "$MT5\MQL5\Files\NNFX_SafetyTest.txt";       Pass = "RESULT: 6 passed, 0 failed, 6 total"; Min = 5 },
        @{ Name = "NNFX_OrderMathTest"; Report = "$MT5\MQL5\Files\NNFX_OrderMathTest.txt"; Pass = "RESULT: 22 passed, 0 failed, 22 total"; Min = 5 },
        @{ Name = "NNFX_RecoveryTest"; Report = "$MT5\MQL5\Files\NNFX_RecoveryTest.txt";  Pass = "RESULT: 30 passed, 0 failed, 30 total"; Min = 5 },
        @{ Name = "NNFX_GuardTest";  Report = "$MT5\MQL5\Files\NNFX_GuardTest.txt";        Pass = "RESULT: 56 passed, 0 failed, 56 total"; Min = 5 },
        @{ Name = "NNFX_EnvCheck";   Report = "$MT5\MQL5\Files\NNFX_EnvCheck.txt";         Pass = "RESULT: VALID";                          Min = 20; Info = $true },
        @{ Name = "NNFX_ExportBars"; Report = "$MT5\MQL5\Files\NNFX\export\_summary.txt";  Pass = "RESULT: 5 of 5 pairs complete";          Min = 30 }
    )
    $exportStart = $null
    foreach ($s in $scripts) {
        $t0 = Get-Date
        if ($s.Name -eq "NNFX_ExportBars") { $exportStart = $t0 }
        $err = Run-Script $s.Name $s.Min
        $label = "3 " + $s.Name
        if (Fresh $s.Report $t0) {
            Copy-Item $s.Report "$Out\" -Force
            $text = ReadText $s.Report
            $res = ([regex]::Matches($text, "(?m)^RESULT:.*$") | Select-Object -Last 1).Value
            if ($s.Name -eq "NNFX_EnvCheck") {
                # D6c-1: stop if the tested terminal is logged in to another account than expected
                $login = [regex]::Match($text, "(?m)^Login:\s+(\d+)").Groups[1].Value
                $server = [regex]::Match($text, "(?m)^Server:\s+(\S+)").Groups[1].Value
                if ($login -ne "$ExpectLogin" -or $server -ne $ExpectServer) {
                    Step "3 account check" "FAIL" "logged in as '$login' on '$server', expected $ExpectLogin on $ExpectServer"
                    Say ""; Say "OVERALL: FAIL (wrong account). Nothing after EnvCheck was run. Output: $Out"
                    $Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
                    exit 1
                }
                Step "3 account check" "PASS" "$login on $server"
            }
            if ($text.Contains($s.Pass)) {
                Step $label $(if ($s.Info) { "INFO" } else { "PASS" }) $(if ($res) { $res.Trim() } else { "finished" })
            } else {
                Step $label "FAIL" $(if ($res) { $res.Trim() } else { "report has no pass line" + $(if ($err) { "; $err" }) })
            }
        } else {
            $why = if ($err) { $err } else { "MT5 ran but wrote no new report" }
            Step $label "NOT RUN" "$why (automation did not engage; see tests/mql5/README.md)"
        }
    }

    # ---------------------------------------------------------------- 4. repaint check in the Strategy Tester
    $repaint = "$Common\NNFX\reports\Repaint_EURUSD_H1.txt"
    if ($SkipTester) {
        Step "4 repaint check (tester)" "NOT RUN" "skipped with -SkipTester"
    } else {
        $t0 = Get-Date
        $ini = "$Out\run_NNFX_RepaintCheck.ini"
        @("[Tester]", "Expert=NNFX\NNFX_RepaintCheck", "Symbol=EURUSD", "Period=H1", "Model=1",
          "FromDate=$TesterFrom", "ToDate=$TesterTo", "ForwardMode=0", "Optimization=0", "Visual=0",
          "Report=NNFX_RepaintCheck_tester", "ReplaceReport=1", "ShutdownTerminal=1") |
            Set-Content -LiteralPath $ini -Encoding ASCII
        $err = Run-Terminal $ini 60
        if (Fresh $repaint $t0) {
            Copy-Item $repaint "$Out\" -Force
            $text = ReadText $repaint
            $res = ([regex]::Matches($text, "(?m)^RESULT:.*$") | Select-Object -Last 1).Value
            Step "4 repaint check (tester)" $(if ($text.Contains("RESULT: NO REPAINTING FOUND")) { "PASS" } else { "FAIL" }) $(if ($res) { $res.Trim() } else { "report has no RESULT line" })
        } else {
            $why = if ($err) { $err } else { "tester ran but wrote no new report (tester Journal copied)" }
            Step "4 repaint check (tester)" "NOT RUN" "$why (automation did not engage; see tests/mql5/README.md)"
        }
        Get-ChildItem "$MT5\NNFX_RepaintCheck_tester*" -ErrorAction SilentlyContinue | Copy-Item -Destination $Out -Force

        # 4b. Phase 6b order run in the tester (orders are allowed only in the tester or on DEMO)
        $orderSummary = "$Common\NNFX\trades\OrderTest_EURUSD_tester_summary.txt"
        $orderLog = "$Common\NNFX\trades\OrderTest_EURUSD_tester.csv"
        $t0 = Get-Date
        $ini = "$Out\run_NNFX_OrderTest.ini"
        @("[Tester]", "Expert=NNFX\NNFX_OrderTest", "Symbol=EURUSD", "Period=H1", "Model=1",
          "FromDate=$TesterFrom", "ToDate=$TesterTo", "ForwardMode=0", "Optimization=0", "Visual=0",
          "Report=NNFX_OrderTest_tester", "ReplaceReport=1", "ShutdownTerminal=1",
          # EVERY input listed: the tester reuses an EA's last-used value for any input left out
          "[TesterInputs]", "InpRiskPct=2.0", "InpEveryBars=6", "InpMaxTrades=0", "InpMinLots=false", "InpMagic=26999",
          "InpStoplessTest=true", "InpLoseReplyOn=3", "InpAbortOn=7", "InpStopsRefuseOn=9", "InpMarginRefuseOn=11",
          "InpModifyOn=13", "InpStopWhenDone=false", "InpRestartAt=none", "InpRestartDeleteState=false",
          "InpRestartIgnoreComments=false", "InpCloseLeftovers=false") |
            Set-Content -LiteralPath $ini -Encoding ASCII
        $err = Run-Terminal $ini 60
        if ((Fresh $orderSummary $t0) -and (Fresh $orderLog $t0)) {
            Copy-Item $orderSummary, $orderLog "$Out\" -Force
            $res = ([regex]::Matches((ReadText $orderSummary), "(?m)^RESULT:.*$") | Select-Object -Last 1).Value
            Step "4b order run (tester)" "PASS" $(if ($res) { $res.Trim() + "; checked in step 5" } else { "summary has no RESULT line" })
            # no simulated restart in this run: "InpRestartAt=" (empty) was reused from an earlier run in 20261006_004127
            $nr = @(Get-Content -LiteralPath $orderLog | Where-Object { $_ -match "^[^,]*,REBUILD," }).Count
            Step "4b no restart in order run" $(if ($nr -eq 0) { "PASS" } else { "FAIL" }) "$nr REBUILD rows (must be 0)"
            $script:OrderLogThisRun = "$Out\OrderTest_EURUSD_tester.csv"
        } else {
            $why = if ($err) { $err } else { "tester ran but wrote no new trade log" }
            Step "4b order run (tester)" "NOT RUN" "$why (automation did not engage)"
        }
        Get-ChildItem "$MT5\NNFX_OrderTest_tester*" -ErrorAction SilentlyContinue | Copy-Item -Destination $Out -Force
    }
}

# ---------------------------------------------------------------- 5. Python
# Runs Python and returns everything it printed, stdout and stderr in order, as plain text.
# Windows PowerShell 5.1 turns each stderr line into an error record that Out-String prints with
# a "NativeCommandError" wrapper; Exception.Message gives back just the line (ToString() would turn
# an empty line into "System.Management.Automation.RemoteException"). $LASTEXITCODE is Python's.
function Plain($item) {
    if ($item -is [System.Management.Automation.ErrorRecord]) { return [string]$item.Exception.Message }
    return [string]$item
}
function Run-Py([string[]]$pyArgs) {
    $lines = & $script:PyExe @($script:PyPre + $pyArgs) 2>&1 | ForEach-Object { Plain $_ }
    return (($lines | Out-String) -replace "`r?`n", "`r`n")
}

# Find a Python that actually runs (on some PCs "python" is only the Microsoft Store stub).
$candidates = @()
if ($Python) { $candidates += , @($Python) }
$candidates += , @("py", "-3")
$candidates += , @("python")
$installed = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
             Sort-Object { [int]($_.Directory.Name -replace "\D", "") } -Descending | Select-Object -First 1
if ($installed) { $candidates += , @($installed.FullName) }
$script:PyExe = $null; $script:PyPre = @()
foreach ($cand in $candidates) {
    if (-not (Get-Command $cand[0] -ErrorAction SilentlyContinue)) { continue }
    $ver = & $cand[0] @($cand | Select-Object -Skip 1) --version 2>&1 | ForEach-Object { Plain $_ }
    if ($LASTEXITCODE -eq 0 -and ($ver -join " ") -match "^Python 3\.") {
        $script:PyExe = $cand[0]; $script:PyPre = @($cand | Select-Object -Skip 1)
        break
    }
}
if ($script:PyExe) {
    $where = (Run-Py @("-c", "import sys; print(sys.executable + ' (Python ' + sys.version.split()[0] + ')')")).Trim()
    Say "Python: $where  [found as: $((@($script:PyExe) + $script:PyPre) -join ' ')]"
} else {
    Say "Python: none found (tried: $(($candidates | ForEach-Object { $_ -join ' ' }) -join '; '))"
}

$csvs = @()
if ($exportStart) {
    $csvs = @(Get-ChildItem "$MT5\MQL5\Files\NNFX\export\*.csv" -ErrorAction SilentlyContinue |
              Where-Object { $_.LastWriteTime -ge $exportStart } | ForEach-Object { $_.FullName })
}
if (-not $script:PyExe) {
    Step "5 Python unit tests" "FAIL" "no working Python found"
    Step "5 check_export.py" "NOT RUN" "no working Python found"
    Step "5 check_indicators.py" "NOT RUN" "no working Python found"
    Step "5 check_trades.py" "NOT RUN" "no working Python found"
} else {
    $py = Run-Py @("-m", "unittest", "discover", "-s", "$Repo\tests\python")
    $code = $LASTEXITCODE
    $py | Set-Content "$Out\python_unittest.txt" -Encoding ASCII
    $m = [regex]::Match($py, "Ran (\d+) tests")
    Step "5 Python unit tests" $(if ($code -eq 0) { "PASS" } else { "FAIL" }) $(if ($m.Success) { "$($m.Groups[1].Value) tests" } else { "" })

    if ($csvs.Count -eq 0) {
        Step "5 check_export.py" "NOT RUN" "no export written in this run"
        Step "5 check_indicators.py" "NOT RUN" "no export written in this run"
    } else {
        $o = Run-Py (@("$Repo\tools\check_export.py") + $csvs + @("--replay"))
        $code = $LASTEXITCODE
        $o | Set-Content "$Out\check_export.txt" -Encoding ASCII
        $n = ([regex]::Matches($o, "(?m)^RESULT .*: PASS")).Count
        Step "5 check_export.py" $(if ($code -eq 0) { "PASS" } else { "FAIL" }) "$n of $($csvs.Count) files PASS"

        $o = Run-Py (@("$Repo\tools\check_indicators.py") + $csvs)
        $code = $LASTEXITCODE
        $o | Set-Content "$Out\check_indicators.txt" -Encoding ASCII
        $n = ([regex]::Matches($o, "(?m)^RESULT .*: PASS")).Count
        Step "5 check_indicators.py" $(if ($code -eq 0) { "PASS" } else { "FAIL" }) "$n of $($csvs.Count) files PASS"
    }

    if (-not $script:OrderLogThisRun) {
        Step "5 check_trades.py" "NOT RUN" "no order-run trade log written in this run"
    } else {
        $o = Run-Py @("$Repo\tools\check_trades.py", $script:OrderLogThisRun, "--min-trades", "20",
                      "--require", "SL,TP1,BE,TRAILON,TRAIL,TP2,EXIT,RETRY,TESTSTOPLESS,ABORT,REFUSE,MODIFY",
                      "--require-note", "free margin", "--require-note", "minimum distance",
                      "--require-note", "via=")
        $code = $LASTEXITCODE
        $o | Set-Content "$Out\check_trades.txt" -Encoding ASCII
        $res = ([regex]::Matches($o, "(?m)^RESULT .*$") | Select-Object -Last 1).Value
        Step "5 check_trades.py" $(if ($code -eq 0) { "PASS" } else { "FAIL" }) $(if ($res) { $res.Trim() } else { "" })
    }
}

# ---------------------------------------------------------------- logs for the record
$today = Get-Date -Format "yyyyMMdd"
New-Item -ItemType Directory -Force "$Out\logs" | Out-Null
Copy-Item "$MT5\Logs\$today.log"      "$Out\logs\terminal_$today.log" -ErrorAction SilentlyContinue
Copy-Item "$MT5\MQL5\Logs\$today.log" "$Out\logs\experts_$today.log"  -ErrorAction SilentlyContinue
Copy-Item "$MT5\Tester\logs\$today.log" "$Out\logs\tester_$today.log" -ErrorAction SilentlyContinue
Get-ChildItem "$MT5\Tester" -Directory -Filter "Agent-*" -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-Item "$($_.FullName)\logs\$today.log" "$Out\logs\$($_.Name)_$today.log" -ErrorAction SilentlyContinue
}

Say ""
Say $(if ($AllPass) { "OVERALL: PASS" } else { "OVERALL: NOT ALL PASSED (see the lines above)" })
Say "Everything from this run: $Out"
$Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
if ($AllPass) { exit 0 } else { exit 1 }
