"""Source scan for the order safety rule (docs/PLAN_PHASE6.md section 1, tests S2 and S2b).

S2   Every trading call (OrderSend, OrderSendAsync, CTrade, PositionClose, PositionModify,
     OrderModify, OrderDelete) anywhere under MQL5/ is inside MQL5/Include/NNFX/Orders.mqh, and
     every public method of class CNNFXOrders starts with a call to NNFXOrdersAllowed.
S2b  The test-only paths (G2 verdict F3; G1_phase6b_1 F1): NNFXTestOpenWithoutStop, TestLoseNextReply,
     TestFailNextHalf2, TestStopsLevelOverride, TestFreeMarginOverride and TestFillOffset exist only
     inside "#ifdef NNFX_TEST_BUILD"; all but TestLoseNextReply refuse unless MQLInfoInteger(MQL_TESTER)
     is true (TestLoseNextReply only drops a reply, the retry then finds the position); NNFX_TEST_BUILD is defined only by the test EA
     MQL5/Experts/NNFX/NNFX_OrderTest.mq5, never by NNFX_EA.mq5 or any other file.

Comments and string literals are removed before scanning, so prose never counts.
The scanned folder can be changed with the environment variable NNFX_SCAN_ROOT (repo root).
"""
import os
import re
import unittest

ROOT = os.environ.get("NNFX_SCAN_ROOT") or os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MQL5 = os.path.join(ROOT, "MQL5")
ORDERS = os.path.join(MQL5, "Include", "NNFX", "Orders.mqh")
TEST_EA = os.path.join(MQL5, "Experts", "NNFX", "NNFX_OrderTest.mq5")
TRADING = re.compile(r"\b(OrderSend|OrderSendAsync|CTrade|PositionClose|PositionModify|OrderModify|OrderDelete)\b")
GUARD = re.compile(r"^\s*if\s*\(\s*!\s*NNFXOrdersAllowed\s*\(")
TEST_ONLY = ("NNFXTestOpenWithoutStop", "TestLoseNextReply", "TestFailNextHalf2", "TestStopsLevelOverride",
             "TestFreeMarginOverride", "TestFillOffset")


def strip_code(text):
    """Remove // and /* */ comments and string/char literals, keeping line breaks."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            seg = text[i:n if j < 0 else j + 2]
            out.append("\n" * seg.count("\n"))
            i = n if j < 0 else j + 2
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            out.append(c + c)
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def mql_files():
    for d, _, files in os.walk(MQL5):
        for f in files:
            if f.endswith((".mq5", ".mqh")):
                yield os.path.join(d, f)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def matching_brace(text, open_at):
    depth = 0
    for k in range(open_at, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return k
    raise ValueError("unbalanced braces")


def public_methods(code):
    """(name, body, start offset) of every method defined in the public: section(s) of CNNFXOrders."""
    m = re.search(r"\bclass\s+CNNFXOrders\b[^{]*\{", code)
    if not m:
        raise AssertionError("class CNNFXOrders not found in Orders.mqh")
    start = m.end() - 1
    end = matching_brace(code, start)
    body = code[start + 1:end]
    methods, access, k = [], "private", 0
    head = re.compile(r"(public|private|protected)\s*:|([A-Za-z_][\w<>&*\s]*?)\b([A-Za-z_~]\w*)\s*\(([^()]|\([^()]*\))*\)\s*(const\s*)?(:[^{;]*)?\{")
    while True:
        h = head.search(body, k)
        if not h:
            break
        if h.group(1):
            access = h.group(1)
            k = h.end()
            continue
        brace = h.end() - 1
        close = matching_brace(body, brace)
        name = h.group(3)
        if access == "public":
            methods.append((name, body[brace + 1:close], start + 1 + h.start()))
        k = close + 1
    return methods, start


def ifdef_ranges(code, symbol):
    """Character ranges covered by '#ifdef symbol' ... matching '#endif' (nesting aware)."""
    ranges, stack = [], []
    for m in re.finditer(r"^[ \t]*#\s*(ifdef|ifndef|if|endif)\b\s*(\w*)", code, re.M):
        kind, sym = m.group(1), m.group(2)
        if kind in ("ifdef", "ifndef", "if"):
            stack.append((kind, sym, m.start()))
        elif stack:
            k2, s2, at = stack.pop()
            if k2 == "ifdef" and s2 == symbol:
                ranges.append((at, m.end()))
    return ranges


def violations():
    found = []
    # S2: trading calls only in Orders.mqh
    for path in mql_files():
        if os.path.normcase(path) == os.path.normcase(ORDERS):
            continue
        code = strip_code(read(path))
        for lineno, line in enumerate(code.splitlines(), 1):
            if TRADING.search(line):
                found.append("S2: trading call outside Orders.mqh: %s:%d: %s"
                             % (os.path.relpath(path, ROOT), lineno, line.strip()))
    # S2: every public method starts with the guard
    code = strip_code(read(ORDERS))
    methods, _ = public_methods(code)
    names = [m[0] for m in methods]
    if len(methods) < 8:
        found.append("S2: only %d public methods found in CNNFXOrders (parser or class changed?): %s" % (len(methods), names))
    for name, body, _ in methods:
        if name in ("CNNFXOrders", "~CNNFXOrders"):
            continue
        first = body.strip().splitlines()[0] if body.strip() else ""
        if not GUARD.match(first):
            found.append("S2: public method %s does not start with NNFXOrdersAllowed: %r" % (name, first.strip()))
    # S2b: test-only methods only inside #ifdef NNFX_TEST_BUILD
    ranges = ifdef_ranges(code, "NNFX_TEST_BUILD")
    for name in TEST_ONLY:
        defs = [m for m in re.finditer(r"\b%s\s*\([^;{]*\)\s*\{" % name, code)]
        if not defs:
            found.append("S2b: %s not found in Orders.mqh" % name)
        for d in defs:
            if not any(a <= d.start() <= b for a, b in ranges):
                found.append("S2b: %s defined outside #ifdef NNFX_TEST_BUILD" % name)
    refuse = re.compile(r"if\s*\(\s*MQLInfoInteger\s*\(\s*MQL_TESTER\s*\)\s*==\s*0\s*\)\s*(\{[^}]*)?return\b")
    for name, body, _ in methods:
        if name in TEST_ONLY and name != "TestLoseNextReply" and not refuse.search(body):
            found.append("S2b: %s does not refuse outside the Strategy Tester" % name)
    # S2b: NNFX_TEST_BUILD defined only by the test EA
    for path in mql_files():
        code_f = strip_code(read(path))
        if re.search(r"^[ \t]*#\s*define\s+NNFX_TEST_BUILD\b", code_f, re.M):
            if os.path.normcase(path) != os.path.normcase(TEST_EA):
                found.append("S2b: NNFX_TEST_BUILD defined in %s (only NNFX_OrderTest.mq5 may)" % os.path.relpath(path, ROOT))
    return found, names


class TestOrderCalls(unittest.TestCase):
    def test_no_violations(self):
        found, names = violations()
        self.assertEqual(found, [], "\n".join(found))
        for required in ("OpenTrade", "MoveStop", "CloseRemaining", "EnforceStops", "Poll", "NNFXTestOpenWithoutStop"):
            self.assertIn(required, names)

    def test_strip_code_ignores_comments_and_strings(self):
        code = 'int a; // OrderSend here\n/* OrderSend\n there */ string s = "OrderSend";\n'
        self.assertIsNone(TRADING.search(strip_code(code)))
        self.assertEqual(strip_code(code).count("\n"), 3)


if __name__ == "__main__":
    unittest.main()
