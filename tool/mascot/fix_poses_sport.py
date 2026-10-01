#!/usr/bin/env python3
"""Upscale the sport sheet's two see-through faces again: racket strings, bike spokes.

    python tool/mascot/fix_poses_sport.py     # rewrites sport_tennis and sport_cycling (masters and app copies)
    python tool/mascot/fix_poses_sport.py --masters <folder> --app <folder>   # anywhere else, to compare

Needs torch, numpy, scipy and Pillow. Runs AFTER `upscale_poses.py --sheet
sport` (step 4 of 4 for this sheet), and upscales the two poses again from
their cut files, so it is safe to rerun; rerunning upscale_poses.py on the
sheet (or --only on either pose) undoes it, so run this after it every time.

WHY
The racket's face and the bike's two wheels are drawn see-through: 1 to 2 px
strings and spokes at alpha up to 0.90 and 0.96 (90th percentile 0.58 and
0.40) over nothing. The anime model draws thin semi-transparent lines as
strokes of its own. On the sheet the strings are a regular grid and each
wheel has about 12 straight, even spokes; out of the model the strings came
back wavy, smeared and broken, some spokes went missing and one front spoke
became a wide see-through fan (reviewer, 2026-09-30, and seen side by side
against a plain Lanczos enlargement). Measured by averaging each 4x master's
alpha back down to the sheet's size inside these faces, the model lost a
quarter of the lines: mean alpha 0.141 where the sheet has 0.187 (racket)
and 0.086 where it has 0.112 (wheels), mean error 0.052 and 0.033,
correlation with the sheet 0.952 and 0.955. This step gives 0.188 and 0.107,
error 0.018 and 0.017, correlation 0.993 and 0.986.

WHAT IS REPLACED
Inside the holes in the pose's solid paint (alpha 250 and over, holes
filled) of 30 px or more, the model's colour and alpha give way to Lanczos.
On the cut files these are exactly the three faces: the racket's 2859 px
(1614 see-through) at x 21 to 76, y 110 to 176, and the front and back
wheels' 1405 px (606) and 819 px (498) at x 178 to 230 and 56 to 96, y 214
to 265 and 219 to 263. The ring 1 px wide along each hole's edge stays the
model's: it holds the frame's and the tyres' inner ink, which the model
draws crisp and Lanczos draws soft (tried first: the whole inner rim went
blurry). That leaves 2682 and 1866 px. The seam is a gaussian of 1 px at
4x, which reaches 4 px: beyond that every pixel of the master is
upscale_poses.master()'s, byte for byte (checked against a plain run).
Only these two poses: the sheet's other holes (inside the jump rope's loop,
under the barbell, beside the treadmill's post, between two of the boxing
burst's tips) are empty space inside solid outlines, which the model draws
well (checked against the cut files side by side).

THE LANCZOS
Plain 4x Lanczos on premultiplied colour (upscale_poses.resize_premult)
turns each 1 px line into a soft 4 to 6 px band, beaded at every stair step
of the native line. Its alpha is smoothed by a gaussian of 1 px at 4x, which
takes the beads out, then sharpened (unsharp mask: 4 times the difference
from a gaussian of 2 px), which brings the line's edge back; colour and
alpha are then clamped to the native 3x3 min and max around each pixel, as
upscale_poses.py clamps the model, so nothing overshoots. Compared by eye on
cream and on #0F1A12 against amounts 1.5, 2.0 and 2.5 without the smoothing:
the weaker ones stay soft, 2.5 without it keeps the beads. The alpha then
takes upscale_poses.master()'s stretch (0.02 to 0.98 onto 0 to 1), and the
app copy is upscale_poses.app_copy() at the pose's size class, so its size
and 12 px margin are unchanged (912x838 and 895x1017).
"""
import argparse
import json
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

import esrgan
import upscale_poses as up

KEY = "sport"
POSES = ("sport_tennis", "sport_cycling")
SOLID = 250 / 255        # native alpha that counts as solid paint
HOLE_MIN = 30            # px: a smaller hole is a gap in the drawing, not a see-through face
RIM = 1                  # native px along each hole's rim left to the model
FEATHER = 1.0            # 4x px: gaussian sigma of the seam between the two
PRE, BLUR, AMOUNT = 1.0, 2.0, 4.0   # 4x px, 4x px, times: smooth, then unsharp mask


def see_through(a):
    """The holes in the native pose's solid paint that hold drawn see-through
    detail, less the RIM px along their edge. Returns the mask and each
    hole's size and semi-transparent count, before the rim comes off."""
    solid = a >= SOLID
    holes = ndi.binary_fill_holes(solid) & ~solid
    lab, k = ndi.label(holes)
    keep = np.zeros_like(holes)
    found = []
    for i, sl in enumerate(ndi.find_objects(lab), 1):
        m = lab[sl] == i
        if m.sum() < HOLE_MIN:
            continue
        keep[sl] |= m
        semi = int((m & (a[sl] > 0) & (a[sl] < SOLID)).sum())
        found.append((int(m.sum()), semi, sl[1].start, sl[0].start, sl[1].stop, sl[0].stop))
    return ndi.binary_erosion(keep, iterations=RIM), found


def lanczos4(n):
    """4x Lanczos on premultiplied colour, its alpha smoothed then sharpened,
    both clamped to the native 3x3 min and max as the model's output is."""
    h, w = n.shape[:2]
    rgb, a = up.resize_premult(n, 4 * w, 4 * h)
    lo, hi = up.bounds_up(n)
    a0 = ndi.gaussian_filter(a, PRE)
    a = a0 + AMOUNT * (a0 - ndi.gaussian_filter(a0, BLUR))
    return np.clip(rgb, lo[..., :3], hi[..., :3]), np.clip(a, lo[..., 3], hi[..., 3])


def master(net, dev, n):
    """upscale_poses.master(), with Lanczos in place of the model inside the
    see-through holes."""
    m = up.master(net, dev, n)
    hole, found = see_through(n[..., 3])
    w = np.clip(ndi.gaussian_filter(np.kron(hole, np.ones((4, 4))), FEATHER), 0, 1)
    rgb, a = lanczos4(n)
    a = np.clip((a - 0.02) / (0.98 - 0.02), 0, 1)        # upscale_poses.master()'s stretch
    rgb = m[..., :3] * (1 - w[..., None]) + rgb * w[..., None]
    a = m[..., 3] * (1 - w) + a * w
    return np.dstack([up.clean_edges(rgb, a, reach=6), a]), found, int(hole.sum())


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--masters", type=pathlib.Path, default=None)
    ap.add_argument("--app", type=pathlib.Path, default=None)
    ap.add_argument("--weights", type=pathlib.Path, default=None, help="a local copy of the model file")
    args = ap.parse_args()
    cfg = up.SHEETS[KEY]
    masters = args.masters or cfg["masters"]
    app = args.app or cfg["app"]
    masters.mkdir(parents=True, exist_ok=True)
    app.mkdir(parents=True, exist_ok=True)
    poses = {p["name"]: p for p in json.loads((up.HERE / cfg["poses"]).read_text())}
    net, dev = esrgan.load(args.weights)
    for name in POSES:
        n = np.asarray(Image.open(cfg["src"] / f"{name}.png").convert("RGBA")).astype(np.float64) / 255
        m4, found, kept = master(net, dev, n)
        up.to_png(m4, masters / f"{name}.png")
        a = up.app_copy(m4, poses[name]["row"], cfg["row_norm"])
        up.to_webp(a, app / f"{name}.webp")
        holes = ", ".join(f"{s} px ({semi} see-through) at x {x0}-{x1} y {y0}-{y1}"
                          for s, semi, x0, y0, x1, y1 in found)
        print(f"{name:28s} holes: {holes}; {kept} px after the rim; "
              f"4x {m4.shape[1]}x{m4.shape[0]}  app {a.shape[1]}x{a.shape[0]}")
