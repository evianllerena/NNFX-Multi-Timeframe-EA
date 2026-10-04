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
              Expected in that run's SUMMARY.txt:
                3 NNFX_EnvCheck   ... FAIL  - RESULT: INVALID (not connected)
                3 NNFX_ExportBars ... FAIL  - RESULT: INVALID (not connected)
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
    $m = [regex]::Match($stdout, "Everything from this run: (.+)")
    if (-not $m.Success) { return "" }
    $summary = Join-Path $m.Groups[1].Value.Trim() "SUMMARY.txt"
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
        $missing = Expect $text @(
            "3 NNFX_EnvCheck\s+FAIL\s+- RESULT: INVALID \(not connected\)",
            "3 NNFX_ExportBars\s+FAIL\s+- RESULT: INVALID \(not connected\)")
        if ($text -and $missing.Count -eq 0) { Write-Host "RESULT mt5-offline: PASS" }
        else { $ok = $false; Write-Host ("RESULT mt5-offline: FAIL (missing: " + ($missing -join " | ") + $(if (-not $text) { "; no SUMMARY.txt" }) + ")") }
    }
}
if ($ok) { exit 0 } else { exit 1 }
