<#
run_ea_tester.ps1 - one Strategy Tester run of NNFX_EA (Phase 6f; docs/PLAN_PHASE6.md 6f, MT5 tests), checked.

  1. Copies the repo's MQL5 files into MT5 and compiles NNFX_EA (0 errors, 0 warnings required).
  2. Writes a /config file that lists EVERY input of NNFX_EA (the tester reuses the last-used value of an input that
     is left out or empty; runs restart_20261005_224233 / 225140), with the -Set overrides applied.
  3. Starts MT5 with it (D-OPS-1: the full-path terminal only) and waits for it to close.
  4. Copies the trade log, the decision log, the tester report and the tester log into
     MQL5\Files\NNFX\checks\ea_<Tag>_<stamp>\ and runs:
       tools/check_trades.py <trade log>                                   RESULT ...: PASS (0 failures)
       tools/check_decision_log.py <decision log> --tf --pairs --trades    RESULT ...: PASS (0 failures)
  5. SUMMARY.txt with every step; OVERALL: PASS only if every step passed.

Usage:
  powershell -ExecutionPolicy Bypass -File tools\run_ea_tester.ps1 -Period H1 -From 2026.06.01 -To 2026.10.01 -Tag h1_3m
  ... -Set "InpRestartAt=2026.07.15 00:00","InpTesterMasterOff=2026.07.13 00:00;2026.07.15 00:00"
#>
param(
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Common  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [string]$Python  = "C:\Users\Evision\AppData\Local\Programs\Python\Python312\python.exe",
    [ValidateSet("M30", "H1", "H4")] [string]$Period = "H1",
    [string]$From    = "2026.06.01",
    [string]$To      = "2026.10.01",
    [string]$Symbol  = "EURUSD",            # the chart symbol (the basket is InpPairs)
    [int]$Model      = 1,                   # 1 = 1 minute OHLC
    [string]$Tag     = "run",
    [string[]]$Set   = @(),                 # "InpName=value" overrides
    [int]$TimeoutMin = 120,
    [int]$MinTrades  = 1
)
$ErrorActionPreference = "Continue"
$Terminal = Join-Path $Install "terminal64.exe"
$ME = Join-Path $Install "MetaEditor64.exe"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Out = Join-Path $MT5 "MQL5\Files\NNFX\checks\ea_$($Tag)_$Stamp"
New-Item -ItemType Directory -Force $Out | Out-Null
$Summary = New-Object System.Collections.Generic.List[string]
$AllPass = $true
function Say([string]$t) { Write-Host $t; $script:Summary.Add($t) }
function Step([string]$name, [string]$status, [string]$detail) {
    if ($status -ne "PASS" -and $status -ne "INFO") { $script:AllPass = $false }
    Say ("{0,-34} {1,-6} {2}" -f $name, $status, $detail)
}
function Fresh([string]$p, [datetime]$since) { return (Test-Path $p) -and ((Get-Item $p).LastWriteTime -ge $since) }

$magic = @{ "M30" = "26030"; "H1" = "26060"; "H4" = "26240" }[$Period]
# EVERY input of NNFX_EA, in source order, with the tester's values (the EA's defaults except where noted)
$inputs = [ordered]@{
    InpMagic = $magic; InpPairs = "EURUSD,AUDNZD,EURGBP,AUDCAD,CHFJPY"; InpRiskPct = "2.0"; InpExposureMode = "first";
    InpTrailOn = "true"; InpTrailStart = "2.0"; InpTrailDist = "1.5"; InpRunnerCap = "0.0";
    InpExitOnExitInd = "true"; InpExitOnC1 = "true"; InpExitOnBaseline = "true"; InpNewsExit = "true";
    InpPullback = "true"; InpOneCandle = "true"; InpBridgeTooFar = "true"; InpBridgeBars = "7"; InpContinuation = "a";
    InpBaseline = "ref_baseline_sma20.txt"; InpC1 = "ref_c1_rvi10.txt"; InpC2 = "ref_c2_macd_main.txt";
    InpExit = "ref_exit_macd_cross.txt"; InpVolume = "ref_volume_ticks20.txt";
    InpInstanceOn = "true"; InpServerWinterOffset = "2"; InpServerDst = "US"; InpWeekendHours = "0"; InpMaxSpread = "0";
    InpNewsBlock = "true"; InpNewsFile = "NNFX\calendar\events_2019.01_2026.09.txt"; InpBlackouts = "none";
    InpNewsMaxAgeHours = "24"; InpWarmupBars = "300";
    InpTesterMaster = "1";            # tester: the master switch on (the tester cannot see terminal global variables)
    InpTesterMasterOff = "none"; InpRestartAt = "none"; InpRestartDeleteState = "false"
}
# 'powershell -File' hands an array to the script as ONE string "InpA=x,InpB=y" (run ea_restart_master_20261006_204349,
# kept in checks\invalid\): split at ",Inp" boundaries
$Set = @($Set | ForEach-Object { $_ -split ',(?=Inp\w+=)' } | Where-Object { $_ -ne "" })
foreach ($s in $Set) {
    if ($s -match ',Inp\w+=') { Write-Host "STOP: an override still holds two inputs: $s"; exit 2 }
    $i = $s.IndexOf("=")
    $k = $s.Substring(0, $i); $v = $s.Substring($i + 1)
    if (-not $inputs.Contains($k)) { Write-Host "STOP: unknown input $k"; exit 2 }
    $inputs[$k] = $v
}
# the EA's own input list must equal this one (a new input would otherwise be reused from an earlier run)
$src = Get-Content -LiteralPath "$Repo\MQL5\Experts\NNFX\NNFX_EA.mq5" -Raw
$eaNames = @([regex]::Matches($src, "(?m)^input\s+\w+\s+(Inp\w+)") | ForEach-Object { $_.Groups[1].Value })
$missing = @($eaNames | Where-Object { -not $inputs.Contains($_) })
if ($missing.Count -gt 0 -or $eaNames.Count -ne $inputs.Count) {
    Write-Host "STOP: the driver's input list differs from NNFX_EA's: missing $($missing -join ', ')"; exit 2
}
foreach ($p in $inputs.Keys) { if ($inputs[$p] -eq "") { Write-Host "STOP: $p is empty (the tester would reuse its last value)"; exit 2 } }

Say "run_ea_tester ${Tag}: NNFX_EA $Period, $From - $To, model $Model, chart $Symbol, out $Out"
Say ("inputs: " + (($inputs.Keys | ForEach-Object { "$_=$($inputs[$_])" }) -join " "))

# D6c-1 / D-OPS-1: only the full-path terminal; wait if it is open
$open = Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Terminal }
if ($open) { Step "0 MT5 closed" "FAIL" "terminal64 is running (pid $($open.Id -join ',')); not touched"; $Summary | Set-Content "$Out\SUMMARY.txt"; exit 1 }

# 1. copy and compile
Copy-Item "$Repo\MQL5\Include\NNFX\*.mqh" "$MT5\MQL5\Include\NNFX\" -Force
Copy-Item "$Repo\MQL5\Experts\NNFX\*.mq5" "$MT5\MQL5\Experts\NNFX\" -Force
Copy-Item "$Repo\profiles\*.txt" "$Common\NNFX\profiles\" -Force
$srcEa = "$MT5\MQL5\Experts\NNFX\NNFX_EA.mq5"; $clog = "$MT5\MQL5\Experts\NNFX\NNFX_EA.log"
if (Test-Path $clog) { Remove-Item $clog -Force }
Start-Process -FilePath $ME -ArgumentList "/compile:`"$srcEa`"", "/log:`"$clog`"" -Wait -WindowStyle Hidden
Copy-Item $clog "$Out\NNFX_EA.compile.log" -ErrorAction SilentlyContinue
$ct = if (Test-Path $clog) { Get-Content -LiteralPath $clog -Raw -Encoding Unicode } else { "" }
$m = [regex]::Match($ct, "Result:\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?")
if ($m.Success -and $m.Groups[1].Value -eq "0" -and $m.Groups[2].Value -eq "0") { Step "1 compile NNFX_EA" "PASS" "0 errors, 0 warnings" }
else { Step "1 compile NNFX_EA" "FAIL" $(if ($m.Success) { $m.Value } else { "no Result line" }); $Summary | Set-Content "$Out\SUMMARY.txt"; exit 1 }
if (-not (Test-Path ("$Common\" + $inputs["InpNewsFile"]))) { Step "1 news file" "FAIL" ("not found: Common\Files\" + $inputs["InpNewsFile"]) }

# 2. config
$name = "EA_$($Period)_$($magic)_tester.csv"
$tradeLog = "$Common\NNFX\trades\$name"; $decLog = "$Common\NNFX\decisions\$name"
$report = "NNFX_EA_$Tag"
$ini = "$Out\run_NNFX_EA.ini"
$lines = @("[Tester]", "Expert=NNFX\NNFX_EA", "Symbol=$Symbol", "Period=$Period", "Model=$Model",
           "FromDate=$From", "ToDate=$To", "ForwardMode=0", "Optimization=0", "Visual=0",
           "Report=$report", "ReplaceReport=1", "ShutdownTerminal=1", "[TesterInputs]")
foreach ($k in $inputs.Keys) { $lines += "$k=$($inputs[$k])" }
$lines | Set-Content -LiteralPath $ini -Encoding ASCII

# 3. run
$t0 = Get-Date
$p = Start-Process -FilePath $Terminal -ArgumentList "/config:`"$ini`"" -PassThru
if (-not $p.WaitForExit($TimeoutMin * 60 * 1000)) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Step "3 tester run" "FAIL" "timeout after $TimeoutMin min (MT5 closed by this script)"
} else { Start-Sleep -Seconds 2 }
$mins = [math]::Round(((Get-Date) - $t0).TotalMinutes, 1)

# 4. collect and check
if ((Fresh $tradeLog $t0) -and (Fresh $decLog $t0)) {
    Copy-Item $tradeLog "$Out\trades_$name" -Force
    Copy-Item $decLog "$Out\decisions_$name" -Force
    Step "3 tester run" "PASS" "$mins min; both logs written"
} else {
    Step "3 tester run" "FAIL" "no fresh trade log and decision log ($mins min)"
}
Get-ChildItem "$MT5\$report*" -ErrorAction SilentlyContinue | Copy-Item -Destination $Out -Force
$tlogs = "$env:APPDATA\MetaQuotes\Tester\D0E8209F77C8CF37AD8BF550E51FF075"
Get-ChildItem $tlogs -Recurse -Filter "*.log" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -ge $t0 } |
    ForEach-Object { Copy-Item $_.FullName ("$Out\tester_" + $_.Directory.Parent.Name + "_" + $_.Name) -Force }

if (Test-Path "$Out\trades_$name") {
    $tf = @{ "M30" = "30"; "H1" = "60"; "H4" = "240" }[$Period]
    $r1 = & $Python -B "$Repo\tools\check_trades.py" "$Out\trades_$name" --min-trades $MinTrades 2>&1 | Out-String
    $r1 | Set-Content "$Out\check_trades.txt" -Encoding ASCII
    $l1 = ([regex]::Matches($r1, "(?m)^RESULT.*$") | Select-Object -Last 1).Value
    Step "4 check_trades" $(if ($l1 -match "PASS") { "PASS" } else { "FAIL" }) $l1.Trim()
    $r2 = & $Python -B "$Repo\tools\check_decision_log.py" "$Out\decisions_$name" --tf $tf --pairs $inputs["InpPairs"] --trades "$Out\trades_$name" 2>&1 | Out-String
    $r2 | Set-Content "$Out\check_decision_log.txt" -Encoding ASCII
    $l2 = ([regex]::Matches($r2, "(?m)^RESULT.*$") | Select-Object -Last 1).Value
    Step "4 check_decision_log" $(if ($l2 -match "PASS") { "PASS" } else { "FAIL" }) $l2.Trim()
    $rows = Get-Content -LiteralPath "$Out\trades_$name"
    $div = @($rows | Where-Object { $_ -match "^[^,]*,DIVERGE," }).Count
    $info = @($rows | Where-Object { $_ -match "^[^,]*,INFO," -and $_ -match "start \(" })
    Step "4 DIVERGE rows" "INFO" "$div (D6f-1; listed in check_trades.txt context)"
    foreach ($i in $info) { Say ("   " + $i) }
}
Say ""
Say $(if ($AllPass) { "OVERALL: PASS" } else { "OVERALL: FAIL" })
$Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
Write-Host "Summary: $Out\SUMMARY.txt"
if ($AllPass) { exit 0 } else { exit 1 }
