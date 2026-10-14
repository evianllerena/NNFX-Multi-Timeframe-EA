"""Tests for tools/summarize_trades.py (SPEC Check 4: V8, V10, V11, V13).

Hand-worked trades (ATR 0.002, 1R = 1.5 x 0.002 = 0.003):
  T0001 long  TP1 at +0.002 (half 1: +0.667R x 1/2), half 2 stopped at breakeven (0)      -> +0.3333R
  T0002 short both halves stopped at the 0.003 stop                                        -> -1R
  T0003 long  TP1 +0.002, half 2 closed at +0.004 (+1.333R x 1/2)                          -> +1R
A tester report with the same deals (deposit 10 000, risk 100 per R) must agree with its own figures (V13)."""
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
sys.path.insert(0, HERE)

import summarize_trades  # noqa: E402
from test_check_trades import COLS, row, opened  # noqa: E402
import csv  # noqa: E402


def log_rows(planned=200.0):
    rs = []
    rs += opened("2026.06.02 10:00:00", "T0001", 1, 1.10000, 1.0, 1.09700, 1.10200, ticket=11)
    rs.append(row("2026.06.02 13:00:00", "TP1", "T0001", 1, 1, ticket=11, price=1.10200))
    rs.append(row("2026.06.02 19:00:00", "SL", "T0001", 2, 1, ticket=12, price=1.10000))
    rs += opened("2026.07.03 10:00:00", "T0002", -1, 1.10000, 1.0, 1.10300, 1.09800, ticket=21)
    rs.append(row("2026.07.03 12:00:00", "SL", "T0002", 1, -1, ticket=21, price=1.10300))
    rs.append(row("2026.07.03 12:00:00", "SL", "T0002", 2, -1, ticket=22, price=1.10300))
    rs += opened("2026.08.04 10:00:00", "T0003", 1, 1.10000, 1.0, 1.09700, 1.10200, ticket=31)
    rs.append(row("2026.08.04 11:00:00", "TP1", "T0003", 1, 1, ticket=31, price=1.10200))
    rs.append(row("2026.08.04 14:00:00", "CLOSE", "T0003", 2, 1, ticket=32, price=1.10400))
    for r in rs:
        if r["event"] == "OPEN":
            r["planned_risk"] = repr(planned)
            r["target_risk"] = "200.0"
    return rs


REPORT = """<html><table>
<tr><td nowrap colspan="3">Initial Deposit:</td><td nowrap><b>10 000.00</b></td></tr>
<tr><td nowrap colspan="3">Total Net Profit:</td><td nowrap><b>%(net)s</b></td></tr>
<tr><td nowrap colspan="3">Balance Drawdown Maximal:</td><td nowrap><b>%(dd)s</b></td></tr>
<tr><td nowrap colspan="3">Equity Drawdown Maximal:</td><td nowrap><b>210.00 (2.08%%)</b></td></tr>
<tr><td nowrap colspan="3">Profit Factor:</td><td nowrap><b>1.67</b></td></tr>
<tr><td nowrap colspan="3">Total Trades:</td><td nowrap><b>%(n)s</b></td></tr>
<tr><th><b>Deals</b></th></tr>
<tr><td>Time</td></tr>
%(deals)s
</table></html>"""


def deal(t, n, typ, d, profit, bal, comment=""):
    cells = [t, str(n), "EURUSD" if typ != "balance" else "", typ, d, "1", "1.1", str(n), "0.00", "0.00",
             "%.2f" % profit, "{:,.2f}".format(bal).replace(",", " "), comment]
    return "<tr>" + "".join("<td>%s</td>" % c for c in cells) + "</tr>"


def report(net="133.33", dd="200.00 (1.97%)", n="6"):
    b = 10000.0
    ds = [deal("2026.06.01 00:00:00", 1, "balance", "", 10000.0, b)]
    k = 2
    for t, p in (("2026.06.02 13:00:00", 66.67), ("2026.06.02 19:00:00", 0.0), ("2026.07.03 12:00:00", -100.0),
                 ("2026.07.03 12:00:00", -100.0), ("2026.08.04 11:00:00", 66.67), ("2026.08.04 14:00:00", 199.99)):
        b += p
        ds.append(deal(t, k, "sell", "out", p, b))
        k += 1
    return REPORT % {"net": net, "dd": dd, "n": n, "deals": "\n".join(ds)}


def run(rows, rep=None):
    with tempfile.TemporaryDirectory() as tmp:
        tp = os.path.join(tmp, "trades.csv")
        with open(tp, "w", encoding="ascii", newline="") as f:
            w = csv.DictWriter(f, fieldnames=COLS, lineterminator="\r\n")
            w.writeheader()
            w.writerows(rows)
        args = [tp, "--json", os.path.join(tmp, "out.json")]
        if rep is not None:
            rp = os.path.join(tmp, "report.htm")
            with open(rp, "w", encoding="utf-16") as f:
                f.write(rep)
            args += ["--report", rp]
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = summarize_trades.main(args)
        import json
        with open(os.path.join(tmp, "out.json"), encoding="utf-8") as f:
            return code, buf.getvalue(), json.load(f)


class TestSummarizeTrades(unittest.TestCase):
    def test_r_per_trade(self):
        code, out, js = run(log_rows())
        o = js["overall"]
        self.assertEqual(o["trades"], 3)
        self.assertAlmostEqual(o["total_r"], 1 / 3 - 1 + 1, places=6)
        self.assertAlmostEqual(o["win_rate"], 2 / 3, places=9)
        self.assertAlmostEqual(o["max_dd_r"], 1.0, places=6)
        self.assertEqual(o["longest_losing_streak"], 1)
        self.assertEqual(code, 0, out)

    def test_v10_one_pair_flagged(self):
        code, out, js = run(log_rows())
        self.assertTrue(any("V10: pair EURUSD" in f for f in js["flags"]), out)

    def test_v8_too_few_trades_flagged(self):
        code, out, js = run(log_rows())
        self.assertTrue(any(f.startswith("V8:") for f in js["flags"]), out)

    def test_v11_over_target_fails(self):
        code, out, js = run(log_rows(planned=230.0))
        self.assertEqual(code, 1, out)
        self.assertIn("V11", out)

    def test_report_agrees(self):
        code, out, js = run(log_rows(), report())
        self.assertEqual(code, 0, out)
        self.assertAlmostEqual(js["money"]["net_profit"], 133.33, places=2)
        self.assertAlmostEqual(js["money"]["balance_dd_max"], 200.0, places=2)
        self.assertTrue(any(f.startswith("V4:") for f in js["flags"]), out)

    def test_report_net_mismatch_fails(self):
        code, out, js = run(log_rows(), report(net="140.00"))
        self.assertEqual(code, 1, out)
        self.assertIn("V13: net profit", out)

    def test_report_dd_mismatch_fails(self):
        code, out, js = run(log_rows(), report(dd="150.00 (1.48%)"))
        self.assertEqual(code, 1, out)
        self.assertIn("V13: balance drawdown", out)

    def test_report_trade_count_mismatch_fails(self):
        code, out, js = run(log_rows(), report(n="5"))
        self.assertEqual(code, 1, out)
        self.assertIn("Total Trades", out)


if __name__ == "__main__":
    unittest.main()
