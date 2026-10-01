#!/usr/bin/env python3
"""Match the sport sheet's paint to the chosen palette and lift its ground shadows.

    python tool/mascot/recolor_sheet_sport.py   # writes design/mascot/sheet-sport/sheet-sport-final.png

Needs numpy, scipy and Pillow. Step 1 for the sport sheet; then run
`cut_poses.py --sheet sport` and `upscale_poses.py --sheet sport`.

The source is design/mascot/sheet-sport/sheet-sport-original.png, the ChatGPT
sheet Aziz generated on 2026-09-30 (1536x1024, transparent ground,
byte-identical to the download): 15 sport poses in three rows of five.
Measured on the interior (alpha >= 240, more than 4 px from any pixel darker
than L 0.40), against the first sheet as shipped:

    body green   L 0.820 C 0.139 h 143.4   first sheet L 0.759 C 0.139 h 145.0
    leaves, belly L 0.977 C 0.018 h 82.8   first sheet L 0.955 C 0.020 h 90.5
    cheeks       L 0.803 C 0.111 h 38.4    first sheet L 0.739 C 0.115 h 26.1

(cheeks: the 29 pink blobs whose 3 px ring is at least 45% body green.) The
body is 0.060 lighter than #74C878, twice the second sheet's gap, and the
leaves and belly 0.022 lighter than #F5F0E1, which shows as a whiter belly
on a cream card. The cheeks are peach (hue 38) where the palette is pink
(25). All three move onto the palette. The outline (L 0.134 C 0.020 h 145,
against the second sheet's 0.152 0.028) is left alone.

HOW THE PAINT MOVES
Each paint moves by the difference between its palette colour and its
measured median, added in OKLab (L, a and b), so the offsets from the median
are kept exactly and the drawing and its plush shading stay as drawn:

  body green  L -0.060, a -0.003, b -0.003 (onto 0.76 0.14 145)
  cream       L -0.022, a -0.002, b +0.002 (onto 0.955 0.02 90)
  blush       L -0.060, a +0.022, b -0.018 (onto 0.743 0.12 25)

A pixel's share of green is its chroma between the cream's 0.018 and 0.11
(the body's 1st percentile is 0.112, so every body pixel is fully green and
a rim pixel half way to the belly moves half as far), times a hue window:
full within 20 degrees of 143.4, none past 35 (the body spans 140 to 150).
Effects, the art that touches no character (cut_poses.py's rule), never
move: that keeps the tennis ball (hue 117 to 127, chroma 0.17, inside the
window) yellow, and the sweat drops, lines and sparkles as drawn. The
orange lines, the basketball, the gold and every red, blue, navy and black
prop sit more than 60 degrees from the body's hue or under chroma 0.03.
Whatever green does not claim, cream may: lightness above 0.88 (none under
0.80), chroma under 0.03 (none past 0.05) and at least 0.008 (none under
0.003), and from chroma 0.012 up a hue within 35 degrees of the cream's 82.8
(none past 60). So pure white eye highlights (chroma 0.001) keep their
white, and the water bottle's pale blue and the burst's pale yellow keep
theirs. The headbands, both towels and the football's white panels are the
same warm white as the belly (C 0.011 to 0.012, h 81 to 85) and take the
same move, so every white on the sheet stays one white (the shaker's pale
rim and highlight too, while its brown drink, chroma 0.041, keeps its
colour). Toward the outline
every move fades out between L 0.55 and 0.25 (as recolor_sheet_2.py), so
the anti-aliased ramp into the dark outline stays clean.

The blush is painted on the body, so it takes the body's lightness move and
lands at L 0.743 (the palette's 0.74); its hue and chroma go to 25 and 0.12.
Each cheek (the blob above, dilated 3 px: its rim is 1 to 2 px of blend,
measured across two cheeks) moves as a mix: a pixel's pink share is its a,b
projected on the line from the body's median to the blush's, and it takes
that share of the blush move and the rest of the green one. Moved by the
green rule alone, the rim (hue 70 to 125) would keep its old lightness and
ring each cheek.

GROUND SHADOWS
ChatGPT drew a flat grey ellipse under every pose, opaque (alpha about 242)
and warm grey (sRGB 206 201 192, L 0.837 C 0.014, spread 0.827 to 0.854 in L
and 0.011 to 0.016 in chroma). No shipped pose has one: on a dark card it
shows as a light grey slab. Only the ground band of each row is searched
(y >= 325, 620 and 935; above them the same grey is art: a towel fold at
y 255, the shaker's lid at y 870). The shadow starts from pieces of 40 px
or more within 0.035 of that colour (OKLab distance, alpha > 16) that touch
the transparent ground: the football's lowest white panel is that grey too
(y 625 to 637) but sits inside the ball's outline, and cutting it bit a
hole in the ball. From there it grows through the neutral greys joined to
it in the band (chroma under 0.03, L 0.55 to 0.92), which takes in its
blended rim and the thin line of it under each mat (2 to 3 px, too mixed to
be within 0.035). The shadow goes fully transparent. The pixels within 3 px
of it are a blend of the shadow and the art beside it (a foot's outline,
the mat's edge, a tyre): each is unmixed against the shadow colour, with
the art's colour taken 1 px inside its solid edge (the edge itself is
blended), its alpha scaled by the share that is not shadow and its colour
set to the art's, so the outline keeps a clean anti-aliased edge and no
grey rim. Ring pixels more than 3 px from any art are the shadow's own soft
edge and go too, and so do crumbs of it left over: pieces under 60 px lying
wholly within 6 px of the shadow (the mat corners, the gym bag's ground
line). Nothing else on the sheet changes its alpha.
"""
import argparse
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

from oklab import from_lch, lch, oklab_to_srgb, srgb_to_oklab

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "design/mascot/sheet-sport/sheet-sport-original.png"
OUT = ROOT / "design/mascot/sheet-sport/sheet-sport-final.png"
EIGHT = np.ones((3, 3))

# ---- the palette (recolor_sheet.py's BODY, the README's cream and cheeks)
BODY = (0.76, 0.14, 145)
CREAM = (0.955, 0.02, 90)
BLUSH_C, BLUSH_H = 0.12, 25

# ---- measured on this sheet (interior medians, see the docstring)
SRC_BODY = (0.820, 0.139, 143.4)
SRC_CREAM = (0.977, 0.018, 82.8)
SRC_BLUSH = (0.803, 0.111, 38.4)
GREEN_C = (0.018, 0.11)                   # chroma: cream's, body's 1st percentile
HUE_FULL, HUE_NONE = 20, 35               # degrees from the body's hue
A_FLOOR, CHARACTER_PX = 16, 10000         # cut_poses.py: art, and a character's size

SHADOW_RGB = (206, 201, 192)              # the ground shadows' median
SHADOW_DE, SHADOW_MIN_PX, SHADOW_RING = 0.035, 40, 3
GROUND = ((0, 325), (375, 620), (684, 935))   # (row starts at y, its ground band starts at y)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def lab_of(lch_):
    return from_lch(np.array(lch_[0]), np.array(lch_[1]), np.array(lch_[2]))


def lift_shadows(rgb, A):
    """The ground shadows go transparent; the pixels blended with them are
    unmixed. Returns the new alpha and colour."""
    lab = srgb_to_oklab(rgb)
    S = srgb_to_oklab(np.array(SHADOW_RGB, float))
    near = (A > A_FLOOR) & (np.linalg.norm(lab - S, axis=-1) < SHADOW_DE)
    band = np.zeros_like(near)
    for (row_y, ground_y), nxt in zip(GROUND, [g[0] for g in GROUND[1:]] + [A.shape[0]]):
        band[ground_y:nxt] = True
    cand = near & band
    parts, n = ndi.label(cand, structure=EIGHT)
    sizes = ndi.sum(cand, parts, range(1, n + 1))
    ground = ndi.binary_dilation(A <= A_FLOOR, iterations=2)
    open_ = ndi.sum(cand & ground, parts, range(1, n + 1))
    seeds = np.isin(parts, [i + 1 for i in range(n) if sizes[i] >= SHADOW_MIN_PX and open_[i] > 0])
    L, C, _ = lch(lab)
    grey = (A > A_FLOOR) & band & (C < 0.03) & (L > 0.55) & (L < 0.92)
    g_parts, _ = ndi.label(grey | seeds, structure=EIGHT)
    core = np.isin(g_parts, np.setdiff1d(np.unique(g_parts[seeds]), [0]))
    ring = (A > A_FLOOR) & ~core & (ndi.distance_transform_edt(~core) <= SHADOW_RING)
    solid = (A >= 240) & ~core & (np.linalg.norm(lab - S, axis=-1) >= 0.08)
    inner = ndi.binary_erosion(solid, structure=EIGHT)      # art, not its blended rim
    d_art, idx = ndi.distance_transform_edt(~inner, return_indices=True)
    F = rgb[idx[0], idx[1]]
    Srgb = np.array(SHADOW_RGB, float)
    d = F - Srgb
    f = np.clip(((rgb - Srgb) * d).sum(-1) / np.maximum((d * d).sum(-1), 1e-6), 0, 1)
    f = np.where(d_art > SHADOW_RING, 0, f)                  # the shadow's own soft edge
    A2, rgb2 = A.copy(), rgb.copy()
    A2[core] = 0
    blend = ring & (f < 1)
    A2[blend] = A[blend] * f[blend]
    rgb2[blend] = F[blend]
    # crumbs: what is left of the shadow's rim, pieces under 60 px lying
    # wholly within 6 px of it (the mat corners, the gym bag's ground line)
    near_shadow = ndi.distance_transform_edt(~core) <= 6
    left = A2 > A_FLOOR
    parts, n = ndi.label(left, structure=EIGHT)
    sizes = ndi.sum(left, parts, range(1, n + 1))
    outside = ndi.sum(left & ~near_shadow, parts, range(1, n + 1))
    crumbs = np.isin(parts, [i + 1 for i in range(n) if sizes[i] < 60 and outside[i] == 0])
    A2[crumbs] = 0
    return A2, rgb2, core | crumbs, blend


def cheeks(L, C, H, A):
    """The pink blobs on the body: hue within 25 of 35, chroma 0.05 to 0.14
    (the mouths' red is 0.15 and over), with at least 45% body green in a
    3 px ring (the gloves, bag and kit are ringed by outline)."""
    off = lambda h0: np.abs((H - h0 + 180) % 360 - 180)
    solid = A >= 200
    green = solid & (off(SRC_BODY[2]) < 25) & (C > 0.08)
    pink = solid & (off(35) < 25) & (C > 0.05) & (C < 0.14) & (L > 0.6) & (L < 0.9)
    parts, n = ndi.label(pink, structure=EIGHT)
    keep = np.zeros_like(pink)
    for i, sl in enumerate(ndi.find_objects(parts), 1):
        comp = np.zeros_like(pink)
        comp[sl] = parts[sl] == i
        if comp.sum() < 40:
            continue
        ring = ndi.binary_dilation(comp, iterations=3) & ~comp
        if green[ring].mean() >= 0.45:
            keep |= comp
    return keep, ndi.label(keep, structure=EIGHT)[1]


def recolor(rgba):
    rgb, A = rgba[..., :3], rgba[..., 3]
    A, rgb, shadow, unmixed = lift_shadows(rgb, A)
    lab = srgb_to_oklab(rgb)
    L, C, H = lch(lab)
    dh = np.abs((H - SRC_BODY[2] + 180) % 360 - 180)

    art = A > A_FLOOR
    parts, n = ndi.label(art, structure=EIGHT)
    sizes = ndi.sum(art, parts, range(1, n + 1))
    effect = art & ~np.isin(parts, [i + 1 for i in range(n) if sizes[i] > CHARACTER_PX])
    live = (A > 0) & ~effect
    fade = smooth(0.25, 0.55, L)

    dG = lab_of(BODY) - lab_of(SRC_BODY)
    dW = lab_of(CREAM) - lab_of(SRC_CREAM)
    blush_to = lab_of((SRC_BLUSH[0] + dG[0], BLUSH_C, BLUSH_H))
    dP = blush_to - lab_of(SRC_BLUSH)

    wG = (np.clip((C - GREEN_C[0]) / (GREEN_C[1] - GREEN_C[0]), 0, 1)
          * np.clip((HUE_NONE - dh) / (HUE_NONE - HUE_FULL), 0, 1))
    dhW = np.abs((H - SRC_CREAM[2] + 180) % 360 - 180)
    warm = np.maximum(1 - smooth(0.012, 0.02, C), np.clip((60 - dhW) / (60 - 35), 0, 1))
    wW = ((1 - wG) * smooth(0.80, 0.88, L) * (1 - smooth(0.03, 0.05, C))
          * smooth(0.003, 0.008, C) * warm)

    blobs, n_cheeks = cheeks(L, C, H, A)
    cheek = ndi.binary_dilation(blobs, iterations=3) & live
    g0, p0 = lab_of(SRC_BODY)[1:], lab_of(SRC_BLUSH)[1:]
    t = np.clip(((lab[..., 1:] - g0) * (p0 - g0)).sum(-1) / ((p0 - g0) ** 2).sum(), 0, 1)
    wG = np.where(cheek, 0, wG)
    wW = np.where(cheek, 0, wW)
    wP = np.where(cheek, t, 0)
    wGc = np.where(cheek, 1 - t, 0)

    move = (((wG + wGc) * fade * live)[..., None] * dG
            + (wW * fade * live)[..., None] * dW
            + (wP * fade * live)[..., None] * dP)
    out = oklab_to_srgb(lab + move)
    changed = np.abs(move).max(-1) > 1e-6
    rgb2 = np.where(changed[..., None], out, rgb)
    stats = dict(shadow=int(shadow.sum()), unmixed=int(unmixed.sum()), cheeks=n_cheeks,
                 green=int((wG * live > 0.5).sum()), cream=int((wW * live > 0.5).sum()))
    return np.dstack([np.clip(np.round(rgb2), 0, 255), np.round(A)]).astype(np.uint8), stats


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src", type=pathlib.Path, default=SRC)
    ap.add_argument("--out", type=pathlib.Path, default=OUT)
    args = ap.parse_args()
    im = np.asarray(Image.open(args.src).convert('RGBA')).astype(np.float64)
    out, stats = recolor(im)
    Image.fromarray(out).save(args.out, optimize=True)
    print(f"wrote {args.out}; {stats['shadow']} shadow px lifted, {stats['unmixed']} unmixed, "
          f"{stats['cheeks']} cheeks, {stats['green']} green and {stats['cream']} cream px moved")
