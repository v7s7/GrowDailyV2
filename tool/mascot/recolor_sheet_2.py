#!/usr/bin/env python3
"""Match the second mascot sheet's paint to the chosen palette.

    python tool/mascot/recolor_sheet_2.py      # writes design/mascot/sheet-2/mascot-sheet-2-final.png

Needs numpy, scipy and Pillow. Step 1 for sheet 2; then run
`cut_poses.py --sheet 2` and `upscale_poses.py --sheet 2`.

The source is design/mascot/sheet-2/mascot-sheet-2-original.png, the ChatGPT
sheet Aziz generated on 2026-09-29: 24 poses in four rows, drawn from the
first package and already in its colours. Measured on each sheet's interior
(more than 4 px from any outline), against the first sheet as shipped:

    body green    L 0.800 C 0.136 h 144.5   first sheet L 0.758 C 0.139 h 145
    leaves, belly L 0.962 C 0.018 h 87.5    first sheet L 0.955 C 0.020 h 90.5

The body came out lighter, which shows when poses from the two sheets sit
side by side, so the body is moved onto the palette (recolor_sheet.py's
BODY, #74C878). The white parts differ by less than the eye can see and are
left alone, and so are the cheeks and the outline.

HOW THE BODY MOVES
Every pixel of green paint moves by the difference between the palette and
the measured median, in OKLab: lightness by -0.040 and chroma by x1.03. The
offsets from the median are kept exactly, so the drawing and its plush
shading stay as drawn and only the paint changes. A pixel counts as green
paint by hue (full weight within 22 degrees of the body's, none past 45) and
chroma (none under 0.03, full from 0.06). Toward the outline the move fades
out between L 0.55 and 0.25, so the anti-aliased ramp into the dark outline
stays clean.

GREEN EFFECTS
The first sheet's "?" and "zZ" are a deeper green (recolor_sheet.py's
DECO_L), so they stay legible on light cards. This sheet draws its green
effects ("?", music notes, "zZ", the calm pose's small leaves) in body green,
about L 0.73, and they take the same deeper green, keeping their own
shading. The music notes are then dropped by cut_poses.py (Aziz,
2026-09-29). An effect is art that does not touch a character (cut_poses.py's
rule). The one green confetti piece is confetti, not an effect glyph, and
keeps its colour: the confetti box below belongs to this sheet.
"""
import argparse
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

from oklab import from_lch, lch, oklab_to_srgb, srgb_to_oklab

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "design/mascot/sheet-2/mascot-sheet-2-original.png"
OUT = ROOT / "design/mascot/sheet-2/mascot-sheet-2-final.png"

# ---- the palette (recolor_sheet.py's BODY and DECO_L)
BODY_L, BODY_C, BODY_H = 0.76, 0.14, 145
DECO_L, DECO_C_MAX = 0.55, 0.14

# ---- measured on this sheet
SRC_L, SRC_C = 0.800, 0.136               # body median, interior
A_FLOOR, CHARACTER_PX = 16, 10000         # cut_poses.py: art, and a character's size
CONFETTI_BOX = (760, 20, 1010, 250)       # x0, y0, x1, y1 around the confetti pose


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def recolor(rgba):
    rgb, A = rgba[..., :3], rgba[..., 3]
    lab = srgb_to_oklab(rgb)
    L, C, H = lch(lab)
    dh = np.abs((H - BODY_H + 180) % 360 - 180)
    paint = np.clip((45 - dh) / (45 - 22), 0, 1) * smooth(0.03, 0.06, C)

    art = A > A_FLOOR
    parts, n = ndi.label(art, structure=np.ones((3, 3)))
    sizes = ndi.sum(art, parts, range(1, n + 1))
    effect = art & ~np.isin(parts, [i + 1 for i in range(n) if sizes[i] > CHARACTER_PX])
    x0, y0, x1, y1 = CONFETTI_BOX
    confetti = np.zeros_like(effect)
    confetti[y0:y1, x0:x1] = True
    deco = effect & ~confetti & (paint > 0)

    body_w = paint * smooth(0.25, 0.55, L) * (A > 0) * ~effect
    L2 = L + body_w * (BODY_L - SRC_L)
    C2 = C * (1 + body_w * (BODY_C / SRC_C - 1))

    # effects: move the effect's own median onto DECO_L, keep its shading
    dparts, dn = ndi.label(deco, structure=np.ones((3, 3)))
    for i in range(1, dn + 1):
        m = dparts == i
        solid = m & (A >= 200)
        base = np.median(L[solid]) if solid.any() else np.median(L[m])
        L2[m] = L[m] + paint[m] * (DECO_L - base)
        C2[m] = np.minimum(C[m], DECO_C_MAX)

    out = oklab_to_srgb(from_lch(L2, C2, H))
    changed = (body_w > 0) | deco
    rgb2 = np.where(changed[..., None], out, rgb)
    return np.dstack([np.clip(np.round(rgb2), 0, 255), A]).astype(np.uint8), deco


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src", type=pathlib.Path, default=SRC)
    ap.add_argument("--out", type=pathlib.Path, default=OUT)
    args = ap.parse_args()
    im = np.asarray(Image.open(args.src).convert('RGBA')).astype(np.float64)
    out, deco = recolor(im)
    Image.fromarray(out).save(args.out, optimize=True)
    print(f"wrote {args.out.relative_to(ROOT)}; {int(deco.sum())} effect pixels deepened")
