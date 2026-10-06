<#
close_test_leftovers.ps1 - D-OPS-1 (owner, 2026-10-06): close the agent's own leftover TEST trades on the demo.

Only MetaQuotes-Demo 113593254, only test magics 26990-26999, only through Orders.mqh: for each -Magics value,
MT5 is started with NNFX_OrderTest and InpCloseLeftovers=true. The EA rebuilds that magic's open trades from the
broker, closes each one with CloseRemaining (logged as EXIT/CLOSE rows), writes an INFO row with the positions left,
and removes itself; it opens nothing. The EA refuses the mode on a non-demo account or any other magic.

  1. D6c-1 account check (NNFX_EnvCheck) first: stop if not the expected demo account.
  2. One MT5 start per magic (the driver's own PID only; closed by that PID).
  3. PASS when every magic's INFO row says "this magic 0" and the last one says "test magics 26990-26999 0".

Output: <MT5 data folder>\MQL5\Files\NNFX\checks\cleanup_<date-time>\ (SUMMARY.txt, the cleanup log, logs).
Usage:  powershell -ExecutionPolicy Bypass -Command "& .\tools\close_test_leftovers.ps1 -Magics 26998,26997"
        (not -File: it passes "26998,26997" as one string; run cleanup_20261006_091939, kept in invalid\)
#>
param(
    [long[]]$Magics,
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Common  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [long]$ExpectLogin = 113593254,
    [string]$ExpectServer = "MetaQuotes-Demo"
)
$ErrorActionPreference = "Continue"
$Terminal = Join-Path $Install "terminal64.exe"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Out = Join-Path $MT5 "MQL5\Files\NNFX\checks\cleanup_$Stamp"
$Log = "$Common\NNFX\trades\OrderTest_EURUSD_cleanup.csv"
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
function Start-MT5([string]$ini) { return Start-Process -FilePath $Terminal -ArgumentList "/config:`"$ini`"" -PassThru }
function Close-MT5($p) {
    if ($p -and -not $p.HasExited) {
        $null = $p.CloseMainWindow()
        if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Say "  (pid $($p.Id) did not close in 120 s: stopped by id)" }
    }
}
function Write-Set([string]$name, [string[]]$lines) {
    [System.IO.File]::WriteAllText("$MT5\MQL5\Presets\$name", (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::Unicode)
    Copy-Item "$MT5\MQL5\Presets\$name" "$Out\" -Force
}

$running = @(Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path })
if (@($running | Where-Object { $_.Path -ieq $Terminal }).Count -gt 0) {
    Write-Host "STOP: the tested MetaTrader 5 ($Terminal) is open. Close it and run this again."; exit 2
}
New-Item -ItemType Directory -Force "$Out", "$MT5\MQL5\Presets" | Out-Null
Say "NNFX test leftovers cleanup (D-OPS-1)  $Stamp"
Say "Repo: $Repo  (commit $(& git -C $Repo rev-parse --short HEAD 2>$null))"
foreach ($o in @($running | Where-Object { $_.Path -ine $Terminal })) { Say ("other terminal running (ignored): pid {0} {1}" -f $o.Id, $o.Path) }
foreach ($m in $Magics) { if ($m -lt 26990 -or $m -gt 26999) { Say "STOP: magic $m is not a test magic (26990-26999)"; $script:AllPass = $false; Done } }
Say ""

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
if (-not $okAcc) { Say "STOP: not the expected demo account; nothing was closed."; Done }

# 2. one start per magic; every EA input listed
$last = ""
foreach ($m in $Magics) {
    $set = "NNFX_OrderTest_cleanup_$m.set"
    Write-Set $set @("InpRiskPct=2.0", "InpEveryBars=2", "InpMaxTrades=0", "InpMinLots=true", "InpMagic=$m", "InpStoplessTest=false",
        "InpLoseReplyOn=0", "InpAbortOn=0", "InpStopsRefuseOn=0", "InpMarginRefuseOn=0", "InpModifyOn=0", "InpStopWhenDone=false",
        "InpRestartAt=none", "InpRestartDeleteState=false", "InpRestartIgnoreComments=false", "InpCloseLeftovers=true")
    $ini = "$Out\run_cleanup_$m.ini"
    @("[StartUp]", "Expert=NNFX\NNFX_OrderTest", "ExpertParameters=$set", "Symbol=EURUSD", "Period=M1") |
        Set-Content $ini -Encoding ASCII
    $t0 = Get-Date
    $p = Start-MT5 $ini
    $row = ""
    $end = (Get-Date).AddMinutes(5)
    while ((Get-Date) -lt $end -and -not $row) {
        Start-Sleep -Seconds 5
        if (Test-Path $Log) {
            $hit = @(Get-Content -LiteralPath $Log | Where-Object { $_ -match ",INFO,.*cleanup magic $m\b" })
            if ($hit.Count -gt 0 -and (Get-Item $Log).LastWriteTime -ge $t0) { $row = $hit[-1] }
        }
    }
    Start-Sleep -Seconds 3
    Close-MT5 $p
    $msg = if ($row) { ($row -split ",", 25)[24] } else { "no cleanup row within 5 minutes" }
    Step "magic $m closed" ($row -match "this magic 0,|this magic 0;|this magic 0 ") $msg
    $last = $msg
}
Step "test magics 26990-26999 flat" ($last -match "test magics 26990-26999 0\b") $last
Step "whole account flat" ($last -match "whole account 0\b") $last
Start-Sleep -Seconds 3
if (Test-Path $Log) { Copy-Item $Log "$Out\" -Force }
$day = Get-Date -Format "yyyyMMdd"
Copy-Item "$MT5\Logs\$day.log" "$Out\terminal_$day.log" -ErrorAction SilentlyContinue
Copy-Item "$MT5\MQL5\Logs\$day.log" "$Out\experts_$day.log" -ErrorAction SilentlyContinue
Done
