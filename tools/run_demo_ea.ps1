<#
run_demo_ea.ps1 - NNFX_EA on the DEMO account (Phase 6f; docs/PLAN_PHASE6.md 6f MT5 tests and carry-overs).
Orders: MetaQuotes-Demo 113593254 only (D6c-1; the EA itself refuses any non-demo account, Orders.mqh section 1).

Modes:
  kill_tp1   (G1_phase6c_2 note 1) the EA on -Period (default M1, so trades come fast) with test magic -Magic
             (default 26995, D-OPS-1). When the trade log shows a TP1, the driver waits 3 s and kills OUR MT5
             (Stop-Process -Force: no OnDeinit, mid-candle), keeps the state file as it was at the kill, and starts
             MT5 again. PASS when: the state file at the kill already had that trade with TP1 done (written after
             the trade event, not at the candle); the start-up rows show core and broker agreeing on that pair; no
             start-up close; the trade is still managed (closed later by the EA or its broker stops, or still open
             with its stop at breakeven or better).
  kill_pause (G1_phase6d_1 item 2) the drawdown peak is set far above equity (NNFX_GvTool), so the EA switches the
             pause on at its first candle; 3 s after its "drawdown pause" GUARD row, OUR MT5 is killed and started
             again. PASS when the EA is still paused after the restart: its first "blocks:" row includes drawdown and
             it logs no new "drawdown pause (R-12)" trip (the flag survived the crash: GlobalVariablesFlush).
  smoke      (PLAN 6f "Demo smoke test") the 1H preset file MQL5\Presets\NNFX_H1.set exactly, on EURUSD H1, for
             -Hours (default 26: one full weekday plus the start); then MT5 is closed normally. PASS when: no
             error lines from NNFX_EA in the Experts log; "orders allowed: DEMO"; check_decision_log PASS (one row per
             pair per candle, none missing); check_trades PASS on the trades it made (if any).
Every mode: the global variables it changes (NNFX_MASTER = 1 so the EA may trade; for kill_pause NNFX_DD_PEAK and
NNFX_DD_PAUSED) are recorded first and restored at the end (G1_phase6d_1 item 1). Open TEST trades (kill modes, magic
26990-26999) are closed at the end with tools/close_test_leftovers.ps1 (D-OPS-1). The smoke mode's 1H trades
(magic 26060) are NOT closed: they are the preset's own trades and stay with their broker-held stops; listed in SUMMARY.
D6c-1: only the tested terminal (full path) is used and closed, by the process id this script started; D6c-3: a
relaunch is adopted only with this run's own config file on its command line.
Output: <MT5 data folder>\MQL5\Files\NNFX\checks\demo_ea_<mode>_<date-time>\
Usage:  powershell -ExecutionPolicy Bypass -File tools\run_demo_ea.ps1 -Mode kill_tp1
#>
param(
    [ValidateSet("kill_tp1", "kill_pause", "smoke", "news_alarm")] [string]$Mode = "kill_tp1",
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Common  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [string]$Python  = "C:\Users\Evision\AppData\Local\Programs\Python\Python312\python.exe",
    [long]$ExpectLogin = 113593254,
    [string]$ExpectServer = "MetaQuotes-Demo",
    [string]$Period  = "M1",
    [long]$Magic     = 26995,
    [int]$Minutes   = 180,
    [double]$Hours  = 26,
    [double]$Risk   = 0.1    # kill modes only (M1: at 2% every entry is refused for margin, OD-5; run demo_ea_kill_tp1_20261006_210939 in invalid). The smoke mode uses the preset as it is
)
$ErrorActionPreference = "Continue"
$Terminal = Join-Path $Install "terminal64.exe"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Out = Join-Path $MT5 "MQL5\Files\NNFX\checks\demo_ea_$($Mode)_$Stamp"
if ($Mode -eq "smoke") { $Period = "H1"; $Magic = 26060 }
elseif ($Magic -lt 26990 -or $Magic -gt 26999) { Write-Host "STOP: kill modes use a test magic 26990-26999 (D-OPS-1)"; exit 2 }
$Name = "EA_$($Period)_$($Magic)_demo.csv"
$TradeLog = "$Common\NNFX\trades\$Name"; $DecLog = "$Common\NNFX\decisions\$Name"
$StateFile = "$MT5\MQL5\Files\NNFX\state\EA_$Magic.txt"
$Pairs = "EURUSD,AUDNZD,EURGBP,AUDCAD,CHFJPY"
$Summary = New-Object System.Collections.Generic.List[string]
$AllPass = $true
function Say([string]$t) { Write-Host $t; $script:Summary.Add($t) }
function Step([string]$name, [bool]$ok, [string]$detail) {
    if (-not $ok) { $script:AllPass = $false }
    Say (("{0,-44} {1}" -f $name, $(if ($ok) { "PASS" } else { "FAIL" })) + $(if ($detail) { "  - $detail" } else { "" }))
}

$running = @(Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path })
if (@($running | Where-Object { $_.Path -ieq $Terminal }).Count -gt 0) { Write-Host "STOP: the tested MT5 is open; not touched"; exit 2 }
New-Item -ItemType Directory -Force $Out, "$MT5\MQL5\Presets" | Out-Null
Say "NNFX_EA demo run, mode $Mode, $Period, magic $Magic$(if ($Mode -ne "smoke") { ", risk $Risk%" })  $Stamp"
Say "Repo: $Repo  (commit $(& git -C $Repo rev-parse --short HEAD 2>$null))"
foreach ($f in @($TradeLog, $DecLog, $StateFile)) {
    if (Test-Path $f) { Move-Item $f "$Out\before_this_run_$(Split-Path $f -Leaf)" -Force }   # kept, never deleted
}

# copy and compile what this run uses
Copy-Item "$Repo\MQL5\Include\NNFX\*.mqh" "$MT5\MQL5\Include\NNFX\" -Force
Copy-Item "$Repo\MQL5\Experts\NNFX\*.mq5" "$MT5\MQL5\Experts\NNFX\" -Force
Copy-Item "$Repo\MQL5\Scripts\NNFX\*.mq5" "$MT5\MQL5\Scripts\NNFX\" -Force
Copy-Item "$Repo\MQL5\Presets\NNFX_*.set" "$MT5\MQL5\Presets\" -Force
New-Item -ItemType Directory -Force "$MT5\MQL5\Files\NNFX\news" | Out-Null
Copy-Item "$Repo\news\news_events.txt" "$MT5\MQL5\Files\NNFX\news\" -Force
Copy-Item "$Repo\profiles\*.txt" "$Common\NNFX\profiles\" -Force
foreach ($f in @("Experts\NNFX\NNFX_EA", "Scripts\NNFX\NNFX_GvTool", "Scripts\NNFX\NNFX_EnvCheck")) {
    $log = "$MT5\MQL5\$f.log"; if (Test-Path $log) { Remove-Item $log -Force }
    Start-Process -FilePath (Join-Path $Install "MetaEditor64.exe") -ArgumentList "/compile:`"$MT5\MQL5\$f.mq5`"", "/log:`"$log`"" -Wait -WindowStyle Hidden
    $r = [regex]::Match((Get-Content $log -Raw -Encoding Unicode), "Result:\s*(\d+) errors?,\s*(\d+) warnings?")
    if (-not ($r.Success -and $r.Groups[1].Value -eq "0" -and $r.Groups[2].Value -eq "0")) { Say "STOP: $f does not compile clean"; exit 2 }
}

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
function Run-Script([string]$script, [string]$set, [int]$min) {
    $ini = "$Out\run_$($script)_$((Get-Date).Ticks).ini"
    @("[StartUp]", "Script=NNFX\$script", "ScriptParameters=$set", "Symbol=EURUSD", "Period=H1", "ShutdownTerminal=1") |
        Set-Content $ini -Encoding ASCII
    $p = Start-MT5 $ini
    if (-not $p.WaitForExit($min * 60000)) { Close-MT5 $p }
    Start-Sleep -Seconds 2
}
function Read-Shared([string]$path) {
    # the EA writes its logs with FILE_SHARE_READ; read without locking them
    try {
        $fs = [System.IO.File]::Open($path, "Open", "Read", "ReadWrite")
        $sr = New-Object System.IO.StreamReader($fs)
        $t = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
        return @($t -split "`r?`n" | Where-Object { $_ -ne "" })
    } catch { return @() }
}
# MT5 logs "<n> inputs read from expert 'NNFX\NNFX_EA' set file" at each start; -1 if none within 60 s
function Inputs-Read([datetime]$since) {
    $day = Get-Date -Format "yyyyMMdd"; $after = Get-Date $since -Format "HH:mm:ss"
    for ($k = 0; $k -lt 12; $k++) {
        Start-Sleep -Seconds 5
        $lines = Read-Shared "$MT5\Logs\$day.log"
        if ($lines.Count -eq 0) {
            $tmp = "$Out\_termlog.tmp"; Copy-Item "$MT5\Logs\$day.log" $tmp -Force -ErrorAction SilentlyContinue
            if (Test-Path $tmp) { $lines = Get-Content $tmp -Encoding Unicode; Remove-Item $tmp -Force }
        }
        $hit = @($lines | ForEach-Object {
            $m = [regex]::Match($_, "\t(\d\d:\d\d:\d\d)\.\d+\tMQL5\t(\d+) inputs read from expert 'NNFX\\NNFX_EA'")
            if ($m.Success -and $m.Groups[1].Value -ge $after) { [int]$m.Groups[2].Value } })
        if ($hit.Count -gt 0) { return $hit[0] }
    }
    return -1
}

# 1. account check (D6c-1)
Write-Set "NNFX_EnvCheck_quick.set" @("InpCheckTicks=false")
$t0 = Get-Date
Run-Script "NNFX_EnvCheck" "NNFX_EnvCheck_quick.set" 10
$env = "$MT5\MQL5\Files\NNFX_EnvCheck.txt"
$text = if ((Test-Path $env) -and (Get-Item $env).LastWriteTime -ge $t0) { Get-Content $env -Raw } else { "" }
Copy-Item $env "$Out\" -ErrorAction SilentlyContinue
$login = [regex]::Match($text, "(?m)^Login:\s+(\d+)").Groups[1].Value
$server = [regex]::Match($text, "(?m)^Server:\s+(\S+)").Groups[1].Value
$okAcc = ($login -eq "$ExpectLogin" -and $server -eq $ExpectServer -and $text.Contains("Trade mode:   DEMO"))
Step "account check" $okAcc "'$login' on '$server'"
if (-not $okAcc) { Say "STOP: not the expected demo account; nothing was traded."; $Summary | Set-Content "$Out\SUMMARY.txt"; exit 1 }

# 2. global variables: record, then set (restored at the end whatever happens)
$gvNames = @("NNFX_MASTER", "NNFX_DD_PEAK", "NNFX_DD_PAUSED", "NNFX_DD_RESET")
Write-Set "NNFX_GvTool_list.set" @("InpDelete=", "InpSet=")
Run-Script "NNFX_GvTool" "NNFX_GvTool_list.set" 5
Copy-Item "$MT5\MQL5\Files\NNFX_GvTool.txt" "$Out\gv_before.txt" -Force
# NNFX_GvTool.txt lists the variables "before:" and "after:" its changes; read one section only (run
# demo_ea_kill_pause_20261006_210518 read both and reported a restored NNFX_MASTER as still 1)
function Gv-Section([string]$file, [string]$section) {
    $vals = @{}; $in = $false
    foreach ($l in (Get-Content $file)) {
        if ($l -match "^(before|after):") { $in = ($l -like "$($section):*"); continue }
        $m = [regex]::Match($l, "^\s+(NNFX_\w+) = (\S+) ")
        if ($in -and $m.Success) { $vals[$m.Groups[1].Value] = $m.Groups[2].Value }
    }
    return $vals
}
$prior = Gv-Section "$Out\gv_before.txt" "before"
Say ("global variables before: " + (($gvNames | ForEach-Object { "$_=" + $(if ($prior.ContainsKey($_)) { $prior[$_] } else { "missing" }) }) -join ", "))
$set = @("NNFX_MASTER=1")
if ($Mode -eq "kill_pause") { $set += @("NNFX_DD_PEAK=1000000000", "NNFX_DD_PAUSED=0", "NNFX_DD_RESET=0") }
Write-Set "NNFX_GvTool_set.set" @("InpDelete=", "InpSet=$($set -join ',')")
Run-Script "NNFX_GvTool" "NNFX_GvTool_set.set" 5
Copy-Item "$MT5\MQL5\Files\NNFX_GvTool.txt" "$Out\gv_set.txt" -Force
Say ("set for this run: " + ($set -join ", "))

function Restore-Gvs {
    $del = @(); $put = @()
    foreach ($n in $gvNames) {
        if ($prior.ContainsKey($n)) { $put += "$n=$($prior[$n])" } else { $del += $n }
    }
    Write-Set "NNFX_GvTool_restore.set" @("InpDelete=$($del -join ',')", "InpSet=$($put -join ',')")
    Run-Script "NNFX_GvTool" "NNFX_GvTool_restore.set" 5
    Copy-Item "$MT5\MQL5\Files\NNFX_GvTool.txt" "$Out\gv_after.txt" -Force
    $after = Gv-Section "$Out\gv_after.txt" "after"
    $same = $true
    foreach ($n in $gvNames) {
        $a = if ($after.ContainsKey($n)) { $after[$n] } else { "missing" }
        $b = if ($prior.ContainsKey($n)) { $prior[$n] } else { "missing" }
        if ($a -ne $b) { $same = $false }
    }
    Step "global variables restored (G1_phase6d_1 item 1)" $same ("now " + (($gvNames | ForEach-Object { "$_=" + $(if ($after.ContainsKey($_)) { $after[$_] } else { "missing" }) }) -join ", "))
}

# 3. the EA's inputs: smoke = the preset file itself; kill modes = the preset's values with test magic and period
if ($Mode -eq "smoke") {
    $setName = "NNFX_H1.set"
    $want = @((Get-Content "$Repo\MQL5\Presets\NNFX_H1.set" -Encoding Unicode) | Where-Object { $_ -match "^Inp" }).Count
} else {
    $lines = @((Get-Content "$Repo\MQL5\Presets\NNFX_H1.set" -Encoding Unicode) | Where-Object { $_ -match "^Inp" } |
               ForEach-Object { if ($_ -match "^InpMagic=") { "InpMagic=$Magic" } elseif ($_ -match "^InpRiskPct=") { "InpRiskPct=$Risk" }
                                elseif ($_ -match "^InpNewsFile=" -and $Mode -eq "news_alarm") { "InpNewsFile=NNFX\calendar\events_stale_test.txt" }
                                else { ($_ -split "\|\|")[0] } })
    if ($Mode -eq "news_alarm") {
        # D6f-3: a deliberately stale event file (generated 2026-09-01, last event 2026-09-02): both live alarms must fire
        @("# NNFX news events, generated 2026.09.01 00:00 GMT, times in UTC (TEST FILE for the live news alarms, D6f-3)",
          "time_utc|currency|event_id|name|vp", "2026.09.02 12:30|USD|840030016|Nonfarm Payrolls|Non-Farm Payrolls") |
            Set-Content "$Common\NNFX\calendar\events_stale_test.txt" -Encoding ASCII
        Copy-Item "$Common\NNFX\calendar\events_stale_test.txt" "$Out\" -Force
    }
    $setName = "NNFX_EA_$Mode.set"
    Write-Set $setName $lines
    $want = $lines.Count
}
Copy-Item "$MT5\MQL5\Presets\$setName" "$Out\" -Force -ErrorAction SilentlyContinue
$ini = "$Out\run_ea.ini"
@("[StartUp]", "Expert=NNFX\NNFX_EA", "ExpertParameters=$setName", "Symbol=EURUSD", "Period=$Period") | Set-Content $ini -Encoding ASCII
function Start-EA {
    $t = Get-Date
    $p = Start-MT5 $ini
    $n = Inputs-Read $t
    if ($n -ne $want) { Say "STOP: MT5 read $n inputs from $setName, expected $want; closing pid $($p.Id)"; Close-MT5 $p; return $null }
    Say ("started pid {0} at {1} ({2} inputs read)" -f $p.Id, (Get-Date -Format "HH:mm:ss"), $n)
    return $p
}
function Find-Relaunch {
    $end = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $end) {
        $own = @(Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" | Where-Object {
            $_.ExecutablePath -ieq $Terminal -and $_.CommandLine -and $_.CommandLine.IndexOf($ini, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
        if ($own.Count -gt 0) { $r = Get-Process -Id $own[0].ProcessId -ErrorAction SilentlyContinue; if ($r) { return $r } }
        Start-Sleep -Seconds 5
    }
    return $null
}
$script:Unplanned = 0
function Keep-Alive($p) {
    if ($p -and -not $p.HasExited) { return $p }
    Say ("MT5 ended by itself at {0}" -f (Get-Date -Format "HH:mm:ss"))
    $r = Find-Relaunch
    if ($r) { Say "  adopted pid $($r.Id) (this run's config on its command line, D6c-3)"; return $r }
    $script:Unplanned++
    if ($script:Unplanned -gt 5) { return $null }
    Say "  starting MT5 again (unplanned restart $($script:Unplanned))"
    return Start-EA
}

$p = Start-EA
if (-not $p) { $AllPass = $false; Restore-Gvs; $Summary | Set-Content "$Out\SUMMARY.txt"; exit 1 }

function Rows { return Read-Shared $TradeLog }

if ($Mode -eq "kill_tp1" -or $Mode -eq "kill_pause") {
    $pattern = if ($Mode -eq "kill_tp1") { "^[^,]*,TP1," } else { "^[^,]*,GUARD,.*drawdown pause \(R-12\)" }
    $deadline = (Get-Date).AddMinutes($Minutes)
    $hit = $null
    while (-not $hit -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $p = Keep-Alive $p
        if (-not $p) { break }
        $hit = @(Rows | Where-Object { $_ -match $pattern }) | Select-Object -First 1
    }
    if (-not $hit) {
        Step "trigger seen ($Mode)" $false "none within $Minutes min"
    } else {
        Say "trigger: $hit"
        Start-Sleep -Seconds 3
        $tid = ($hit -split ",")[2]
        Copy-Item $StateFile "$Out\state_at_kill.txt" -Force -ErrorAction SilentlyContinue
        Stop-Process -Id $p.Id -Force
        $p.WaitForExit(30000) | Out-Null
        $killedAt = Get-Date
        Say ("hard kill of pid {0} at {1} (forced, by its id: no OnDeinit)" -f $p.Id, (Get-Date $killedAt -Format "HH:mm:ss"))
        $before = (Rows).Count
        Start-Sleep -Seconds 10
        $p = Start-EA
        # wait for the start-up rows
        $startRows = @()
        for ($k = 0; $k -lt 60 -and $startRows.Count -lt 5; $k++) {
            Start-Sleep -Seconds 5
            $startRows = @(Rows | Select-Object -Skip $before | Where-Object { $_ -match "start \(start\)" })
        }
        Step "start-up after the kill" ($startRows.Count -eq 5) "$($startRows.Count) start-up rows (one per pair)"
        $after = @(Rows | Select-Object -Skip $before)
        if ($Mode -eq "kill_tp1") {
            $st = if (Test-Path "$Out\state_at_kill.txt") { Get-Content "$Out\state_at_kill.txt" } else { @() }
            $line = @($st | Where-Object { $_ -like "TRADE|$tid|*" }) | Select-Object -First 1
            $tp1Saved = $line -and (($line -split "\|")[14] -eq "1")
            Step "state file had TP1 done at the kill (note 1)" ([bool]$tp1Saved) $(if ($line) { $line } else { "no TRADE line for $tid" })
            $sym = ($hit -split ",")[4]
            $row = @($startRows | Where-Object { ($_ -split ",")[4] -eq $sym }) | Select-Object -First 1
            $agree = $row -and $row -match ",INFO," -and $row -match "broker (long|short) \($tid\)"
            Step "start-up: core and broker agree on $sym" ([bool]$agree) $(if ($row) { ($row -split ",")[-1] } else { "no row" })
            $closedAtStart = @($after | Where-Object { $_ -match ",(EXIT|CLOSE),$tid," -and $_ -match "D6f-1" })
            Step "nothing closed by the restart" ($closedAtStart.Count -eq 0) "$($closedAtStart.Count) D6f-1 closes of $tid"
            # let the trade run to its end (or the deadline), managed by the restarted EA / its broker stops
            $end = (Get-Date).AddMinutes(60)
            while ((Get-Date) -lt $end) {
                Start-Sleep -Seconds 10
                $p = Keep-Alive $p
                $st = Read-Shared $StateFile
                if (-not @($st | Where-Object { $_ -like "TRADE|$tid|*" })) { break }
            }
            $last = @(Rows | Where-Object { ($_ -split ",")[2] -eq $tid }) | Select-Object -Last 3
            Say "trade $tid after the restart: $($last -join ' / ')"
        } else {
            $trip = @($after | Where-Object { $_ -match "drawdown pause \(R-12\)" })
            $first = @($after | Where-Object { $_ -match ",GUARD,.*blocks:" }) | Select-Object -First 1
            # the first candle after the restart may take up to one candle to come
            for ($k = 0; $k -lt 30 -and -not $first; $k++) {
                Start-Sleep -Seconds 5
                $after = @(Rows | Select-Object -Skip $before)
                $first = @($after | Where-Object { $_ -match ",GUARD,.*blocks:" }) | Select-Object -First 1
                $trip = @($after | Where-Object { $_ -match "drawdown pause \(R-12\)" })
            }
            Step "still paused after the crash (item 2)" ($first -and $first -match "drawdown" -and $trip.Count -eq 0) `
                 ("first blocks row: " + $(if ($first) { ($first -split ",")[-1] } else { "none" }) + "; new pause trips: $($trip.Count)")
        }
    }
} elseif ($Mode -eq "news_alarm") {
    # the start-up runs the news checks once after login; give it 3 minutes, then read the Experts log
    $end = (Get-Date).AddMinutes(3)
    while ((Get-Date) -lt $end) { Start-Sleep -Seconds 10; $p = Keep-Alive $p }
} else {
    $end = (Get-Date).AddHours($Hours)
    while ((Get-Date) -lt $end) {
        Start-Sleep -Seconds 30
        $p = Keep-Alive $p
        if (-not $p) { Step "MT5 kept running" $false "ended more than 5 times"; break }
    }
}
Close-MT5 $p
Start-Sleep -Seconds 3

# 4. checks and clean-up
Copy-Item $TradeLog "$Out\trades_$Name" -Force -ErrorAction SilentlyContinue
Copy-Item $DecLog "$Out\decisions_$Name" -Force -ErrorAction SilentlyContinue
Copy-Item $StateFile "$Out\state_at_end.txt" -Force -ErrorAction SilentlyContinue
$runStart = [datetime]::ParseExact($Stamp, "yyyyMMdd_HHmmss", $null)
foreach ($lf in @(Get-ChildItem "$MT5\MQL5\Logs\*.log" | Where-Object { $_.LastWriteTime -ge $runStart })) { Copy-Item $lf.FullName "$Out\experts_$($lf.Name)" -Force }
foreach ($lf in @(Get-ChildItem "$MT5\Logs\*.log" | Where-Object { $_.LastWriteTime -ge $runStart })) { Copy-Item $lf.FullName "$Out\terminal_$($lf.Name)" -Force }
$rows = if (Test-Path "$Out\trades_$Name") { Get-Content "$Out\trades_$Name" } else { @() }
Step "orders allowed: DEMO" (@($rows | Where-Object { $_ -match "orders allowed: DEMO" }).Count -ge 1) ""
$tfMin = @{ "M1" = "1"; "M5" = "5"; "M15" = "15"; "M30" = "30"; "H1" = "60"; "H4" = "240" }[$Period]
if (Test-Path "$Out\decisions_$Name") {
    $o = & $Python -B "$Repo\tools\check_decision_log.py" "$Out\decisions_$Name" --tf $tfMin --pairs $Pairs --trades "$Out\trades_$Name" 2>&1 | Out-String
    $o | Set-Content "$Out\check_decision_log.txt" -Encoding ASCII
    $r = ([regex]::Matches($o, "(?m)^RESULT.*$") | Select-Object -Last 1).Value
    Step "check_decision_log" ($r -match "PASS") $r.Trim()
}
if (Test-Path "$Out\trades_$Name") {
    # live: the breakeven move from the TP1 transaction can land 1-2 s after TP1 (6c/6d demo drivers; run
    # demo_ea_kill_tp1_20261006_212051 left this option out and FAILed on a 1 s lag)
    $o = & $Python -B "$Repo\tools\check_trades.py" "$Out\trades_$Name" --be-lag-seconds 2 2>&1 | Out-String
    $o | Set-Content "$Out\check_trades.txt" -Encoding ASCII
    $r = ([regex]::Matches($o, "(?m)^RESULT.*$") | Select-Object -Last 1).Value
    $none = $o -match "\(0 trades"
    Step "check_trades" (($r -match "PASS") -or ($none -and $Mode -eq "smoke")) $(if ($none) { "no trades in this run" } else { $r.Trim() })
}
$errs = @()
foreach ($lf in @(Get-ChildItem "$Out\experts_*.log" -ErrorAction SilentlyContinue)) {
    $errs += @(Get-Content $lf.FullName -Encoding Unicode | Where-Object { $_ -match "NNFX_EA" -and $_ -match "(?i)\berror\b|critical|array out of range|zero divide|invalid pointer" })
}
$errs | Set-Content "$Out\error_lines.txt" -Encoding ASCII
Step "no error lines from NNFX_EA (Experts log)" ($errs.Count -eq 0) "$($errs.Count) lines (error_lines.txt)"
if ($Mode -eq "news_alarm") {
    $all = @(); foreach ($lf in @(Get-ChildItem "$Out\experts_*.log" -ErrorAction SilentlyContinue)) { $all += @(Get-Content $lf.FullName -Encoding Unicode) }
    $age = @($all | Where-Object { $_ -match "news file .*events_stale_test.txt is [0-9.]+ h old \(more than 24 h, OD-12\)" }) | Select-Object -First 1
    $rec = @($all | Where-Object { $_ -match "news file .*events_stale_test.txt has no event after .*may not cover the next 24 h" }) | Select-Object -First 1
    Step "live alarm: news file older than 24 h (D6f-3, OD-12)" ([bool]$age) $(if ($age) { ($age -split "\t")[-1] } else { "not in the Experts log" })
    Step "live alarm: no event in the next 24 h (D6f-3, recency)" ([bool]$rec) $(if ($rec) { ($rec -split "\t")[-1] } else { "not in the Experts log" })
}
Restore-Gvs
if ($Mode -ne "smoke") {
    $c = & powershell -ExecutionPolicy Bypass -Command "& '$Repo\tools\close_test_leftovers.ps1' -Magics $Magic" 2>&1 | Out-String
    $c | Set-Content "$Out\cleanup.txt" -Encoding ASCII
    # judged on this magic and the test magics (G1_phase6c_2 note 2); the whole account may hold the 1H smoke EA's
    # own trades (magic 26060), reported only
    $m = [regex]::Match($c, "this magic (\d+)[,;] test magics 26990-26999 (\d+)[,;] whole account (\d+)")
    Step "test trades closed, account flat of tests (D-OPS-1)" ($m.Success -and $m.Groups[1].Value -eq "0" -and $m.Groups[2].Value -eq "0") $(
        if ($m.Success) { "this magic $($m.Groups[1].Value), test magics $($m.Groups[2].Value), whole account $($m.Groups[3].Value)" }
        else { "no positions line from close_test_leftovers" })
} else {
    $open = @($rows | Where-Object { $_ -match "^[^,]*,OPEN," }).Count
    Say "1H preset trades opened in this run: $open OPEN rows; open trades stay with their broker-held stops (not closed by the driver)"
}
Say ""
Say $(if ($AllPass) { "OVERALL: PASS" } else { "OVERALL: NOT ALL PASSED (see the lines above)" })
Say "Everything from this run: $Out"
$Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
if ($AllPass) { exit 0 } else { exit 1 }
