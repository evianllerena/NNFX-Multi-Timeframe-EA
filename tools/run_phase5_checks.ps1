<#
run_phase5_checks.ps1 - runs every Phase 5 check with no clicking, and writes one summary.

What it does, in order (each step's result goes in SUMMARY.txt):
  1. Copies the repo's MQL5 files, fixtures and profiles into MT5.
  2. Compiles all five MQL5 programs; each must report 0 errors, 0 warnings.
  3. Starts MT5 once per script with a /config file ([StartUp] Script=..., ShutdownTerminal=1):
       NNFX_RulesTest   pass line  RESULT: 47 passed, 0 failed, 47 total
       NNFX_SignalTest  pass line  RESULT: 56 passed, 0 failed, 56 total
       NNFX_EnvCheck    information only (must finish: "== END ==")
       NNFX_ExportBars  pass line  RESULT: 5 of 5 pairs complete
     A report only counts if it was written during this run.
  4. Starts the Strategy Tester with a /config file ([Tester] Expert=NNFX\NNFX_RepaintCheck ...)
       pass line  RESULT: NO REPAINTING FOUND
  5. Runs the Python tests, tools/check_export.py --replay and tools/check_indicators.py on the
     exports written in step 3.

Everything (reports, compile logs, MT5 logs, Python output, SUMMARY.txt) is copied to
  <MT5 data folder>\MQL5\Files\NNFX\checks\<date-time>\
so it can be read back as-is.

MT5 must be CLOSED before running: what /config does when the terminal is already open is not
documented, so the script refuses to start rather than guess.

If a step cannot be automated on this PC (MT5 starts but no fresh report appears), the step is
marked "NOT RUN (automation did not engage)" and the manual steps in tests/mql5/README.md apply.

Usage (PowerShell, from anywhere):
  powershell -ExecutionPolicy Bypass -File C:\Users\Evision\NNFX-Multi-Timeframe-EA\tools\run_phase5_checks.ps1
#>
param(
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Common  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [string]$Python  = "python",
    [string]$TesterFrom = "2026.06.01",
    [string]$TesterTo   = "2026.10.01",
    [switch]$SkipTester
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
if (Get-Process -Name terminal64 -ErrorAction SilentlyContinue) {
    Write-Host "STOP: MetaTrader 5 is open. Close it (File > Exit) and run this again."
    exit 2
}
New-Item -ItemType Directory -Force $Out | Out-Null
Say "NNFX Phase 5 checks  $Stamp"
Say "Repo:   $Repo  (commit $(& git -C $Repo rev-parse --short HEAD 2>$null))"
Say "MT5:    $MT5"
Say ""

# ---------------------------------------------------------------- 1. copy
New-Item -ItemType Directory -Force "$MT5\MQL5\Include\NNFX", "$MT5\MQL5\Scripts\NNFX", "$MT5\MQL5\Experts\NNFX",
    "$MT5\MQL5\Files\NNFX\fixtures", "$MT5\MQL5\Files\NNFX\signals", "$MT5\MQL5\Files\NNFX\profiles_bad",
    "$MT5\MQL5\Files\NNFX\export", "$Common\NNFX\profiles", "$Common\NNFX\reports" | Out-Null
$ErrorActionPreference = "Stop"
Copy-Item "$Repo\MQL5\Include\NNFX\*.mqh" "$MT5\MQL5\Include\NNFX\" -Force
Copy-Item "$Repo\MQL5\Scripts\NNFX\*.mq5" "$MT5\MQL5\Scripts\NNFX\" -Force
Copy-Item "$Repo\MQL5\Experts\NNFX\*.mq5" "$MT5\MQL5\Experts\NNFX\" -Force
Copy-Item "$Repo\tests\fixtures\mql5\*.txt" "$MT5\MQL5\Files\NNFX\fixtures\" -Force
Copy-Item "$Repo\tests\fixtures\signals\signal_cases.txt" "$MT5\MQL5\Files\NNFX\signals\" -Force
Copy-Item "$Repo\tests\fixtures\profiles_bad\*.txt" "$MT5\MQL5\Files\NNFX\profiles_bad\" -Force
Copy-Item "$Repo\profiles\*.txt" "$Common\NNFX\profiles\" -Force
$ErrorActionPreference = "Continue"
Step "1 copy files" "PASS" ""

# ---------------------------------------------------------------- 2. compile
$programs = @("Scripts\NNFX\NNFX_RulesTest", "Scripts\NNFX\NNFX_SignalTest", "Scripts\NNFX\NNFX_ExportBars",
              "Scripts\NNFX\NNFX_EnvCheck", "Experts\NNFX\NNFX_RepaintCheck")
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
    @{ Name = "NNFX_EnvCheck";   Report = "$MT5\MQL5\Files\NNFX_EnvCheck.txt";         Pass = "== END ==";                              Min = 20; Info = $true },
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
}

# ---------------------------------------------------------------- 5. Python
$py = & $Python -m unittest discover -s "$Repo\tests\python" 2>&1 | Out-String
$py | Set-Content "$Out\python_unittest.txt" -Encoding ASCII
$m = [regex]::Match($py, "Ran (\d+) tests")
Step "5 Python unit tests" $(if ($LASTEXITCODE -eq 0) { "PASS" } else { "FAIL" }) $(if ($m.Success) { "$($m.Groups[1].Value) tests" } else { "" })

$csvs = @()
if ($exportStart) {
    $csvs = @(Get-ChildItem "$MT5\MQL5\Files\NNFX\export\*.csv" -ErrorAction SilentlyContinue |
              Where-Object { $_.LastWriteTime -ge $exportStart } | ForEach-Object { $_.FullName })
}
if ($csvs.Count -eq 0) {
    Step "5 check_export.py" "NOT RUN" "no export written in this run"
    Step "5 check_indicators.py" "NOT RUN" "no export written in this run"
} else {
    $o = & $Python "$Repo\tools\check_export.py" @csvs --replay 2>&1 | Out-String
    $code = $LASTEXITCODE
    $o | Set-Content "$Out\check_export.txt" -Encoding ASCII
    $n = ([regex]::Matches($o, "(?m)^RESULT .*: PASS")).Count
    Step "5 check_export.py" $(if ($code -eq 0) { "PASS" } else { "FAIL" }) "$n of $($csvs.Count) files PASS"

    $o = & $Python "$Repo\tools\check_indicators.py" @csvs 2>&1 | Out-String
    $code = $LASTEXITCODE
    $o | Set-Content "$Out\check_indicators.txt" -Encoding ASCII
    $n = ([regex]::Matches($o, "(?m)^RESULT .*: PASS")).Count
    Step "5 check_indicators.py" $(if ($code -eq 0) { "PASS" } else { "FAIL" }) "$n of $($csvs.Count) files PASS"
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
