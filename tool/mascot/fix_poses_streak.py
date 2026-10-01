#!/usr/bin/env python3
"""Cut the streak sheet's poses again, without the ground patch and with their ink kept.

    python tool/mascot/fix_poses_streak.py   # rewrites design/mascot/sheet-streak/poses-native/*.png
    python tool/mascot/fix_poses_streak.py --out <folder>     # anywhere else, to compare

Needs numpy, scipy and Pillow. Runs between `cut_poses.py --sheet streak` and
`upscale_poses.py --sheet streak`, as fix_poses_2.py does for sheet 2, and
like it cuts from the sheet itself, so it is safe to rerun.

WHY
ChatGPT drew every pose on this sheet standing on a flat cream ellipse, and
the coal piles and the calendar on one too. It is not a shadow: under the
feet it is alpha 225 to 250 at L 0.77 to 0.86, hue about 90 (the sheet's
cream), so on a dark card it shows as a light patch under each pose. No
shipped pose has one: sheet 2 and the winter pictures draw none, and sheet
1's faint teal shadow leaves nothing visible in its app copies. So the patch
goes, and the poses stand on nothing, like the other 40.

WHY HERE, AND WHY FROM THE SHEET
The patch is what joins the calendar (16,487 px, over cut_poses.py's 10,000
px character size) and four coal piles to their poses: taken out before the
cut, the calendar would be cut as a sixteenth character. So the poses are
assigned on the sheet with the patch (cut_poses.assign_pixels, the streak
entry's splits), and cut (cut_poses.cut) from the sheet with the patch taken
out. Taking it out of the cut files instead does not work: the cut gives
every semi-transparent pixel near an opaque one that pixel's colour, so the
patch's soft edge under the feet has already turned outline-dark (alpha 0.55
to 0.99 at L 0.16) and would stay as dark ticks under every foot, and a pink
smear under the calendar's brown leg.

WHAT COUNTS AS THE PATCH
Sheet pixels over cut_poses.py's alpha floor (16) that are light (L over
0.45), low in chroma (under 0.07) and outside every closed dark outline
(holes filled in the mask of pixels over alpha 128 under L 0.42), in pieces
that reach within 4 rows of the lowest row of the character they belong to,
and no higher than 34 rows above their own lowest row. The ellipses are 16
to 28 rows tall where they are wider than 40 px; what the pieces reach above
34 rows is the watering can's spray and the mist around it (419 px, pale
cyan and cream at chroma 0.02 to 0.07, joined to the ground by a haze line
along the hand) and the same faint haze up two bodies beside their fires (75
and 17 px, and 1 px on a third). Without the row limit the spray's tip was
cut off square. That
leaves the 15 ellipses and the strips under the coal piles and the calendar
(45,739 px), and nothing else: the smoke, the speech bubble, the clock face
and the flames' cores match the colour but sit higher, and the bellies,
leaves and calendar page sit inside outlines.

THE EDGE IT LEAVES
Where an outline met the patch, its anti-aliasing was drawn against cream
(a 1 to 2 px band from L 0.16 to about 0.7, alpha near 255). Left alone it
would be a light rim under the feet on a dark card, and dropped with the
patch it leaves the outline's lower edge stepped. So the patch's pixels
darker than L 0.70 within 1.5 px of dark ink (L under 0.30, alpha over 128)
are kept (1,793 px), and every pixel within 2.5 px of what remains of the
patch is solved as a mix of ink and cream (projected in linear RGB, as
recolor_sheet.py rebuilds its seams) and becomes that ink at the ink's share
of its alpha (7,492 px). The ink is the nearest dark ink when one lies
within 3 px (all but 16 of them), else the nearest art 3 px from the patch;
the cream is the nearest pure patch pixel (L over 0.75, alpha over 128).
Taking the nearest art 3 px in as the ink everywhere, as the first version
of this step did, painted the outline's lower edge in body green wherever
the outline is under 3 px thick, and the patch's own anti-aliasing, dropped
whole, left the coal piles and the calendar's base serrated.

INK THE CUT REPAINTS LIGHT
cut_poses.cut gives every pixel under its full alpha (240) the colour of the
nearest pixel at or over it, which on the other sheets is the outline. Here
the outline is not always at full alpha: beside the fires, and at a few
ends (the stick's, the bubble tail's), ChatGPT drew it at alpha 154 to 239.
There the nearest full pixel is whatever lies inside: the firelight's yellow
rim on the poking hand (outline L 0.28 to 0.34 came out 0.48 to 0.76), the
stick's wood (0.33 to 0.52), the bubble's grey inner blend (0.41 and 0.59),
the blow pose's cyan wind (0.62), a coal's brown (0.41 to 0.43), and the can
hand's body green (L 0.28 to 0.35 at chroma 0.055 to 0.076), so the outline
showed light or green breaks on cream and on dark. The shared cut stays as
it is (sheets 1 and 2 must still cut byte for byte). Instead, after it, a
pixel drawn as ink (L under 0.36 at alpha over 150) that the cut made more
than 0.10 lighter, into a colour that is not ink (L over 0.36, or chroma
over 0.05; the sheet's opaque ink, alpha over 240 and L under 0.30, has its
median at L 0.14 and chroma 0.021, and 90% of it under chroma 0.044), gets
its own colour back at the cut's alpha, and the transparent pixels nearest
it carry that colour, as the cut does. That is 52 pixels in five poses:
poke 32, watering can 12, phone 4, blow 3, lying scribble 1. The ink the
cut makes lighter and leaves ink (37 pixels, L 0.10 to 0.30 at chroma under
0.04) is the outline's own shading, what the cut does on every sheet, and
stays.
"""
import argparse
import json
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

import cut_poses as cp
from oklab import lch, srgb_to_lin, srgb_to_oklab

KEY = "streak"
PATCH_L, PATCH_C, OUTLINE_L = 0.45, 0.07, 0.42
FOOT_ROWS = 4                      # a patch piece reaches its character's lowest rows
TALL = 34                          # rows: no patch pixel sits higher above its piece's lowest row
INK_L, BLEND_L, PURE_L = 0.30, 0.70, 0.75   # outline ink, outline-on-cream blend, pure cream
RING, INK_FROM, INK_NEAR = 2.5, 3, 3.0      # px: the band to un-blend, the fallback ink, dark ink reach
KEEP_L, KEEP_A, KEEP_C, KEEP_STEP = 0.36, 150, 0.05, 0.10   # ink; the lightening the cut may not make


def patch_of(rgb, A):
    """The ground patch on the sheet, as a mask."""
    L, C, _ = lch(srgb_to_oklab(rgb))
    inside = ndi.binary_fill_holes((A > 128) & (L < OUTLINE_L))
    cand = (A > cp.A_FLOOR) & ~inside & (L > PATCH_L) & (C < PATCH_C)
    art, n = ndi.label(A > cp.A_FLOOR, structure=cp.EIGHT)
    sizes = ndi.sum(A > cp.A_FLOOR, art, range(1, n + 1))
    objs = ndi.find_objects(art)
    lowest = {c: objs[c - 1][0].stop - 1 for c in range(1, n + 1) if sizes[c - 1] > 10000}
    parts, pn = ndi.label(cand, structure=cp.EIGHT)
    rows = np.arange(A.shape[0])[:, None]
    patch = np.zeros_like(cand)
    for i, sl in enumerate(ndi.find_objects(parts), 1):
        m = parts[sl] == i
        owner = np.bincount(art[sl][m]).argmax()
        bottom = sl[0].stop - 1
        if owner in lowest and bottom >= lowest[owner] - FOOT_ROWS:
            patch[sl] |= m & (rows[sl[0]] >= bottom - TALL)
    return patch


def remove_patch(rgb, A, patch):
    """Alpha 0 on the patch; the ring of ink drawn against it un-blended.
    Returns the new colour and alpha, the patch as removed, and counts."""
    rgb, A = rgb.copy(), A.copy()
    L, _, _ = lch(srgb_to_oklab(rgb))
    lin = srgb_to_lin(rgb)
    art = A > cp.A_FLOOR
    dark = art & ~patch & (A > 128) & (L < INK_L)
    d_dark, near_dark = ndi.distance_transform_edt(~dark, return_indices=True)
    blend = patch & (L < BLEND_L) & (d_dark <= 1.5)     # outline anti-aliasing, solved below
    patch = patch & ~blend
    pure = patch & (A > 128) & (L > PURE_L)
    _, near_pure = ndi.distance_transform_edt(~pure, return_indices=True)
    d = ndi.distance_transform_edt(~patch)
    ring = ~patch & art & (d <= RING)
    far = ~patch & art & (d >= INK_FROM)
    _, near_far = ndi.distance_transform_edt(~far, return_indices=True)
    by_dark = d_dark <= INK_NEAR
    iy = np.where(by_dark, near_dark[0], near_far[0])
    ix = np.where(by_dark, near_dark[1], near_far[1])
    s = lin[near_pure[0], near_pure[1]]
    v = lin[iy, ix] - s
    t = np.clip(((lin - s) * v).sum(-1) / np.maximum((v * v).sum(-1), 1e-6), 0, 1)
    solve = ring & ((v * v).sum(-1) > 0.01)            # ink and cream differ enough to tell apart
    A[solve] *= t[solve]
    rgb[solve] = rgb[iy[solve], ix[solve]]
    A[patch] = 0
    counts = dict(patch=int(patch.sum()), blend=int(blend.sum()), solved=int(solve.sum()),
                  by_dark=int((solve & by_dark).sum()))
    return rgb, A, patch, counts


def keep_ink(piece, rgb, A, m):
    """Ink the cut repainted light gets its own colour back, in place.
    `piece` is cp.cut(rgb, A, m); returns how many pixels changed."""
    ys, xs = np.nonzero(m)
    y0, x0 = ys.min(), xs.min()          # with cp.MARGIN around it, where cp.cut put the piece
    H, W = piece.shape[:2]

    def own(a):
        a = np.pad(a, [(cp.MARGIN, cp.MARGIN)] * 2 + [(0, 0)] * (a.ndim - 2))
        return a[y0:y0 + H, x0:x0 + W]

    o_rgb, o_a = own(rgb), own(np.where(m, A, 0))
    o_L = lch(srgb_to_oklab(o_rgb))[0]
    c_rgb = piece[..., :3].astype(np.float64)
    c_L, c_C, _ = lch(srgb_to_oklab(c_rgb))
    not_ink = (c_L > KEEP_L) | (c_C > KEEP_C)
    back = (o_a > KEEP_A) & (o_L < KEEP_L) & (c_L > o_L + KEEP_STEP) & not_ink
    c_rgb[back] = np.round(o_rgb[back])
    seen = piece[..., 3] > 0
    _, idx = ndi.distance_transform_edt(~seen, return_indices=True)
    carry = ~seen & back[idx[0], idx[1]]            # transparent, nearest to a pixel given back
    c_rgb[carry] = c_rgb[idx[0][carry], idx[1][carry]]
    piece[..., :3] = c_rgb.astype(np.uint8)
    return int(back.sum())


def main(out=None):
    cfg = cp.SHEETS[KEY]
    poses = json.loads((cp.HERE / cfg["poses"]).read_text())
    index = {p["name"]: i for i, p in enumerate(poses, 1)}
    im = np.asarray(Image.open(cfg["sheet"]).convert("RGBA")).astype(np.float64)
    rgb, A = im[..., :3], im[..., 3]
    pose_of = cp.assign_pixels(A, len(poses), cfg["row_splits"],
                               {xy: index[n] if n else 0 for xy, n in cfg["give"].items()})
    patch = patch_of(rgb, A)
    rgb2, A2, patch, n = remove_patch(rgb, A, patch)
    print(f"patch {n['patch']} px removed, {n['blend']} outline blends kept to solve, "
          f"edge {n['solved']} px un-blended ({n['by_dark']} against dark ink)")
    out = out or cfg["out"]
    out.mkdir(parents=True, exist_ok=True)
    for p, pose in enumerate(poses, 1):
        m = (pose_of == p) & (A2 > cp.A_FLOOR)
        piece = cp.cut(rgb2, A2, m)
        kept = keep_ink(piece, rgb2, A2, m)
        Image.fromarray(piece).save(out / f"{pose['name']}.png", optimize=True)
        print(f"{pose['name']:28s} {piece.shape[1]}x{piece.shape[0]}  ink given back {kept} px")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--out", type=pathlib.Path, default=None)
    main(ap.parse_args().out)
