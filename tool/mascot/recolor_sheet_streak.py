#!/usr/bin/env python3
"""Match the streak sheet's paint to the chosen palette, and part two poses.

    python tool/mascot/recolor_sheet_streak.py   # writes design/mascot/sheet-streak/sheet-streak-final.png

Needs numpy, scipy and Pillow. Step 1 for the streak sheet; then run
`cut_poses.py --sheet streak`, `fix_poses_streak.py` (the poses without the
cream ground ellipse) and `upscale_poses.py --sheet streak`.

The source is design/mascot/sheet-streak/sheet-streak-original.png, the
ChatGPT sheet Aziz generated on 2026-09-29 (byte-identical to the download
"ChatGPT Image 29 سبتمبر 2026، 09_51_26 م.png"): 15 poses in three rows of
five about a streak whose flame is dying, on a transparent ground. Measured
on its interior (more than 4 px from any outline), against the shipped app
copies measured the same way:

    body green    L 0.806 C 0.133 h 143.1   shipped L 0.758 to 0.763 C 0.140 h 145
    leaves, belly L 0.969 C 0.018 h 83.1    shipped L 0.955 to 0.966 C 0.020 h 89 to 91
    cheeks        L 0.807 C 0.106 h 31.6    sheet 1 L 0.739 C 0.116 h 26, sheet 2 L 0.780 C 0.106 h 30
    outline       L 0.155 (core 0.099)      sheet 2 L 0.148 (core 0.093)

Every pose's body measures within 0.007 of that median one by one (L 0.799
to 0.811), the shelter pose's once its prop leaf is left out. After the move,
on the same pixels: L 0.762 C 0.140 h 145.2, every pose L 0.754 to 0.766.

THE BODY MOVES
Every pixel of green paint moves by the difference between the palette and
the measured median, in OKLab: lightness by -0.046, chroma by x1.053 and
hue by +1.9 degrees, keeping its offsets from the median, so the drawing and
its plush shading stay as drawn. A pixel counts as green paint by hue (full
weight within 12 degrees of the body's median, none past 25) and chroma (none
under 0.03, full from 0.06). The window is narrow because of the fire: every
flame's yellow core sits at hue 95 to 108 (99.5th percentile 105 on the
free-standing flames), so sheet 2's wider window (none past 45) would have
darkened them. 98.9% of the body's interior green lies within 12 degrees; the
other 1.1% (median hue 124) is firelight on the body beside each campfire,
which fades out through the 12 to 25 degree band and so stays a little
brighter than the body, as firelight does. Toward the outline the move fades
out between L 0.55 and 0.25, so the anti-aliased ramp into the dark outline
stays clean. Effects (art that does not touch a character, cut_poses.py's
rule) are never moved: this sheet has no green glyph, only 50 faint grey
anti-aliasing pixels on the motion lines at chroma 0.03 to 0.04.

THE PROP LEAF
The shelter pose holds a big leaf over its head, drawn in green paint a
little yellower and darker than the body: on its interior L 0.727 C 0.153
h 134.7 (the lit half L 0.759 C 0.161, the shaded half and the underside L
0.56 to 0.59), against that pose's body at L 0.799 h 143.2. It lies inside
the hue window and moves with the body, to L 0.681 C 0.161 h 136.7. The
generator drew it relative to the body, and the same offset that made the
body too light made the leaf so: moving both keeps the drawn step (0.07 in
the median, 0.04 on the lit half). Left alone, the lit half (0.759) would sit
at the new body's lightness (0.762) and read as part of him. Sheet 2's deeper
effect green (L 0.55, chroma capped) is for floating glyphs that must stay
legible on light cards, not for a held prop with its own light and shade.

THE CHEEKS MOVE WITH THE BODY
The cheeks are a flat blush drawn at the body's own lightness (0.807 on a
0.806 body). Left alone they would sit 0.047 above the new body, a pale patch
where both shipped sheets draw a blush near the body's lightness (sheet 1
0.02 below it, sheet 2 0.02 above). Each cheek moves by the body's lightness
step, keeping its chroma and hue, and lands at about L 0.761: between the two
shipped sheets, with the drawn cheek-to-body relation kept. A cheek is a
pink blob (hue within 25 degrees of 31, chroma over 0.04, L over 0.55) whose
median chroma is 0.08 to 0.12 and median L at least 0.77: exactly the 30
cheeks, two per pose. The fire, the embers and the red props (watering can,
broken heart, alert dot, calendar) sit at chroma 0.15 to 0.21, and the coals'
glow under L 0.68, so none of them passes. The 1 to 2 px blend between blush
and green is neither pink nor green paint, so the move covers each cheek
grown by 2 px, over pixels between L 0.55 and 0.90 under chroma 0.13, with
the same outline fade; without that the blend stays at 0.81 and rings the
cheek in light.

LEFT ALONE
The leaves, stem and belly (0.005 in OKLab from sheet 2's shipped whites,
far below what the eye sees, as sheet 2 left its own), the outline, the
fire, embers, smoke, sweat drops, props and every effect.

TWO POSES TOUCH (a drawing fix)
The poking pose's ground shadow runs into the lying pose's left arm: at sheet
x 602 to 604, y 364 to 373, its faint end (alpha 17 to 48) touches the arm's
outline, so the two poses form one piece at cut_poses.py's alpha floor of 16
and the cut finds 14 characters instead of 15 (they part at a floor of 48).
In a small box around the join, every pixel of alpha 17 to 48 that touches
the arm (its alpha over 48) is set to the floor: the arm's faintest
anti-aliasing ring over 19 px, at most 14% opaque once cut. The script checks
that the two poses are apart afterwards.
"""
import argparse
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

from oklab import from_lch, lch, oklab_to_srgb, srgb_to_oklab

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "design/mascot/sheet-streak/sheet-streak-original.png"
OUT = ROOT / "design/mascot/sheet-streak/sheet-streak-final.png"

# ---- the palette (recolor_sheet.py's BODY)
BODY_L, BODY_C, BODY_H = 0.76, 0.14, 145

# ---- measured on this sheet
SRC_L, SRC_C, SRC_H = 0.806, 0.133, 143.1   # body median, interior
HUE_FULL, HUE_NONE = 12, 25                 # degrees from SRC_H: full weight, none
CHEEK_H, CHEEK_C, CHEEK_L = 31, (0.08, 0.12), 0.77   # a cheek blob's hue, median chroma, median L floor
CHEEK_GROW = 2                              # px: the blend between blush and green
A_FLOOR, CHARACTER_PX = 16, 10000           # cut_poses.py: art, and a character's size
EIGHT = np.ones((3, 3))

# ---- the join between the poking pose (2) and the lying pose (3), sheet coordinates
SEAM_BOX = (596, 358, 608, 386)             # x0, y0, x1, y1
SEAM_A = 48                                 # the two poses part at this alpha
POKE_AT, LYING_AT = (480, 200), (720, 330)  # (x, y) inside each pose


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def part_poses(A):
    """The seam: alpha 17..48 pixels touching the lying pose's arm, in SEAM_BOX,
    go to the floor. Returns the new alpha and how many pixels changed."""
    core, _ = ndi.label(A > SEAM_A, structure=EIGHT)
    lying = core == core[LYING_AT[1], LYING_AT[0]]
    x0, y0, x1, y1 = SEAM_BOX
    box = np.zeros(A.shape, bool)
    box[y0:y1, x0:x1] = True
    seam = box & (A > A_FLOOR) & (A <= SEAM_A) & ndi.binary_dilation(lying, structure=EIGHT)
    A = np.where(seam, A_FLOOR, A)
    art, _ = ndi.label(A > A_FLOOR, structure=EIGHT)
    if art[POKE_AT[1], POKE_AT[0]] == art[LYING_AT[1], LYING_AT[0]]:
        raise SystemExit("the poking and lying poses still touch")
    return A, int(seam.sum())


def cheek_zone(L, C, H, A):
    """The 30 cheeks, each grown by CHEEK_GROW px over blush-to-green blend."""
    dh = np.abs((H - CHEEK_H + 180) % 360 - 180)
    pink = (A >= 128) & (dh < 25) & (C > 0.04) & (L > 0.55)
    blobs, n = ndi.label(pink, structure=EIGHT)
    idx = range(1, n + 1)
    med_c = ndi.median(C, blobs, idx)
    med_l = ndi.median(L, blobs, idx)
    sizes = ndi.sum(pink, blobs, idx)
    keep = [i for i, c, l, s in zip(idx, med_c, med_l, sizes)
            if CHEEK_C[0] <= c <= CHEEK_C[1] and l >= CHEEK_L and s >= 15]
    grown = ndi.binary_dilation(np.isin(blobs, keep), structure=EIGHT, iterations=CHEEK_GROW)
    return grown & (A > 0) & (L > 0.55) & (L < 0.90) & (C < 0.13), len(keep)


def recolor(rgba):
    rgb, A = rgba[..., :3], rgba[..., 3]
    A, seam_px = part_poses(A)
    L, C, H = lch(srgb_to_oklab(rgb))
    dh = np.abs((H - SRC_H + 180) % 360 - 180)
    paint = np.clip((HUE_NONE - dh) / (HUE_NONE - HUE_FULL), 0, 1) * smooth(0.03, 0.06, C)

    art = A > A_FLOOR
    parts, n = ndi.label(art, structure=EIGHT)
    sizes = ndi.sum(art, parts, range(1, n + 1))
    effect = art & ~np.isin(parts, [i + 1 for i in range(n) if sizes[i] > CHARACTER_PX])
    toe = smooth(0.25, 0.55, L) * (A > 0) * ~effect

    body_w = paint * toe
    cheeks, n_cheeks = cheek_zone(L, C, H, A)
    lift_w = np.maximum(body_w, cheeks * toe)          # the lightness step: body and cheeks
    L2 = L + lift_w * (BODY_L - SRC_L)
    C2 = C * (1 + body_w * (BODY_C / SRC_C - 1))       # chroma and hue: green paint only
    H2 = H + body_w * (BODY_H - SRC_H)

    out = oklab_to_srgb(from_lch(L2, C2, H2))
    changed = lift_w > 0
    rgb2 = np.where(changed[..., None], out, rgb)
    return np.dstack([np.clip(np.round(rgb2), 0, 255), A]).astype(np.uint8), seam_px, n_cheeks


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src", type=pathlib.Path, default=SRC)
    ap.add_argument("--out", type=pathlib.Path, default=OUT)
    args = ap.parse_args()
    im = np.asarray(Image.open(args.src).convert('RGBA')).astype(np.float64)
    out, seam_px, n_cheeks = recolor(im)
    Image.fromarray(out).save(args.out, optimize=True)
    print(f"wrote {args.out}; {n_cheeks} cheeks, {seam_px} seam pixels between the poking and lying poses")
