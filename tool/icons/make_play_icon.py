#!/usr/bin/env python3
"""Regenerate the Google Play store-listing icon from the app icon.

Run after any change to assets/images/icon_app.png:

    python3 tool/icons/make_play_icon.py

Needs Pillow (`pip3 install Pillow`). Writes tool/play-assets/play_icon_512.png,
which is uploaded by hand to the Play Console listing (see ANDROID_RELEASE.md).

Why this exists: nothing else generates it. It was produced once as a 512px
downscale and then sat there while the source art changed, so the listing icon
silently disagreed with the icon actually installed on the device - the drifted
logo in the store, the corrected one on the home screen. A store listing is the
one icon no build step ever touches, which is exactly why it needs a script.

512x512 RGB with no alpha is what the Play Console requires; it applies its own
rounding, so the art must stay full-bleed and square.
"""
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/images/icon_app.png"
DST = ROOT / "tool/play-assets/play_icon_512.png"
SIZE = 512


def main() -> None:
    src = Image.open(SRC).convert("RGB")
    if src.width != src.height:
        raise SystemExit(f"source icon is {src.size}, expected a square")
    src.resize((SIZE, SIZE), Image.LANCZOS).save(DST)
    print(f"wrote {DST.relative_to(ROOT)} ({SIZE}x{SIZE}, RGB)")


if __name__ == "__main__":
    main()
