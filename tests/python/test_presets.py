"""The three NNFX_EA presets (Phase 6f; SPEC Settings, OD-16): every input listed, the EA's defaults, own magic,
MT5's set-file format (tools/make_presets.py), and the files on disk are the ones the script writes."""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

import make_presets as mp  # noqa: E402


def read_set(path):
    with open(path, "rb") as f:
        raw = f.read()
    assert raw[:2] == b"\xff\xfe", "no UTF-16LE byte-order mark"
    text = raw[2:].decode("utf-16-le")
    vals = {}
    for ln in text.split("\r\n"):
        if not ln or ln.startswith(";"):
            continue
        name, rest = ln.split("=", 1)
        vals[name] = rest.split("||")[0]
    return text, vals


class TestPresets(unittest.TestCase):
    def test_files_match_the_script(self):
        with open(os.devnull, "w") as dn:
            old, sys.stdout = sys.stdout, dn
            try:
                ok = mp.write_all(check=True)
            finally:
                sys.stdout = old
        self.assertTrue(ok, "a preset differs from tools/make_presets.py's output: run it")

    def test_every_input_defaults_and_own_magic(self):
        inputs = mp.ea_inputs()
        names = [n for _, n, _ in inputs]
        self.assertIn("InpTesterMaster", names)
        for tf, magic in (("M30", 26030), ("H1", 26060), ("H4", 26240)):
            with self.subTest(tf=tf):
                text, vals = read_set(os.path.join(mp.OUT, "NNFX_%s.set" % tf))
                self.assertEqual(list(vals), names, "every input, in source order")
                self.assertEqual(vals["InpMagic"], str(magic))
                for typ, n, d in inputs:
                    if n == "InpMagic":
                        continue
                    if typ == "double":
                        self.assertEqual(float(vals[n]), float(d), n)
                    else:
                        self.assertEqual(vals[n], d, n)
                # live safety: the master switch is read from MT5 (missing = OFF, D6d-1); tester-only inputs off
                self.assertEqual(vals["InpTesterMaster"], "-1")
                self.assertEqual(vals["InpTesterMasterOff"], "none")
                self.assertEqual(vals["InpRestartAt"], "none")
                self.assertTrue(text.endswith("\r\n"))

    def test_presets_differ_only_in_magic(self):
        sets = [read_set(os.path.join(mp.OUT, "NNFX_%s.set" % tf))[1] for tf in ("M30", "H1", "H4")]
        for s in sets:
            s.pop("InpMagic")
        self.assertEqual(sets[0], sets[1])
        self.assertEqual(sets[1], sets[2])


if __name__ == "__main__":
    unittest.main()
