<#
check_presets_mt5.ps1 - proves MT5 loads each NNFX_EA preset (Phase 6f; tools/make_presets.py).

For NNFX_M30.set, NNFX_H1.set and NNFX_H4.set: copies the preset to MQL5\Profiles\Tester\, runs the Strategy Tester
for two days with "ExpertParameters=<preset>" and NO [TesterInputs] section, and reads the EA's own first INFO row:
  - "NNFX_EA <tf>, magic <magic>, pairs EURUSD,AUDNZD,EURGBP,AUDCAD,CHFJPY, risk 2.00%, exposure first" (the preset's
    values, not the tester's last-used ones)
  - the trade log and decision log carry the preset's magic in their names
  - "news auto, master input -1": the preset's live settings (the EA's own calendar export; the master switch read
    from MT5, missing = OFF, D6d-1)
  - "NOT STARTED: InpNewsFile "auto" ...": the live export cannot run in the tester, so the EA refuses to start
    there (a tester run must name an exported history file); no order
Writes MQL5\Files\NNFX\checks\presets_<stamp>\SUMMARY.txt. D-OPS-1: the full-path terminal only.
#>
param(
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Common  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [string]$From    = "2026.09.22",
    [string]$To      = "2026.09.24"
)
$ErrorActionPreference = "Continue"
$Terminal = Join-Path $Install "terminal64.exe"
$Out = Join-Path $MT5 ("MQL5\Files\NNFX\checks\presets_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force $Out | Out-Null
$Summary = New-Object System.Collections.Generic.List[string]
$AllPass = $true
function Say([string]$t) { Write-Host $t; $script:Summary.Add($t) }
if (Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Terminal }) { Say "STOP: MT5 is running"; exit 1 }
Copy-Item "$Repo\MQL5\Presets\NNFX_*.set" "$MT5\MQL5\Profiles\Tester\" -Force
Copy-Item "$Repo\MQL5\Presets\NNFX_*.set" "$MT5\MQL5\Presets\" -Force
foreach ($p in @(@{ Tf = "M30"; Magic = "26030" }, @{ Tf = "H1"; Magic = "26060" }, @{ Tf = "H4"; Magic = "26240" })) {
    $name = "EA_$($p.Tf)_$($p.Magic)_tester.csv"
    $tlog = "$Common\NNFX\trades\$name"; $dlog = "$Common\NNFX\decisions\$name"
    $ini = "$Out\run_$($p.Tf).ini"
    @("[Tester]", "Expert=NNFX\NNFX_EA", "ExpertParameters=NNFX_$($p.Tf).set", "Symbol=EURUSD", "Period=$($p.Tf)", "Model=1",
      "FromDate=$From", "ToDate=$To", "ForwardMode=0", "Optimization=0", "Visual=0", "Report=NNFX_EA_preset_$($p.Tf)",
      "ReplaceReport=1", "ShutdownTerminal=1") | Set-Content -LiteralPath $ini -Encoding ASCII
    $t0 = Get-Date
    $proc = Start-Process -FilePath $Terminal -ArgumentList "/config:`"$ini`"" -PassThru
    if (-not $proc.WaitForExit(20 * 60 * 1000)) { Stop-Process -Id $proc.Id -Force; Say "$($p.Tf): FAIL timeout"; $AllPass = $false; continue }
    Start-Sleep -Seconds 2
    $fresh = (Test-Path $tlog) -and ((Get-Item $tlog).LastWriteTime -ge $t0) -and (Test-Path $dlog) -and ((Get-Item $dlog).LastWriteTime -ge $t0)
    if (-not $fresh) { Say "$($p.Tf): FAIL no fresh logs named with magic $($p.Magic)"; $AllPass = $false; continue }
    Copy-Item $tlog "$Out\trades_$name" -Force; Copy-Item $dlog "$Out\decisions_$name" -Force
    $rows = Get-Content -LiteralPath $tlog
    $want = "NNFX_EA $($p.Tf); magic $($p.Magic); pairs EURUSD;AUDNZD;EURGBP;AUDCAD;CHFJPY; risk 2.00%; exposure first; news auto; master input -1"
    $info = @($rows | Where-Object { $_ -match ",INFO," -and $_.Contains($want) }).Count
    $master = @($rows | Where-Object { $_ -match ",INFO," -and $_ -match "NOT STARTED: InpNewsFile" }).Count
    $opens = @($rows | Where-Object { $_ -match "^[^,]*,OPEN," }).Count
    $mag = @($rows | Select-Object -Skip 1 | Where-Object { ($_ -split ",")[6] -ne $p.Magic }).Count
    $ok = ($info -eq 1 -and $master -eq 1 -and $opens -eq 0 -and $mag -eq 0)
    if (-not $ok) { $AllPass = $false }
    Say ("{0}: {1} - preset values in the EA's INFO row {2}; 'NOT STARTED (auto)' rows {3}; OPEN rows {4}; rows with another magic {5}" -f
         $p.Tf, $(if ($ok) { "PASS" } else { "FAIL" }), $info, $master, $opens, $mag)
}
Say $(if ($AllPass) { "OVERALL: PASS" } else { "OVERALL: FAIL" })
$Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
if ($AllPass) { exit 0 } else { exit 1 }
