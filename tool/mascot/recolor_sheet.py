#!/usr/bin/env python3
"""Recolour the mascot sheet to the chosen palette and fix its drawing faults.

    python tool/mascot/recolor_sheet.py            # writes design/mascot/mascot-sheet-final.png

Needs numpy, scipy and Pillow. Step 1 of 3; then run cut_poses.py and
upscale_poses.py. The full setup is in design/mascot/README.md.

The source is design/mascot/mascot-sheet-original.png, the ChatGPT sheet Aziz
generated on 2026-09-27: a dark forest-green body with gold leaves, stem and
belly. The chosen palette (2026-09-27, after three rounds of boards) is a fresh
green body with white leaves, stem and belly and soft pink cheeks. Change the
PALETTE block and re-run all three steps to try another.

HOW THE PAINT IS SWAPPED WITHOUT LOSING THE DRAWING
Everything happens in OKLab (oklab.py). The body green was measured on the
sheet's interior (more than 4 px from the outline): L 0.458, C 0.094, hue
150.6, with 98% of pixels within 3 degrees of that hue. A pixel counts as green
paint by hue (full weight within 22 degrees, none past 45) and chroma (none
under 0.012), and translucent pixels are left alone (the ground shadow is a
translucent teal that would otherwise turn pastel and vanish). Its new
lightness keeps 80% of its offset from the body median, so the plush shading
survives, and below L 0.33 a Hermite toe bends down to the outline at 0.20, so
anti-aliasing into the dark outline stays a clean ramp. The gold (L 0.812,
C 0.152, hue 80.8) is swapped the same way with its own toe (0.20 to 0.68).

WHICH GOLD IS THE CHARACTER'S
Only the leaves, stem and belly change. Gold components whose 10 px ring is 95%
air are effects (sparkles, laugh and "!" lines) and keep their gold; the pencil
is a prop with the same gold and is excluded by a box; clipboard wood and the
backpack fail the "median colour is still gold" test. Leaves are components
over 3000 px whose bounding box is under 60% full (a V shape); the rest are
bellies. Green paint whose 3 px ring is mostly air or paper is decoration ("?",
"zZ", the clipboard's tick boxes) and gets a deeper green so it stays legible.

DRAWING FAULTS THIS FIXES (each measured and checked at 6x zoom)
- Seams: where gold met green (belly rim, leaf folds) the 1-2 px blend pixels
  were half claimed by each pass and came out grey or olive. Each is rebuilt
  as the same mix of its NEW neighbours, found by projecting the original
  colour onto the segment between its nearest pure gold and nearest pure
  green. Pure green must sit within 10 degrees of the body hue, or olive
  blends count as green and survive.
- Leftover olive inside the gold zones (a leaf's underside seen edge-on is all
  blend, and outline pixels carried a gold tint) keeps its lightness and takes
  the body hue.
- Cheeks: every blush is repainted pink over the new green, from its own
  opacity profile. Two hide half behind the laptop and the book, so they are
  not holes in the green paint and are found as cheek-coloured blobs touching
  green instead. Three were olive in the source. A cheek's soft edge never
  paints over dark, grey or gold pixels.
- The walking pose's strap was drawn as a green and brown smear: the band is
  flood-filled from a seed inside it, closed over its dark blobs and painted
  the backpack's own brown with a light top and darker rim.
- A faint grey smudge beside the sleeping pose's "zZ" is dropped.

The coordinates below (the pencil box, strap seed, backpack sample, smudge)
belong to mascot-sheet-original.png. A different sheet needs its own.
"""
import argparse
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

from oklab import from_lch, lch, oklab_to_srgb, srgb_to_oklab

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "design/mascot/mascot-sheet-original.png"
OUT = ROOT / "design/mascot/mascot-sheet-final.png"

# ---- PALETTE: OKLCh (L, C, hue); leaf and belly also carry their shading keep
BODY = (0.76, 0.14, 145)                 # #74C878 fresh green
LEAF = (0.955, 0.02, 90, 0.6)            # #F5F0E1 white, keeps 60% of gold's shading
BELLY = (0.955, 0.02, 90, 0.6)
BLUSH = (0.74, 0.12, 25)                 # soft pink
DECO_L = 0.55                            # "?", "zZ", tick boxes: a deeper green
K = 0.8                                  # share of the body's shading kept

# ---- measured on the source sheet
L_G, C_G, H_G = 0.458, 0.094, 150.6      # body green, interior median
L_TOE0, L_TOE1 = 0.20, 0.33              # outline core ends / body shading starts
L_Y, C_Y, H_Y = 0.812, 0.152, 80.8       # gold, interior median
L_Y1 = 0.68                              # bottom of the gold's shading range

# ---- coordinates on mascot-sheet-original.png (x0, y0, x1, y1)
PROP_BOXES = [(920, 840, 990, 960)]      # the pencil: gold, but a prop
STRAP_SEED, STRAP_ROI = (71, 848), (40, 820, 135, 955)
BACKPACK_ROI = (15, 825, 75, 935)
SMUDGE_BOX = (1444, 819, 1460, 839)

EIGHT = np.ones((3, 3))


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def hermite(x, x0, x1, y0, y1, m0, m1):
    t = np.clip((x - x0) / (x1 - x0), 0, 1)
    d = x1 - x0
    h00 = 2 * t ** 3 - 3 * t ** 2 + 1
    h10 = t ** 3 - 2 * t ** 2 + t
    h01 = -2 * t ** 3 + 3 * t ** 2
    h11 = t ** 3 - t ** 2
    return h00 * y0 + h10 * d * m0 + h01 * y1 + h11 * d * m1


def remap_L(L, Lt, k):
    """Body lightness: shading kept around the new base, toe into the outline."""
    shade = Lt + k * (L - L_G)
    y1 = Lt + k * (L_TOE1 - L_G)
    toe = hermite(L, L_TOE0, L_TOE1, L_TOE0, y1, 1.0, k)
    out = np.where(L >= L_TOE1, shade, np.where(L <= L_TOE0, L, toe))
    return np.clip(out, 0, 0.975)


def remap_LY(L, Lt, k):
    """Gold lightness, the same idea with the gold's own range."""
    y1 = Lt + k * (L_Y1 - L_Y)
    toe = hermite(L, 0.20, L_Y1, 0.20, y1, 1.0, k)
    out = np.where(L >= L_Y1, Lt + k * (L - L_Y), np.where(L <= 0.20, L, toe))
    return np.clip(out, 0, 0.985)


def pad_slices(sl, n):
    return tuple(slice(max(s.start - n, 0), s.stop + n) for s in sl)


def analyse(rgb, A):
    lab = srgb_to_oklab(rgb)
    L, C, H = lch(lab)
    dh = np.abs(((H - H_G) + 180) % 360 - 180)
    w_green = (1 - smoothstep(22, 45, dh)) * smoothstep(0.012, 0.03, C)
    alpha_w = smoothstep(150, 220, A)
    paint = (w_green > 0.5) & (L > 0.25) & (L < 0.62) & (A > 150)
    # green on air or paper is decoration, green inside the outline is body
    lab_c, _ = ndi.label(paint, structure=EIGHT)
    deco = np.zeros_like(paint)
    open_px = (A < 100) | ((L > 0.82) & (C < 0.06))
    for i, sl in enumerate(ndi.find_objects(lab_c), 1):
        pad = pad_slices(sl, 4)
        comp = lab_c[pad] == i
        ring = ndi.binary_dilation(comp, iterations=3) & ~comp
        if ring.sum() and open_px[pad][ring].mean() > 0.4:
            deco[pad] |= comp
    return dict(lab=lab, L=L, C=C, H=H, w_green=w_green, alpha_w=alpha_w, paint=paint,
                deco=deco, deco_zone=ndi.binary_dilation(deco, iterations=2))


def find_cheeks(an):
    """Blushes fully surrounded by green paint: holes in the paint mask."""
    L, C, H = an['L'], an['C'], an['H']
    paint = an['paint'] & ~an['deco']
    holes = ndi.binary_fill_holes(paint) & ~paint
    lab_h, _ = ndi.label(holes, structure=EIGHT)
    cheeks = []
    for i, sl in enumerate(ndi.find_objects(lab_h), 1):
        comp = lab_h[sl] == i
        if not (25 <= comp.sum() <= 1500):
            continue
        Lc, Cc, Hc = L[sl][comp], C[sl][comp], H[sl][comp]
        dark = (Lc < 0.32).mean()
        gold = ((Hc > 62) & (Hc < 92) & (Cc > 0.12) & (Lc > 0.72)).mean()
        hue = np.median(Hc)
        if dark < 0.05 and gold < 0.3 and 10 <= hue <= 118 and np.median(Cc) > 0.045:
            cheeks.append((sl, comp, hue))
    return cheeks


def gold_parts(an, A, cheeks):
    """(leaf zone, belly zone): the character's gold, each dilated 3 px."""
    L, C, H = an['L'], an['C'], an['H']
    dh = np.abs(((H - H_Y) + 180) % 360 - 180)
    gold = (dh < 25) & (C > 0.08) & (L > 0.55) & (A > 150)
    cheek_mask = np.zeros(A.shape, bool)
    for sl, comp, _ in cheeks:
        cheek_mask[sl] |= comp
    cheek_mask = ndi.binary_dilation(cheek_mask, iterations=3)
    open_px = (A < 100) | ((L > 0.82) & (C < 0.06))
    lab_c, _ = ndi.label(gold, structure=EIGHT)
    leaf = np.zeros(A.shape, bool)
    belly = np.zeros(A.shape, bool)
    for i, sl in enumerate(ndi.find_objects(lab_c), 1):
        comp = lab_c[sl] == i
        px = comp.sum()
        if px < 40:
            continue
        box = (sl[1].start, sl[0].start, sl[1].stop, sl[0].stop)
        pad = pad_slices(sl, 12)
        full = lab_c[pad] == i
        ring10 = ndi.binary_dilation(full, iterations=10) & ~ndi.binary_dilation(full, iterations=6)
        if open_px[pad][ring10].mean() >= 0.95:
            continue                                        # effect: sparkle, lines
        if cheek_mask[sl][comp].mean() > 0.3:
            continue                                        # an olive cheek
        if any(b[0] <= box[0] and b[1] <= box[1] and box[2] <= b[2] and box[3] <= b[3] for b in PROP_BOXES):
            continue                                        # the pencil
        mL, mC, mH = np.median(L[sl][comp]), np.median(C[sl][comp]), np.median(H[sl][comp])
        if not (0.72 <= mL <= 0.88 and 72 <= mH <= 92 and mC > 0.12):
            continue                                        # wood, backpack
        fill = px / ((box[2] - box[0]) * (box[3] - box[1]))
        (leaf if px > 3000 and fill < 0.6 else belly)[sl] |= comp
    leaf_z = ndi.binary_dilation(leaf, iterations=3)
    return leaf_z, ndi.binary_dilation(belly, iterations=3) & ~leaf_z


def cheeks_touching_green(an, A, cheeks, gold_zone):
    """Blushes half hidden behind a prop: cheek-coloured blobs touching green."""
    L, C, H = an['L'], an['C'], an['H']
    paint = an['paint'] & ~an['deco']
    found = np.zeros(A.shape, bool)
    for sl, comp, _ in cheeks:
        found[sl] |= comp
    cand = ((A > 200) & (H > 10) & (H < 118) & (C > 0.045) & (C < 0.2) & (L > 0.52) & (L < 0.8)
            & ~gold_zone & ~an['deco_zone'])
    lab, _ = ndi.label(cand, structure=EIGHT)
    extra = []
    for i, sl in enumerate(ndi.find_objects(lab), 1):
        comp = lab[sl] == i
        if not (15 <= comp.sum() <= 1500) or found[sl][comp].any():
            continue
        pad = pad_slices(sl, 3)
        full = np.zeros(A.shape, bool)
        full[sl] = comp
        cp = full[pad]
        ring = ndi.binary_dilation(cp, iterations=2) & ~cp
        if paint[pad][ring].mean() >= 0.25:
            extra.append((sl, comp, float(np.median(H[sl][comp]))))
    return extra


def disk(r):
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
    return xx * xx + yy * yy <= r * r


def recolor(src):
    Lt, Ct, ht = BODY
    im = np.asarray(Image.open(src).convert('RGBA')).astype(np.float64)
    rgb, A = im[..., :3], im[..., 3].copy()
    an = analyse(rgb, A)
    lab, L, C, H = an['lab'], an['L'], an['C'], an['H']
    leaf_z, belly_z = gold_parts(an, A, find_cheeks(an))
    gold_zone = leaf_z | belly_z

    # ---- green paint (body, leaf undersides, decorations) and gold paint
    body_new = from_lch(remap_L(L, Lt, K), Ct * np.clip(C / C_G, 0, 1.4), H + (ht - H_G))
    deco_new = from_lch(np.clip(L + (DECO_L - L_G), 0, 0.97),
                        min(Ct * 1.35, 0.14) * np.clip(C / C_G, 0, 1.4), H + (ht - H_G))
    wG = an['w_green'] * np.where(an['deco_zone'], 1.0, an['alpha_w'])
    g_new = np.where(an['deco_zone'][..., None], deco_new, body_new)
    dhY = np.abs(((H - H_Y) + 180) % 360 - 180)
    wY = (1 - smoothstep(22, 45, dhY)) * smoothstep(0.02, 0.05, C) * gold_zone
    y_new = np.zeros_like(lab)
    for zone, (tL, tC, th, tk) in ((leaf_z, LEAF), (belly_z, BELLY)):
        t = from_lch(remap_LY(L, tL, tk), tC * np.clip(C / C_Y, 0, 1.3), H + (th - H_Y))
        y_new = np.where(zone[..., None], t, y_new)
    s = np.maximum(wG + wY, 1.0)
    out = oklab_to_srgb(lab + (wG / s)[..., None] * (g_new - lab) + (wY / s)[..., None] * (y_new - lab))

    # ---- seams where gold met green: rebuild as a mix of the new neighbours
    Ypure = gold_zone & (dhY < 15) & (C > 0.1) & (L > 0.6)
    Gpure = an['paint'] & (an['w_green'] >= 0.9) & (np.abs(((H - H_G) + 180) % 360 - 180) <= 10)
    dY, iY = ndi.distance_transform_edt(~Ypure, return_indices=True)
    dG, iG = ndi.distance_transform_edt(~Gpure, return_indices=True)
    seam = (dY <= 2) & (dG <= 2) & ~Ypure & ~Gpure & (A > 0) & (L >= 0.3)
    ys, xs = np.nonzero(seam)
    yc, gc = lab[iY[0][seam], iY[1][seam]], lab[iG[0][seam], iG[1][seam]]
    out_lab = srgb_to_oklab(out)
    yn, gn = out_lab[iY[0][seam], iY[1][seam]], out_lab[iG[0][seam], iG[1][seam]]
    c = lab[seam]
    seg = gc - yc
    t = np.clip(((c - yc) * seg).sum(1) / np.maximum((seg * seg).sum(1), 1e-9), 0, 1)[:, None]
    dL = np.minimum(c[:, 0] - (yc[:, 0] + t[:, 0] * seg[:, 0]), 0)   # the rim crease
    new = yn + t * (gn - yn)
    new[:, 0] += 0.8 * dL
    out[ys, xs] = oklab_to_srgb(new)

    # ---- leftover olive in the gold zones: keep lightness, take the body hue
    zone = ndi.binary_dilation(gold_zone, iterations=2)
    oL, oC, oH = lch(srgb_to_oklab(out))
    snap = zone & (A > 0) & (oH > 95) & (oH < 138) & (oC > 0.03)
    out[snap] = oklab_to_srgb(from_lch(oL[snap], np.minimum(oC[snap], Ct), np.full(int(snap.sum()), float(ht))))

    # ---- cheeks: pink over the new green, following each blush's own profile
    P_new = oklab_to_srgb(from_lch(np.array(BLUSH[0]), np.array(BLUSH[1]), np.array(BLUSH[2])))
    paint = an['paint'] & ~an['deco']
    allowed = (L >= 0.45) & (C >= 0.03) & ~gold_zone & ~an['deco_zone']
    cheeks = find_cheeks(an)
    cheeks += cheeks_touching_green(an, A, cheeks, gold_zone)
    for sl, comp, _ in cheeks:
        pad = pad_slices(sl, 8)
        full = np.zeros(A.shape, bool)
        full[sl] = comp
        cp = full[pad]
        ring = ndi.binary_dilation(cp, iterations=7) & ~ndi.binary_dilation(cp, iterations=3) & paint[pad]
        if ring.sum() < 10:
            continue
        G_old = np.median(rgb[pad][ring], 0)
        G_new = np.median(out[pad][ring], 0)
        c = rgb[pad]
        d = np.linalg.norm(c[cp] - G_old, axis=1)
        P_old = np.median(c[cp][d >= np.percentile(d, 70)], 0)
        v = P_old - G_old
        beta = ndi.gaussian_filter(np.clip(((c - G_old) @ v) / (v @ v), 0, 1), 0.6)
        cheek_rgb = G_new + beta[..., None] * (P_new - G_new)
        dist = ndi.distance_transform_edt(~cp)
        feather_zone = ndi.binary_dilation(cp, iterations=4) & allowed[pad]
        feather = (np.clip(1 - (dist - 1) / 2.5, 0, 1) * feather_zone)[..., None]
        out[pad] = out[pad] * (1 - feather) + cheek_rgb * feather

    # ---- the walking pose's strap: one solid brown band
    x0, y0, x1, y1 = STRAP_ROI
    Dm = ((L < 0.24) | (A < 128))[y0:y1, x0:x1]
    lab_s, _ = ndi.label(~Dm)
    strap = lab_s == lab_s[STRAP_SEED[1] - y0, STRAP_SEED[0] - x0]
    strap = ndi.binary_closing(np.pad(strap, 6), structure=disk(4))[6:-6, 6:-6]
    bx0, by0, bx1, by1 = BACKPACK_ROI
    bL, bC, bH = L[by0:by1, bx0:bx1], C[by0:by1, bx0:bx1], H[by0:by1, bx0:bx1]
    brown = (bH > 45) & (bH < 75) & (bC > 0.06) & (bL > 0.38) & (bL < 0.62)
    L_hi, L_lo = np.percentile(bL[brown], 70), np.percentile(bL[brown], 30)
    C_b, H_b = np.median(bC[brown]), np.median(bH[brown])
    ys, xs = np.nonzero(strap)
    t = (ys - ys.min()) / max(ys.max() - ys.min(), 1)
    din = ndi.distance_transform_edt(np.pad(strap, 1))[1:-1, 1:-1][ys, xs]
    Ls = L_hi - t * (L_hi - L_lo) - 0.05 * np.clip(1 - (din - 1) / 2, 0, 1)
    fill = oklab_to_srgb(from_lch(Ls, np.full_like(Ls, C_b), np.full_like(Ls, H_b)))
    ink = np.median(rgb[y0:y1, x0:x1][Dm & (A[y0:y1, x0:x1] > 200)], 0)
    fill = np.where((din <= 1.0)[..., None], 0.6 * fill + 0.4 * ink, fill)
    out[y0:y1, x0:x1][ys, xs] = fill

    # ---- the smudge beside "zZ"
    sx0, sy0, sx1, sy1 = SMUDGE_BOX
    A[sy0:sy1, sx0:sx1] = np.where(A[sy0:sy1, sx0:sx1] <= 80, 0, A[sy0:sy1, sx0:sx1])

    print(f"seam px {int(seam.sum())}, olive snapped {int(snap.sum())}, cheeks {len(cheeks)}, strap px {int(strap.sum())}")
    return np.dstack([np.clip(np.round(out), 0, 255), A]).astype(np.uint8)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src", type=pathlib.Path, default=SRC)
    ap.add_argument("--out", type=pathlib.Path, default=OUT)
    args = ap.parse_args()
    Image.fromarray(recolor(args.src)).save(args.out, optimize=True)
    print("wrote", args.out)
