<#
run_backtest_set.ps1 - one backtest per timeframe, each checked and summarised (Phase 7, DECISIONS P7-3).

For each of -Periods (default M30, H1, H4): tools/run_ea_tester.ps1 with the preset's inputs (its own magic), the given
window and -Set overrides (default InpTesterDdPause=0, P7-2), which runs check_trades, check_decision_log,
check_news_inputs and check_replay (Check 1b); then tools/summarize_trades.py on its trade log and tester report.
Everything goes to <MT5 data folder>\MQL5\Files\NNFX\checks\backtest_<Tag>_<date-time>\ (SUMMARY.txt, one
summary_<period>.txt and .json per run, the run folders' paths).

Usage:  powershell -ExecutionPolicy Bypass -File tools\run_backtest_set.ps1 -From 2019.01.01 -To 2024.03.01 -Tag explore1
#>
param(
    [string]$Repo    = (Split-Path -Parent $PSScriptRoot),
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Python  = "C:\Users\Evision\AppData\Local\Programs\Python\Python312\python.exe",
    [string]$From    = "2019.01.01",
    [string]$To      = "2024.03.01",
    [string[]]$Periods = @("M30", "H1", "H4"),
    [string]$Tag     = "explore",
    [string[]]$Set   = @("InpTesterDdPause=0"),
    [int]$Model      = 1,
    [int]$TimeoutMin = 240
)
$ErrorActionPreference = "Continue"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Checks = Join-Path $MT5 "MQL5\Files\NNFX\checks"
$Out = Join-Path $Checks "backtest_$($Tag)_$Stamp"
New-Item -ItemType Directory -Force $Out | Out-Null
$Summary = New-Object System.Collections.Generic.List[string]
$AllPass = $true
function Say([string]$t) { Write-Host $t; $script:Summary.Add($t) }
$Periods = @($Periods | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })
Say "Backtest set $Tag  $Stamp  repo $Repo (commit $(& git -C $Repo rev-parse --short HEAD 2>$null))"
Say "window $From - $To, model $Model, periods $($Periods -join ' '), overrides $($Set -join ' ')"
foreach ($p in $Periods) {
    $tag = "$($Tag)_$($p)"
    $a = @("-ExecutionPolicy", "Bypass", "-File", "$Repo\tools\run_ea_tester.ps1", "-Repo", $Repo, "-Period", $p, "-From", $From,
           "-To", $To, "-Model", "$Model", "-Tag", $tag, "-TimeoutMin", "$TimeoutMin", "-MinTrades", "1")
    if ($Set.Count -gt 0) { $a += @("-Set", ($Set -join ",")) }
    $o = & powershell @a 2>&1 | Out-String
    $dir = (Get-ChildItem "$Checks\ea_$($tag)_*" -Directory | Sort-Object Name | Select-Object -Last 1).FullName
    $o | Set-Content "$Out\run_$p.txt" -Encoding ASCII
    $overall = [regex]::Match($o, "(?m)^OVERALL: \w+").Value
    Say ""
    Say "$p  run folder $dir  $overall"
    foreach ($m in [regex]::Matches($o, "(?m)^[0-9] \S.*$")) { Say ("   " + $m.Value.Trim()) }
    if ($overall -ne "OVERALL: PASS") { $AllPass = $false }
    $trades = if ($dir) { Get-ChildItem "$dir\trades_*.csv" | Select-Object -First 1 } else { $null }
    $report = if ($dir) { Get-ChildItem "$dir\NNFX_EA_*.htm" | Select-Object -First 1 } else { $null }
    if ($trades -and $report) {
        $s = & $Python -B "$Repo\tools\summarize_trades.py" $trades.FullName --report $report.FullName --label "$p $From-$To" `
                 --json "$Out\summary_$p.json" 2>&1 | Out-String
        $s | Set-Content "$Out\summary_$p.txt" -Encoding ASCII
        foreach ($l in ($s -split "`r?`n")) { if ($l.Trim() -ne "" -and $l -notmatch "^=+$") { Say ("   " + $l.TrimEnd()) } }
        if ($s -notmatch "(?m)^RESULT summary .*: OK") { $AllPass = $false }
        $pause = Select-String -LiteralPath $trades.FullName -Pattern "drawdown pause \(R-12\)" | Select-Object -First 1
        Say ("   R-12 drawdown pause would first have started: " + $(if ($pause) { ($pause.Line -split ",")[0] } else { "never" }))
    } else {
        Say "   no trade log or report: not summarised"
        $AllPass = $false
    }
}
Say ""
Say $(if ($AllPass) { "OVERALL: PASS" } else { "OVERALL: FAIL" })
$Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
Write-Host "Summary: $Out\SUMMARY.txt"
if ($AllPass) { exit 0 } else { exit 1 }
