#!/usr/bin/env python3
"""Fixes for the October sheets' cut poses, run after cut_poses.py.

    python tool/mascot/fix_poses_oct.py

Needs numpy and Pillow. Rewrites design/mascot/sheet-moments/poses-native/
moments_peek_edge.png.

THE PEEK POSE'S EDGE
The prompt asked for Doum peeking over a flat edge, and the sheet draws the
edge as a dark line under his hands, about 375 px long. In the app the edge
is the card or screen edge he peeks over, so the line goes: the rows from
its top down are cut, and the pose ends flat at the line's top, where his
hands rest. The line is found as the top row whose opaque run spans more
than 80% of the pose's width (his hands together span about 70%).
"""
import pathlib

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
PEEK = ROOT / "design/mascot/sheet-moments/poses-native/moments_peek_edge.png"
MARGIN = 8


def cut_edge_line(path):
    im = np.asarray(Image.open(path).convert("RGBA")).copy()
    A = im[..., 3]
    W = A.shape[1]
    rows = [y for y in range(A.shape[0]) if (A[y] >= 128).sum() > 0.8 * W]
    if not rows:
        raise SystemExit("no edge line found in the peek pose")
    top = rows[0]
    im[top:, :, 3] = 0
    ys, xs = np.nonzero(im[..., 3] > 0)
    x0, x1 = max(xs.min() - MARGIN, 0), min(xs.max() + 1 + MARGIN, W)
    y0 = max(ys.min() - MARGIN, 0)
    out = im[y0:top, x0:x1]
    Image.fromarray(out).save(path, optimize=True)
    print(f"{path.name}: edge line from y {top} cut, now {out.shape[1]}x{out.shape[0]}")


if __name__ == "__main__":
    cut_edge_line(PEEK)
