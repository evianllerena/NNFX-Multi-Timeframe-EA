"""Backtest results from the raw logs (SPEC Check 4: V8 sample, V10 per pair / per year, V11 sizes, V13 recompute).

Reads an NNFX trade log (MQL5/Include/NNFX/TradeLog.mqh) and, optionally, the Strategy Tester's HTML report.

  R            per trade, from the trade log's prices only: each half's (exit - entry) x dir / (1.5 x entry ATR), x 1/2
               (1R = the initial stop distance of the whole trade; the same definition as nnfx_ref/core.py r_result).
               A trade counts when both halves are closed; still open at the end = listed, not counted
  money        from the report's Deals table: profit + commission + swap per deal, the balance after each deal
  V13          the report's own figures (Total Net Profit, Balance Drawdown Maximal, Total Trades) are compared with
               the ones recomputed from its deals; a difference is a FAIL
  V8           trades in total (SPEC: at least 100) - reported
  V10          R per pair and per year; FLAG when one pair or one year carries more than half of the positive R
  V11          planned risk per trade over target (from the OPEN rows) - FAIL if any trade planned above 2% + 1%
  costs        commission and swap totals (V4: must not be all zero on a broker that charges them) - reported

Usage:  python tools/summarize_trades.py TRADES.csv [--report REPORT.htm] [--label TEXT] [--json OUT.json]
Exit code 0 = no FAIL (a FLAG is information for the reviewer).
"""
import argparse
import csv
import html
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime

SL_ATR = 1.5


def fnum(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return 0.0


def read_trades(path):
    with open(path, encoding="ascii", newline="") as f:
        rows = list(csv.DictReader(f))
    by = defaultdict(list)
    for r in rows:
        if r["trade_id"]:
            by[r["trade_id"]].append(r)
    trades, still_open, aborted = [], [], []
    for tid, evs in by.items():
        opens = {int(r["half"]): r for r in evs if r["event"] == "OPEN"}
        if not opens:
            continue
        o1 = opens.get(1)
        if o1 is None:
            continue
        d, atr = int(o1["dir"]), fnum(o1["atr_entry"])
        closes = {}
        for r in evs:
            if r["event"] in ("SL", "TP1", "TP2", "CLOSE") and int(r["half"] or 0) in (1, 2):
                closes[int(r["half"])] = r
        aborted_trade = any(r["event"] == "ABORT" for r in evs)
        halves = (1,) if aborted_trade else (1, 2)
        if any(h not in closes for h in halves) or atr <= 0:
            still_open.append(tid)
            continue
        r_total = 0.0
        for h in halves:
            entry = fnum(opens[h]["entry"]) or fnum(opens[h]["price"])
            r_total += 0.5 * (fnum(closes[h]["price"]) - entry) * d / (SL_ATR * atr)
        last = max(closes[h]["time"] for h in halves)
        target = fnum(o1["target_risk"])
        planned = fnum(o1["planned_risk"])   # each OPEN row holds the whole trade's planned risk (2 x the half's)
        t = {"id": tid, "symbol": o1["symbol"], "dir": d, "open": o1["time"], "close": last, "r": r_total,
             "aborted": aborted_trade, "planned": planned, "target": target, "balance": fnum(o1["balance"]),
             "risk_pct": fnum(o1["risk_pct"])}
        (aborted if aborted_trade else trades).append(t)
    trades.sort(key=lambda t: (t["close"], t["id"]))
    return trades, still_open, aborted


def read_report(path):
    with open(path, "rb") as f:
        raw = f.read()
    text = raw.decode("utf-16") if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else raw.decode("utf-8", errors="replace")

    def figure(label):
        m = re.search(r"%s</td>\s*<td[^>]*>(?:<b>)?([^<]*)" % re.escape(label), text)
        return html.unescape(m.group(1)).strip() if m else ""

    def money(s):
        s = s.replace("\xa0", "").replace(" ", "")
        m = re.match(r"-?[\d.]+", s)
        return float(m.group(0)) if m else 0.0

    figs = {k: figure(k) for k in ("Initial Deposit:", "Total Net Profit:", "Balance Drawdown Maximal:",
                                   "Equity Drawdown Maximal:", "Profit Factor:", "Total Trades:",
                                   "History Quality:", "Bars:", "Ticks:")}
    start = text.rfind("<b>Deals</b>")
    deals = []
    if start >= 0:
        for tr in re.finditer(r"<tr[^>]*>(.*?)</tr>", text[start:], re.S):
            tds = [html.unescape(re.sub(r"<[^>]+>", "", c)).strip() for c in re.findall(r"<td[^>]*>(.*?)</td>", tr.group(1), re.S)]
            if len(tds) == 13 and re.match(r"\d{4}\.\d\d\.\d\d", tds[0]):
                deals.append({"time": tds[0], "symbol": tds[2], "type": tds[3], "dir": tds[4],
                              "commission": money(tds[8]), "swap": money(tds[9]), "profit": money(tds[10]),
                              "balance": money(tds[11]), "comment": tds[12]})
    return figs, deals, money


def max_drawdown(curve):
    peak, worst, worst_pct = None, 0.0, 0.0
    for v in curve:
        peak = v if peak is None or v > peak else peak
        dd = peak - v
        if dd > worst:
            worst = dd
        if peak > 0 and dd / peak > worst_pct:
            worst_pct = dd / peak
    return worst, worst_pct


def stats(rs):
    n = len(rs)
    if n == 0:
        return {"trades": 0}
    wins = [r for r in rs if r > 0]
    losses = [r for r in rs if r <= 0]
    cum, curve = 0.0, []
    for r in rs:
        cum += r
        curve.append(cum)
    dd_r, _ = max_drawdown([0.0] + curve)
    streak = best = 0
    for r in rs:
        streak = streak + 1 if r <= 0 else 0
        best = max(best, streak)
    gross_win, gross_loss = sum(wins), -sum(losses)
    return {"trades": n, "win_rate": len(wins) / n, "expectancy_r": sum(rs) / n, "total_r": sum(rs),
            "max_dd_r": dd_r, "longest_losing_streak": best,
            "profit_factor_r": (gross_win / gross_loss) if gross_loss > 0 else None}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("trades")
    ap.add_argument("--report", default=None)
    ap.add_argument("--label", default="")
    ap.add_argument("--json", default=None)
    a = ap.parse_args(argv)

    trades, still_open, aborted = read_trades(a.trades)
    fails, flags, out = [], [], {"label": a.label, "trade_log": os.path.basename(a.trades)}
    rs = [t["r"] for t in trades]
    out["overall"] = stats(rs)
    out["still_open"] = still_open
    out["aborted"] = len(aborted)

    per_pair, per_year, per_month = defaultdict(list), defaultdict(list), defaultdict(float)
    for t in trades:
        per_pair[t["symbol"]].append(t["r"])
        per_year[t["close"][:4]].append(t["r"])
        per_month[t["close"][:7]] += t["r"]
    out["per_pair"] = {k: stats(v) for k, v in sorted(per_pair.items())}
    out["per_year"] = {k: stats(v) for k, v in sorted(per_year.items())}
    months = list(per_month.values())
    out["months_positive"] = (sum(1 for m in months if m > 0) / len(months)) if months else None
    pos_total = sum(r for r in rs if r > 0)
    for name, groups in (("pair", per_pair), ("year", per_year)):
        total = sum(rs)
        for k, v in groups.items():
            if total > 0 and sum(v) > 0.5 * total:
                flags.append("V10: %s %s carries %.1fR of the total %.1fR" % (name, k, sum(v), total))
    # V11: planned risk vs target (OPEN rows); 2% + 1% float/rounding bound is generous on purpose
    over = [t for t in trades + aborted if t["target"] > 0 and t["planned"] > t["target"] * 1.01]
    if over:
        fails.append("V11: %d trade(s) planned above the target risk (first %s: %.2f > %.2f)"
                     % (len(over), over[0]["id"], over[0]["planned"], over[0]["target"]))
    if len(trades) < 100:
        flags.append("V8: %d trades, fewer than the 100 SPEC asks for" % len(trades))

    if a.report:
        figs, deals, money = read_report(a.report)
        out["report_figures"] = figs
        if not deals:
            fails.append("report: no Deals table read from %s" % a.report)
        else:
            dep = money(figs.get("Initial Deposit:", "") or "0") or deals[0]["balance"]
            net = sum(d["profit"] + d["commission"] + d["swap"] for d in deals if d["type"] != "balance")
            comm = sum(d["commission"] for d in deals)
            swap = sum(d["swap"] for d in deals)
            curve = [dep] + [d["balance"] for d in deals if d["type"] != "balance"]
            dd_money, dd_pct = max_drawdown(curve)
            n_out = sum(1 for d in deals if d["dir"] in ("out", "out by"))
            out["money"] = {"deposit": dep, "net_profit": round(net, 2), "return_pct": 100.0 * net / dep if dep else None,
                            "balance_dd_max": round(dd_money, 2), "balance_dd_max_pct": round(100.0 * dd_pct, 2),
                            "commission": round(comm, 2), "swap": round(swap, 2), "deals_out": n_out,
                            "return_over_dd": (net / dd_money) if dd_money > 0 else None}
            # V13: recomputed vs the report's own figures
            rep_net = money(figs.get("Total Net Profit:", ""))
            if abs(rep_net - net) > 0.015:
                fails.append("V13: net profit recomputed %.2f, report says %.2f" % (net, rep_net))
            m = re.match(r"([\d\s.\xa0]+)\s*\(([\d.]+)%\)", figs.get("Balance Drawdown Maximal:", ""))
            if m:
                rep_dd = money(m.group(1))
                if abs(rep_dd - dd_money) > 0.015:
                    fails.append("V13: balance drawdown recomputed %.2f, report says %.2f" % (dd_money, rep_dd))
            rep_trades = int(money(figs.get("Total Trades:", "0")))
            if rep_trades != n_out:
                fails.append("V13: %d closing deals recomputed, report Total Trades %d" % (n_out, rep_trades))
            if comm == 0 and swap == 0:
                flags.append("V4: commission and swap are both 0 over %d deals (the cost model has no costs)" % len(deals))

    out["fails"], out["flags"] = fails, flags
    o = out["overall"]
    print("=" * 70)
    print("%s  %s" % (a.label or "", os.path.basename(a.trades)))
    if o["trades"]:
        print("  trades %d (+%d ABORT, %d still open)  win rate %.1f%%  expectancy %+.3fR  total %+.1fR  max DD %.1fR  "
              "longest losing streak %d  PF(R) %s  months positive %s"
              % (o["trades"], len(aborted), len(still_open), 100 * o["win_rate"], o["expectancy_r"], o["total_r"],
                 o["max_dd_r"], o["longest_losing_streak"],
                 "%.2f" % o["profit_factor_r"] if o["profit_factor_r"] else "-",
                 "%.0f%%" % (100 * out["months_positive"]) if out["months_positive"] is not None else "-"))
    else:
        print("  no closed trades")
    if "money" in out:
        m = out["money"]
        print("  money: deposit %.2f  net %+.2f (%+.1f%%)  balance DD max %.2f (%.2f%%)  return/DD %s  commission %.2f  swap %.2f"
              % (m["deposit"], m["net_profit"], m["return_pct"] or 0, m["balance_dd_max"], m["balance_dd_max_pct"],
                 "%.2f" % m["return_over_dd"] if m["return_over_dd"] is not None else "-", m["commission"], m["swap"]))
        f = out["report_figures"]
        print("  report: net %s | balance DD %s | equity DD %s | PF %s | trades %s | history quality %s"
              % (f["Total Net Profit:"], f["Balance Drawdown Maximal:"], f["Equity Drawdown Maximal:"],
                 f["Profit Factor:"], f["Total Trades:"], f["History Quality:"] or "-"))
    for k, s in out["per_pair"].items():
        print("  pair %-8s trades %4d  win %5.1f%%  exp %+.3fR  total %+7.1fR  maxDD %5.1fR"
              % (k, s["trades"], 100 * s["win_rate"], s["expectancy_r"], s["total_r"], s["max_dd_r"]))
    for k, s in out["per_year"].items():
        print("  year %-8s trades %4d  win %5.1f%%  exp %+.3fR  total %+7.1fR  maxDD %5.1fR"
              % (k, s["trades"], 100 * s["win_rate"], s["expectancy_r"], s["total_r"], s["max_dd_r"]))
    for x in flags:
        print("  FLAG " + x)
    for x in fails:
        print("  FAIL " + x)
    print("RESULT summary %s: %s" % (os.path.basename(a.trades), "OK (%d flags)" % len(flags) if not fails else "FAIL (%d failures)" % len(fails)))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(out, f, indent=1)
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
