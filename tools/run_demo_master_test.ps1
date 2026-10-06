<#
run_demo_master_test.ps1 - Phase 6d demo master-switch test (docs/PLAN_PHASE6.md section 5, "Master switch").

"Demo: two charts with the test EA. Set the global variable off -> both log blocked:master on their next candle;
open test trades keep being managed."

  1. D6c-1 account check (NNFX_EnvCheck): stop if not the expected demo account.
  2. NNFX_TemplateProbe saves a chart template, to get this build's .tpl format; its <expert> block is replaced by
     instance B (NNFX_OrderTest on GBPUSD M1, magic 26994, guard on) -> MQL5\Profiles\Templates\nnfx_master_b.tpl.
  3. Instance A (NNFX_OrderTest on EURUSD M1, magic 26993, guard on, InpMasterTestTpl=nnfx_master_b) starts: it sets
     NNFX_MASTER = 1, opens B's chart from the template, switches NNFX_MASTER to 0 after 5 candles and back to 1
     after 5 more (GUARD rows). Every input listed; MT5 must read them all.
  3b. OFF comes after 10 candles, so instance B (its history loaded) is running (run master_20261006_135454).
  4. After ON, A drives its chart buttons through the panel (instance off, on, drawdown reset, close-all; one
     every two candles); ten candles after ON, MT5 (the driver's own PID; D-OPS-1) is closed.
  5. tools/close_test_leftovers.ps1 closes both magics' leftover test trades and checks the whole account is flat
     (G1_phase6c_2 verdict note 2).
  6. tools/check_master_test.py --panel on both logs; tools/check_trades.py on each.
Weekday, market open. Minimum lots. Nobody needs to watch it.
Output: <MT5 data folder>\MQL5\Files\NNFX\checks\master_<date-time>\
Usage:  powershell -ExecutionPolicy Bypass -File tools\run_demo_master_test.ps1
#>
param(
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Common  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [string]$Python  = "C:\Users\Evision\AppData\Local\Programs\Python\Python312\python.exe",
    [long]$ExpectLogin = 113593254,
    [string]$ExpectServer = "MetaQuotes-Demo",
    [int]$Minutes = 40
)
$ErrorActionPreference = "Continue"
$Terminal = Join-Path $Install "terminal64.exe"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Out = Join-Path $MT5 "MQL5\Files\NNFX\checks\master_$Stamp"
$Summary = New-Object System.Collections.Generic.List[string]
$AllPass = $true
function Say([string]$t) { Write-Host $t; $script:Summary.Add($t) }
function Step([string]$name, [bool]$ok, [string]$detail) {
    if (-not $ok) { $script:AllPass = $false }
    Say (("{0,-40} {1}" -f $name, $(if ($ok) { "PASS" } else { "FAIL" })) + $(if ($detail) { "  - $detail" } else { "" }))
}
function Done { Say ""; Say $(if ($script:AllPass) { "OVERALL: PASS" } else { "OVERALL: NOT ALL PASSED (see the lines above)" })
    Say "Everything from this run: $Out"; $script:Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
    if ($script:AllPass) { exit 0 } else { exit 1 } }
function Tested-Open { return @(Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $Terminal }) }
function Start-MT5([string]$ini) { return Start-Process -FilePath $Terminal -ArgumentList "/config:`"$ini`"" -PassThru }
function Close-MT5($p) {
    if ($p -and -not $p.HasExited) {
        $null = $p.CloseMainWindow()
        if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Say "  (pid $($p.Id) did not close in 120 s: stopped by id)" }
    }
}
# The EA keeps its trade log open: read it shared (Get-Content fails on it; run master_20261006_122240, kept in invalid\)
function Read-Shared([string]$path) {
    try {
        $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $sr = New-Object System.IO.StreamReader($fs)
        $text = $sr.ReadToEnd()
        $sr.Close()
        return $text
    } catch { return "" }
}
function Write-Set([string]$name, [string[]]$lines) {
    [System.IO.File]::WriteAllText("$MT5\MQL5\Presets\$name", (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::Unicode)
    Copy-Item "$MT5\MQL5\Presets\$name" "$Out\" -Force
}

if ((Tested-Open).Count -gt 0) { Write-Host "STOP: the tested MetaTrader 5 ($Terminal) is open. Close it and run this again."; exit 2 }
New-Item -ItemType Directory -Force "$Out", "$MT5\MQL5\Presets" | Out-Null
Say "NNFX demo master-switch test  $Stamp"
Say "Repo: $Repo  (commit $(& git -C $Repo rev-parse --short HEAD 2>$null))"
Say ""
$LogA = "$Common\NNFX\trades\OrderTest_EURUSD_demo.csv"
$LogB = "$Common\NNFX\trades\OrderTest_GBPUSD_demo.csv"
foreach ($sym in "EURUSD", "GBPUSD") {
    foreach ($f in @("$MT5\MQL5\Files\NNFX\state\OrderTest_$sym.txt", "$MT5\MQL5\Files\NNFX\state\OrderTest_${sym}_schedule.txt",
                     "$Common\NNFX\trades\OrderTest_${sym}_demo.csv")) {
        if (Test-Path $f) { Move-Item $f "$Out\before_this_run_$(Split-Path $f -Leaf)" -Force }   # kept, never deleted
    }
}

# 1. account check (D6c-1)
Write-Set "NNFX_EnvCheck_quick.set" @("InpCheckTicks=false")
@("[StartUp]", "Script=NNFX\NNFX_EnvCheck", "ScriptParameters=NNFX_EnvCheck_quick.set", "Symbol=EURUSD", "Period=H1", "ShutdownTerminal=1") |
    Set-Content "$Out\run_envcheck.ini" -Encoding ASCII
$t0 = Get-Date
$p = Start-MT5 "$Out\run_envcheck.ini"
if (-not $p.WaitForExit(600000)) { Close-MT5 $p }
$env = "$MT5\MQL5\Files\NNFX_EnvCheck.txt"
$text = if ((Test-Path $env) -and (Get-Item $env).LastWriteTime -ge $t0) { Get-Content $env -Raw } else { "" }
Copy-Item $env "$Out\" -ErrorAction SilentlyContinue
$login = [regex]::Match($text, "(?m)^Login:\s+(\d+)").Groups[1].Value
$server = [regex]::Match($text, "(?m)^Server:\s+(\S+)").Groups[1].Value
$okAcc = ($login -eq "$ExpectLogin" -and $server -eq $ExpectServer -and $text.Contains("Trade mode:   DEMO"))
Step "account check" $okAcc "'$login' on '$server'"
if (-not $okAcc) { Say "STOP: not the expected demo account; nothing was traded."; Done }

# 2. template for instance B, from this build's own .tpl format
$probeTpl = "$MT5\MQL5\Profiles\Templates\nnfx_template_probe.tpl"
@("[StartUp]", "Expert=NNFX\NNFX_TemplateProbe", "Symbol=GBPUSD", "Period=M1") | Set-Content "$Out\run_probe.ini" -Encoding ASCII
$t0 = Get-Date
$p = Start-MT5 "$Out\run_probe.ini"
$end = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $end -and -not ((Test-Path $probeTpl) -and (Get-Item $probeTpl).LastWriteTime -gt $t0)) { Start-Sleep -Seconds 3 }
Start-Sleep -Seconds 2
Close-MT5 $p
$fresh = (Test-Path $probeTpl) -and (Get-Item $probeTpl).LastWriteTime -gt $t0
Step "template probe" $fresh $(if ($fresh) { "nnfx_template_probe.tpl written" } else { "no fresh template" })
if (-not $fresh) { Done }
Copy-Item $probeTpl "$Out\" -Force

# every NNFX_OrderTest input listed (test_input_lists.py); A and B differ in magic, symbol and the test inputs
$inputsB = @("InpRiskPct=2.0", "InpEveryBars=1", "InpMaxTrades=0", "InpMinLots=true", "InpMagic=26994", "InpStoplessTest=false",
    "InpLoseReplyOn=0", "InpAbortOn=0", "InpStopsRefuseOn=0", "InpMarginRefuseOn=0", "InpModifyOn=0", "InpStopWhenDone=false",
    "InpRestartAt=none", "InpRestartDeleteState=false", "InpRestartIgnoreComments=false", "InpCloseLeftovers=false",
    "InpGuard=true", "InpInstanceOn=true", "InpServerWinterOffset=2", "InpServerDst=US", "InpWeekendHours=0",
    "InpMaxSpread=0", "InpTesterMaster=-1", "InpTesterPauseAt=none",
    "InpMasterTestTpl=", "InpMasterTestSymbol=GBPUSD", "InpMasterOffAfter=10", "InpMasterOffFor=5")

$inputsA = @("InpRiskPct=2.0", "InpEveryBars=1", "InpMaxTrades=0", "InpMinLots=true", "InpMagic=26993", "InpStoplessTest=false",
    "InpLoseReplyOn=0", "InpAbortOn=0", "InpStopsRefuseOn=0", "InpMarginRefuseOn=0", "InpModifyOn=0", "InpStopWhenDone=false",
    "InpRestartAt=none", "InpRestartDeleteState=false", "InpRestartIgnoreComments=false", "InpCloseLeftovers=false",
    "InpGuard=true", "InpInstanceOn=true", "InpServerWinterOffset=2", "InpServerDst=US", "InpWeekendHours=0",
    "InpMaxSpread=0", "InpTesterMaster=-1", "InpTesterPauseAt=none",
    "InpMasterTestTpl=nnfx_master_b", "InpMasterTestSymbol=GBPUSD", "InpMasterOffAfter=10", "InpMasterOffFor=5")

$tpl = [System.IO.File]::ReadAllText($probeTpl, [System.Text.Encoding]::Unicode)
$expertB = "<expert>`r`nname=NNFX_OrderTest`r`npath=Experts\NNFX\NNFX_OrderTest.ex5`r`nexpertmode=1`r`n<inputs>`r`n" +
           (($inputsB | ForEach-Object { $_ }) -join "`r`n") + "`r`n</inputs>`r`n</expert>"
$tplB = [regex]::Replace($tpl, "(?s)<expert>.*?</expert>", [System.Text.RegularExpressions.MatchEvaluator] { param($m) $expertB })
if ($tplB -eq $tpl) { Step "template B" $false "no <expert> block to replace"; Done }
[System.IO.File]::WriteAllText("$MT5\MQL5\Profiles\Templates\nnfx_master_b.tpl", $tplB, [System.Text.Encoding]::Unicode)
Copy-Item "$MT5\MQL5\Profiles\Templates\nnfx_master_b.tpl" "$Out\" -Force
Step "template B" $true "nnfx_master_b.tpl: NNFX_OrderTest, magic 26994, $($inputsB.Count) inputs"

# 3. instance A
Write-Set "NNFX_OrderTest_masterA.set" $inputsA
@("[StartUp]", "Expert=NNFX\NNFX_OrderTest", "ExpertParameters=NNFX_OrderTest_masterA.set", "Symbol=EURUSD", "Period=M1") |
    Set-Content "$Out\run_master.ini" -Encoding ASCII
$t0 = Get-Date
$p = Start-MT5 "$Out\run_master.ini"
Say ("started pid {0} at {1}" -f $p.Id, (Get-Date -Format "HH:mm:ss"))
$on = $null
$end = (Get-Date).AddMinutes($Minutes)
while ((Get-Date) -lt $end) {
    Start-Sleep -Seconds 10
    if ($p.HasExited) { Say "pid $($p.Id) exited by itself"; break }
    if (Test-Path $LogA) {
        $hit = [regex]::Matches((Read-Shared $LogA), ",GUARD,.*NNFX_MASTER = 1 \(ON\)")
        if ($hit.Count -gt 0 -and -not $on) { $on = Get-Date; Say ("master back ON seen at {0}; 10 more candles (the panel steps)" -f (Get-Date -Format "HH:mm:ss")) }
    }
    if ($on -and (Get-Date) -gt $on.AddMinutes(10)) { break }
}
# MT5 reads every input of A (its own log line), checked after the run from the terminal log
Close-MT5 $p
Start-Sleep -Seconds 3
$day = Get-Date -Format "yyyyMMdd"
Copy-Item "$MT5\Logs\$day.log" "$Out\terminal_$day.log" -ErrorAction SilentlyContinue
Copy-Item "$MT5\MQL5\Logs\$day.log" "$Out\experts_$day.log" -ErrorAction SilentlyContinue
foreach ($f in @($LogA, $LogB)) { if (Test-Path $f) { Copy-Item $f "$Out\" -Force } }
$tl = if (Test-Path "$Out\terminal_$day.log") { Get-Content "$Out\terminal_$day.log" -Encoding Unicode } else { @() }
$readA = @($tl | Where-Object { $_ -match "(\d+) inputs read from expert 'NNFX\\NNFX_OrderTest' set file .*NNFX_OrderTest_masterA" } | Select-Object -Last 1)
$nA = if ($readA.Count) { [int][regex]::Match($readA[0], "(\d+) inputs read").Groups[1].Value } else { -1 }
Step "A read every input" ($nA -eq $inputsA.Count) "$nA of $($inputsA.Count)"
Step "master switched OFF and back ON" ([bool]$on) $(if ($on) { "ON seen" } else { "not within $Minutes minutes" })

# 5. leftovers and the whole account flat
$c = & powershell -NoProfile -ExecutionPolicy Bypass -Command "& '$Repo\tools\close_test_leftovers.ps1' -Magics 26993,26994" 2>&1 | ForEach-Object { [string]$_ }
$c | Set-Content "$Out\close_test_leftovers.txt" -Encoding ASCII
$flat = @($c | Where-Object { $_ -match "^whole account flat\s+PASS" }).Count -gt 0
Step "leftovers closed, whole account flat" $flat (@($c | Where-Object { $_ -match "^whole account flat" }) -join "")

# 6. checks
if ((Test-Path "$Out\OrderTest_EURUSD_demo.csv") -and (Test-Path "$Out\OrderTest_GBPUSD_demo.csv")) {
    foreach ($ck in @(@{ N = "check_master_test"; A = @("$Repo\tools\check_master_test.py", "$Out\OrderTest_EURUSD_demo.csv", "$Out\OrderTest_GBPUSD_demo.csv", "--panel") },
                      @{ N = "check_trades A"; A = @("$Repo\tools\check_trades.py", "$Out\OrderTest_EURUSD_demo.csv", "--require-note", "orders allowed: DEMO", "--be-lag-seconds", "2") },
                      @{ N = "check_trades B"; A = @("$Repo\tools\check_trades.py", "$Out\OrderTest_GBPUSD_demo.csv", "--require-note", "orders allowed: DEMO", "--be-lag-seconds", "2") })) {
        $lines = & $Python @($ck.A) 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ } }
        $code = $LASTEXITCODE
        $txt = (($lines | Out-String) -replace "`r?`n", "`r`n")
        $txt | Set-Content ("$Out\" + ($ck.N -replace "[^A-Za-z0-9]+", "_") + ".txt") -Encoding ASCII
        $res = ([regex]::Matches($txt, "(?m)^RESULT.*$") | Select-Object -Last 1).Value
        Step $ck.N ($code -eq 0) $res.Trim()
    }
} else {
    Step "logs of A and B" $false "missing: $(if (-not (Test-Path "$Out\OrderTest_EURUSD_demo.csv")) { 'A ' })$(if (-not (Test-Path "$Out\OrderTest_GBPUSD_demo.csv")) { 'B' })"
}
Done
