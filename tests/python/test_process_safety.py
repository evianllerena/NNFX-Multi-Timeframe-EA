"""Source scan for owner decision D6c-1 (tools never touch a terminal they did not start).

In every PowerShell and Python file under tools/:
  P1  Stop-Process only by process id: every Stop-Process has -Id (never -Name / -ProcessName / a pipe
      from Get-Process).
  P2  taskkill only by /PID (never /IM).
  P3  every "is MT5 running" check (Get-Process ... terminal64) filters by the full path on the same line,
      so another broker's terminal64.exe is never mistaken for the one being tested.
Comments are removed before scanning (PowerShell '#' and '<# #>', Python '#').
The scanned folder can be changed with the environment variable NNFX_SCAN_ROOT (repo root).
"""
import os
import re
import unittest

ROOT = os.environ.get("NNFX_SCAN_ROOT") or os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TOOLS = os.path.join(ROOT, "tools")


def strip_comments(text, ps):
    if ps:
        text = re.sub(r"<#.*?#>", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    out = []
    for line in text.splitlines():
        out.append(re.sub(r"#.*$", "", line) if not line.lstrip().startswith(("\"", "'")) else line)
    return out


def violations():
    found = []
    for name in sorted(os.listdir(TOOLS)):
        if not name.endswith((".ps1", ".py")):
            continue
        path = os.path.join(TOOLS, name)
        lines = strip_comments(open(path, encoding="utf-8", errors="replace").read(), name.endswith(".ps1"))
        for n, line in enumerate(lines, 1):
            low = line.lower()
            if "stop-process" in low and not re.search(r"stop-process\s+(.*\s)?-id\b", low):
                found.append("P1 %s:%d: Stop-Process without -Id: %s" % (name, n, line.strip()))
            if "stop-process" in low and re.search(r"-(process)?name\b", low):
                found.append("P1 %s:%d: Stop-Process by name: %s" % (name, n, line.strip()))
            if "taskkill" in low and ("/im" in low or "/pid" not in low):
                found.append("P2 %s:%d: taskkill not by /PID: %s" % (name, n, line.strip()))
            if "get-process" in low and "terminal64" in low and "path" not in low:
                found.append("P3 %s:%d: terminal64 check without the full path: %s" % (name, n, line.strip()))
    return found


class TestProcessSafety(unittest.TestCase):
    def test_no_violations(self):
        found = violations()
        self.assertEqual(found, [], "\n".join(found))

    def test_rules_catch_bad_lines(self):
        bad = ["Get-Process -Name terminal64 | Stop-Process -Force",
               "Stop-Process -Name terminal64",
               "taskkill /IM terminal64.exe /F",
               "if (Get-Process -Name terminal64) { exit 2 }"]
        good = ["Stop-Process -Id $p.Id -Force",
                "$x = @(Get-Process -Name terminal64 | Where-Object { $_.Path -ieq $Terminal })",
                "taskkill /PID 1234 /F"]
        import tempfile
        global TOOLS
        saved = TOOLS
        with tempfile.TemporaryDirectory() as tmp:
            TOOLS = tmp
            try:
                for line in bad:
                    with open(os.path.join(tmp, "x.ps1"), "w") as f:
                        f.write(line + "\n")
                    self.assertTrue(violations(), line)
                for line in good:
                    with open(os.path.join(tmp, "x.ps1"), "w") as f:
                        f.write(line + "\n")
                    self.assertEqual(violations(), [], line)
            finally:
                TOOLS = saved


if __name__ == "__main__":
    unittest.main()
