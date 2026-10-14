<#
run_coldstart_check.ps1 - NNFX_EA started together with MT5 on the DEMO account (review fixes set 2, A7 follow-up).

MT5 is started with a /config file that attaches NNFX_EA to an EURUSD H1 chart, so the EA's OnInit runs while the
terminal is still connecting (before login), as after a power cut or a terminal restart. The EA gets a test magic
(26991, D-OPS-1) and risk 0.1%, and the master switch is not touched: NNFX_MASTER missing = OFF (D6d-1), so it can
place no order. After -Seconds the terminal is closed by the process id this script started (D6c-1).

PASS when:
  - the Experts log has no "NNFX orders: orders refused" line and no "initialization failed" line for NNFX_EA
  - the EA's trade log has its "orders allowed: DEMO" INFO row (OnInit passed)
  - the EA's start-up ran after login: a trade-log row with "start (start)" or "start:" text, or the Experts log has
    no "waiting to start" line older than 60 s (information)
Output: <MT5 data folder>\MQL5\Files\NNFX\checks\coldstart_<date-time>\SUMMARY.txt
Usage:  powershell -ExecutionPolicy Bypass -File tools\run_coldstart_check.ps1 [-Seconds 150]
#>
param(
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Common  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [long]$Magic     = 26991,
    [int]$Seconds    = 150
)
$ErrorActionPreference = "Continue"
$Terminal = Join-Path $Install "terminal64.exe"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Out = Join-Path $MT5 "MQL5\Files\NNFX\checks\coldstart_$Stamp"
$Summary = New-Object System.Collections.Generic.List[string]
$AllPass = $true
function Say([string]$t) { Write-Host $t; $script:Summary.Add($t) }
function Step([string]$name, [bool]$ok, [string]$detail) {
    if (-not $ok) { $script:AllPass = $false }
    Say (("{0,-48} {1}" -f $name, $(if ($ok) { "PASS" } else { "FAIL" })) + $(if ($detail) { "  - $detail" } else { "" }))
}
if ($Magic -lt 26990 -or $Magic -gt 26999) { Write-Host "STOP: a test magic 26990-26999 is required (D-OPS-1)"; exit 2 }
if (Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $Terminal }) { Write-Host "STOP: the tested MT5 is open; not touched"; exit 2 }
New-Item -ItemType Directory -Force $Out, "$MT5\MQL5\Presets" | Out-Null
Say "NNFX_EA cold start on the demo, magic $Magic, $Seconds s  $Stamp"
Say "Repo: $Repo  (commit $(& git -C $Repo rev-parse --short HEAD 2>$null))"

$Name = "EA_H1_$($Magic)_demo.csv"
$TradeLog = "$Common\NNFX\trades\$Name"; $DecLog = "$Common\NNFX\decisions\$Name"
$StateFile = "$MT5\MQL5\Files\NNFX\state\EA_$Magic.txt"
foreach ($f in @($TradeLog, $DecLog, $StateFile)) {
    if (Test-Path $f) { Move-Item $f "$Out\before_this_run_$(Split-Path $f -Leaf)" -Force }   # kept, never deleted
}

# copy and compile
Copy-Item "$Repo\MQL5\Include\NNFX\*.mqh" "$MT5\MQL5\Include\NNFX\" -Force
Copy-Item "$Repo\MQL5\Experts\NNFX\*.mq5" "$MT5\MQL5\Experts\NNFX\" -Force
Copy-Item "$Repo\MQL5\Presets\NNFX_*.set" "$MT5\MQL5\Presets\" -Force
New-Item -ItemType Directory -Force "$MT5\MQL5\Files\NNFX\news" | Out-Null
Copy-Item "$Repo\news\news_events.txt" "$MT5\MQL5\Files\NNFX\news\" -Force
Copy-Item "$Repo\profiles\*.txt" "$Common\NNFX\profiles\" -Force
$log = "$MT5\MQL5\Experts\NNFX\NNFX_EA.log"; if (Test-Path $log) { Remove-Item $log -Force }
Start-Process -FilePath (Join-Path $Install "MetaEditor64.exe") -ArgumentList "/compile:`"$MT5\MQL5\Experts\NNFX\NNFX_EA.mq5`"", "/log:`"$log`"" -Wait -WindowStyle Hidden
$r = [regex]::Match([System.IO.File]::ReadAllText($log), "Result:\s*(\d+)\s+errors?,\s*(\d+)\s+warnings?")
Copy-Item $log "$Out\NNFX_EA.compile.log" -Force
$ok = $r.Success -and $r.Groups[1].Value -eq "0" -and $r.Groups[2].Value -eq "0"
Step "compile NNFX_EA" $ok $(if ($r.Success) { $r.Value } else { "no Result line" })
if (-not $ok) { $Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII; exit 1 }

# inputs: the 1H preset with the test magic and 0.1% risk
$lines = @((Get-Content "$Repo\MQL5\Presets\NNFX_H1.set" -Encoding Unicode) | Where-Object { $_ -match "^Inp" } |
           ForEach-Object { if ($_ -match "^InpMagic=") { "InpMagic=$Magic" } elseif ($_ -match "^InpRiskPct=") { "InpRiskPct=0.1" }
                            else { ($_ -split "\|\|")[0] } })
$setName = "NNFX_EA_coldstart.set"
[System.IO.File]::WriteAllText("$MT5\MQL5\Presets\$setName", (($lines -join "`r`n") + "`r`n"), [System.Text.Encoding]::Unicode)
Copy-Item "$MT5\MQL5\Presets\$setName" "$Out\" -Force
$ini = "$Out\run_ea.ini"
@("[StartUp]", "Expert=NNFX\NNFX_EA", "ExpertParameters=$setName", "Symbol=EURUSD", "Period=H1") | Set-Content $ini -Encoding ASCII

$t0 = Get-Date
$p = Start-Process -FilePath $Terminal -ArgumentList "/config:`"$ini`"" -PassThru
Say "MT5 started (pid $($p.Id)) at $(Get-Date $t0 -Format 'HH:mm:ss'); waiting $Seconds s"
Start-Sleep -Seconds $Seconds
if (-not $p.HasExited) {
    $null = $p.CloseMainWindow()
    if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; Say "  (pid $($p.Id) did not close in 120 s: stopped by id)" }
}
Start-Sleep -Seconds 2

# logs
foreach ($lf in @(Get-ChildItem "$MT5\MQL5\Logs\*.log" | Where-Object { $_.LastWriteTime -ge $t0 })) { Copy-Item $lf.FullName "$Out\experts_$($lf.Name)" -Force }
foreach ($lf in @(Get-ChildItem "$MT5\Logs\*.log" | Where-Object { $_.LastWriteTime -ge $t0 })) { Copy-Item $lf.FullName "$Out\terminal_$($lf.Name)" -Force }
$after = Get-Date $t0 -Format "HH:mm:ss"
$exp = @(Get-ChildItem "$Out\experts_*.log" | ForEach-Object { Get-Content $_.FullName -Encoding Unicode } |
         Where-Object { $m = [regex]::Match($_, "\t(\d\d:\d\d:\d\d)\.\d+\t"); $m.Success -and $m.Groups[1].Value -ge $after -and $_ -match "NNFX_EA" })
$exp | Set-Content "$Out\experts_nnfx_ea_lines.txt" -Encoding UTF8
$term = @(Get-ChildItem "$Out\terminal_*.log" | ForEach-Object { Get-Content $_.FullName -Encoding Unicode } |
          Where-Object { $m = [regex]::Match($_, "\t(\d\d:\d\d:\d\d)\.\d+\t"); $m.Success -and $m.Groups[1].Value -ge $after })
$term | Set-Content "$Out\terminal_lines.txt" -Encoding UTF8
if (Test-Path $TradeLog) { Copy-Item $TradeLog "$Out\$Name" -Force }

$refused = @($exp | Where-Object { $_ -match "NNFX orders: orders refused" })
$initFail = @($exp + $term | Where-Object { $_ -match "NNFX_EA.*(initialization failed|init failed)" })
$rows = if (Test-Path "$Out\$Name") { @(Get-Content "$Out\$Name") } else { @() }
$allowed = @($rows | Where-Object { $_ -match "orders allowed: DEMO" })
$started = @($rows | Where-Object { $_ -match ",INFO,.*start \(start\)" })
$login = @($term | Where-Object { $_ -match "authorized on|has been enabled" } | Select-Object -First 1)
Say ("terminal login line: " + $(if ($login) { $login[0].Trim() } else { "(none in the terminal log)" }))
Step "no 'orders refused' line from NNFX_EA" ($refused.Count -eq 0) $(if ($refused) { $refused[0].Trim() } else { "" })
Step "no initialization failure" ($initFail.Count -eq 0) $(if ($initFail) { $initFail[0].Trim() } else { "" })
Step "trade log: 'orders allowed: DEMO' (OnInit passed)" ($allowed.Count -gt 0) $(if ($allowed) { ($allowed[0] -split ",")[-1] } else { "no such row" })
Step "trade log: start-up ran after login" ($started.Count -gt 0) $(if ($started) { "$($started.Count) start rows; first: " + ($started[0] -split ",")[-1].Substring(0, [Math]::Min(120, ($started[0] -split ",")[-1].Length)) } else { "no start row" })
Say ""
Say $(if ($AllPass) { "OVERALL: PASS" } else { "OVERALL: FAIL" })
$Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
if ($AllPass) { exit 0 } else { exit 1 }
