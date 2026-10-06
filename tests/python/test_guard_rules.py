"""Source scans for the owner's 6d decisions (docs/DECISIONS.md).

D6d-4  The EA never uses TimeLocal() (this PC's clock). Only NNFX_EnvCheck's read-only report may print it, on
       its "Local (PC):" line.
D6d-3  A drawdown reset is manual only: NNFXDrawdownReset( is called only inside NNFXDrawdownResetRequested in
       Guard.mqh (owner input: the NNFX_DD_RESET global variable or the chart button), plus the fixture test
       NNFX_GuardTest.mq5. NNFXDrawdownResetRequested returns a log text that its callers must log.
"""
import os
import re
import unittest

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MQL5 = os.path.join(ROOT, "MQL5")


def mql_files():
    for d, _, names in os.walk(MQL5):
        for n in sorted(names):
            if n.endswith((".mq5", ".mqh")):
                yield os.path.join(d, n)


def code_lines(path):
    """Lines with // comments removed (string contents kept)."""
    with open(path, encoding="utf-8", errors="replace") as f:
        for n, line in enumerate(f, 1):
            yield n, re.sub(r"//.*$", "", line.rstrip("\n"))


def time_local_violations():
    found = []
    for path in mql_files():
        rel = os.path.relpath(path, ROOT)
        for n, line in code_lines(path):
            if "TimeLocal" in line:
                if os.path.basename(path) == "NNFX_EnvCheck.mq5" and '"Local (PC):' in line:
                    continue
                found.append("D6d-4 %s:%d: %s" % (rel, n, line.strip()))
    return found


def reset_violations():
    found = []
    for path in mql_files():
        name = os.path.basename(path)
        rel = os.path.relpath(path, ROOT)
        func = None
        for n, line in code_lines(path):
            m = re.match(r"^\s*\w[\w\s&*]*\s(\w+)\s*\(", line)
            if m and not line.strip().endswith(";") and not line.startswith(" "):
                func = m.group(1)
            if re.search(r"\bNNFXDrawdownReset\s*\(", line):
                if name == "Guard.mqh" and (func in ("NNFXDrawdownReset", "NNFXDrawdownResetRequested")):
                    continue
                if name == "NNFX_GuardTest.mq5":
                    continue
                found.append("D6d-3 %s:%d (in %s): %s" % (rel, n, func, line.strip()))
    return found


class TestGuardRules(unittest.TestCase):
    def test_no_time_local(self):
        v = time_local_violations()
        self.assertEqual(v, [], "\n".join(v))

    def test_drawdown_reset_manual_only(self):
        v = reset_violations()
        self.assertEqual(v, [], "\n".join(v))

    def test_reset_request_returns_a_log_text(self):
        with open(os.path.join(MQL5, "Include", "NNFX", "Guard.mqh"), encoding="utf-8") as f:
            text = f.read()
        self.assertRegex(text, r"bool NNFXDrawdownResetRequested\(NNFXDrawdown &dd, const double equity, string &logText\)")
        self.assertIn("drawdown reset by hand (D6d-3)", text)

    def test_scans_catch_planted_lines(self):
        import tempfile
        import shutil
        global MQL5
        keep = MQL5
        tmp = tempfile.mkdtemp()
        try:
            os.makedirs(os.path.join(tmp, "Include", "NNFX"))
            with open(os.path.join(tmp, "Include", "NNFX", "X.mqh"), "w") as f:
                f.write("void Daily(void)\n  {\n   datetime t = TimeLocal();\n   NNFXDrawdownReset(g_dd, 1.0);\n  }\n")
            MQL5 = tmp
            self.assertEqual(len(time_local_violations()), 1)
            self.assertEqual(len(reset_violations()), 1)
        finally:
            MQL5 = keep
            shutil.rmtree(tmp)


if __name__ == "__main__":
    unittest.main()
