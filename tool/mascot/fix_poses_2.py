#!/usr/bin/env python3
"""Drawing fixes on the second sheet's cut poses.

    python tool/mascot/fix_poses_2.py      # rewrites design/mascot/sheet-2/poses-native/mascot_idea.png

Needs numpy, scipy and Pillow. Runs between `cut_poses.py --sheet 2` and
`upscale_poses.py --sheet 2`, on the cut files (the sheet has no room: the
fix moves a piece into the space beside the next pose).

THE IDEA POSE'S LEAVES (Aziz, 2026-09-29)
ChatGPT drew the idea pose with one leaf, standing up; every other pose has
the pair. Its leaves and stem are replaced by the waving pose's (front_wave_2),
which the sheet drew in the same row, so at the same size, with the head
facing the same way. On the sheet the two stems measure 17 and 18 px wide,
centred at x 623.8 and 1388, with the head starting at y 122 and 126: the
pair moves 764 px left and 4 px up, and the stems meet within a pixel. What
is removed is everything of the idea pose's own body above y 118 (its leaf
and the top of its stem); the head's outline starts at 119 and stays.

The new right leaf reaches where the bulb was, so the bulb and its rays move
70 px right and 18 px up: the lowest place that keeps 6 px from the leaf's
tip (the step checks it) and still beside the leaves rather than above them (on the
Grid's board edge the bulb must not rise far into the day card). The original
stem had a one-pixel dark tick near the head; it takes the stem's cream.

Everything is placed in sheet coordinates, then cut again with cut_poses.py's
margin, and transparent pixels take the nearest visible colour, as the cut
does, so upscaling never bleeds dark into an edge.
"""
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

import cut_poses as cp

ROOT = pathlib.Path(__file__).resolve().parents[2]
NATIVE = ROOT / "design/mascot/sheet-2/poses-native"

IDEA, WAVE = "mascot_idea", "mascot_front_wave_2"
SHIFT = (-764, -4)          # the waving pose's leaves onto the idea pose's stem
CUT_ABOVE = 118             # the idea pose's own body above this row goes
TAKE_TO = 124               # the waving pose's rows down to here come across,
LEAVES_TO = 118             # but below this only its stem (x 1372 to 1404), not its head's outline
STEM_COLS = (1372, 1404)
BULB = dict(region=(660, 0, 820, 125), shift=(70, -18))   # x0, y0, x1, y1 on the sheet
STEM = (608, 119, 642, 134)   # the old stem below the join: dark ticks inside it take its cream
CLEAR = 6                     # px the moved bulb keeps from everything else


def cuts():
    """The two poses exactly as cut_poses.py cuts them, and where each sits on
    the sheet. Cutting again here (rather than reading the files) keeps this
    step safe to rerun: it never fixes its own output a second time."""
    import json
    cfg = cp.SHEETS[2]
    poses = json.loads((cp.HERE / cfg["poses"]).read_text())
    index = {p["name"]: i for i, p in enumerate(poses, 1)}
    im = np.asarray(Image.open(cfg["sheet"]).convert("RGBA")).astype(np.float64)
    rgb, A = im[..., :3], im[..., 3]
    pose_of = cp.assign_pixels(A, len(poses), cfg["row_splits"],
                               {xy: index[n] if n else 0 for xy, n in cfg["give"].items()})
    out = {}
    for name in (IDEA, WAVE):
        m = pose_of == index[name]
        ys, xs = np.nonzero(m)
        out[name] = (cp.cut(rgb, A, m).astype(np.float64) / 255, (xs.min() - cp.MARGIN, ys.min() - cp.MARGIN))
    return out


def body_mask(rgba):
    solid = rgba[..., 3] > 0.35
    lab, n = ndi.label(solid, structure=cp.EIGHT)
    sizes = ndi.sum(solid, lab, range(1, n + 1))
    body = int(np.argmax(sizes)) + 1
    _, idx = ndi.distance_transform_edt(lab == 0, return_indices=True)
    owner = lab[idx[0], idx[1]]
    return (owner == body) & (rgba[..., 3] > 0)


def over(dst, src):
    """src over dst, both straight-alpha float RGBA 0..1."""
    sa, da = src[..., 3:4], dst[..., 3:4]
    oa = sa + da * (1 - sa)
    rgb = np.where(oa > 0, (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6), 0)
    return np.concatenate([rgb, oa], -1)


def main():
    c = cuts()
    idea, (ix, iy) = c[IDEA]
    wave, (wx, wy) = c[WAVE]

    # a sheet-space canvas big enough for the idea pose, the moved bulb and the new leaves
    pad = 2 * max(abs(v) for v in BULB["shift"] + SHIFT[1:])
    X0, Y0 = ix - pad, iy - pad
    W, H = idea.shape[1] + 2 * pad, idea.shape[0] + 2 * pad
    canvas = np.zeros((H, W, 4))

    def place(img, mask, sx, sy):
        """Put `img` (pixels where mask) with its top-left at sheet (sx, sy)."""
        layer = np.zeros((H, W, 4))
        h, w = img.shape[:2]
        layer[sy - Y0:sy - Y0 + h, sx - X0:sx - X0 + w] = np.where(mask[..., None], img, 0)
        return layer

    body = body_mask(idea)
    rows = np.arange(idea.shape[0])[:, None] + iy
    cols = np.arange(idea.shape[1])[None, :] + ix
    keep_body = body & (rows > CUT_ABOVE)
    x0, y0, x1, y1 = BULB["region"]
    effects = (~body) & (idea[..., 3] > 0)
    bulb = effects & (cols >= x0) & (cols < x1) & (rows >= y0) & (rows < y1)
    rest = effects & ~bulb

    wbody = body_mask(wave)
    wrows = np.arange(wave.shape[0])[:, None] + wy
    wcols = np.arange(wave.shape[1])[None, :] + wx
    leaves = wbody & ((wrows <= LEAVES_TO) |
                      ((wrows <= TAKE_TO) & (wcols >= STEM_COLS[0]) & (wcols <= STEM_COLS[1])))

    canvas = over(canvas, place(idea, keep_body | rest, ix, iy))
    canvas = over(canvas, place(wave, leaves, wx + SHIFT[0], wy + SHIFT[1]))
    moved = place(idea, bulb, ix + BULB["shift"][0], iy + BULB["shift"][1])
    gap = ndi.distance_transform_edt(~(canvas[..., 3] > .2))[moved[..., 3] > .2].min()
    if gap < CLEAR:
        raise SystemExit(f"the moved bulb is {gap:.1f} px from the leaves, needs {CLEAR}")
    canvas = over(canvas, moved)

    # the old stem's dark tick: a pixel darker than the cream all around it
    lum = canvas[..., :3] @ np.array([.2126, .7152, .0722])
    x0s, y0s, x1s, y1s = STEM
    for y in range(y0s - Y0, y1s - Y0):
        for x in range(x0s - X0, x1s - X0):
            if lum[y, x] < .85 and canvas[y, x, 3] > .9:
                win = lum[y - 2:y + 3, x - 2:x + 3]
                if np.median(win) > .9:
                    around = canvas[y - 2:y + 3, x - 2:x + 3, :3][win > .9]
                    canvas[y, x, :3] = np.median(around, axis=0)
    print(f"bulb clears the leaves by {gap:.1f} px")

    # cut again with the cut's margin, and give transparent pixels the nearest visible colour
    ys, xs = np.nonzero(canvas[..., 3] > 0)
    m = cp.MARGIN
    out = canvas[ys.min() - m:ys.max() + 1 + m, xs.min() - m:xs.max() + 1 + m].copy()
    clear = out[..., 3] <= 0
    _, idx = ndi.distance_transform_edt(clear, return_indices=True)
    out[..., :3] = np.where(clear[..., None], out[idx[0], idx[1], :3], out[..., :3])
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)).save(NATIVE / f"{IDEA}.png", optimize=True)
    print(f"{IDEA}: {idea.shape[1]}x{idea.shape[0]} -> {out.shape[1]}x{out.shape[0]}")


if __name__ == "__main__":
    main()
