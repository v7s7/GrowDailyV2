#!/usr/bin/env python3
"""Regenerate every iOS app-icon PNG from the app icon.

Run after any change to assets/images/icon_app.png:

    python3 tool/icons/make_ios_appicons.py

Needs Pillow (`pip3 install Pillow`). Rewrites the PNGs in
ios/Runner/Assets.xcassets/AppIcon.appiconset/, sized from that catalogue's own
Contents.json so the two can never drift apart.

Why this exists rather than `dart run flutter_launcher_icons` with ios: true:
that generator (0.14.4) corrupts ios/Runner.xcodeproj/project.pbxproj on every
iOS run, rewriting ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS,
ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME and
ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME to the literal "AppIcon" in
both build configurations, which breaks the accent colour and the widget
extension's background. pubspec.yaml keeps ios: false for exactly that reason
and says the iOS icons are committed instead - this is how they get rebuilt.

Output is RGB with no alpha channel: the App Store rejects a 1024 icon that
carries transparency, and the smaller sizes have no reason to differ.
"""
import json
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/images/icon_app.png"
DST = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"


def main() -> None:
    contents = json.loads((DST / "Contents.json").read_text())

    # Several entries share a filename across idioms at the same pixel size
    # (a 40x40@2x iPhone icon and an 80x80 iPad icon are the same 80px file),
    # so collapse to filename -> pixels and check the duplicates agree.
    wanted = {}
    for entry in contents.get("images", []):
        name, size, scale = (entry.get("filename"), entry.get("size"),
                             entry.get("scale", "1x"))
        if not name or not size:
            continue
        px = round(float(size.split("x")[0]) * int(scale.rstrip("x")))
        if wanted.setdefault(name, px) != px:
            raise SystemExit(f"{name} is declared at two different pixel sizes")

    src = Image.open(SRC).convert("RGB")
    if src.width != src.height:
        raise SystemExit(f"source icon is {src.size}, expected a square")

    for name, px in sorted(wanted.items(), key=lambda kv: kv[1]):
        # LANCZOS: the mark is a hard-edged two-colour shape, and a lesser
        # filter visibly stair-steps the leaf diagonals at the small sizes.
        src.resize((px, px), Image.LANCZOS).save(DST / name)
        print(f"  {name:32s} {px:4d}x{px}")

    stale = {p.name for p in DST.glob("*.png")} - set(wanted)
    if stale:
        print("\n  NOT declared in Contents.json, left untouched: "
              + ", ".join(sorted(stale)))
    print(f"\nwrote {len(wanted)} icons to {DST.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
