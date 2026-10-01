#!/usr/bin/env python3
"""Give the firelight back its colour at the edges of the ghutra sheet's cut poses.

    python tool/mascot/fix_poses_ghutra.py    # rewrites design/mascot/sheet-ghutra/poses-native/*.png

Needs numpy, scipy and Pillow. Runs between `cut_poses.py --sheet ghutra`
and `upscale_poses.py --sheet ghutra`, on the cut files.

WHY
cut_poses.py gives every semi-transparent pixel within 3 px of an opaque one
the colour of the nearest opaque pixel. On sheets 1 and 2 those pixels are
an outline over nothing, so that is right and keeps fringes out. On this
sheet recolor_sheet_ghutra.py mattes them over the ground beyond them, and
beside a fire that ground is firelight: the glow's colour-to-alpha orange at
about 30% alpha. Painted the outline's brown instead, the glow turns into a
tan line along every outline it touches, on a cream card: at sheet y 565 in
the blowing pose, the two glow pixels right of the mitten's outline (x 272
and 273, alpha 30 and 32%) became brown 146 82 26 where the matte gave them
241 160 0, which on cream reads L 0.81 C 0.05 against the glow's 0.90 and
0.08. The same happens where the glow meets the logs, the hourglass's frame
and a flame's own edge, and on a dark card the breath streak's crossings in
the blowing pose showed grey-green blotches.

WHAT
Each pose is cut again exactly as cut_poses.py cuts it (so this step never
fixes its own output a second time), then the pixels that rule repainted
take back the sheet's colour where the sheet has firelight there: hue 55 to
100, chroma over 0.12, L over 0.6. Measured on the sheet, the 4,910 such
edge pixels read hue 58 to 88, chroma 0.127 to 0.174 and L 0.66 to 0.89 (5th
to 95th percentile), at 9 to 82% alpha (median 31); an outline's own
anti-aliasing is darker (L under 0.6) and a shadow is grey, so both keep the
cut's colour. Alpha is never touched. On a dark card the pixels that change
most are where the glow meets the top of a log or the hourglass's frame:
a faint firelight tint there instead of the outline's brown, as drawn.

upscale_poses.py's clean_edges then gives pixels within 6 px of a solid one
at 4x (1.5 px here) the nearest solid colour again, so a pixel right
against an outline still turns brown: the tan line in the app copy halves
(6 app px wide to 3 at the blowing pose's mitten, y 500) rather than going.
"""
import json
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

import cut_poses as cp
from oklab import lch, srgb_to_oklab

FIRE_H, FIRE_C, FIRE_L = (55, 100), 0.12, 0.6   # the glow's colour-to-alpha colour
REACH = 3                                        # cut_poses.py's reach for edge colour


def main():
    cfg = cp.SHEETS["ghutra"]
    poses = json.loads((cp.HERE / cfg["poses"]).read_text())
    index = {p["name"]: i for i, p in enumerate(poses, 1)}
    im = np.asarray(Image.open(cfg["sheet"]).convert("RGBA")).astype(np.float64)
    rgb, A = im[..., :3], im[..., 3]
    pose_of = cp.assign_pixels(A, len(poses), cfg["row_splits"],
                               {xy: index[n] if n else 0 for xy, n in cfg["give"].items()})
    L, C, H = lch(srgb_to_oklab(rgb))
    lit = (H > FIRE_H[0]) & (H < FIRE_H[1]) & (C > FIRE_C) & (L > FIRE_L)
    # the sheet padded by the cut's margin, as a pose's box can start off the sheet
    P = cp.MARGIN
    rgb_p = np.pad(rgb, ((P, P), (P, P), (0, 0)))
    lit_p = np.pad(lit, P)
    total = 0
    for pose in poses:
        m = pose_of == index[pose["name"]]
        piece = cp.cut(rgb, A, m)
        ys, xs = np.nonzero(m)
        x0, y0 = xs.min() - P, ys.min() - P
        h, w = piece.shape[:2]
        win = np.s_[y0 + P:y0 + P + h, x0 + P:x0 + P + w]
        a = piece[..., 3]
        repainted = (a > 0) & (a < 255) & (ndi.distance_transform_edt(a < 255) <= REACH)
        back = repainted & lit_p[win] & np.pad(m, P)[win]
        piece[..., :3][back] = np.clip(np.round(rgb_p[win][back]), 0, 255).astype(np.uint8)
        Image.fromarray(piece).save(cfg["out"] / f"{pose['name']}.png", optimize=True)
        total += int(back.sum())
        print(f"{pose['name']:28s} {int(back.sum()):4d} px given back their firelight")
    print(f"{total} px in all")


if __name__ == "__main__":
    main()
