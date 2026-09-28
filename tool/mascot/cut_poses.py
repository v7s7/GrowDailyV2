#!/usr/bin/env python3
"""Cut the recoloured mascot sheet into one transparent PNG per pose.

    python tool/mascot/cut_poses.py                # writes design/mascot/poses-native/

Needs numpy, scipy and Pillow. Step 2 of 3: reads the sheet recolor_sheet.py
wrote, and upscale_poses.py reads what this writes. Names, sheet rows and what
each pose shows are in poses.json, in sheet order (row by row, left to right).

WHAT BELONGS TO A POSE
Every piece of art at alpha > 16 is a connected component. The 18 over
10,000 px are the characters (props they hold touch them, so they come
along). Everything else is an effect: sparkles, hearts, "?", motion lines,
"zZ". Effects within 12 px of each other are grouped first and the group goes
to the nearest character. Grouping is not optional: measured one piece at a
time, the big "Z" is nearer the determined pose's feet (50 px) than the
sleeping pose it belongs to (57 px).

ALPHA, BECAUSE THE SHEET'S TRANSPARENCY IS NOT CLEAN
The generator left the body at alpha 250 to 254, never 255, so every pose was
faintly see-through on a dark card; and a faint halo (alpha 1 to 16) reaching
about 7 px past each outline. Alpha is remapped 16..240 -> 0..255, which drops
the halo, makes the body solid and keeps the edge ramp. Semi-transparent edge
pixels then take the colour of the nearest fully opaque pixel (the outline):
in the source they carried the old gold, which shows as a light rim on dark
backgrounds. Fully transparent pixels carry the nearest visible colour so
scaling never bleeds dark into the edge. Isolated 1-12 px dark specks sitting
on the body (two in this sheet) take the colour of the body around them.
What stays translucent on purpose: the gap between the two leaves, the soft
ground shadows, and the effects' own edges.
"""
import argparse
import json
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

from oklab import lch, srgb_to_oklab

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SHEET = ROOT / "design/mascot/mascot-sheet-final.png"
OUT = ROOT / "design/mascot/poses-native"

A_FLOOR, A_FULL, MARGIN, CLUSTER = 16, 240, 8, 12
ROW_SPLITS = (410, 715)          # sheet y between the three rows of this sheet
EIGHT = np.ones((3, 3))


def assign_pixels(A, count):
    """Label map: 1..count for the poses in sheet order, 0 for empty."""
    mask = A > A_FLOOR
    lab, n = ndi.label(mask, structure=EIGHT)
    sizes = ndi.sum(mask, lab, range(1, n + 1))
    objs = ndi.find_objects(lab)
    anchors = [i + 1 for i in range(n) if sizes[i] > 10000]

    def key(c):
        sl = objs[c - 1]
        cy, cx = (sl[0].start + sl[0].stop) / 2, (sl[1].start + sl[1].stop) / 2
        return (sum(cy >= s for s in ROW_SPLITS), cx)

    anchors.sort(key=key)
    if len(anchors) != count:
        raise SystemExit(f"found {len(anchors)} characters, poses.json lists {count}")
    effects = np.isin(lab, [c for c in range(1, n + 1) if c not in anchors])
    groups, en = ndi.label(ndi.binary_dilation(effects, iterations=CLUSTER // 2), structure=EIGHT)
    dist = np.stack([ndi.distance_transform_edt(lab != c) for c in anchors])
    pose_of = np.zeros(A.shape, int)
    for p, c in enumerate(anchors, 1):
        pose_of[lab == c] = p
    for e in range(1, en + 1):
        members = effects & (groups == e)
        pose_of[members] = int(np.argmin(dist[:, members].min(axis=1))) + 1
    return pose_of


def cut(rgb, A, m):
    ys, xs = np.nonzero(m)
    x0, y0, x1, y1 = xs.min() - MARGIN, ys.min() - MARGIN, xs.max() + 1 + MARGIN, ys.max() + 1 + MARGIN
    H, W = A.shape
    cx0, cy0, cx1, cy1 = max(x0, 0), max(y0, 0), min(x1, W), min(y1, H)
    c_rgb = np.zeros((y1 - y0, x1 - x0, 3))
    c_a = np.zeros((y1 - y0, x1 - x0))
    c_m = np.zeros((y1 - y0, x1 - x0), bool)
    sy, sx = slice(cy0 - y0, cy1 - y0), slice(cx0 - x0, cx1 - x0)
    c_rgb[sy, sx] = rgb[cy0:cy1, cx0:cx1]
    c_a[sy, sx] = A[cy0:cy1, cx0:cx1]
    c_m[sy, sx] = m[cy0:cy1, cx0:cx1]
    a2 = np.where(c_m, np.clip((c_a - A_FLOOR) / (A_FULL - A_FLOOR), 0, 1) * 255, 0)
    opaque = a2 >= 255
    d_op, idx = ndi.distance_transform_edt(~opaque, return_indices=True)
    edge = (a2 > 0) & ~opaque & (d_op <= 3)
    c_rgb[edge] = c_rgb[idx[0][edge], idx[1][edge]]
    _, idx2 = ndi.distance_transform_edt(~(a2 > 0), return_indices=True)
    clear = a2 == 0
    c_rgb[clear] = c_rgb[idx2[0][clear], idx2[1][clear]]
    # isolated dark specks on the body
    Lc, Cc, Hc = lch(srgb_to_oklab(c_rgb))
    body = (a2 > 200) & (np.abs(Hc - 145) < 15) & (Cc > 0.08) & (Lc > 0.62)
    darkish = (a2 > 200) & ~body & (Lc < ndi.median_filter(Lc, size=7) - 0.08)
    sl_, sn = ndi.label(darkish, structure=EIGHT)
    for i in range(1, sn + 1):
        comp = sl_ == i
        if comp.sum() > 12:
            continue
        ring = ndi.binary_dilation(comp, iterations=2) & ~comp
        if body[ring].mean() >= 0.9:
            c_rgb[comp] = np.median(c_rgb[ring], 0)
    return np.dstack([np.clip(np.round(c_rgb), 0, 255), np.round(a2)]).astype(np.uint8)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sheet", type=pathlib.Path, default=SHEET)
    ap.add_argument("--out", type=pathlib.Path, default=OUT)
    args = ap.parse_args()
    poses = json.loads((HERE / "poses.json").read_text())
    im = np.asarray(Image.open(args.sheet).convert('RGBA')).astype(np.float64)
    rgb, A = im[..., :3], im[..., 3]
    pose_of = assign_pixels(A, len(poses))
    args.out.mkdir(parents=True, exist_ok=True)
    for p, pose in enumerate(poses, 1):
        out = cut(rgb, A, pose_of == p)
        Image.fromarray(out).save(args.out / f"{pose['name']}.png", optimize=True)
        print(f"{pose['name']:28s} {out.shape[1]}x{out.shape[0]}")
