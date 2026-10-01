#!/usr/bin/env python3
"""Make the three October sheets transparent and match their paint to the palette.

    python tool/mascot/recolor_sheets_oct.py --sheet moments   # also habits, ramadan
        # writes design/mascot/sheet-<name>/sheet-<name>-final.png

Needs numpy, scipy and Pillow. Step 1 for these sheets; then run
`cut_poses.py --sheet <name>` and `upscale_poses.py --sheet <name>`.
`--debug DIR` also writes the ground mask this step decides on.

THE SOURCES (Aziz, 2026-10-01, from the "Where Doum lives" canvas)
Three ChatGPT sheets, each 1536x1024 with 12 poses in three rows of four,
drawn from the prompts in the memory note doum-sheet-3-prompts (sheets A, B
and C), byte-identical to the downloads:

  moments  "ملصقات دووم الخضراء المرحة.png"       app moments (peek, gift, ...)
  habits   "ملصقات كرتونية لطيفة لعادات يومية.png"   habits (swimming, cooking, ...)
  ramadan  "ملصقات دوْم الرمضانية اللطيفة.png"      Ramadan and Eid

and two more the same day, for the language switch (the canvas "Doum picks
the language", memory note doum-language-canvas):

  suit     "ورقة ملصقات ماسكوت البراعم المرحة.png"   12 poses: the English look
           (rows 2 and 3) kept, its first Arabic look rejected by Aziz
  thobe    "ملصقات mascot خليجي لطيف pose poses.png"  6 poses in a 3 x 2 grid:
           the Arabic look redrawn (leaves hidden, long thobe and sleeves)

THE GROUND
moments, suit and thobe are RGBA with a real transparent ground: the green seen in a viewer
that ignores alpha is colour stored under alpha 0, plus a soft halo of alpha
1 to about 20 round each pose. cut_poses.py's alpha remap (16..240) takes
the halo off, as for sheets 1 and 2, so only the paint moves here.

habits and ramadan are RGB with a checkerboard PAINTED into them (two greys,
RGB about 140 and 195, squares of about 8 px with soft 2 to 3 px edges): a
picture of transparency, not transparency. The ground is found as what
reaches the sheet border through neutral grey paint (OKLab chroma under
0.025, lightness 0.50 to 0.885) without crossing the drawing. Every pose has
a dark outline (L under 0.35), the cream leaves, belly and the white props
(pillow, thobe, plate, envelope) are lighter than 0.885 can reach, and the
effects (sparkles, motion lines, confetti, splash) are coloured, so none of
them floods. Where an arm or a prop closes a loop, the checkerboard seen
through it is a pocket the border flood cannot reach: a pocket of 40 px or
more where at least 15% of the pixels are the dark grey (L 0.55 to 0.72)
and 15% the light grey (L 0.74 to 0.88) is ground too (the script prints
each one). Real grey paint is never both.

Alpha: the drawing two pixels in from its edge is solid. Its first two
layers and the two ground pixels beside it are a drawing colour F (the
nearest solid pixel) over the local ground B (the mean of the ground in an
11 px window, at least 3 px from the drawing): alpha is the pixel's
projection on the line from B to F. Where F and B are under 30 apart in RGB
the pixel cannot be parted and goes by side (drawing solid, ground clear).
The cut then paints every semi-transparent pixel within 3 px of solid in the
nearest solid colour, so no grey fringe is left on a dark card.

THE PAINT
Measured on each sheet's solid pixels inside its characters (art pieces
over 10,000 px; effects never move), as the sport sheet's script does:
each paint moves by the difference between its palette colour and its
median, added in OKLab, so the drawing's shading offsets stay as drawn.

  body green   onto #74C878 (L 0.76 C 0.14 h 145): a pixel's share is its
               chroma between 0.02 and 0.11 times a hue window, full within
               20 degrees of the sheet's median body hue, none past 35.
  cream        onto #F5F0E1 (L 0.955 C 0.02 h 90): lightness over 0.88,
               chroma 0.008 to 0.04, hue within 35 degrees of the median
               cream (pure white highlights and the white props keep theirs).

Toward the outline every move fades out between L 0.55 and 0.25, so the
anti-aliased ramp into the outline stays clean. The cheeks and the outline
are left as drawn; the script prints their measure beside the first
sheet's (cheeks L 0.739 C 0.115 h 26, outline L 0.13 to 0.15).
"""
import argparse
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

from oklab import from_lch, lch, oklab_to_srgb, srgb_to_oklab

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SHEETS = {name: dict(src=ROOT / f"design/mascot/sheet-{name}/sheet-{name}-original.png",
                     out=ROOT / f"design/mascot/sheet-{name}/sheet-{name}-final.png",
                     checker=name in ("habits", "ramadan"), glow=name == "ramadan")
          for name in ("moments", "habits", "ramadan", "suit", "thobe")}

BODY = from_lch(np.array(0.76), np.array(0.14), np.array(145.0))
CREAM = from_lch(np.array(0.955), np.array(0.02), np.array(90.0))
FOUR = ndi.generate_binary_structure(2, 1)
EIGHT = np.ones((3, 3))


def checker_matte(rgb, debug=None, with_glow=False):
    """RGB with a painted checkerboard -> (rgb, alpha 0..255)."""
    L, C, _ = lch(srgb_to_oklab(rgb))
    groundish = (C < 0.025) & (L > 0.50) & (L < 0.885)
    lab, n = ndi.label(groundish, structure=FOUR)
    border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    exterior = np.isin(lab, border[border > 0])
    sizes = ndi.sum(np.ones_like(L), lab, range(1, n + 1))
    for i in range(1, n + 1):
        if sizes[i - 1] < 40 or exterior[lab == i].any():
            continue
        Ls = L[lab == i]
        dark = ((Ls > 0.55) & (Ls < 0.72)).mean()
        light = ((Ls > 0.74) & (Ls < 0.88)).mean()
        if dark >= 0.15 and light >= 0.15:
            ys, xs = np.nonzero(lab == i)
            print(f"  pocket of ground at x {xs.mean():.0f} y {ys.mean():.0f}: {len(Ls)} px")
            exterior |= lab == i
    # Grey crumbs: small pieces of "drawing" that are only the checkerboard
    # blended with the edge of a coloured effect (beside the watering can's
    # water, the broom's dust). Under 60 px, grey on average: ground.
    pieces, pn = ndi.label(~exterior, structure=EIGHT)
    psize = ndi.sum(np.ones_like(L), pieces, range(1, pn + 1))
    pC = ndi.mean(C, pieces, range(1, pn + 1))
    pL = ndi.mean(L, pieces, range(1, pn + 1))
    crumbs = [i + 1 for i in range(pn) if psize[i] < 60 and pC[i] < 0.06 and 0.5 < pL[i] < 0.9]
    if crumbs:
        print(f"  {len(crumbs)} grey crumbs to ground ({int(sum(psize[c - 1] for c in crumbs))} px)")
        exterior |= np.isin(pieces, crumbs)
    # Glow (ramadan only: habits has no light, and its cooking steam is the
    # same warm pale paint, drawn solid): a lantern's or a bulb's light
    # painted OVER the checkerboard. It
    # is warm (hue 40 to 120), not saturated like the drawn sparkles (chroma
    # under 0.12) and reaches the ground without crossing an outline. Its
    # colour is the glow's own light (the median of its lightest tenth), its
    # alpha the pixel's lightness above the local ground over that light's,
    # averaged over 17 px so the squares under it cancel out.
    glow, glow_alpha, glow_rgb = None, None, None
    warm = ~exterior & (C >= 0.025) & (C < 0.12) & (L > 0.5) & (L < 0.97)
    hue = lch(srgb_to_oklab(rgb))[2]
    warm &= (hue > 40) & (hue < 120)
    wl, wn = ndi.label(warm, structure=EIGHT)
    touching = np.unique(wl[ndi.binary_dilation(exterior) & warm])
    touching = touching[touching > 0]
    big = [t for t in touching if (wl == t).sum() >= 150]
    if big and with_glow:
        glow = np.isin(wl, big)
        G = np.median(rgb[glow & (L >= np.quantile(L[glow], 0.9))], 0)
        LG = srgb_to_oklab(G)[0]
        groundL = np.median(L[exterior])
        raw = np.clip((L - groundL) / max(LG - groundL, 1e-3), 0, 1)
        sm = ndi.uniform_filter(np.where(glow, raw, 0.0), 17) / np.maximum(ndi.uniform_filter(glow * 1.0, 17), 1e-6)
        glow_alpha = np.clip(sm, 0, 0.85)
        glow_rgb = G
        print(f"  glow over the ground: {glow.sum()} px, light RGB {np.round(G).astype(int).tolist()}")
        exterior |= glow
    drawing = ~exterior
    core = ndi.binary_erosion(drawing, iterations=2)
    d_draw = ndi.distance_transform_edt(~drawing)
    band = (exterior & (d_draw <= 2)) | (drawing & ~core)
    _, idx = ndi.distance_transform_edt(~core, return_indices=True)
    F = rgb[idx[0], idx[1]]
    far = (exterior & (d_draw >= 3)).astype(np.float64)
    wsum = ndi.uniform_filter(far, 11)
    B = np.stack([ndi.uniform_filter(rgb[..., c] * far, 11) for c in range(3)], -1) / np.maximum(wsum, 1e-6)[..., None]
    _, idxg = ndi.distance_transform_edt(wsum <= 1e-6, return_indices=True)
    B = np.where((wsum > 1e-6)[..., None], B, B[idxg[0], idxg[1]])
    FB = F - B
    den = (FB ** 2).sum(-1)
    proj = np.clip(((rgb - B) * FB).sum(-1) / np.maximum(den, 1e-6), 0, 1)
    alpha = np.where(core, 1.0, 0.0)
    parted = den >= 30 ** 2
    alpha = np.where(band & parted, proj, alpha)
    alpha = np.where(band & ~parted, drawing.astype(np.float64), alpha)
    out = np.where((band & (alpha > 0))[..., None], F, rgb)
    if glow is not None:
        # The glow under the drawing's edge band keeps the larger of the two.
        g = glow & ~drawing
        take = g & (glow_alpha > alpha)
        alpha = np.where(take, glow_alpha, alpha)
        out = np.where(take[..., None], glow_rgb, out)
    if debug:
        debug.mkdir(parents=True, exist_ok=True)
        Image.fromarray((exterior * 255).astype(np.uint8)).save(debug / "ground.png")
    return out, alpha * 255


def recolor(rgb, A):
    """Move body green and cream onto the palette, inside the characters only."""
    lab = srgb_to_oklab(rgb)
    L, C, H = lch(lab)
    art, n = ndi.label(A > 16, structure=EIGHT)
    sizes = ndi.sum(np.ones_like(A), art, range(1, n + 1))
    chars = np.isin(art, [i + 1 for i in range(n) if sizes[i] > 10000])
    outline = L < 0.40
    inner = chars & (A >= 240) & (ndi.distance_transform_edt(~outline) > 4)

    body = inner & (C > 0.11) & (H > 120) & (H < 170) & (L > 0.6)
    bh = np.median(H[body])
    bmed = np.median(lab[body], 0)
    print(f"  body   L {np.median(L[body]):.3f} C {np.median(C[body]):.3f} h {bh:.1f}  ({body.sum()} px)")
    cream = inner & (L > 0.88) & (C > 0.008) & (C < 0.04) & (np.abs(H - 85) < 40)
    ch = np.median(H[cream])
    cmed = np.median(lab[cream], 0)
    print(f"  cream  L {np.median(L[cream]):.3f} C {np.median(C[cream]):.3f} h {ch:.1f}  ({cream.sum()} px)")
    blush = inner & (C > 0.07) & ((H < 45) | (H > 350)) & (L > 0.65) & (L < 0.88)
    if blush.any():
        print(f"  cheeks L {np.median(L[blush]):.3f} C {np.median(C[blush]):.3f} h {np.median(H[blush]):.1f}  (left as drawn)")
    ol = chars & (A >= 240) & (L < 0.25)
    print(f"  outline L {np.median(L[ol]):.3f} C {np.median(C[ol]):.3f} h {np.median(H[ol]):.1f}  (left as drawn)")

    hd = lambda h, c: np.abs((H - c + 180) % 360 - 180)
    fade = np.clip((L - 0.25) / (0.55 - 0.25), 0, 1)
    g = np.clip((C - 0.02) / (0.11 - 0.02), 0, 1) * np.clip((35 - hd(H, bh)) / 15, 0, 1)
    k = np.clip((40 - hd(H, ch)) / 15, 0, 1) * ((C >= 0.008) & (C < 0.04) & (L > 0.88))
    k = k * (1 - g)
    move = (g * fade * chars)[..., None] * (BODY - bmed) + (k * fade * chars)[..., None] * (CREAM - cmed)
    out = oklab_to_srgb(lab + move)
    L2, C2, H2 = lch(srgb_to_oklab(out))
    print(f"  after: body L {np.median(L2[body]):.3f} C {np.median(C2[body]):.3f} h {np.median(H2[body]):.1f};"
          f" cream L {np.median(L2[cream]):.3f} C {np.median(C2[cream]):.3f} h {np.median(H2[cream]):.1f}")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sheet", choices=list(SHEETS), required=True)
    ap.add_argument("--debug", type=pathlib.Path, default=None)
    args = ap.parse_args()
    cfg = SHEETS[args.sheet]
    im = np.asarray(Image.open(cfg["src"]).convert("RGBA")).astype(np.float64)
    rgb, A = im[..., :3], im[..., 3]
    print(args.sheet)
    if cfg["checker"]:
        rgb, A = checker_matte(rgb, args.debug, cfg["glow"])
    rgb = recolor(rgb, A)
    out = np.dstack([np.clip(np.round(rgb), 0, 255), np.clip(np.round(A), 0, 255)]).astype(np.uint8)
    Image.fromarray(out).save(cfg["out"], optimize=True)
    print(f"  wrote {cfg['out'].relative_to(ROOT)}")
