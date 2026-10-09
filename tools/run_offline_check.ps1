<#
run_offline_check.ps1 - proves the two failure paths that a normal run never reaches
(G1_phase5_2 verdict, carry-over 1; docs/PLAN_PHASE6.md section 7).

  -NoPython   Runs tools/run_phase5_checks.ps1 -PythonOnly in a child PowerShell whose PATH has
              no python/py and whose LOCALAPPDATA is an empty folder, so no Python can be found.
              Expected in that run's SUMMARY.txt:
                5 Python unit tests ... FAIL  - no working Python found
                5 check_export.py   ... NOT RUN
                5 check_indicators.py ... NOT RUN
                OVERALL: NOT ALL PASSED
              Needs nothing from the owner; MT5 may be open or closed.

  -Mt5Offline Runs tools/run_phase5_checks.ps1 -SkipTester while MT5 cannot reach its server.
              The owner first blocks terminal64.exe in Windows Firewall from an ADMIN PowerShell:
                New-NetFirewallRule -DisplayName "NNFX offline test" -Direction Outbound `
                  -Program "C:\Program Files\MetaTrader 5\terminal64.exe" -Action Block
              and removes it afterwards:
                Remove-NetFirewallRule -DisplayName "NNFX offline test"
              This script only checks that the rule exists; it never creates or removes it.
              Since 6c the runner stops at its account check (D6c-1) right after EnvCheck when no account can
              be read, so it never reaches ExportBars (run 20261009_102801, in invalid\). Expected:
                runner SUMMARY.txt:           3 account check ... FAIL  - logged in as '' on ''
                the run's NNFX_EnvCheck.txt:  RESULT: INVALID (not connected)
              then this script starts NNFX_ExportBars itself (the runner's /config form, the tested terminal
              only, closed by its own process id); its _summary.txt, copied into the runner's folder as
              NNFX_ExportBars_offline_summary.txt, must end RESULT: INVALID (not connected).
              The runner's account-check stop is unchanged (owner, 2026-10-09: 1A).
              MT5 must be closed (the runner refuses otherwise).

Each part prints "RESULT <part>: PASS" or "RESULT <part>: FAIL (<why>)" and copies nothing; the
runner's own results folder (printed) holds the evidence. Exit code 0 only if every part run passed.

Usage:
  powershell -ExecutionPolicy Bypass -File tools\run_offline_check.ps1 -NoPython
  powershell -ExecutionPolicy Bypass -File tools\run_offline_check.ps1 -Mt5Offline
#>
param(
    [string]$Repo = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [switch]$NoPython,
    [switch]$Mt5Offline
)
$ErrorActionPreference = "Continue"
$Runner = Join-Path $Repo "tools\run_phase5_checks.ps1"
$Rule = "NNFX offline test"
$MT5 = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
$Terminal = "C:\Program Files\MetaTrader 5\terminal64.exe"
$script:RunnerOut = ""
$ok = $true
if (-not $NoPython -and -not $Mt5Offline) { Write-Host "Give -NoPython and/or -Mt5Offline"; exit 2 }

# Runs the runner in a child PowerShell with the given environment; returns its SUMMARY.txt text.
function Run-Runner([string[]]$runnerArgs, [hashtable]$envOverride) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$Runner`" " + ($runnerArgs -join " ")
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($k in $envOverride.Keys) { $psi.EnvironmentVariables[$k] = $envOverride[$k] }
    $p = [System.Diagnostics.Process]::Start($psi)
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    Write-Host $stdout
    if ($stderr) { Write-Host $stderr }
    # the runner ends "Everything from this run: <folder>", or "... Output: <folder>" when it stops early
    $m = [regex]::Match($stdout, "(?:Everything from this run|Output): (.+)")
    if (-not $m.Success) { return "" }
    $script:RunnerOut = $m.Groups[1].Value.Trim()
    $summary = Join-Path $script:RunnerOut "SUMMARY.txt"
    if (Test-Path $summary) { return (Get-Content -LiteralPath $summary -Raw) } else { return "" }
}

function Expect([string]$text, [string[]]$patterns) {
    $missing = @($patterns | Where-Object { -not ($text -match $_) })
    return $missing
}

if ($NoPython) {
    # PATH without any folder that holds python.exe / py.exe, and without WindowsApps (the Store stub).
    $paths = $env:PATH -split ";" | Where-Object {
        $_ -and -not ($_ -match "WindowsApps") -and
        -not (Test-Path (Join-Path $_ "python.exe")) -and -not (Test-Path (Join-Path $_ "py.exe"))
    }
    $empty = Join-Path $env:TEMP ("nnfx_no_python_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
    New-Item -ItemType Directory -Force $empty | Out-Null
    Write-Host "== NoPython: PATH has $(@($paths).Count) entries, none with python/py; LOCALAPPDATA=$empty"
    $text = Run-Runner @("-PythonOnly") @{ PATH = ($paths -join ";"); LOCALAPPDATA = $empty }
    $missing = Expect $text @(
        "5 Python unit tests\s+FAIL\s+- no working Python found",
        "5 check_export\.py\s+NOT RUN",
        "5 check_indicators\.py\s+NOT RUN",
        "OVERALL: NOT ALL PASSED")
    if ($text -and $missing.Count -eq 0) { Write-Host "RESULT no-python: PASS" }
    else { $ok = $false; Write-Host ("RESULT no-python: FAIL (missing: " + ($missing -join " | ") + $(if (-not $text) { "; no SUMMARY.txt" }) + ")") }
}

if ($Mt5Offline) {
    $r = Get-NetFirewallRule -DisplayName $Rule -ErrorAction SilentlyContinue
    if (-not $r -or "$($r.Enabled)" -ne "True" -or "$($r.Action)" -ne "Block") {
        $ok = $false
        Write-Host "RESULT mt5-offline: NOT RUN (firewall rule '$Rule' not found, not enabled or not Block; see the header)"
    } else {
        Write-Host "== Mt5Offline: firewall rule '$Rule' present (Block, enabled)"
        $text = Run-Runner @("-SkipTester") @{}
        $missing = @(Expect $text @("3 account check\s+FAIL\s+- logged in as '' on ''"))
        $envFile = if ($script:RunnerOut) { Join-Path $script:RunnerOut "NNFX_EnvCheck.txt" } else { "" }
        if (-not ($envFile -and (Test-Path $envFile) -and (Get-Content -LiteralPath $envFile -Raw).Contains("RESULT: INVALID (not connected)"))) {
            $missing += "NNFX_EnvCheck.txt: RESULT: INVALID (not connected)"
        }
        # ExportBars, started here (the runner stops before it); only the tested terminal, closed by its own id
        $exportOk = $false
        if ($script:RunnerOut -and @(Get-Process -Name terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -ieq $Terminal }).Count -eq 0) {
            $ini = Join-Path $script:RunnerOut "run_NNFX_ExportBars_offline.ini"
            @("[StartUp]", "Script=NNFX\NNFX_ExportBars", "Symbol=EURUSD", "Period=H1", "ShutdownTerminal=1") |
                Set-Content -LiteralPath $ini -Encoding ASCII
            $report = "$MT5\MQL5\Files\NNFX\export\_summary.txt"
            $t0 = Get-Date
            $p = Start-Process -FilePath $Terminal -ArgumentList "/config:`"$ini`"" -PassThru
            if (-not $p.WaitForExit(10 * 60 * 1000)) {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                Write-Host "  (ExportBars: MT5 pid $($p.Id) did not close in 10 min: stopped by id)"
            }
            Start-Sleep -Seconds 2
            if ((Test-Path $report) -and (Get-Item $report).LastWriteTime -ge $t0) {
                Copy-Item $report (Join-Path $script:RunnerOut "NNFX_ExportBars_offline_summary.txt") -Force
                $res = ([regex]::Matches((Get-Content -LiteralPath $report -Raw), "(?m)^RESULT:.*$") | Select-Object -Last 1).Value
                Write-Host "  NNFX_ExportBars (offline): $res"
                $exportOk = ("$res".Trim() -eq "RESULT: INVALID (not connected)")
            } else { Write-Host "  NNFX_ExportBars (offline): no new _summary.txt" }
        } else { Write-Host "  NNFX_ExportBars (offline): not started (no runner folder, or the tested MT5 is open)" }
        if (-not $exportOk) { $missing += "NNFX_ExportBars _summary.txt: RESULT: INVALID (not connected)" }
        if ($text -and $missing.Count -eq 0) { Write-Host "RESULT mt5-offline: PASS" }
        else { $ok = $false; Write-Host ("RESULT mt5-offline: FAIL (missing: " + ($missing -join " | ") + $(if (-not $text) { "; no SUMMARY.txt" }) + ")") }
    }
}
if ($ok) { exit 0 } else { exit 1 }
