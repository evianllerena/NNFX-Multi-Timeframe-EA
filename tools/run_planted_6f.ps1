<#
run_planted_6f.ps1 - Phase 6f planted bugs: each defect is put into the MT5 COPY of the code (never the repo), the
check aimed at it must FAIL with the expected text, and the copy is then restored from the repo and proved byte for
byte (SHA-256). Two Python plants change a repo checker for one test run and are restored from git (git diff clean).

  baselines (clean code): the 2-week H1 run (2026.06.01-06.15) and the same run with the master switch off on
  2026.06.02 12:00-24:00; both must PASS. They are the baselines for the restart plants.
  E1  the decision log skips rows with no event                  -> check_decision_log  "gap from|no row at"
  E2  pairs visited in reverse order                             -> check_decision_log  "out of the fixed order"
  E3  the decision time is half a candle late                    -> check_decision_log  "candle boundary"
  E4  an acted-on ENTER is not written as "OPEN <id>"            -> check_decision_log  "but the action is"
  E5  the order is sent under another trade id than logged       -> check_decision_log  "has no OPEN for it|has no decision row"
  E6  news N1/N2 not fed into the core's block                   -> check_news_inputs   "N1/N2 in the block"
  E7  the X5 flag computed at the candle's open, not its close   -> check_news_inputs   "news flag"
  E8  the core snapshot loses the C1 run length                  -> NNFX_CoreStateTest  "FAIL"
  E9  a restart acts on the waiting candle (no missed rows)      -> check_ea_restart    "no missed-candle row"
  E10 a restart skips the broker trail of the missed candle      -> check_ea_restart    "trade log differs"
  P1  check_trades: the slippage-window rule switched off        -> test_check_trades   window beyond the slippage
  P2  check_news_inputs: the news flag not compared              -> test_check_news_inputs wrong first-close flag
Output: <MT5 data folder>\MQL5\Files\NNFX\checks\planted_6f_<date-time>\SUMMARY.txt
#>
param(
    [string]$Repo    = "C:\Users\Evision\NNFX-Multi-Timeframe-EA",
    [string]$MT5     = "C:\Users\Evision\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$Install = "C:\Program Files\MetaTrader 5",
    [string]$Python  = "C:\Users\Evision\AppData\Local\Programs\Python\Python312\python.exe"
)
$ErrorActionPreference = "Continue"
$Terminal = Join-Path $Install "terminal64.exe"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Out = Join-Path $MT5 "MQL5\Files\NNFX\checks\planted_6f_$Stamp"
$Checks = Join-Path $MT5 "MQL5\Files\NNFX\checks"
New-Item -ItemType Directory -Force $Out | Out-Null
$Summary = New-Object System.Collections.Generic.List[string]
$Caught = 0; $Total = 0; $AllPass = $true
function Say([string]$t) { Write-Host $t; $script:Summary.Add($t) }
if (Get-Process terminal64 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Terminal }) { Say "STOP: MT5 is running"; exit 2 }
Say "Phase 6f planted bugs  $Stamp  (repo commit $(& git -C $Repo rev-parse --short HEAD 2>$null))"

function Copy-Clean {
    Copy-Item "$Repo\MQL5\Include\NNFX\*.mqh" "$MT5\MQL5\Include\NNFX\" -Force
    Copy-Item "$Repo\MQL5\Experts\NNFX\*.mq5" "$MT5\MQL5\Experts\NNFX\" -Force
    Copy-Item "$Repo\MQL5\Scripts\NNFX\*.mq5" "$MT5\MQL5\Scripts\NNFX\" -Force
    New-Item -ItemType Directory -Force "$MT5\MQL5\Files\NNFX\fixtures" | Out-Null
    Copy-Item "$Repo\tests\fixtures\mql5\*.txt" "$MT5\MQL5\Files\NNFX\fixtures\" -Force
}
function Plant([string]$rel, [string]$old, [string]$new) {
    $path = Join-Path $MT5 $rel
    $text = [System.IO.File]::ReadAllText($path)
    # the plant text is written with CRLF; match the file's own line ends
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $old = $old.Replace("`r`n", "`n").Replace("`n", $nl)
    $new = $new.Replace("`r`n", "`n").Replace("`n", $nl)
    $n = ([regex]::Matches($text, [regex]::Escape($old))).Count
    if ($n -ne 1) { return "the text to replace occurs $n times (need 1)" }
    [System.IO.File]::WriteAllText($path, $text.Replace($old, $new), (New-Object System.Text.UTF8Encoding($false)))
    return ""
}
function Tester([string]$tag, [string[]]$set) {
    $a = @("-ExecutionPolicy", "Bypass", "-File", "$Repo\tools\run_ea_tester.ps1", "-Period", "H1", "-From", "2026.06.01",
           "-To", "2026.06.15", "-Tag", $tag, "-TimeoutMin", "30", "-NoCopy")
    if ($set.Count -gt 0) { $a += @("-Set", ($set -join ",")) }
    $o = & powershell @a 2>&1 | Out-String
    $dir = (Get-ChildItem "$Checks\ea_$($tag)_*" -Directory | Sort-Object Name | Select-Object -Last 1).FullName
    return @{ Text = $o; Dir = $dir }
}
function Folder-Text([string]$dir) {
    if (-not $dir) { return "" }
    return ((Get-ChildItem $dir -Filter "check_*.txt" | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n")
}
function Result([string]$id, [string]$what, [bool]$caught, [string]$detail) {
    $script:Total++
    if ($caught) { $script:Caught++ } else { $script:AllPass = $false }
    Say ("{0,-4} {1,-58} {2}  - {3}" -f $id, $what, $(if ($caught) { "CAUGHT" } else { "MISSED" }), $detail)
}
function First-Match([string]$text, [string]$pattern) {
    $m = [regex]::Match($text, "(?m)^.*(" + $pattern + ").*$")
    if ($m.Success) { return $m.Value.Trim() } else { return "" }
}

# baselines on the clean code
Copy-Clean
$b1 = Tester "planted_base" @()
$b2 = Tester "planted_base_master" @("InpTesterMasterOff=2026.06.02 12:00;2026.06.03 00:00")
$ok1 = $b1.Text -match "(?m)^OVERALL: PASS"; $ok2 = $b2.Text -match "(?m)^OVERALL: PASS"
Say ("baseline clean run: {0}; baseline with the master switch off: {1}" -f $(if ($ok1) { "PASS" } else { "FAIL" }), $(if ($ok2) { "PASS" } else { "FAIL" }))
if (-not ($ok1 -and $ok2)) { Say "STOP: the clean code does not pass; no plant is meaningful"; $Summary | Set-Content "$Out\SUMMARY.txt"; exit 1 }
$Base = "$($b1.Dir)\decisions_EA_H1_26060_tester.csv"; $BaseT = "$($b1.Dir)\trades_EA_H1_26060_tester.csv"

$ea = "MQL5\Experts\NNFX\NNFX_EA.mq5"
$plants = @(
    @{ Id = "E1"; What = "the decision log skips rows with no event"; File = $ea;
       Old = 'g_dlog.Write(sym, Tf(), bars[j], true, NNFXEventsText(g_core[k], 0), action == "" ? "-" : action, batchNote + note);'
       New = 'if(NNFXEventsText(g_core[k], 0) != "" || action != "") g_dlog.Write(sym, Tf(), bars[j], true, NNFXEventsText(g_core[k], 0), action == "" ? "-" : action, batchNote + note);'
       Kind = "tester"; Expect = "gap from|no row at" },
    @{ Id = "E2"; What = "pairs visited in reverse order"; File = $ea;
       Old = "   int ks[];`r`n   for(int k = 0; k < n; k++)"; New = "   int ks[];`r`n   for(int k = n - 1; k >= 0; k--)"
       Kind = "tester"; Expect = "out of the fixed order" },
    @{ Id = "E3"; What = "the decision time is half a candle late"; File = "MQL5\Include\NNFX\DecisionLog.mqh";
       Old = "TimeToString((datetime)b.t, TIME_DATE | TIME_MINUTES)"; New = "TimeToString((datetime)b.t + PeriodSeconds() / 2, TIME_DATE | TIME_MINUTES)"
       Kind = "tester"; Expect = "candle boundary" },
    @{ Id = "E4"; What = "an acted-on ENTER is not written as OPEN <id>"; File = $ea;
       Old = 'action += (action == "" ? "" : "; ") + "OPEN " + id;'; New = 'action += "";'
       Kind = "tester"; Expect = "but the action is" },
    @{ Id = "E5"; What = "the order is sent under another trade id than logged"; File = $ea;
       Old = "g_orders.OpenTrade(sym, e.dir, bars[j].atr, risk, cap, id, false)"; New = "g_orders.OpenTrade(sym, e.dir, bars[j].atr, risk, cap, id + ""x"", false)"
       Kind = "tester"; Expect = "has no OPEN for it|has no decision row" },
    @{ Id = "E6"; What = "news N1/N2 not fed into the core's block"; File = $ea;
       Old = "AddReason(block, NewsBlock(k, tc));"; New = "// news block left out (planted)"
       Kind = "tester"; Expect = "N1/N2 in the block" },
    @{ Id = "E7"; What = "the X5 flag computed at the candle's open, not its close"; File = $ea;
       Old = "bars[j].news = g_news_ok && NNFXNewsFirstClose(g_pairs[k], tc, g_prevClose[k], g_news, g_broker);"
       New = "bars[j].news = g_news_ok && NNFXNewsFirstClose(g_pairs[k], t, g_prevClose[k], g_news, g_broker);"
       Kind = "tester"; Expect = "news flag" },
    @{ Id = "E8"; What = "the core snapshot loses the C1 run length"; File = "MQL5\Include\NNFX\RulesCore.mqh";
       Old = "m_prev_ex, m_c1_run_dir, m_c1_run_len,"; New = "m_prev_ex, m_c1_run_dir, 0,"
       Kind = "corestate"; Expect = "FAIL" },
    @{ Id = "E9"; What = "a restart acts on the waiting candle (no missed rows)"; File = $ea;
       Old = "ClosedSince(k, saved, InpWarmupBars + 1, times);"; New = "ArrayResize(times, 0);"
       Kind = "restart_master"; Expect = "no missed-candle row" },
    @{ Id = "E10"; What = "a restart skips the broker trail of the missed candle"; File = $ea;
       Old = "g_orders.OnBarClose(sym, b.c, b.atr);   // open trades stay managed (S-2): the T4 trail at this close"
       New = "// trail left out (planted)"
       Kind = "restart_open"; Expect = "trade log differs" }
)
foreach ($p in $plants) {
    Copy-Clean
    $err = Plant $p.File $p.Old $p.New
    if ($err) { Result $p.Id $p.What $false "NOT PLANTED: $err"; continue }
    $text = ""
    switch ($p.Kind) {
        "tester" {
            $r = Tester "planted_$($p.Id)" @()
            $text = $r.Text + "`n" + (Folder-Text $r.Dir)
        }
        "corestate" {
            $src = "$MT5\MQL5\Scripts\NNFX\NNFX_CoreStateTest.mq5"; $log = "$Out\E8_compile.log"
            Start-Process -FilePath (Join-Path $Install "MetaEditor64.exe") -ArgumentList "/compile:`"$src`"", "/log:`"$log`"" -Wait -WindowStyle Hidden
            $ini = "$Out\run_corestate.ini"
            @("[StartUp]", "Script=NNFX\NNFX_CoreStateTest", "Symbol=EURUSD", "Period=H1", "ShutdownTerminal=1") | Set-Content $ini -Encoding ASCII
            $t0 = Get-Date
            $pr = Start-Process -FilePath $Terminal -ArgumentList "/config:`"$ini`"" -PassThru
            if (-not $pr.WaitForExit(300000)) { Stop-Process -Id $pr.Id -Force }
            $rep = "$MT5\MQL5\Files\NNFX_CoreStateTest.txt"
            if ((Test-Path $rep) -and (Get-Item $rep).LastWriteTime -ge $t0) { Copy-Item $rep "$Out\E8_NNFX_CoreStateTest.txt" -Force; $text = Get-Content $rep -Raw }
        }
        "restart_master" {
            $r = Tester "planted_$($p.Id)" @("InpTesterMasterOff=2026.06.02 12:00;2026.06.03 00:00", "InpRestartAt=2026.06.02 21:00")
            $o = & $Python -B "$Repo\tools\check_ea_restart.py" "$($r.Dir)\decisions_EA_H1_26060_tester.csv" "$($r.Dir)\trades_EA_H1_26060_tester.csv" `
                    --master-off "2026.06.02 12:00;2026.06.03 00:00" --replay-differs EURGBP --baseline "$($b2.Dir)\decisions_EA_H1_26060_tester.csv" 2>&1 | Out-String
            if ($r.Dir) { $o | Set-Content "$($r.Dir)\check_ea_restart.txt" -Encoding ASCII }
            $text = $o
        }
        "restart_open" {
            $r = Tester "planted_$($p.Id)" @("InpRestartAt=2026.06.02 21:00")
            $o = & $Python -B "$Repo\tools\check_ea_restart.py" "$($r.Dir)\decisions_EA_H1_26060_tester.csv" "$($r.Dir)\trades_EA_H1_26060_tester.csv" `
                    --baseline $Base --baseline-trades $BaseT 2>&1 | Out-String
            if ($r.Dir) { $o | Set-Content "$($r.Dir)\check_ea_restart.txt" -Encoding ASCII }
            $text = $o
        }
    }
    $hit = First-Match $text $p.Expect
    Result $p.Id $p.What ([bool]$hit) $(if ($hit) { $hit.Substring(0, [Math]::Min(150, $hit.Length)) } else { "expected '$($p.Expect)' not found" })
}

# Python plants: the repo file is changed for one test run, then restored from git (git diff must be clean)
$py = @(
    @{ Id = "P1"; What = "check_trades: the slippage-window rule switched off"; File = "tools\check_trades.py";
       Old = "if held > target + slip_risk + RISK_BOUND:"; New = "if False:"; Test = "tests.python.test_check_trades" },
    @{ Id = "P2"; What = "check_news_inputs: the news flag not compared"; File = "tools\check_news_inputs.py";
       Old = 'if (r[15] == "1") != fc:'; New = "if False:"; Test = "tests.python.test_check_news_inputs" }
)
foreach ($p in $py) {
    $path = Join-Path $Repo $p.File
    # restored with "git checkout": never on a file with uncommitted changes (they would be lost)
    if (& git -C $Repo status --porcelain -- $p.File.Replace("\", "/")) { Result $p.Id $p.What $false "NOT PLANTED: the file has uncommitted changes"; continue }
    $text = [System.IO.File]::ReadAllText($path)
    if (([regex]::Matches($text, [regex]::Escape($p.Old))).Count -ne 1) { Result $p.Id $p.What $false "NOT PLANTED"; continue }
    [System.IO.File]::WriteAllText($path, $text.Replace($p.Old, $p.New), (New-Object System.Text.UTF8Encoding($false)))
    Push-Location $Repo
    $o = & $Python -B -m unittest $p.Test 2>&1 | Out-String
    & git checkout -- $p.File.Replace("\", "/")
    $clean = (& git status --porcelain -- $p.File.Replace("\", "/")) -eq $null
    Pop-Location
    $o | Set-Content "$Out\$($p.Id)_unittest.txt" -Encoding ASCII
    $hit = First-Match $o "^FAIL: test_\w+"
    Result $p.Id $p.What ([bool]$hit -and $clean) $(if ($hit) { $hit + $(if ($clean) { "; restored, git clean" } else { "; NOT RESTORED" }) } else { "no failing test" })
}

# restore the MT5 copy and prove it byte for byte
Copy-Clean
$same = $true
foreach ($rel in @("MQL5\Experts\NNFX\NNFX_EA.mq5", "MQL5\Include\NNFX\DecisionLog.mqh", "MQL5\Include\NNFX\RulesCore.mqh",
                   "MQL5\Scripts\NNFX\NNFX_CoreStateTest.mq5")) {
    $a = (Get-FileHash (Join-Path $Repo $rel) -Algorithm SHA256).Hash; $b = (Get-FileHash (Join-Path $MT5 $rel) -Algorithm SHA256).Hash
    Say ("restored {0}: {1} ({2})" -f $rel, $(if ($a -eq $b) { "byte for byte" } else { "DIFFERS" }), $a.Substring(0, 12))
    if ($a -ne $b) { $same = $false; $AllPass = $false }
}
$after = Tester "planted_clean_rerun" @()
$okC = $after.Text -match "(?m)^OVERALL: PASS"
Say ("clean re-run after the restore: {0}" -f $(if ($okC) { "PASS" } else { "FAIL" }))
if (-not $okC) { $AllPass = $false }
$git = & git -C $Repo status --porcelain 2>$null
Say ("repo git status after the Python plants: {0}" -f $(if ($git) { "NOT CLEAN: " + ($git -join "; ") } else { "clean" }))
Say ""
Say ("RESULT: {0} of {1} planted bugs caught" -f $Caught, $Total)
Say $(if ($AllPass -and $same) { "OVERALL: PASS" } else { "OVERALL: FAIL" })
$Summary | Set-Content "$Out\SUMMARY.txt" -Encoding ASCII
if ($AllPass -and $same) { exit 0 } else { exit 1 }
