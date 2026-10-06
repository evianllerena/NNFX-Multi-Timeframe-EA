<#
run_demo_restarts.ps1 - Phase 6c restart test (b): REAL restarts on the demo account
(docs/PLAN_PHASE6.md section 9; SPEC "Rebuilding after a restart"). Orders: MetaQuotes-Demo only.

  1. D6c-1 account check: NNFX_EnvCheck (tick probe off) must report Login -ExpectLogin on -ExpectServer.
  2. Starts MT5 with NNFX_OrderTest on EURUSD M1 (minimum lots, a trade every 2 candles; test hooks are
     tester-only and refused on demo anyway).
  3. Polls the EA's state file (MQL5\Files\NNFX\state\OrderTest_EURUSD.txt). When a state not yet tested is
     seen in two polls in a row - R1 both halves open before TP1, R2 after TP1 at breakeven, R3 trailing,
     R4 flat with the continuation armed - the terminal THIS script started is closed by its process id
     (OnDeinit writes PRESTOP with the memory) and started again (OnInit rebuilds from the broker, the state
     file and the candles, and writes REBUILD).
  4. When all four states were tested, or after -Minutes, the EA is restarted with no new trades allowed
     (InpMaxTrades=1, InpStopWhenDone): it manages its open trade to the end and removes itself.
  5. tools/compare_runs.py rebuilds (every REBUILD = the PRESTOP before it, field for field; for the -HardKill
     restart, done with Stop-Process -Force on our own PID right after a candle, there is no PRESTOP and the
     REBUILD must equal the last STATE row) and
     tools/check_trades.py on the whole demo log.

D6c-1: only the tested terminal (full path) blocks the run; others are listed, never touched; a terminal is
closed only by the process id this script started. D6c-3: if that process ends by itself, the driver adopts a
relaunch only if it has the tested terminal's path and this run's own config file on its command line; otherwise it
starts MT5 again (an unplanned restart, max 5). Nobody needs to watch the run.
Output: <MT5 data folder>\MQL5\Files\NNFX\checks\demo_restart_<date-time>\
Usage:  powershell -ExecutionPolicy Bypass -File tools\run_demo_restarts.ps1
#>
param(
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Common  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [string]$Python  = "C:\Users\Evision\AppData\Local\Programs\Python\Python312\python.exe",
    [long]$ExpectLogin = 113593254,
    [string]$ExpectServer = "MetaQuotes-Demo",
    [int]$Minutes = 120,
    [string]$HardKill = "R2"     # G1_phase6c_1 F2: this restart is a hard kill of our own PID ("" = none)
)
$ErrorActionPreference = "Continue"
$Terminal = Join-Path $Install "terminal64.exe"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Out = Join-Path $MT5 "MQL5\Files\NNFX\checks\demo_restart_$Stamp"
$StateFile = Join-Path $MT5 "MQL5\Files\NNFX\state\OrderTest_EURUSD.txt"
$Schedule = Join-Path $MT5 "MQL5\Files\NNFX\state\OrderTest_EURUSD_schedule.txt"
$Log = "$Common\NNFX\trades\OrderTest_EURUSD_demo.csv"
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

$running = @(Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path })
if (@($running | Where-Object { $_.Path -ieq $Terminal }).Count -gt 0) {
    Write-Host "STOP: the tested MetaTrader 5 ($Terminal) is open. Close it (File > Exit) and run this again."; exit 2
}
New-Item -ItemType Directory -Force "$Out", "$MT5\MQL5\Presets" | Out-Null
Say "NNFX restart tests (real, demo)  $Stamp"
Say "Repo: $Repo  (commit $(& git -C $Repo rev-parse --short HEAD 2>$null))"
foreach ($o in @($running | Where-Object { $_.Path -ine $Terminal })) { Say ("other terminal running (ignored): pid {0} {1}" -f $o.Id, $o.Path) }
Say ""
foreach ($f in @($StateFile, $Schedule, $Log)) {
    if (Test-Path $f) { Move-Item $f "$Out\before_this_run_$(Split-Path $f -Leaf)" -Force }   # kept, never deleted
}

function Start-MT5([string]$ini) { return Start-Process -FilePath $Terminal -ArgumentList "/config:`"$ini`"" -PassThru }
function Close-MT5($p) {
    if ($p -and -not $p.HasExited) {
        $null = $p.CloseMainWindow()
        if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Say "  (pid $($p.Id) did not close in 120 s: stopped by id)" }
    }
}
# MT5 logs "<n> inputs read from expert 'NNFX\NNFX_OrderTest' set file ..." at each start. Returns the n of the
# first such line at or after $since (same day), or -1 if none appears within 60 s.
function Inputs-Read([datetime]$since) {
    $day = Get-Date -Format "yyyyMMdd"
    $after = Get-Date $since -Format "HH:mm:ss"
    for ($k = 0; $k -lt 12; $k++) {
        Start-Sleep -Seconds 5
        $tmp = "$Out\_termlog.tmp"
        Copy-Item "$MT5\Logs\$day.log" $tmp -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $tmp)) { continue }
        $hit = @(Get-Content $tmp -Encoding Unicode | ForEach-Object {
            $m = [regex]::Match($_, "\t(\d\d:\d\d:\d\d)\.\d+\tMQL5\t(\d+) inputs read from expert 'NNFX\\NNFX_OrderTest'")
            if ($m.Success -and $m.Groups[1].Value -ge $after) { [int]$m.Groups[2].Value } })
        Remove-Item $tmp -Force
        if ($hit.Count -gt 0) { return $hit[0] }
    }
    return -1
}
# Our PID ended by itself. Seen twice on 2026-10-06 (both runs kept in checks\invalid\): MT5 LiveUpdate (build
# 6238 -> 6241) came back under a NEW pid, and the window was closed by hand. D6c-3 (owner, 2026-10-06: "you need to
# figure out how to close it ... i cant be always"): the driver adopts a relaunch ONLY if it has the tested terminal's
# full path AND this run's own config file on its command line; any other terminal64 is never touched (D6c-1).
# With no such relaunch, the driver starts MT5 again itself (an unplanned restart; its REBUILD row is checked too).
$script:Unplanned = 0
function Find-Relaunch([string]$ini) {
    $end = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $end) {
        $own = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object {
            $_.ExecutablePath -ieq $Terminal -and $_.CommandLine -and
            $_.CommandLine.IndexOf($ini, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
        if ($own.Count -gt 0) { $r = Get-Process -Id $own[0].ProcessId -ErrorAction SilentlyContinue; if ($r) { return $r } }
        Start-Sleep -Seconds 5
    }
    return $null
}
function Resolve-Exited($proc, [string]$ini) {
    Say ("pid {0} exited by itself at {1} (not closed by this driver)" -f $proc.Id, (Get-Date -Format "HH:mm:ss"))
    $r = Find-Relaunch $ini
    if ($r) {
        Say ("  adopted pid {0}: tested terminal path and this run's own {1} on its command line (D6c-3)" -f $r.Id, (Split-Path $ini -Leaf))
        return $r
    }
    $script:Unplanned++
    if ($script:Unplanned -gt 5) { Say "STOP: MT5 ended by itself more than 5 times"; $script:AllPass = $false; Done }
    Say "  no relaunch found: starting MT5 again (unplanned restart $($script:Unplanned); its REBUILD row is checked too)"
    return Start-EA $ini ($eaInputs.Count + 2)
}
function Start-EA([string]$ini, [int]$want) {
    $t0 = Get-Date
    $proc = Start-MT5 $ini
    $n = Inputs-Read $t0
    if ($n -ne $want) {
        Say ("STOP: MT5 read {0} inputs from the set file, expected {1}; closing pid {2}" -f $n, $want, $proc.Id)
        Close-MT5 $proc
        $script:AllPass = $false
        Done
    }
    Start-Sleep -Seconds 5
    if ($proc.HasExited) { $proc = Resolve-Exited $proc $ini }
    return $proc
}
function Write-Set([string]$name, [string[]]$lines) {
    [System.IO.File]::WriteAllText("$MT5\MQL5\Presets\$name", (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::Unicode)
    Copy-Item "$MT5\MQL5\Presets\$name" "$Out\" -Force
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

# 2. start the EA
# NOT "$common": PowerShell names ignore case, and $Common is the [string] Common Files parameter (run
# demo_restart_20261005_225412, kept in checks\invalid\, squashed this list into one string).
# Magic 26997: its own deal history. 26999 = the 6b demo run; 26998 = run demo_restart_20261006_000708 (invalid),
# which left trade T0003 open at the broker (its own SL/TP); 26997 = run demo_restart_20261006_001959 (invalid, T0001 left open).
$eaInputs = @("InpRiskPct=2.0", "InpEveryBars=2", "InpMinLots=true", "InpMagic=26996", "InpStoplessTest=false", "InpLoseReplyOn=0",
            "InpAbortOn=0", "InpStopsRefuseOn=0", "InpMarginRefuseOn=0", "InpModifyOn=0",
            "InpRestartAt=none", "InpRestartDeleteState=false", "InpRestartIgnoreComments=false", "InpCloseLeftovers=false",
            "InpGuard=false", "InpInstanceOn=true", "InpServerWinterOffset=2", "InpServerDst=US", "InpWeekendHours=0", "InpMaxSpread=0", "InpTesterMaster=-1", "InpTesterPauseAt=none",
            "InpMasterTestTpl=", "InpMasterTestSymbol=GBPUSD", "InpMasterOffAfter=5", "InpMasterOffFor=5")
Write-Set "NNFX_OrderTest_restart.set" ($eaInputs + @("InpMaxTrades=0", "InpStopWhenDone=false"))
@("[StartUp]", "Expert=NNFX\NNFX_OrderTest", "ExpertParameters=NNFX_OrderTest_restart.set", "Symbol=EURUSD", "Period=M1") |
    Set-Content "$Out\run_demo.ini" -Encoding ASCII
$p = Start-EA "$Out\run_demo.ini" ($eaInputs.Count + 2)
Say ("started pid {0} at {1}" -f $p.Id, (Get-Date -Format "HH:mm:ss"))

$HardKilled = $false
function Proc-Line {
    try { return @(Get-Content -LiteralPath $StateFile -ErrorAction Stop | Where-Object { $_ -like "PROC|*" })[0] } catch { return "" }
}
function Classify {
    if (-not (Test-Path $StateFile)) { return @() }
    try { $lines = Get-Content -LiteralPath $StateFile -ErrorAction Stop } catch { return @() }
    $found = @()
    $trades = @($lines | Where-Object { $_ -like "TRADE|*" })
    foreach ($t in $trades) {
        $f = $t -split "\|"
        if ($f[6] -eq "1" -and $f[7] -eq "1" -and $f[14] -eq "0") { $found += "R1" }
        if ($f[14] -eq "1" -and $f[7] -eq "1" -and $f[15] -eq "0") { $found += "R2" }
        if ($f[14] -eq "1" -and $f[7] -eq "1" -and $f[15] -eq "1") { $found += "R3" }
    }
    $cont = @($lines | Where-Object { $_ -like "CONT|*" })
    if ($trades.Count -eq 0 -and $cont.Count -gt 0 -and ($cont[0] -split "\|")[3] -eq "1") { $found += "R4" }
    return $found
}

# 3. restarts
$done = @{}
$deadline = (Get-Date).AddMinutes($Minutes)
$prev = @()
while ($done.Count -lt 4 -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    if ($p.HasExited) { $p = Resolve-Exited $p "$Outun_demo.ini"; $prev = @(); continue }
    $now = @(Classify)
    $target = @($now | Where-Object { -not $done.ContainsKey($_) -and $prev -contains $_ }) | Select-Object -First 1
    $prev = $now
    if (-not $target) { continue }
    $snap = "$Out\state_before_$target.txt"
    Copy-Item $StateFile $snap -Force -ErrorAction SilentlyContinue
    if ($target -eq $HardKill) {
        # G1_phase6c_1 F2: a HARD kill of our own PID (D-OPS-1), like a crash or power cut: OnDeinit never runs, so
        # there is no PRESTOP row and the rebuild must equal the last STATE row. Killed right after the EA has
        # processed a new candle (the state file's PROC line changes), so that STATE row is the state at the kill.
        $proc0 = Proc-Line
        $until = (Get-Date).AddSeconds(150)
        while ((Proc-Line) -eq $proc0 -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 300 }
        Start-Sleep -Milliseconds 500
        Copy-Item $StateFile $snap -Force -ErrorAction SilentlyContinue
        Say ("{0}: state seen twice; after the candle of {1}, HARD KILL of pid {2} at {3} (Stop-Process -Force -Id)" -f
             $target, (Proc-Line), $p.Id, (Get-Date -Format "HH:mm:ss"))
        Stop-Process -Id $p.Id -Force
        $null = $p.WaitForExit(60000)
        $script:HardKilled = $true
    } else {
        Say ("{0}: state seen twice at {1}; closing pid {2} and restarting" -f $target, (Get-Date -Format "HH:mm:ss"), $p.Id)
        Close-MT5 $p
    }
    $p = Start-EA "$Out\run_demo.ini" ($eaInputs.Count + 2)
    Say ("  restarted pid {0} at {1}" -f $p.Id, (Get-Date -Format "HH:mm:ss"))
    $done[$target] = (Get-Date -Format "HH:mm:ss")
    $prev = @()
    Start-Sleep -Seconds 20
}
foreach ($r in "R1", "R2", "R3", "R4") { if (-not $done.ContainsKey($r)) { Say "$r NOT RUN (state not seen within $Minutes minutes)"; $script:AllPass = $false } }

# 4. finish: no new trades; the EA manages its open trade to the end and removes itself
Close-MT5 $p
Write-Set "NNFX_OrderTest_finish.set" ($eaInputs + @("InpMaxTrades=1", "InpStopWhenDone=true"))
@("[StartUp]", "Expert=NNFX\NNFX_OrderTest", "ExpertParameters=NNFX_OrderTest_finish.set", "Symbol=EURUSD", "Period=M1") |
    Set-Content "$Out\run_finish.ini" -Encoding ASCII
$t0 = Get-Date
$p = Start-EA "$Out\run_finish.ini" ($eaInputs.Count + 2)
$sum = "$Common\NNFX\trades\OrderTest_EURUSD_demo_summary.txt"
$end = (Get-Date).AddMinutes(60)
while ((Get-Date) -lt $end -and -not ((Test-Path $sum) -and (Get-Item $sum).LastWriteTime -gt $t0.AddSeconds(30))) { Start-Sleep -Seconds 10 }
Close-MT5 $p
Start-Sleep -Seconds 3
foreach ($f in @($Log, $sum, $StateFile, $Schedule)) { if (Test-Path $f) { Copy-Item $f "$Out\" -Force } }
$day = Get-Date -Format "yyyyMMdd"
Copy-Item "$MT5\Logs\$day.log" "$Out\terminal_$day.log" -ErrorAction SilentlyContinue
Copy-Item "$MT5\MQL5\Logs\$day.log" "$Out\experts_$day.log" -ErrorAction SilentlyContinue

# 5. checks
$lg = "$Out\OrderTest_EURUSD_demo.csv"
foreach ($c in @(@{ N = "rebuilt = before (compare_runs rebuilds)"; A = @("$Repo\tools\compare_runs.py", "rebuilds", $lg, "--min", "$($done.Count)") },
                 @{ N = "check_trades (whole demo log)"; A = @("$Repo\tools\check_trades.py", $lg, "--require-note", "orders allowed: DEMO") })) {
    $lines = & $Python @($c.A) 2>&1 | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { [string]$_ } }
    $code = $LASTEXITCODE
    $txt = (($lines | Out-String) -replace "`r?`n", "`r`n")
    $txt | Set-Content ("$Out\" + ($c.N -replace "[^A-Za-z0-9]+", "_") + ".txt") -Encoding ASCII
    $res = ([regex]::Matches($txt, "(?m)^RESULT.*$") | Select-Object -Last 1).Value
    Step $c.N ($code -eq 0) $res.Trim()
    if ($c.N -like "rebuilt*" -and $HardKill) {
        # exactly one restart without a PRESTOP row (the hard kill), compared with the last STATE row before it
        $hard = @([regex]::Matches($txt, "(?m)^.*no PRESTOP: hard stop.*$") | ForEach-Object { $_.Value.Trim() })
        Step "$HardKill hard kill: no PRESTOP, rebuilt = last STATE row" ($script:HardKilled -and $hard.Count -eq 1) $(
            if ($hard.Count -eq 1) { $hard[0] } else { "$($hard.Count) restarts without PRESTOP (must be 1); killed: $($script:HardKilled)" })
    }
}
Done
