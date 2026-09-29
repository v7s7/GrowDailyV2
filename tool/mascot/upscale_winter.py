#!/usr/bin/env python3
"""Crop, colour-match and upscale Doum's winter pictures.

    python tool/mascot/upscale_winter.py [source folder]

Aziz, 2026-09-29: "I loved this, save it in a winter folder, we will use it
later, cropped and upscaled". The source is three 512x512 Canva exports on a
transparent ground (~/Downloads/new 3 imgs/ by default). Writes to
design/mascot/winter/ (not bundled):

  originals/  the files as received
  cropped/    each cut to the picture plus a 12 px margin, stray specks
              removed (a dot off the cloak, a dot beside the blanket)
  4x/         the cropped picture with its body colour matched, at four
              times the size, through the same Real-ESRGAN model and
              clean-up as the app's poses (see upscale_poses.py: the clamp
              against the anime model's light ring, a solid body, edges
              without a fringe)

And the app copies, lossless WebP like the other poses, to
assets/images/mascot/winter/ (not in pubspec.yaml until a screen draws one).

Aziz, the same day, after seeing how they differ from the sheets (thinner
greyer outline, softer shading, peach cheeks, leaves hidden in two): "use
it, but change the sizes, and upscale to make it high quality matching the
other poses". So the drawing stays as drawn and only two things change.

COLOUR
The body green came out lighter and a little yellower than the palette
(interior medians L 0.80 to 0.81, hue 140 to 142, against #74C878's 0.76 and
145). Each picture's green moves by the difference from its own median, in
OKLab, keeping the offsets, as recolor_sheet_2.py does for the second sheet.
The hue window is narrow (full within 12 degrees of the median, none past
25) because the fire, the embers and the heater's bars sit at hue 95 to 120
and must not turn green; paint lighter than L 0.94 (the firelight) is left
alone too. Cheeks, outline, clothes and props are untouched.

ONE CHARACTER SIZE
Each app copy is scaled so Doum's face matches the app's other poses at
their shared scale. The eyes are shut or behind sunglasses, so the
measures are the closed-eye spacing and the cheek spacing against the
app's eyes-shut poses (mug, calm, headphones, laugh, confetti: about 170
and 253 app px), and for the ghutra picture, whose cup hides one cheek, the
sunglasses' width against mascot_sunglasses (365 app px). The pictures
draw Doum at different sizes: the ghutra face is about a quarter bigger
than the other two. The leaves (only the blanket picture shows them) are
drawn bigger than the sheets', so they were not used. Settled by eye
beside the mug, calm and sunglasses poses: the cloak and blanket faces
match calm's eye spacing, and the ghutra's lenses come out the same width
as mascot_sunglasses' (about 145 app px each).
"""
import pathlib
import shutil
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import esrgan  # noqa: E402
from oklab import from_lch, lch, oklab_to_srgb, srgb_to_oklab  # noqa: E402
from upscale_poses import S, app_copy, master, to_webp  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "design/mascot/winter"
APP = ROOT / "assets/images/mascot/winter"
MARGIN = 12

# ---- the palette (recolor_sheet.py's BODY, #74C878)
BODY_L, BODY_C, BODY_H = 0.76, 0.14, 145

# file -> (name, specks to remove as (x, y) points on the original,
#          app px per original px)
PICTURES = {
    "1.png": ("winter_ghutra_cup", [], 2.05),
    "2.png": ("winter_cloak_campfire", [(51, 329)], 2.40),
    "3.png": ("winter_blanket_heater", [(71, 226)], 2.55),
}


def clean(rgba, specks):
    """Clears each speck: the connected piece of the picture at that point."""
    a = rgba[..., 3] > 0.02
    labels, _ = ndi.label(a)
    for x, y in specks:
        found = labels[y, x]
        if found == 0:
            # The point may sit a pixel off the piece: take the nearest one.
            window = labels[max(y - 4, 0):y + 5, max(x - 4, 0):x + 5]
            found = window.max()
        if found:
            rgba[labels == found] = 0
    return rgba


def crop(rgba):
    ys, xs = np.nonzero(rgba[..., 3] > 0.02)
    y0, y1 = max(ys.min() - MARGIN, 0), min(ys.max() + 1 + MARGIN, rgba.shape[0])
    x0, x1 = max(xs.min() - MARGIN, 0), min(xs.max() + 1 + MARGIN, rgba.shape[1])
    return rgba[y0:y1, x0:x1]


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def match_colour(rgba):
    """Moves the body's green onto the palette, keeping its shading."""
    rgb, a = rgba[..., :3] * 255, rgba[..., 3]
    L, C, H = lch(srgb_to_oklab(rgb))
    off = lambda h0: np.abs((H - h0 + 180) % 360 - 180)
    solid = a >= 0.8
    dark = solid & (L < 0.40)
    interior = solid & (ndi.distance_transform_edt(~dark) > 4)
    body = interior & (off(BODY_H) < 22) & (C > 0.06) & (L < 0.90)
    Lm, Cm, Hm = np.median(L[body]), np.median(C[body]), np.median(H[body])
    w = (np.clip((25 - off(Hm)) / (25 - 12), 0, 1) * smooth(0.03, 0.06, C)
         * smooth(0.25, 0.55, L) * (1 - smooth(0.90, 0.94, L)) * (a > 0))
    L2 = L + w * (BODY_L - Lm)
    C2 = C * (1 + w * (BODY_C / Cm - 1))
    H2 = H + w * (BODY_H - Hm)
    out = oklab_to_srgb(from_lch(L2, C2, H2))
    rgb2 = np.where((w > 0)[..., None], out, rgb)
    print(f"  body L {Lm:.3f} C {Cm:.3f} h {Hm:.1f} -> {BODY_L} {BODY_C} {BODY_H}")
    return np.dstack([np.clip(rgb2, 0, 255) / 255, a])


def main():
    src = pathlib.Path(sys.argv[1] if len(sys.argv) > 1
                       else pathlib.Path.home() / "Downloads/new 3 imgs")
    for d in ("originals", "cropped", "4x"):
        (OUT / d).mkdir(parents=True, exist_ok=True)
    APP.mkdir(parents=True, exist_ok=True)
    weights = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else None
    net, dev = esrgan.load(weights)
    for file, (name, specks, scale) in PICTURES.items():
        shutil.copyfile(src / file, OUT / "originals" / f"{name}.png")
        rgba = np.asarray(Image.open(src / file).convert("RGBA")).astype(np.float64) / 255
        rgba = crop(clean(rgba.copy(), specks))
        Image.fromarray(np.round(rgba * 255).astype(np.uint8), "RGBA").save(
            OUT / "cropped" / f"{name}.png", optimize=True)
        print(name)
        m4 = master(net, dev, match_colour(rgba))
        Image.fromarray(np.round(np.clip(m4, 0, 1) * 255).astype(np.uint8), "RGBA").save(
            OUT / "4x" / f"{name}.png", optimize=True)
        app = app_copy(m4, 1, {1: scale / S})
        to_webp(app, APP / f"{name}.webp")
        print(f"  {rgba.shape[1]}x{rgba.shape[0]} -> 4x {m4.shape[1]}x{m4.shape[0]}"
              f" -> app {app.shape[1]}x{app.shape[0]} (x{scale})")


if __name__ == "__main__":
    main()
