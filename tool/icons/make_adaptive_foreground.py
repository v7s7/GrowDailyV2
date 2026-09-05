#!/usr/bin/env python3
"""Regenerate the Android adaptive-icon foreground from the app icon.

Run after any change to assets/images/icon_app.png, then re-run
`dart run flutter_launcher_icons`:

    python3 tool/icons/make_adaptive_foreground.py

Needs Pillow (`pip3 install Pillow`). Writes
tool/icons/icon_adaptive_foreground.png, which pubspec.yaml's
flutter_launcher_icons block points at as adaptive_icon_foreground.

Why this exists: an Android adaptive icon is two layers, and the launcher
masks them to whatever shape it likes (circle, squircle, teardrop). Handing
it the flat app icon means the green plate gets masked twice and the mark
sits too close to the edge. This lifts just the gold seedling onto
transparency and insets it into the guaranteed-visible safe zone, letting
the launcher paint the green itself via adaptive_icon_background.

Centring is on the POT, not on the mark's bounding box. The two leaves are
deliberately asymmetric and the taller right-hand one drags the bbox centre
26.5px right of the pot, so bbox-centring used to land the pot 24.8px (2.4% of
the icon) left of centre - three times the drift the source icon itself had. The
eye reads the solid base as the centre of a mark like this, so that is what gets
aligned. See tool/icons/center_icon_mark.py, which applies the same rule to the
source art.
"""
import pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/images/icon_app.png"
DST = ROOT / "tool/icons/icon_adaptive_foreground.png"

# The source art is exactly two flat colours: a green plate and a gold mark.
# Their red channels (14 vs 226) are far enough apart that red alone is a
# clean discriminator, and the values in between are precisely the
# anti-aliased edge pixels worth keeping as partial alpha.
BG_R, FG_R = 14.0, 226.0
GOLD = (226, 163, 54)
# The plate is not perfectly flat (red wanders 14-16). Without a floor that
# leaves an invisible alpha=1 haze over the whole plate, which still counts
# toward getbbox() and silently defeats the crop below.
FLOOR = 0.06
# Adaptive icons are 108dp with only the central 72dp (66.7%) guaranteed
# visible under every launcher mask. 62% keeps margin beyond that.
CANVAS, SAFE = 1024, 0.62
# Rows sampled to find the pot's vertical sides, as fractions of the MARK's own
# height (not the canvas): below the leaves and the point where the stem meets
# the pot, above the pot's rounded bottom corners.
POT_TOP, POT_BOT = 0.65, 0.90


def pot_centre(mark):
    """Sub-pixel horizontal centre of the pot, from the mark's alpha channel.

    The pot's sides are the only long vertical edges in the artwork, so the
    average of the outermost alpha=0.5 crossings over rows inside the pot body
    is a far steadier reference than any bounding box.
    """
    w, h = mark.size
    px = mark.load()
    lefts, rights = [], []
    for y in range(int(h * POT_TOP), int(h * POT_BOT)):
        row = [px[x, y][3] / 255.0 for x in range(w)]
        left = right = None
        for x in range(1, w):
            if row[x - 1] < 0.5 <= row[x]:
                left = x - 1 + (0.5 - row[x - 1]) / (row[x] - row[x - 1])
                break
        for x in range(w - 1, 0, -1):
            if row[x] < 0.5 <= row[x - 1]:
                right = x - 1 + (row[x - 1] - 0.5) / (row[x - 1] - row[x])
                break
        if left is not None and right is not None:
            lefts.append(left)
            rights.append(right)
    if not lefts:
        raise SystemExit("could not find the pot; check POT_TOP/POT_BOT")
    return (sum(lefts) + sum(rights)) / (2 * len(lefts))


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    w, h = src.size
    px = src.load()
    span = FG_R - BG_R

    mark = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mp = mark.load()
    for y in range(h):
        for x in range(w):
            r, _, _, a = px[x, y]
            t = (r - BG_R) / span
            if t < FLOOR:
                continue
            mp[x, y] = (*GOLD, int(min(t, 1.0) * (a / 255.0) * 255))

    mark = mark.crop(mark.getbbox())
    pot_cx = pot_centre(mark)

    # Centring on the pot means the mark has to fit within twice its longest
    # reach from the pot, not merely within its own width, or the far leaf runs
    # out of the safe zone.
    reach = 2 * max(pot_cx, mark.width - 1 - pot_cx)
    scale = min(CANVAS * SAFE / reach, CANVAS * SAFE / mark.height)
    size = (max(1, round(mark.width * scale)), max(1, round(mark.height * scale)))
    mark = mark.resize(size, Image.LANCZOS)
    pot_cx *= scale

    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    # Horizontally the pot centre lands on the canvas centre; vertically the
    # mark is centred as a whole, which is what reads correctly in a launcher.
    left = round((CANVAS - 1) / 2 - pot_cx)
    out.paste(mark, (left, (CANVAS - mark.height) // 2), mark)
    out.save(DST)

    check = pot_centre(out)
    print(f"wrote {DST.relative_to(ROOT)} ({CANVAS}x{CANVAS}, mark {mark.size})")
    print(f"  pot centre {check:.2f} vs canvas centre {(CANVAS - 1) / 2:.2f} "
          f"-> off {check - (CANVAS - 1) / 2:+.2f} px "
          f"({(check - (CANVAS - 1) / 2) / CANVAS * 100:+.3f}%)")


if __name__ == "__main__":
    main()
