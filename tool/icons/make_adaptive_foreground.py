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
    scale = min(CANVAS * SAFE / mark.width, CANVAS * SAFE / mark.height)
    mark = mark.resize(
        (max(1, int(mark.width * scale)), max(1, int(mark.height * scale))),
        Image.LANCZOS,
    )

    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    out.paste(mark, ((CANVAS - mark.width) // 2, (CANVAS - mark.height) // 2), mark)
    out.save(DST)
    print(f"wrote {DST.relative_to(ROOT)} ({CANVAS}x{CANVAS}, mark {mark.size})")


if __name__ == "__main__":
    main()
