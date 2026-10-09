"""Writes the three NNFX_EA presets MQL5/Presets/NNFX_M30.set, NNFX_H1.set, NNFX_H4.set (Phase 6f; SPEC Settings,
OD-16; MQL5/Presets/README.md).

All three carry the EA's own defaults (read from MQL5/Experts/NNFX/NNFX_EA.mq5) and differ only in the magic number
(30M 26030, 1H 26060, 4H 26240). Every input is listed (an input left out of a set file keeps its last-used value).
The format is the one MT5 writes itself (MQL5/Profiles/Tester/NNFX_EA.set, saved by MT5 on 2026-10-06 20:49:30):
UTF-16LE with a byte-order mark, CRLF, ";" comment lines, strings as "name=value", numbers and booleans as
"name=value||start||step||stop||N" (start = the default, step = default/10 for a double and 1 for an int, stop =
default x 10; booleans "||false||0||true||N"). The plan says to save them from MT5's settings dialog; an agent cannot
click it, so they are written here and proved by loading each one in the Strategy Tester (ExpertParameters=)
[C, recorded in DESIGN_6F]. The owner may re-save them from the dialog at any time.

Usage:  python tools/make_presets.py [--check]     (--check: exit 1 if a preset on disk differs)
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
EA = os.path.join(ROOT, "MQL5", "Experts", "NNFX", "NNFX_EA.mq5")
OUT = os.path.join(ROOT, "MQL5", "Presets")
MAGIC = {"M30": 26030, "H1": 26060, "H4": 26240}   # OD-16
INPUT = re.compile(r'^input\s+(\w+)\s+(Inp\w+)\s*=\s*(.+?);', re.M)


def ea_inputs():
    """[(type, name, default text)] in source order; string defaults unquoted with MQL escapes undone."""
    with open(EA, encoding="utf-8") as f:
        src = f.read()
    out = []
    for typ, name, val in INPUT.findall(src):
        val = val.strip()
        if typ == "string":
            val = val[1:-1].replace("\\\\", "\\")
        out.append((typ, name, val))
    return out


def fmt_num(x):
    return ("%.6f" % x)


def line(typ, name, val):
    if typ == "string":
        return "%s=%s" % (name, val)
    if typ == "bool":
        return "%s=%s||false||0||true||N" % (name, val)
    if typ in ("int", "long"):
        d = int(val)
        return "%s=%d||%d||1||%d||N" % (name, d, d, d * 10)
    if typ == "double":
        d = float(val)
        v = val if "." in val else val + ".0"    # MT5 writes a double's default as "24.0", not "24"
        return "%s=%s||%s||%s||%s||N" % (name, v, v, fmt_num(d / 10), fmt_num(d * 10))
    raise ValueError("unsupported input type %s for %s" % (typ, name))


def preset_text(tf):
    rows = ["; NNFX_EA preset %s (magic %d, OD-16); written by tools/make_presets.py from NNFX_EA.mq5's defaults" % (tf, MAGIC[tf]),
            "; in the format MT5 writes (MQL5/Profiles/Tester/NNFX_EA.set); every input listed",
            ";"]
    for typ, name, val in ea_inputs():
        if name == "InpMagic":
            val = str(MAGIC[tf])
        rows.append(line(typ, name, val))
    return "\r\n".join(rows) + "\r\n"


def write_all(check=False):
    bad = []
    for tf in MAGIC:
        path = os.path.join(OUT, "NNFX_%s.set" % tf)
        data = b"\xff\xfe" + preset_text(tf).encode("utf-16-le")
        if check:
            if not os.path.exists(path) or open(path, "rb").read() != data:
                bad.append(path)
        else:
            with open(path, "wb") as f:
                f.write(data)
            print("wrote %s" % path)
    for p in bad:
        print("DIFFERS: %s (run tools/make_presets.py)" % p)
    return not bad


if __name__ == "__main__":
    sys.exit(0 if write_all("--check" in sys.argv[1:]) else 1)
