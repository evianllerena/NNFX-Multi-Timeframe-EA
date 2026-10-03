"""Proves the MQL5 text fixtures carry exactly the same data as the JSON fixtures,
so the Python answer key and the MQL5 rules core are tested on identical cases."""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nnfx_ref import fixtures  # noqa: E402

MQL5_DIR = os.path.join(fixtures.FIXTURE_DIR, "mql5")


def parse_text(path):
    out = {"settings": {}, "bars": [], "expect": [], "expect_r": []}
    with open(path, encoding="ascii") as f:
        lines = [ln.rstrip("\n") for ln in f]
    assert lines[-1] == "END", path
    for ln in lines[:-1]:
        p = ln.split("|")
        tag = p[0]
        if tag == "NAME":
            out["name"] = p[1]
        elif tag == "RULE":
            out["rule"] = p[1]
        elif tag == "SET":
            out["settings"][p[1]] = p[2]
        elif tag == "CHECK":
            out["check"] = p[1].split(",")
        elif tag == "BAR":
            out["bars"].append({
                "t": int(p[1]), "o": float(p[2]), "h": float(p[3]), "l": float(p[4]), "c": float(p[5]),
                "atr": float(p[6]), "base": float(p[7]), "c1": int(p[8]), "c2": int(p[9]),
                "ex": int(p[10]), "vol": p[11] == "1", "block": [x for x in p[12].split(";") if x],
                "news": p[13] == "1"})
        elif tag == "EXP":
            out["expect"].append([int(p[1]), p[2], p[3], int(p[4])])
        elif tag == "EXPR":
            out["expect_r"].append(float(p[1]))
        else:
            raise AssertionError("unknown line %r in %s" % (ln, path))
    return out


def setting_text(v):
    if v is None:
        return "none"
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, (int, float)):
        return repr(float(v))
    return str(v)


class TestFixtureFormats(unittest.TestCase):
    def test_text_matches_json(self):
        all_fx = fixtures.load_all()
        txt = sorted(n for n in os.listdir(MQL5_DIR) if n.endswith(".txt"))
        self.assertEqual(len(txt), len(all_fx), "JSON and MQL5 text fixture counts differ")
        for fx in all_fx:
            with self.subTest(fixture=fx["name"]):
                t = parse_text(os.path.join(MQL5_DIR, fx["name"] + ".txt"))
                self.assertEqual(t["name"], fx["name"])
                self.assertEqual(t["rule"], fx["rule"])
                self.assertEqual(t["check"], fx["check"])
                self.assertEqual(t["expect"], fx["expect"])
                self.assertEqual(t["expect_r"], fx.get("expect_r", []))
                self.assertEqual(t["settings"], {k: setting_text(v) for k, v in fx["settings"].items()})
                self.assertEqual(len(t["bars"]), len(fx["bars"]))
                for a, b in zip(t["bars"], fx["bars"]):
                    self.assertEqual(a, {k: b[k] for k in a}, "bar %s differs" % b["t"])


if __name__ == "__main__":
    unittest.main()
