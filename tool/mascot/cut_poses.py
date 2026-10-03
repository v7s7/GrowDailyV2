#!/usr/bin/env python3
"""Cut the recoloured mascot sheet into one transparent PNG per pose.

    python tool/mascot/cut_poses.py                # writes design/mascot/poses-native/
    python tool/mascot/cut_poses.py --sheet 2      # writes design/mascot/sheet-2/poses-native/
    python tool/mascot/cut_poses.py --sheet sport  # also streak, ghutra: design/mascot/sheet-<name>/

Needs numpy, scipy and Pillow. Step 2 of 3: reads the sheet recolor_sheet.py
wrote, and upscale_poses.py reads what this writes. Names, sheet rows and what
each pose shows are in poses.json, in sheet order (row by row, left to right);
the second sheet's are in poses-2.json.

WHAT BELONGS TO A POSE
Every piece of art at alpha > 16 is a connected component. The 18 over
10,000 px are the characters (props they hold touch them, so they come
along). Everything else is an effect: sparkles, hearts, "?", motion lines,
"zZ". Effects within 12 px of each other are grouped first and the group goes
to the nearest character. Grouping is not optional: measured one piece at a
time, the big "Z" is nearer the determined pose's feet (50 px) than the
sleeping pose it belongs to (57 px). The second sheet has one piece that
grouping cannot place: the cheering pose's upper right-hand line is 15 px from
its own arm and 18 px from the magnifier pose's leaf, and the lines on either
side of it are more than 12 px away. SHEETS gives it to its pose by where it
sits on the sheet, and drops the headphones pose's two music notes the same
way (Aziz, 2026-09-29).

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

# Each sheet's rows and fixes belong to that sheet. `give` hands the piece of
# art whose centre sits at sheet (x, y) to the named pose, or drops it (None).
SHEETS = {
    1: dict(sheet=SHEET, poses="poses.json", out=OUT, row_splits=ROW_SPLITS, give={}),
    2: dict(sheet=ROOT / "design/mascot/sheet-2/mascot-sheet-2-final.png",
            poses="poses-2.json", out=ROOT / "design/mascot/sheet-2/poses-native",
            row_splits=(290, 555, 790),
            give={(224, 96): "mascot_cheer",
                  (1029, 395): None, (1251, 388): None}),   # the headphones' music notes
    # 2026-09-30: three more sheets, named by what they show. Their row
    # splits and fixes are measured on each sheet (see its recolor script).
    # sport: the rows' art spans y 34 to 359, 388 to 659 and 698 to 974 once
    # recolor_sheet_sport.py has lifted the ground shadows; the splits sit in
    # the two gaps. Every prop touches its pose (bag, rope, mat, bike,
    # treadmill) and every effect group lands on its own pose (2 to 23 px from
    # it, 37 px or more from the next), so nothing is given by hand.
    "sport": dict(sheet=ROOT / "design/mascot/sheet-sport/sheet-sport-final.png",
                  poses="poses-sport.json", out=ROOT / "design/mascot/sheet-sport/poses-native",
                  row_splits=(375, 679), give={}),
    # streak: the characters' box centres sit at y 234 to 289, 560 to 572 and
    # 849 to 872; the splits are the midpoints. Every effect lands on its own
    # pose by grouping (each group 2 to 49 px from its pose, 25 to 206 px from
    # the next), so nothing is given by hand. recolor_sheet_streak.py parts
    # poses 2 and 3, whose shadow and arm touch; fix_poses_streak.py then
    # cuts all 15 again without the cream ground ellipse under them.
    "streak": dict(sheet=ROOT / "design/mascot/sheet-streak/sheet-streak-final.png",
                   poses="poses-streak.json", out=ROOT / "design/mascot/sheet-streak/poses-native",
                   row_splits=(424, 711), give={}),
    # ghutra: the characters' box centres sit at y 196 to 210, 506 to 516 and
    # 808 to 841 on the sheet recolor_sheet_ghutra.py makes transparent; the
    # splits are the midpoints. Every effect group lands on its own pose (2 to
    # 42 px from it). Two of the cold-wind pose's leaves do so by a hair: they
    # sit nearly as close to the warming-hands pose's shadow above them (22.2
    # against 23.0 px, 36.2 against 39.8), so they are given by hand and a
    # small change to the matte cannot flip them. fix_poses_ghutra.py then
    # gives the firelight back the colour the cut paints over at the edges.
    "ghutra": dict(sheet=ROOT / "design/mascot/sheet-ghutra/sheet-ghutra-final.png",
                   poses="poses-ghutra.json", out=ROOT / "design/mascot/sheet-ghutra/poses-native",
                   row_splits=(358, 661),
                   give={(449, 679): "winter_bisht_cold_wind", (708, 693): "winter_bisht_cold_wind"}),
    # 2026-10-01: the three October sheets (recolor_sheets_oct.py makes them
    # transparent), 12 poses each in a 4 x 3 grid of 384 x 341 cells; the
    # splits sit in the gaps between the rows. Then run fix_poses_oct.py,
    # which takes the edge line off the peek pose.
    "moments": dict(sheet=ROOT / "design/mascot/sheet-moments/sheet-moments-final.png",
                    poses="poses-moments.json", out=ROOT / "design/mascot/sheet-moments/poses-native",
                    row_splits=(345, 685), give={}),
    "habits": dict(sheet=ROOT / "design/mascot/sheet-habits/sheet-habits-final.png",
                   poses="poses-habits.json", out=ROOT / "design/mascot/sheet-habits/poses-native",
                   row_splits=(345, 685), give={}),
    # ramadan: the night-lantern pose's small crescent (centre 727, 730) sits
    # nearer the dallah pose's leaf than its own pose, so it is given by hand.
    "ramadan": dict(sheet=ROOT / "design/mascot/sheet-ramadan/sheet-ramadan-final.png",
                    poses="poses-ramadan.json", out=ROOT / "design/mascot/sheet-ramadan/poses-native",
                    row_splits=(345, 685), give={(727, 730): "ramadan_night_lantern"}),
    # 2026-10-01: the language switch's two looks (recolor_sheets_oct.py).
    # suit is a 4 x 3 sheet whose Arabic poses Aziz rejected: they are listed
    # in poses-suit.json with "skip" so the sheet still counts 12 characters,
    # and only the English ones are written. thobe is the Arabic look redrawn,
    # 6 poses in a 3 x 2 grid of 512 px cells (box centres at y 260 and 730).
    "suit": dict(sheet=ROOT / "design/mascot/sheet-suit/sheet-suit-final.png",
                 poses="poses-suit.json", out=ROOT / "design/mascot/sheet-suit/poses-native",
                 row_splits=(345, 685), give={}),
    "thobe": dict(sheet=ROOT / "design/mascot/sheet-thobe/sheet-thobe-final.png",
                  poses="poses-thobe.json", out=ROOT / "design/mascot/sheet-thobe/poses-native",
                  row_splits=(512,), give={}),    # 2026-10-03: Doum at work, for the "Doum's Planet" canvas (direction G,
    # the oasis), a 4 x 3 sheet like the October ones.
    "work": dict(sheet=ROOT / "design/mascot/sheet-work/sheet-work-final.png",
                 poses="poses-work.json", out=ROOT / "design/mascot/sheet-work/poses-native",
                 row_splits=(345, 685), give={}),
}


def sheet_key(s):
    """--sheet 1, --sheet 2, or a named sheet such as --sheet sport."""
    return int(s) if s.isdigit() else s


def assign_pixels(A, count, row_splits=ROW_SPLITS, give=None):
    """Label map: 1..count for the poses in sheet order, 0 for empty.
    `give` maps a piece's centre on the sheet to the pose (1..count) it joins,
    or to 0 to drop it."""
    mask = A > A_FLOOR
    lab, n = ndi.label(mask, structure=EIGHT)
    sizes = ndi.sum(mask, lab, range(1, n + 1))
    objs = ndi.find_objects(lab)
    anchors = [i + 1 for i in range(n) if sizes[i] > 10000]

    def key(c):
        sl = objs[c - 1]
        cy, cx = (sl[0].start + sl[0].stop) / 2, (sl[1].start + sl[1].stop) / 2
        return (sum(cy >= s for s in row_splits), cx)

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
    if give:
        centres = ndi.center_of_mass(mask, lab, range(1, n + 1))
        for (x, y), p in give.items():
            near = [c for c in range(1, n + 1) if c not in anchors
                    and np.hypot(centres[c - 1][1] - x, centres[c - 1][0] - y) < 8]
            if len(near) != 1:
                raise SystemExit(f"found {len(near)} pieces at ({x}, {y}), expected one")
            pose_of[lab == near[0]] = p
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
    ap.add_argument("--sheet", type=sheet_key, choices=list(SHEETS), default=1)
    ap.add_argument("--src", type=pathlib.Path, default=None, help="the sheet image, if not the usual one")
    ap.add_argument("--out", type=pathlib.Path, default=None)
    args = ap.parse_args()
    cfg = SHEETS[args.sheet]
    out = args.out or cfg["out"]
    poses = json.loads((HERE / cfg["poses"]).read_text())
    index = {pose["name"]: p for p, pose in enumerate(poses, 1)}
    im = np.asarray(Image.open(args.src or cfg["sheet"]).convert('RGBA')).astype(np.float64)
    rgb, A = im[..., :3], im[..., 3]
    pose_of = assign_pixels(A, len(poses), cfg["row_splits"],
                            {xy: index[name] if name else 0 for xy, name in cfg["give"].items()})
    out.mkdir(parents=True, exist_ok=True)
    for p, pose in enumerate(poses, 1):
        if pose.get("skip"):
            continue
        piece = cut(rgb, A, pose_of == p)
        Image.fromarray(piece).save(out / f"{pose['name']}.png", optimize=True)
        print(f"{pose['name']:28s} {piece.shape[1]}x{piece.shape[0]}")
