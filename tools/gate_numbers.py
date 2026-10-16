"""The numbers behind the Phase 8 plan's sample sizes and its drawdown gate, from this system's own trades
(G2_phase8_1 F1, F2): the plan used R s.d. 1.5-2R, the measured value is about 0.6R.

  R           per trade as tools/summarize_trades.py (each half's (exit - entry) x dir / (1.5 x entry ATR), x 1/2)
  s.d., SE    sample standard deviation of R; standard error of the mean at n trades = s.d. / sqrt(n)
  n needed    trades to detect a difference `delta` in mean R at two-sided alpha and the given power:
                one system against zero      n = ((z_a + z_b) x s.d. / delta)^2
                two systems (equal n each)   n = 2 x ((z_a + z_b) x s.d. / delta)^2 per system
  P(DD)       the chance that the equity drawdown (peak to trough, 2% risk per trade compounded: equity x (1 + 0.02 R))
              exceeds 10% within a horizon, by reshuffling the trades' R with replacement (bootstrap), each R shifted
              so the mean is `edge`. Horizon: a fixed number of trades, or `months` of trading at the run's own trade
              rate (trades / months of the window)

Usage:  python tools/gate_numbers.py TRADES.csv [...] --months-window 62 [--edge 0.10] [--paths 4000] [--seed 1]
Prints one block per trade log. Deterministic for a given --seed.
"""
import argparse
import math
import os
import random
import statistics
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import summarize_trades as st  # noqa: E402

Z = {0.05: 1.959964, 0.05 / 3: 2.393980, 0.10: 1.644854}
ZB = {0.8: 0.841621, 0.9: 1.281552}


def n_needed(sd, delta, alpha=0.05, power=0.9, two_systems=False):
    k = ((Z[alpha] + ZB[power]) * sd / delta) ** 2
    return math.ceil(2 * k if two_systems else k)


def p_drawdown(rs, n, edge, paths, rng, risk=0.02, limit=0.10):
    shift = edge - sum(rs) / len(rs)
    hit = 0
    for _ in range(paths):
        eq = peak = 1.0
        for _ in range(n):
            eq *= 1.0 + risk * (rng.choice(rs) + shift)
            if eq > peak:
                peak = eq
            elif (peak - eq) / peak > limit:
                hit += 1
                break
    return hit / paths


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("trades", nargs="+")
    ap.add_argument("--months-window", type=float, required=True)
    ap.add_argument("--edge", type=float, default=0.10)
    ap.add_argument("--paths", type=int, default=4000)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--horizons", default="100,200,400")
    a = ap.parse_args(argv)
    for path in a.trades:
        rng = random.Random(a.seed)
        trades, _, _ = st.read_trades(path)
        rs = [t["r"] for t in trades]
        sd = statistics.stdev(rs)
        per_year = len(rs) / a.months_window * 12
        print("%s: %d trades, mean %+.3fR, s.d. %.3fR, %.0f trades per 12 months" % (os.path.basename(path), len(rs),
              sum(rs) / len(rs), sd, per_year))
        print("  SE of the mean: n=30 %.3fR, n=100 %.3fR, n=200 %.3fR" % tuple(sd / math.sqrt(n) for n in (30, 100, 200)))
        print("  trades needed, 90%% power, two-sided 5%%: edge 0.10R vs 0: %d; 0.10R between two systems: %d each; "
              "the same at 5%%/3 (three timeframes, Bonferroni): %d each"
              % (n_needed(sd, 0.10), n_needed(sd, 0.10, two_systems=True),
                 n_needed(sd, 0.10, alpha=0.05 / 3, two_systems=True)))
        hs = [int(x) for x in a.horizons.split(",")]
        ps = [p_drawdown(rs, n, a.edge, a.paths, rng) for n in hs]
        n12 = int(round(per_year))
        p12 = p_drawdown(rs, n12, a.edge, a.paths, rng)
        p0 = p_drawdown(rs, 100, 0.0, a.paths, rng)
        print("  P(drawdown > 10%%), edge %+.2fR, %d paths: %s; 12 months (%d trades): %.2f; no edge, 100 trades: %.2f"
              % (a.edge, a.paths, ", ".join("n=%d %.2f" % (n, p) for n, p in zip(hs, ps)), n12, p12, p0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
