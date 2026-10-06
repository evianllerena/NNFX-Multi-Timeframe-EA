<#
run_calendar_export.ps1 - Phase 6e: run NNFX_CalendarExport (live terminal; the calendar is not available in the
tester) and check its output.

  1. Copies the approved event list (news/news_events.txt, D6e-1) into MQL5\Files\NNFX\news\.
  2. Starts MT5 (the tested terminal only, D6c-1; its own PID, D-OPS-1) with the script in mode "export", every
     input listed, ShutdownTerminal=1.
  3. Copies the summary and the event file into the run folder.
  4. tools/check_calendar.py on the export (months, duplicates, VP's events per year, the time base in UTC against
     New York release times; the three releases that really moved are named as exceptions).
Output: <MT5 data folder>\MQL5\Files\NNFX\checks\calendar_export_<date-time>\
Usage:  powershell -ExecutionPolicy Bypass -File tools\run_calendar_export.ps1 [-From 2019.01] [-To 2026.09]
#>
param(
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Common  = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [string]$Python  = "C:\Users\Evision\AppData\Local\Programs\Python\Python312\python.exe",
    [string]$From    = "2019.01",
    [string]$To      = "2026.09"
)
# US releases that really moved (New York date|event): the Fed's emergency cuts of March 2020 and the NFP of
# 2025-11-20 (run calendar_export_20261006_181154)
$Exceptions = @("2020.03.03|Fed Interest Rate Decision", "2020.03.15|Fed Interest Rate Decision", "2025.11.20|Nonfarm Payrolls")
$ErrorActionPreference = "Continue"
$Terminal = Join-Path $Install "terminal64.exe"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Out = Join-Path $MT5 "MQL5\Files\NNFX\checks\calendar_export_$Stamp"
$Summary = New-Object System.Collections.Generic.List[string]
$AllPass = $true
function Say([string]$t) { Write-Host $t; $script:Summary.Add($t) }
function Step([string]$name, [bool]$ok, [string]$detail) {
    if (-not $ok) { $script:AllPass = $false }
    Say (("{0,-34} {1}" -f $name, $(if ($ok) { "PASS" } else { "FAIL" })) + $(if ($detail) { "  - $detail" } else { "" }))
}
if (@(Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $Terminal }).Count -gt 0) {
    Write-Host "STOP: the tested MetaTrader 5 ($Terminal) is open. Close it and run this again."; exit 2
}
New-Item -ItemType Directory -Force "$Out", "$MT5\MQL5\Presets", "$MT5\MQL5\Files\NNFX\news" | Out-Null
Say "NNFX calendar export  $Stamp"
Say "Repo: $Repo  (commit $(& git -C $Repo rev-parse --short HEAD 2>$null))"
Copy-Item "$Repo\news\news_events.txt" "$MT5\MQL5\Files\NNFX\news\" -Force
$set = "NNFX_CalendarExport_export.set"
[System.IO.File]::WriteAllText("$MT5\MQL5\Presets\$set", (@("InpMode=export", "InpCurrencies=USD,EUR,GBP,CAD,AUD,NZD,JPY,CHF",
    "InpList=NNFX\news\news_events.txt", "InpFrom=$From", "InpTo=$To") -join "`r`n") + "`r`n", [System.Text.Encoding]::Unicode)
Copy-Item "$MT5\MQL5\Presets\$set" $Out
@("[StartUp]", "Script=NNFX\NNFX_CalendarExport", "ScriptParameters=$set", "Symbol=EURUSD", "Period=H1", "ShutdownTerminal=1") |
    Set-Content "$Out\run_export.ini" -Encoding ASCII
$t0 = Get-Date
$p = Start-Process -FilePath $Terminal -ArgumentList "/config:`"$Out\run_export.ini`"" -PassThru
if (-not $p.WaitForExit(1800000)) {
    $null = $p.CloseMainWindow()
    if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Say "  (pid $($p.Id) still running after 30 min: closed by id)"
}
$sum = "$MT5\MQL5\Files\NNFX\calendar\_summary.txt"
$evf = "$Common\NNFX\calendar\events_${From}_${To}.txt"
$fresh = (Test-Path $sum) -and (Get-Item $sum).LastWriteTime -ge $t0 -and (Test-Path $evf) -and (Get-Item $evf).LastWriteTime -ge $t0
if ($fresh) { Copy-Item $sum, $evf $Out -Force }
$res = if ($fresh) { ([regex]::Matches((Get-Content $sum -Raw), "(?m)^RESULT:.*$") | Select-Object -Last 1).Value } else { "" }
Step "export" ($fresh -and $res -match "^RESULT: (\d+) of \1 months exported, 0 errors") $(if ($res) { $res.Trim() } else { "no fresh summary or event file" })
if ($fresh) {
    $lines = & $Python "$Repo\tools\check_calendar.py" "$Out\events_${From}_${To}.txt" "$Out\_summary.txt" --from $From --to $To `
        --list "$Repo\news\news_events.txt" @($Exceptions | ForEach-Object { "--exception"; $_ }) 2>&1 | ForEach-Object { [string]$_ }
    $code = $LASTEXITCODE
    $lines | Set-Content "$Out\check_calendar.txt" -Encoding ASCII
    $r = @($lines | Where-Object { $_ -match "^RESULT" }) | Select-Object -Last 1
    Step "check_calendar.py" ($code -eq 0) $r
}
$day = Get-Date -Format "yyyyMMdd"
Copy-Item "$MT5\Logs\$day.log" "$Out\terminal_$day.log" -ErrorAction SilentlyContinue
Say ""
Say $(if ($AllPass) { "OVERALL: PASS" } else { "OVERALL: NOT ALL PASSED (see the lines above)" })
Say "Everything from this run: $Out"
$Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
if ($AllPass) { exit 0 } else { exit 1 }
