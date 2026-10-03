#!/usr/bin/env python3
"""Cut a ChatGPT sheet of world objects (no Doum) into one transparent PNG per cell.

    python tool/world/cut_world_sheet.py --sheet plants   # also fx, later, palm, show, inside
        # writes design/world/sheet-<name>/cells/<name>.png

Needs numpy, scipy and Pillow. For the "Doum's Planet" canvas (2026-10-03,
direction G, Doum's oasis): the things Doum can plant, the small effects
the moments animate, and the things later levels bring (the "later" sheet,
drawn to the no-animals prompt: kite, lanterns, dhow, bench, falaj, ...). Both sheets are 4 x 3 grids of 384 x 341 cells on a
1536 x 1024 sheet, drawn from the prompts on the canvas's Art board.

THE GROUND
plants is RGB with a checkerboard PAINTED into it, like the October habits
and ramadan sheets, so it goes through recolor_sheets_oct.checker_matte.
fx and later are RGBA with a real transparent ground; its alpha tops out at 250 to 254
and carries a faint halo, so alpha is remapped 16..240 -> 0..255 as
cut_poses.py does for the mascot.

WHAT BELONGS TO A CELL
Every piece of art at alpha > 16 belongs to the cell its centre falls in.
Colours are left as drawn: these are objects, not Doum, so nothing moves to
his palette.

NO ANIMALS (Aziz, 2026-10-03: "make it halal")
The world is drawn without beings that have a soul: trees, plants, water,
buildings and objects only. The plants sheet's beehive came with two bees
with faces (and their dotted flight trails) beside it; for that cell only
the largest piece, the hive, is kept ("keep_largest").

A PAINTED, BLURRED GROUND ("blurbg")
The show sheet (sheet 6, the showpieces for the high bases) came back RGB on
a dark, blurred green backdrop with soft glows, not transparent. The art has
a sharp dark outline and the backdrop is smooth, so the ground is every
low-gradient region that reaches a cell edge (the grid lines included), plus
any big closed-in region that is as smooth as the ground and its colour
(the space under the majlis shade).
"""
import argparse
import json
import pathlib
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tool/mascot"))
from recolor_sheets_oct import checker_matte  # noqa: E402

SHEETS = {
    "plants": dict(checker=True, keep_largest={"hive"},
                   names=["palm", "lemon", "pomegranate", "sidr", "rose", "jasmine",
                          "flowers", "well", "house", "hive", "vegetables", "spring"]),
    # palm: drawn off the grid (six palms on the first row, four date bunches
    # on the second, crown and trunk on the third), so its objects are found
    # by shape ("free"): pieces within 8 px of each other are one object,
    # read row by row (rows split where the objects' centres jump more than
    # 120 px), left to right.
    "palm": dict(checker=False, keep_largest=set(), free=True,
                 names=["palm_shoot", "palm_offshoot", "palm_young", "palm_medium", "palm_tall", "palm_lanterns",
                        "dates_hababou", "dates_khalal", "dates_rutab", "dates_tamr", "palm_crown", "palm_trunk"]),
    "later": dict(checker=False, keep_largest=set(),
                  names=["stones", "kite", "lanterns", "dhow", "swing", "vine", "bench", "falaj",
                         "rose_arch", "rain_cloud", "rainbow", "telescope"]),
    # show: sheet 6, the rare showpieces for the high bases (gold trim to
    # star crown). Painted blurred ground, see blur_matte.
    "show": dict(checker=False, blurbg=True, keep_largest=set(),
                 names=["coral_house", "fountain", "golden_palm", "lantern_arch", "pearl_chest", "big_dhow",
                        "majlis", "frond_hut", "lighthouse", "lamp_posts", "lily_pool", "jasmine_pergola"]),
    # inside: sheet 7, furniture for the room inside Doum's house. Painted
    # blurred ground again, see blur_matte.
    "inside": dict(checker=False, blurbg=True, keep_largest=set(),
                   names=["mandoos", "dallah_set", "mabkhara", "cushions", "low_table", "carved_door",
                          "lattice_window", "shelf", "hanging_lantern", "potted_palm", "pattern_frame", "frond_mat"]),
    "fx": dict(checker=False, keep_largest=set(),
               names=["water_arc", "drops", "splash", "soil_puff", "sparkle", "ripple",
                      "pearl", "shell_pearl", "harvest_basket", "canopy", "trunk", "flower_head"]),
}
EIGHT = np.ones((3, 3))


def blur_matte(rgb, thr=40.0):
    """Alpha for art painted on a smooth, blurred backdrop (see the docstring)."""
    sm = ndi.gaussian_filter(rgb, (1, 1, 0))
    g = np.zeros(rgb.shape[:2])
    for c in range(3):
        g = np.maximum(g, np.hypot(ndi.sobel(sm[..., c], 1), ndi.sobel(sm[..., c], 0)))
    low = g < thr
    lab, _ = ndi.label(low)
    h, w = low.shape
    edge = np.zeros_like(low)
    for r in range(4):
        edge[min(round(r * h / 3), h - 1), :] = True
    for c in range(5):
        edge[:, min(round(c * w / 4), w - 1)] = True
    ids = np.unique(lab[edge & low])
    bg = np.isin(lab, ids[ids > 0])
    # closed-in smooth regions with the ground's colour, judged per cell
    for r in range(3):
        for c in range(4):
            ys, xs = slice(round(r * h / 3), round((r + 1) * h / 3)), slice(round(c * w / 4), round((c + 1) * w / 4))
            near = ndi.binary_dilation(~bg[ys, xs], iterations=24) & bg[ys, xs]
            ground = rgb[ys, xs][near]
            mu, sd = ground.mean(0), ground.std(0) + 4
            sub = lab[ys, xs] * (low[ys, xs] & ~bg[ys, xs])
            for k in np.unique(sub):
                if k == 0:
                    continue
                m = sub == k
                # big, very smooth and the ground's colour: green leaves are
                # smooth too but carry more texture (mean gradient > 15)
                if m.sum() < 1000 or g[ys, xs][m].mean() > 15:
                    continue
                if np.all(np.abs(rgb[ys, xs][m].mean(0) - mu) < 0.8 * sd):
                    bg[ys, xs] |= m
    # the outline's outer pixel carries some glow: take one pixel off, then soften
    bg = ndi.binary_dilation(bg, iterations=1)
    A = 255.0 * (1 - ndi.gaussian_filter(bg.astype(float), 0.7))
    A[A < 8] = 0
    return rgb, A

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sheet", choices=list(SHEETS), required=True)
    args = ap.parse_args()
    cfg = SHEETS[args.sheet]
    base = ROOT / f"design/world/sheet-{args.sheet}"
    im = np.asarray(Image.open(base / f"sheet-{args.sheet}-original.png").convert("RGBA")).astype(np.float64)
    rgb, A = im[..., :3], im[..., 3]
    if cfg.get("blurbg"):
        rgb, A = blur_matte(rgb)
    elif cfg["checker"]:
        rgb, A = checker_matte(rgb)
    else:
        A = np.clip((A - 16) / (240 - 16) * 255, 0, 255)
    art, n = ndi.label(A > 16, structure=EIGHT)
    if cfg.get("free"):
        # one label per object: pieces within 8 px of each other join
        joined, m = ndi.label(ndi.binary_dilation(A > 16, iterations=4), structure=EIGHT)
        objs = []
        for j, sl in enumerate(ndi.find_objects(joined)):
            area = int(((joined[sl] == j + 1) & (A[sl] > 16)).sum())
            if area < 1500:
                continue
            cy, cx = ndi.center_of_mass(joined[sl] == j + 1)
            objs.append((sl[0].start + cy, sl[1].start + cx, j + 1))
        objs.sort()
        rows, cur = [], [objs[0]]
        for o in objs[1:]:
            if o[0] - cur[-1][0] > 120:
                rows.append(cur); cur = [o]
            else:
                cur.append(o)
        rows.append(cur)
        order = [o for r in rows for o in sorted(r, key=lambda t: t[1])]
        assert len(order) == len(cfg["names"]), f"found {len(order)} objects, expected {len(cfg['names'])}"
        art = np.where(A > 16, joined, 0)
        cells = {k: [(1, o[2])] for k, o in enumerate(order)}
    else:
        cells = {}
    for i, sl in enumerate([] if cfg.get("free") else ndi.find_objects(art)):
        cy, cx = ndi.center_of_mass(art[sl] == i + 1)
        r = min(2, int((sl[0].start + cy) // 341)); c = min(3, int((sl[1].start + cx) // 384))
        size = int((art[sl] == i + 1).sum())
        if size < 6:
            continue
        cells.setdefault(r * 4 + c, []).append((size, i + 1))
    out_dir = base / "cells"; out_dir.mkdir(exist_ok=True)
    meta = []
    for k, name in enumerate(cfg["names"]):
        pieces = sorted(cells.get(k, []), reverse=True)
        keep = [pieces[0][1]] if name in cfg["keep_largest"] else [p[1] for p in pieces]
        mask = np.isin(art, keep)
        mask = ndi.binary_dilation(mask, iterations=2) & (A > 0)
        ys, xs = np.nonzero(mask)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        a = np.where(mask, A, 0)[y0:y1, x0:x1]
        tile = np.dstack([rgb[y0:y1, x0:x1], a])
        pad = 8
        canvas = np.zeros((tile.shape[0] + 2 * pad, tile.shape[1] + 2 * pad, 4))
        canvas[pad:-pad, pad:-pad] = tile
        Image.fromarray(np.clip(np.round(canvas), 0, 255).astype(np.uint8)).save(out_dir / f"{name}.png", optimize=True)
        dropped = len(pieces) - len(keep)
        meta.append(dict(name=name, cell=k + 1, size=[int(x1 - x0), int(y1 - y0)], pieces=len(keep), dropped=dropped))
        print(f"{name:16s} {x1 - x0}x{y1 - y0}  pieces {len(keep)}" + (f"  dropped {dropped}" if dropped else ""))
    (base / "cells.json").write_text(json.dumps(meta, indent=1, ensure_ascii=False) + "\n")
