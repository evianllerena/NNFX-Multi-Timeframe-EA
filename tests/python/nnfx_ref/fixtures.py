"""Load and run the JSON rule fixtures in tests/fixtures.

Fixture format (shared with the MQL5 test scripts in Phase 4):
{
  "name": "E1_fires_long",
  "rule": "E1",
  "description": "...",
  "settings": {"one_candle": false},          # overrides of Settings defaults
  "bars": [{"t":0,"o":..,"h":..,"l":..,"c":..,"atr":..,"base":..,
            "c1":..,"c2":..,"ex":..,"vol":true,"block":[],"news":false}, ...],
  "check": ["ENTER","EXIT","SKIP","PENDING","OPEN","CLOSE", ...],   # event types compared
  "expect": [[bar_index, "EVENT", "RULE", dir], ...]
}
The comparison is exact: the engine's events of the checked types must equal
`expect`, in order, with nothing missing and nothing extra.
"""
import json
import os
from typing import Dict, List, Tuple

from .core import PairCore
from .settings import Settings

FIXTURE_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "fixtures"))

DEFAULT_CHECK = ["ENTER", "EXIT", "SKIP", "PENDING"]


def load_all(directory: str = FIXTURE_DIR) -> List[Dict]:
    out = []
    for name in sorted(os.listdir(directory)):
        if name.endswith(".json"):
            with open(os.path.join(directory, name), encoding="utf-8") as f:
                fx = json.load(f)
            fx["_file"] = name
            out.append(fx)
    return out


def run(fx: Dict) -> Tuple[List[list], List[Dict], PairCore]:
    core = PairCore("TEST", Settings.from_dict(fx.get("settings", {})))
    for bar in fx["bars"]:
        core.on_bar(bar)
    check = set(fx.get("check", DEFAULT_CHECK))
    got = [[e["i"], e["event"], e["rule"], e["dir"]] for e in core.events if e["event"] in check]
    return got, core.events, core


def describe(events: List[Dict]) -> str:
    return "\n".join("  bar %(i)s  %(event)-8s %(rule)-4s dir=%(dir)+d  price=%(price)s  %(note)s" % e
                     for e in events)
