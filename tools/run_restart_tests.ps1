<#
run_restart_tests.ps1 - Phase 6c restart test (a): SIMULATED restarts in the Strategy Tester
(docs/PLAN_PHASE6.md section 9; SPEC "Rebuilding after a restart").

  1. Runs NNFX_OrderTest without a restart (test hooks and the stopless test off, so only trading state is involved).
  2. tools/pick_restart_times.py picks a restart time for each state R1-R4 from that run's STATE rows.
  3. Runs NNFX_OrderTest again with InpRestartAt = each time: all memory is thrown away and rebuilt from the
     broker, the state file and the candles. Two extra R2 runs: state file deleted first, comments ignored.
  4. For each run: tools/compare_runs.py compare (identical to the run without a restart, every row and column,
     from the restart on) and tools/compare_runs.py rebuilds (the rebuilt state = the state before, field for field).

Owner decision D6c-1: only the tested terminal (full path) blocks the run; others are listed and never touched;
a terminal is only ever closed by the process id this script started.

Output: <MT5 data folder>\MQL5\Files\NNFX\checks\restart_<date-time>\ with every log, ini and the SUMMARY.txt.
Usage:  powershell -ExecutionPolicy Bypass -File tools\run_restart_tests.ps1
#>
param(
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Common  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [string]$Python  = "C:\Users\Evision\AppData\Local\Programs\Python\Python312\python.exe",
    [string]$From    = "2026.06.01",
    [string]$To      = "2026.10.01"
)
$ErrorActionPreference = "Continue"
$Terminal = Join-Path $Install "terminal64.exe"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Out = Join-Path $MT5 "MQL5\Files\NNFX\checks\restart_$Stamp"
$Log = "$Common\NNFX\trades\OrderTest_EURUSD_tester.csv"
$Summary = New-Object System.Collections.Generic.List[string]
$AllPass = $true
function Say([string]$t) { Write-Host $t; $script:Summary.Add($t) }
function Step([string]$name, [bool]$ok, [string]$detail) {
    if (-not $ok) { $script:AllPass = $false }
    Say (("{0,-40} {1}" -f $name, $(if ($ok) { "PASS" } else { "FAIL" })) + $(if ($detail) { "  - $detail" } else { "" }))
}

$running = @(Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path })
if (@($running | Where-Object { $_.Path -ieq $Terminal }).Count -gt 0) {
    Write-Host "STOP: the tested MetaTrader 5 ($Terminal) is open. Close it (File > Exit) and run this again."; exit 2
}
New-Item -ItemType Directory -Force $Out | Out-Null
Say "NNFX restart tests (simulated, tester)  $Stamp"
Say "Repo: $Repo  (commit $(& git -C $Repo rev-parse --short HEAD 2>$null))"
foreach ($o in @($running | Where-Object { $_.Path -ine $Terminal })) { Say ("other terminal running (ignored): pid {0} {1}" -f $o.Id, $o.Path) }
Say ""

# Restart scenario: no test hooks, no stopless test. EVERY input is listed in every run: the Strategy Tester
# reuses an EA's last-used value for any input left out (found in run restart_20261005_224233, kept in invalid\),
# AND for an input listed with an EMPTY value: "InpRestartAt=" did not clear it, so the base run of
# restart_20261005_225140 restarted too (kept in invalid\). "No restart" is "InpRestartAt=none", and every run's
# REBUILD rows are counted: the base must have 0, each restart run exactly 1.
$defaults = [ordered]@{ InpRiskPct = "2.0"; InpEveryBars = "6"; InpMaxTrades = "0"; InpMinLots = "false"; InpMagic = "26999";
    InpStoplessTest = "false"; InpLoseReplyOn = "0"; InpAbortOn = "0"; InpStopsRefuseOn = "0"; InpMarginRefuseOn = "0";
    InpModifyOn = "0"; InpStopWhenDone = "false"; InpRestartAt = "none"; InpRestartDeleteState = "false";
    InpRestartIgnoreComments = "false" }
function Run-Tester([string]$name, [string[]]$inputs) {
    $ini = "$Out\run_$name.ini"
    $vals = [ordered]@{}
    foreach ($k in $defaults.Keys) { $vals[$k] = $defaults[$k] }
    foreach ($kv in $inputs) { $i = $kv.IndexOf("="); $vals[$kv.Substring(0, $i)] = $kv.Substring($i + 1) }
    $lines = @($vals.Keys | ForEach-Object { "$_=$($vals[$_])" })
    @("[Tester]", "Expert=NNFX\NNFX_OrderTest", "Symbol=EURUSD", "Period=H1", "Model=1", "FromDate=$From", "ToDate=$To",
      "ForwardMode=0", "Optimization=0", "Visual=0", "Report=NNFX_RestartTest_$name", "ReplaceReport=1", "ShutdownTerminal=1",
      "[TesterInputs]") + $lines | Set-Content -LiteralPath $ini -Encoding ASCII
    $t0 = Get-Date
    $p = Start-Process -FilePath $Terminal -ArgumentList "/config:`"$ini`"" -PassThru
    if (-not $p.WaitForExit(3600000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; return $null }
    Start-Sleep -Seconds 2
    if ((Test-Path $Log) -and (Get-Item $Log).LastWriteTime -ge $t0) {
        Copy-Item $Log "$Out\$name.csv" -Force
        return "$Out\$name.csv"
    }
    return $null
}
function Rebuild-Rows([string]$csv) { return @(Get-Content -LiteralPath $csv | Where-Object { $_ -match "^[^,]*,REBUILD," }).Count }
function Py([string[]]$a) {
    $lines = & $Python @a 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ } }
    return @{ Code = $LASTEXITCODE; Text = (($lines | Out-String) -replace "`r?`n", "`r`n") }
}

$b = Run-Tester "base" @("InpRestartAt=none")
if (-not $b) { Step "base run (no restart)" $false "no fresh trade log"; $Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII; exit 1 }
$n = Rebuild-Rows $b
Step "base run (no restart)" ($n -eq 0) "$n REBUILD rows (must be 0) - $b"
if ($n -ne 0) { $Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII; exit 1 }
$pick = Py @("$Repo\tools\pick_restart_times.py", $b)
$pick.Text | Set-Content "$Out\pick_restart_times.txt" -Encoding ASCII
$times = @{}
foreach ($line in ($pick.Text -split "`r`n")) {
    $m = [regex]::Match($line, "^(R\d) (\d{4}\.\d\d\.\d\d \d\d:\d\d(:\d\d)?)")
    if ($m.Success) { $times[$m.Groups[1].Value] = $m.Groups[2].Value.Substring(0, 16) }
}
Step "restart times picked" ($pick.Code -eq 0) (($times.Keys | Sort-Object | ForEach-Object { "$_ $($times[$_])" }) -join "; ")

$runs = @(
    @{ Name = "R1"; At = $times["R1"]; Extra = @() },
    @{ Name = "R2"; At = $times["R2"]; Extra = @() },
    @{ Name = "R3"; At = $times["R3"]; Extra = @() },
    @{ Name = "R4"; At = $times["R4"]; Extra = @() },
    @{ Name = "R2_state_deleted"; At = $times["R2"]; Extra = @("InpRestartDeleteState=true") },
    @{ Name = "R2_comments_ignored"; At = $times["R2"]; Extra = @("InpRestartIgnoreComments=true") }
)
foreach ($r in $runs) {
    if (-not $r.At) { Step "$($r.Name) restart" $false "no restart time"; continue }
    $f = Run-Tester $r.Name (@("InpRestartAt=$($r.At)") + $r.Extra)
    if (-not $f) { Step "$($r.Name) restart at $($r.At)" $false "no fresh trade log"; continue }
    $n = Rebuild-Rows $f
    Step "$($r.Name) restarted once" ($n -eq 1) "$n REBUILD rows (must be 1)"
    $c = Py @("$Repo\tools\compare_runs.py", "compare", $b, $f, "--from", $r.At)
    $c.Text | Set-Content "$Out\$($r.Name).compare.txt" -Encoding ASCII
    $res = ([regex]::Matches($c.Text, "(?m)^RESULT.*$") | Select-Object -Last 1).Value
    Step "$($r.Name) compare (from $($r.At))" ($c.Code -eq 0) $res.Trim()
    $k = Py @("$Repo\tools\compare_runs.py", "rebuilds", $f)
    $k.Text | Set-Content "$Out\$($r.Name).rebuilds.txt" -Encoding ASCII
    $res = ([regex]::Matches($k.Text, "(?m)^RESULT.*$") | Select-Object -Last 1).Value
    Step "$($r.Name) rebuilt = before" ($k.Code -eq 0) $res.Trim()
}
Say ""
Say $(if ($AllPass) { "OVERALL: PASS" } else { "OVERALL: NOT ALL PASSED (see the lines above)" })
Say "Everything from this run: $Out"
$Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
if ($AllPass) { exit 0 } else { exit 1 }
