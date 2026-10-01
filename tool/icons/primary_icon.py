"""Which icon of tool/icons/app_icon_art.json is the shipped one, and its colours.

Imported by the icon scripts beside it; not run on its own.

The shipped icon (iOS's AppIcon, Android's launcher icon, the Play listing,
the in-app logo) is one of the shape x colour icons, rendered from the same
art as the other 99 by make_alternate_icons.py, which writes it to
assets/images/icon_app.png. Every other script reads that PNG, and the two
that have to tell the plant from its ground on it (center_icon_mark.py,
make_adaptive_foreground.py) take the two colours from here, so changing
the shipped icon is this one line plus a rerun.

Doum's since 2026-09-30 (Aziz: "the green and white, is the main logo"):
the cream sprout on the mascot's green. The gold sprout on emerald it
replaced is still an alternate icon, «الأصلية» in the picker.
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
ART = ROOT / "tool/icons/app_icon_art.json"

SHAPE = "sprout"
COLOUR = "doum"


def rgb(hexc):
    h = hexc.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def colours():
    """(ground, plant) of the shipped icon, as RGB tuples."""
    art = json.loads(ART.read_text())
    c = next(c for c in art["colours"] if c["id"] == COLOUR)
    return rgb(c["ground"]), rgb(c["sprout"])
