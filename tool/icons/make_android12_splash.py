#!/usr/bin/env python3
"""Regenerate the Android 12+ splash icon from the full splash artwork.

Run after any change to assets/images/splash_background.png, then re-run
`dart run flutter_native_splash:create`:

    python3 tool/icons/make_android12_splash.py

Needs Pillow (`pip3 install Pillow`). Writes
tool/icons/splash_android12_icon.png, which pubspec.yaml's
flutter_native_splash `android_12.image` points at.

Why this exists: Android 12 replaced the full-screen splash image with a
fixed 288dp ICON slot. Pointing that at the 853x1844 portrait background
makes Android squash a 1:2.16 image into a square, and the mark's four
rounded tiles render as stretched bars. This lifts the mark out of that
artwork and squares it about its own centre, so nothing is scaled
non-uniformly. The cream ground comes from `android_12.color`, so the
output is transparent.
"""
import pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/images/splash_background.png"
DST = ROOT / "tool/icons/splash_android12_icon.png"

# The plate is a pale, near-neutral cream carrying a soft vignette; the mark
# is both markedly darker and far more saturated. Gate on BOTH, or the
# vignette (dark but neutral) expands the bounding box to the whole canvas.
SAT_MIN, VAL_MAX = 40, 245
PAD = 18           # keep the mark's soft drop shadow
CANVAS = 1152      # 288dp at xxxhdpi; smaller densities downsample from this
# How much of the slot the mark occupies. 0.47, not something larger:
# without an icon background Android shows only the central 192dp of the
# 288dp slot, i.e. a circle 2/3 of the canvas wide, and it really does clip
# to that circle (observed on an Android 16 emulator at 0.62, where the
# corners of the outer tiles were visibly sliced off). A SQUARE mark only
# fits inside that circle when side/2 * sqrt(2) <= 1/3 of the canvas, so
# side <= 0.471. This looks modest next to the pre-12 splash, which is
# correct: Android 12+ splash icons are meant to be small.
FILL = 0.47


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    w, h = src.size
    px = src.load()

    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            if max(r, g, b) - min(r, g, b) > SAT_MIN and max(r, g, b) < VAL_MAX:
                minx, miny = min(minx, x), min(miny, y)
                maxx, maxy = max(maxx, x), max(maxy, y)
    if maxx < 0:
        raise SystemExit("no mark found in splash artwork; check SAT_MIN/VAL_MAX")

    minx, miny = max(0, minx - PAD), max(0, miny - PAD)
    maxx, maxy = min(w - 1, maxx + PAD), min(h - 1, maxy + PAD)
    mark = src.crop((minx, miny, maxx + 1, maxy + 1))

    side = max(mark.size)
    squared = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    squared.paste(mark, ((side - mark.width) // 2, (side - mark.height) // 2))

    target = int(CANVAS * FILL)
    squared = squared.resize((target, target), Image.LANCZOS)
    out = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    out.paste(squared, ((CANVAS - target) // 2, (CANVAS - target) // 2), squared)
    out.save(DST)
    print(f"wrote {DST.relative_to(ROOT)} ({CANVAS}x{CANVAS}, mark {squared.size})")


if __name__ == "__main__":
    main()
