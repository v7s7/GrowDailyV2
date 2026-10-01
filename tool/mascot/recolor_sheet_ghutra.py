#!/usr/bin/env python3
"""Make the ghutra sheet transparent, then match its body green to the palette.

    python tool/mascot/recolor_sheet_ghutra.py    # writes design/mascot/sheet-ghutra/sheet-ghutra-final.png

Needs numpy, scipy and Pillow. Step 1 for the ghutra sheet; then run
`cut_poses.py --sheet ghutra`, `fix_poses_ghutra.py` (which gives the
firelight back the colour the cut paints over at the poses' edges) and
`upscale_poses.py --sheet ghutra`.
`--debug DIR` also writes the masks this step decides on, as PNGs.

The source is design/mascot/sheet-ghutra/sheet-ghutra-original.png, the
ChatGPT sheet Aziz generated on 2026-09-29 (byte-identical to the download
"ChatGPT Image 29 سبتمبر 2026، 09_47_26 م.png"): 12 poses in three rows of
four, Doum in a white ghutra, black agal and a black bisht with gold trim
and a cream fur collar, by a small campfire. Unlike sheets 1 and 2 it is RGB
with NO transparency: the poses sit on a near-white ground, measured on the
sheet's border as RGB 254 254 254 (standard deviation about 1 per channel).

THE MATTE, AND WHY NOT BY COLOUR
The ghutra, the fur collar and the eye highlights are white on that white
ground, so keying out "white" would eat them. The ground is found instead as
what reaches the sheet border without crossing the drawing:

  barrier    OKLab L under 0.70 or chroma over 0.08: every outline (L 0 to
             0.45), the bisht and agal, the fire, the sparkles and glyphs,
             plus the SEALS and FLAME_PAINT boxes below. The shadows' lighter
             body (L 0.71 to 0.97, warm) and the smoke (L 0.76 to 0.88,
             grey) stay out of it, so the flood reaches them. The contact
             shadow's core right under a pose is darker and is in it; it
             joins the ground afterwards (THE CONTACT SHADOW'S CORE).
  exterior   the barrier's complement, 4-connected, in pieces that touch the
             sheet border, plus the enclosed pockets of ground listed below,
             plus the contact shadow's core.
  interior   everything else: fully opaque, never keyed.

Five short lines (SEALS) close the places where the flood got into the
drawing, each drawn on the faint outline itself so it becomes the edge.
Left out one at a time, each opens a piece of the drawing: the ghutra's
lower left edge in the warming-hands and in the heart pose, where its
outline thins to L 0.70 to 0.82 for 5 to 8 px before the bisht (12,240 and
10,190 px of opaque ghutra go see-through); the blowing pose's cheek
outline, which the breath streak crosses twice (about 580 px of cheek
each); and its mitten's outline, which holds until the glow below is taken
out and then lets the flood 124 px in (364 px of mitten go see-through), so
the script stops (GLOW_LEAK, below). Growing the barrier by 3 px
everywhere instead also sealed a lit strip of ground beside the first
pose's campfire (it came out as an opaque cream wedge), so the seals are
explicit.

THE FIRELIGHT'S GLOW
Light warm paint beside a flame (L over 0.86, hue 40 to 100, chroma 0.08 to
0.12) is in the barrier by its chroma, yet where a piece of it touches both
a flame's saturated body (chroma over 0.14, hue 25 to 95, L over 0.55) and
the ground, it is light cast on the ground, not paint. Those pieces (2,725
px) leave the barrier and the flood runs again. If that opens more than 100
px of the drawing beyond the glow itself, the script stops; it opens 45,
the pockets between a flame's outer tongues, and 169 without the mitten's
seal.

One flame breaks that rule. In the hourglass pose, a pale inner tongue runs
between the flame's left orange tongue and its pink tongue (x 326 to 336, y
860 to 883): paint of the glow's own colour (L 0.86 to 0.92, C 0.07 to 0.11)
that meets the glow at the tongue's tip. Taken as glow, it came out at 22 to
43% alpha, a dark slot inside the flame on a dark card, and the 82 px of
paler paint down its middle were opened as a pocket. Its FLAME_PAINT box keeps
it paint, never glow, ground or edge. What would have been glow or ground in
it fades in over the box's top 4 rows, from its colour-to-alpha to opaque
(20% of the way on the top row, all of it on the fifth), so the tip melts
into the glow above with no line; the rest of the box stays as drawn.

THE CONTACT SHADOW'S CORE
Right under each pose, and under the logs, the soft shadow darkens to L 0.49
to 0.69 (chroma 0.035 to 0.075, hue 42 to 57: 5th to 95th percentile), below
the barrier's L 0.70. Left in the barrier, it was paint: 2,893 px of it came
out opaque beige beside the translucent shadow around it, crumbs on a dark
card and beige blotches on a cream one. So warm mid-tone paint (L 0.45 to
0.70, chroma 0.03 to 0.08, hue 35 to 100) that reaches the ground through
paint of its own kind joins the ground, with the 52 px of enclosed shadow
(L 0.70 to 0.73, bits of 30 px or less) caught between it. It joins as
itself only: flooding the barrier's complement again would run on through the
faint warm spots in the outline and open 39,251 px of drawing (the grey-cloud
pose's ghutra, the cold pose's and the flame-up pose's fur). For the same
reason, the 42 px that sit right against the drawing's light paint stay in
the barrier: the grey-cloud pose's ghutra hem (6), the flame-up pose's fur
hem (20) and a fur stroke of the cold pose (16), where the paint sits on the
shadow with no dark line. In all 5,638 px join; matted as shadow below, they
come out 67 to 90% opaque (median 75). The logs, the bisht and the firelit
patch painted under each campfire stay paint.

Enclosed pockets that are the ground colour (median OKLab distance from the
ground under 0.02) are listed when the script runs. Two kinds were found:
eye highlights inside the pupils (44 and 39 px, grey cloud and cold wind),
which stay opaque, and the inside of the dizzy spiral in the lying-down
pose, which is ground seen through the glyph and becomes transparent
(GROUND_POCKETS). No arm-and-body pocket exists on this sheet: of the 98
enclosed pockets over 30 px, the nearest to the ground colour is the
ghutra's own cloth (distance 0.027 to 0.045, a warmer white), then fur,
the hourglass's glass and firelit paint; none is ground or shadow.

ALPHA IN THE EXTERIOR
Every exterior pixel is matted against the measured ground G, so it
composites over G exactly as drawn. Colour-to-alpha: alpha is the largest
of (G - pixel) / G over the three channels, the colour is what that alpha
over G gives back. Where the exterior meets the drawing it is edge, then
the soft ground is shadow or firelight:

  edge       the barrier's first layer against the exterior (an outline
             pixel half over the ground reads L 0.5 to 0.7), light warm
             paint within 4 px of it (a flame's pale outer tongue) and the
             2 px of exterior beside the drawing. An edge pixel is a drawing
             colour F over the ground just beyond it, B: the matted ground
             (glow, shadow or bare) at the nearest exterior pixel more than
             2 px from the drawing, within 6 px, composited over G. Its
             alpha is its projection on the line from B to F, plus what B
             itself covers; its colour mixes F and B's colour by the same
             weights. Over bare ground B is G and this is the plain
             projection. The first layer takes colour-to-alpha, or this
             where larger, with F the nearest solid colour behind it, so an
             outline's ramp keeps the outline's colour and a flame's edge
             its orange. The 2 px beside the drawing take this with F the
             colour of the drawing pixel next to them, as matted: over
             firelight outright, elsewhere where its alpha is larger than
             the ground rule's. Measured against G alone, the mitten's brown
             outline over the yellow glow in the blowing pose left a grey-tan
             second line on a cream card, as the ground rule goes by the
             pixel's own hue and read the ramp as shadow. Over shadow the
             luminance already fits a dark outline's ramp. 55,509 px are
             edge, 3,786 of them over firelight; where F and B are under 40
             in RGB apart (170 px, pale flame paint over its own glow) the
             pixel cannot be parted and takes B. An edge pixel stored fully
             opaque keeps its own colour. The cut then repaints every
             semi-transparent pixel within 3 px of an opaque one in the
             nearest opaque colour; fix_poses_ghutra.py gives the firelight
             among them its colour back.
  shadow     ground darker than G at hue under 66 (or grey): alpha by
             luminance toward one dark warm grey (OKLCh 0.25 0.02 65), 5 to
             39% (median 15) away from the edge, 67 to 90% in the contact
             shadow's core. Colour-to-alpha would read the shadow's faint
             warmth through its blue channel, the one that darkens most, and
             give a saturated brown at a low alpha: a brown stain on a dark
             card rather than a shadow.
  firelight  ground at hue over 76 with chroma over 0.03 (the yellow the
             flames cast, L 0.94 to 0.98, hue 75 to 93): colour-to-alpha, 8
             to 24%, so it keeps its warm colour. Between hue 66 and 76 the
             two blend.

A light ring the generator left beside the outlines (1,211 exterior px at
RGB 255, lighter than the ground) takes only the ground beyond it:
transparent over bare ground, and where a shadow runs under it (527 px)
that shadow's dark grey at 1 to 11% alpha. None of it is lighter, so there
is no white halo on dark cards. Alpha under 0.02 (the ground's own noise,
standard deviation about 1 of 254) is cut.

The soft ground shadow stays, translucent, core and all, as sheets 1 and 2
keep theirs: these poses sit on the ground by a fire and the shadow is what
places them there on a cream card; on a dark card it is dark on dark and
fades out. The glow stays for the same reason: on a dark card the fire
keeps a faint warm halo, as a real flame would.

Smoke, steam and breath (grey, chroma under 0.03) and the wind swirls of the
cold pose (light blue, hue 240) are effects, not shadows: colour-to-alpha
would make them a translucent black or navy that vanishes on a dark card.
Their core is kept opaque in its own colour: seeded where the exterior is
under L 0.90, more than 2 px from the barrier and not warm (hue 35 to 100
with chroma over 0.03 is shadow or glow), in pieces of 6 px or more, then
grown through any hue under L 0.90, so a wisp keeps its whole length where
it rises through the glow and takes on its tint. The 3 px around a core take
alpha by projecting each pixel onto the line from the ground to the nearest
core colour, so the wisps keep their soft edge. The mug's steam in sheet 2
is drawn the same way (an opaque grey, L 0.87).

COLOUR
Measured on the interior (more than 4 px from any L < 0.40 outline):

    body green   L 0.811 C 0.131 h 139.8    palette #74C878: L 0.76 C 0.14 h 145
    fire         chroma over 0.14: h 28 to 95 (5th to 95th percentile), L 0.67 to 0.89
    firelit body h 95 to 130, where the campfire lights the face and mittens
    cheeks       L 0.79 to 0.84, C 0.09 to 0.12, h 41 to 60 (peach)

The three rows measure alike (L 0.810 to 0.814, h 137.7 to 140.8; row 2's
faces are the most firelit). The body moves onto the palette by the
difference from its median, in OKLab, keeping every offset, as
upscale_winter.py does for the winter pictures (which measured the same L
0.80 to 0.81, h 140 to 142): full weight within 12 degrees of the median
hue, none past 25 (so nothing under hue 115: the fire, the embers, the gold
trim at h 70 to 80 and the warmest firelight are never turned green), faded
out toward the outline between L 0.55 and 0.25, and nothing lighter than L
0.94 (the firelight's highlights). After, on the same pixels: L 0.760 C
0.140 h 145.0 (the script prints it); row 2 alone lands at h 142.5, as its
firelit offsets are kept. The falling leaves of the cold pose
are an effect and keep their own olive green (L 0.585 C 0.105 h 120.5). The
cheeks stay peach, as in the winter pictures (winter_blanket_heater's
measure h 43; the sheets' are pink, h 26 to 33). The ghutra, the fur, the
bisht and the props are not touched: of the 185,802 solid pixels at hue
under 110 with chroma over 0.05, the colour move changes none (the matte
changes 7, by at most 14 in RGB, where the hourglass pose's smoke meets its
flame); of the 1,811 solid blue ones and the 131,402 lighter than L 0.94,
none.
"""
import argparse
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

from oklab import from_lch, lch, oklab_to_srgb, srgb_to_lin, srgb_to_oklab

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "design/mascot/sheet-ghutra/sheet-ghutra-original.png"
OUT = ROOT / "design/mascot/sheet-ghutra/sheet-ghutra-final.png"

# ---- the palette (recolor_sheet.py's BODY, #74C878)
BODY_L, BODY_C, BODY_H = 0.76, 0.14, 145

# ---- the matte, measured on this sheet
BARRIER_L, BARRIER_C = 0.70, 0.08      # outlines, bisht, fire, glyphs
NOISE = 0.02                           # colour-to-alpha under this is the ground's noise
EFFECT_L, EFFECT_GAP, EFFECT_EDGE = 0.90, 2, 3
LIGHT_L, LIGHT_DEPTH = 0.80, 4         # light warm paint, and how deep it is matted toward the fire
SHADOW = (0.25, 0.02, 65)              # OKLCh: the ground shadow's colour, a dark warm grey
LIT_H = (66, 76)                       # ground hue: shadow below the first, firelight above the second
EDGE_BAND = 2                          # px of exterior beside the drawing matted toward it
WARM_H, WARM_C = (35, 100), 0.03       # shadow and glow, not an effect
FIRE_C, FIRE_H, FIRE_L = 0.14, (25, 95), 0.55          # the flames' saturated body
GLOW_L, GLOW_H, GLOW_C = 0.86, (40, 100), 0.12         # light warm paint beside it
GLOW_LEAK = 100                        # px the glow may open beyond itself (pockets between tongues: 45)
POCKET_D = 0.02                        # an enclosed pocket this close to the ground is listed
SHADE_L, SHADE_C = 0.45, 0.03          # the contact shadow's core: L 0.45 to 0.70, chroma 0.03 to 0.08, warm
SHADE_BIT = 30                         # an enclosed bit of shadow this small joins with it
BACK_REACH = 6                         # px an edge looks outward for the ground behind it
EDGE_SEP = 40                          # RGB distance under which paint and the ground behind it cannot be parted

# Short lines (x0, y0, x1, y1) on the sheet where the drawing's outline is too
# faint to stop the flood. Each is drawn 2 px wide into the barrier.
SEALS = [
    (405, 614, 414, 614),   # warming hands: the ghutra's lower left edge
    (794, 613, 802, 613),   # heart: the ghutra's lower left edge
    (266, 533, 270, 539),   # blowing: cheek outline under the breath streak
    (271, 542, 273, 547),   # blowing: the same outline, second crossing
    (272, 583, 265, 595),   # blowing: the mitten's outline under the breath streak
]
# Boxes (x0, y0, x1, y1) on the sheet: every enclosed pocket wholly inside
# one is ground seen through the drawing, not paint.
GROUND_POCKETS = [
    (1040, 695, 1105, 750),  # lying down: the four pockets inside the dizzy spiral
]
# Boxes (x0, y0, x1, y1) on the sheet: every pixel inside one is a flame's
# own paint, never glow or ground. Its pale paint fades in from the glow's
# matte over the box's top FLAME_FADE rows, as the tongue's tip melts into
# the glow above it with no line between them.
FLAME_PAINT = [
    (326, 860, 337, 884),    # hourglass: the pale inner tongue between the left and the pink tongue
]
FLAME_FADE = 4


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def seal_mask(shape):
    m = np.zeros(shape, bool)
    for x0, y0, x1, y1 in SEALS:
        n = int(4 * max(abs(x1 - x0), abs(y1 - y0))) + 1
        for t in np.linspace(0, 1, n):
            x, y = round(x0 + t * (x1 - x0)), round(y0 + t * (y1 - y0))
            m[y:y + 2, x:x + 2] = True
    return m


def box_mask(shape, boxes):
    m = np.zeros(shape, bool)
    for x0, y0, x1, y1 in boxes:
        m[y0:y1, x0:x1] = True
    return m


def ground_colour(rgb):
    """Median of the sheet's 4 px border, leaving out the drawing where a
    pose comes within 4 px of the edge."""
    strip = np.concatenate([rgb[:4].reshape(-1, 3), rgb[-4:].reshape(-1, 3),
                            rgb[:, :4].reshape(-1, 3), rgb[:, -4:].reshape(-1, 3)])
    return np.median(strip[strip.min(1) > 240], 0)


def flood(barrier):
    """The ground: the barrier's complement, 4-connected, in the pieces that
    touch the sheet border or fill a GROUND_POCKETS box."""
    parts, n = ndi.label(~barrier)
    edge = np.unique(np.concatenate([parts[0], parts[-1], parts[:, 0], parts[:, -1]]))
    outside = set(edge[edge > 0].tolist())
    objs = ndi.find_objects(parts)
    for x0, y0, x1, y1 in GROUND_POCKETS:
        found = [i for i in range(1, n + 1) if i not in outside
                 and objs[i - 1][1].start >= x0 and objs[i - 1][1].stop <= x1
                 and objs[i - 1][0].start >= y0 and objs[i - 1][0].stop <= y1]
        if not found:
            raise SystemExit(f"no enclosed pocket inside ({x0}, {y0}, {x1}, {y1})")
        outside.update(found)
    return np.isin(parts, list(outside)), parts, n, outside


def matte(rgb, debug=None):
    lab = srgb_to_oklab(rgb)
    L, C, H = lch(lab)
    G = ground_colour(rgb)
    Glab = srgb_to_oklab(G)
    dist = np.linalg.norm(lab - Glab, axis=-1)

    seals = seal_mask(L.shape)
    flame = box_mask(L.shape, FLAME_PAINT)
    eight = np.ones((3, 3))
    barrier = (L < BARRIER_L) | (C > BARRIER_C) | seals | flame
    first, _, _, _ = flood(barrier)

    # the firelight's glow: light warm paint that touches both a flame's
    # saturated body and the ground is light on the ground, not paint
    fire = (C > FIRE_C) & (H > FIRE_H[0]) & (H < FIRE_H[1]) & (L > FIRE_L)
    glowlike = (barrier & ~seals & ~flame & (L > GLOW_L) & (H > GLOW_H[0]) & (H < GLOW_H[1])
                & (C < GLOW_C))
    g_parts, _ = ndi.label(glowlike, structure=eight)
    at_fire = np.unique(g_parts[ndi.binary_dilation(fire, structure=eight) & glowlike])
    at_ground = np.unique(g_parts[ndi.binary_dilation(first, structure=eight) & glowlike])
    glow = np.isin(g_parts, np.intersect1d(at_fire[at_fire > 0], at_ground[at_ground > 0]))
    barrier &= ~glow
    exterior, parts, n, outside = flood(barrier)
    grown = exterior & ~first & ~glow
    if grown.sum() > GLOW_LEAK:
        raise SystemExit(f"taking the glow out opened {grown.sum()} px of the drawing to the ground")
    objs = ndi.find_objects(parts)

    # the contact shadow's core: warm mid-tone paint that reaches the ground
    # through its own kind only (never through what it would open), minus
    # the pixels where the drawing's light paint sits right on it
    enclosed, _ = ndi.label(~barrier & ~exterior)
    sizes = np.bincount(enclosed.ravel())
    sizes[0] = 0
    shadelike = (barrier & ~seals & ~flame & (L >= SHADE_L) & (C >= SHADE_C) & (C <= BARRIER_C)
                 & (H > WARM_H[0]) & (H < WARM_H[1]))
    shadelike &= ~ndi.binary_dilation(sizes[enclosed] > SHADE_BIT)
    bits = (enclosed > 0) & (sizes[enclosed] <= SHADE_BIT)
    joined, _ = ndi.label(exterior | shadelike | bits)
    keep = np.unique(joined[exterior])
    shade = np.isin(joined, keep[keep > 0]) & ~exterior
    exterior |= shade
    barrier &= ~shade

    # enclosed pockets of ground colour, for the record
    inside = [i for i in range(1, n + 1) if i not in outside]
    med = ndi.median(dist, parts, inside)
    for i, m in zip(inside, med):
        if m < POCKET_D:
            sl = objs[i - 1]
            size = int((parts[sl] == i).sum())
            if size >= 6:
                print(f"  enclosed ground-coloured pocket: {size:4d} px at x {sl[1].start}-{sl[1].stop}"
                      f" y {sl[0].start}-{sl[0].stop} (median distance {m:.3f})")

    # colour-to-alpha against the ground
    Gs = np.maximum(G, 1.0)
    a_c2a = np.clip(((G - rgb) / Gs).max(-1), 0, 1)
    a_c2a = np.clip((a_c2a - NOISE) / (1 - NOISE), 0, 1)
    with np.errstate(divide='ignore', invalid='ignore'):
        x_c2a = np.where(a_c2a[..., None] > 0, G + (rgb - G) / np.maximum(a_c2a, 1e-6)[..., None], G)
    x_c2a = np.clip(x_c2a, 0, 255)

    def toward(F):
        """Alpha of each pixel as a mix of colour F over the ground: its
        projection on the line from the ground to F."""
        FG = F - G
        return np.clip(((rgb - G) * FG).sum(-1) / np.maximum((FG * FG).sum(-1), 1e-6), 0, 1)

    # the drawing's edge: the barrier's first layer against the exterior is
    # anti-aliasing (an outline pixel half over the ground reads L 0.5 to
    # 0.7, a flame's edge pale orange), and the exterior just outside it
    layer = barrier & ~flame & ndi.binary_dilation(exterior, structure=eight)
    # light warm paint next to the ground (a flame's pale outer tongue, the
    # glow's brightest ring) is matted deeper, toward the fire behind it;
    # a FLAME_PAINT box is paint throughout and never edge
    light = barrier & ~flame & (L > LIGHT_L) & (H > GLOW_H[0]) & (H < GLOW_H[1])
    layer |= light & (ndi.distance_transform_edt(~exterior) <= LIGHT_DEPTH)
    deep = barrier & ~layer
    _, idx = ndi.distance_transform_edt(~deep, return_indices=True)
    F_edge = rgb[idx[0], idx[1]]
    band = exterior & (ndi.distance_transform_edt(~barrier) <= EDGE_BAND)

    # effects in the exterior: smoke, steam, breath, wind swirls
    off_barrier = ndi.distance_transform_edt(~barrier) > EFFECT_GAP
    warm = (H > WARM_H[0]) & (H < WARM_H[1]) & (C > WARM_C)
    seed = exterior & (L < EFFECT_L) & off_barrier & ~warm
    lab_s, ns = ndi.label(seed, structure=eight)
    sizes = ndi.sum(seed, lab_s, range(1, ns + 1))
    seed = np.isin(lab_s, [i + 1 for i in range(ns) if sizes[i] >= 6])
    # a wisp keeps its whole length where it rises through the glow and
    # takes on its warm tint: grown from the grey seed through any hue
    reach = exterior & (L < EFFECT_L) & off_barrier
    lab_c, _ = ndi.label(reach, structure=eight)
    core = np.isin(lab_c, np.unique(lab_c[seed]))
    d_core, idx = ndi.distance_transform_edt(~core, return_indices=True)
    F_core = rgb[idx[0], idx[1]]
    a_core = toward(F_core)
    near = exterior & ~core & (d_core <= EFFECT_EDGE)

    # the soft ground is shadow (darkness) or firelight (light). Shadow is
    # matted by luminance toward one dark warm grey, so it darkens a card as
    # a shadow does and fades out on a dark one; firelight (the yellower hue
    # the flames cast on the ground) keeps colour-to-alpha's warm colour
    lin = lambda c: srgb_to_lin(c) @ np.array([0.2126, 0.7152, 0.0722])
    S = oklab_to_srgb(from_lch(np.array(SHADOW[0]), np.array(SHADOW[1]), np.array(SHADOW[2])))
    YG, YS = lin(G), lin(S)
    a_dark = np.clip((YG - lin(rgb)) / (YG - YS), 0, 1)
    a_dark = np.clip((a_dark - NOISE) / (1 - NOISE), 0, 1)
    w = smooth(*LIT_H, H) * smooth(0.01, 0.03, C)
    a_ground = w * a_c2a + (1 - w) * a_dark
    with np.errstate(divide='ignore', invalid='ignore'):
        pm = (w * a_c2a)[..., None] * x_c2a + ((1 - w) * a_dark)[..., None] * S
        x_ground = np.where(a_ground[..., None] > 0, pm / np.maximum(a_ground, 1e-6)[..., None], G)

    # an edge lies over the ground just beyond it (glow, shadow or bare
    # ground), so it is a drawing colour F over that, not over G: the
    # projection of the pixel on the line from that ground to F
    ground = exterior & ~core
    far = ground & ~near & (ndi.distance_transform_edt(~barrier) > EDGE_BAND)
    d_far, idx = ndi.distance_transform_edt(~far, return_indices=True)
    a_b = np.where(d_far <= BACK_REACH, a_ground[idx[0], idx[1]], 0)
    x_b = x_ground[idx[0], idx[1]]
    lit = (d_far <= BACK_REACH) & (w[idx[0], idx[1]] >= 0.5) & (a_b > 0)
    B = a_b[..., None] * x_b + (1 - a_b[..., None]) * G
    parted = []

    def over_ground(F):
        FB = F - B
        sep = (FB * FB).sum(-1)
        parted.append(sep >= EDGE_SEP ** 2)
        a_e = np.where(parted[-1], np.clip(((rgb - B) * FB).sum(-1) / np.maximum(sep, 1e-6), 0, 1), 0)
        a = a_e + (1 - a_e) * a_b
        return a, (a_e[..., None] * F + ((1 - a_e) * a_b)[..., None] * x_b) / np.maximum(a, 1e-6)[..., None]

    alpha = np.ones(L.shape)
    colour = rgb.copy()
    alpha[ground] = a_ground[ground]
    colour[ground] = x_ground[ground]
    # the drawing's first layer: colour-to-alpha, or where larger its deeper
    # colour over the ground behind it
    alpha[layer] = a_c2a[layer]
    colour[layer] = x_c2a[layer]
    a_new, x_new = over_ground(F_edge)
    wins = layer & (a_new > alpha)
    alpha[wins] = a_new[wins]
    colour[wins] = x_new[wins]
    # an edge pixel stored fully opaque keeps its own colour (by the stored
    # alpha: one just under 1 is 255 too)
    solid = layer & (alpha >= 254.5 / 255)
    colour[solid] = rgb[solid]
    # the band beside the drawing: the colour of the drawing pixel next to it
    # (as matted just above) over the ground behind it. Over firelight it
    # decides outright: the ground rule goes by the pixel's own hue, and an
    # outline's brown ramp over the yellow glow reads as shadow and takes the
    # shadow's grey. Over shadow or bare ground it wins where its alpha is
    # larger, as the shadow's luminance already fits a dark outline's ramp
    _, idx = ndi.distance_transform_edt(~barrier, return_indices=True)
    a_new, x_new = over_ground(colour[idx[0], idx[1]])
    edge = band & ~near & (lit | (a_new > alpha))
    alpha[edge] = a_new[edge]
    colour[edge] = x_new[edge]
    solid = edge & (alpha >= 254.5 / 255)
    colour[solid] = rgb[solid]
    print(f"  edge px {int((band | layer).sum())} ({int((band & lit).sum())} over firelight), of which"
          f" paint too close to the ground behind to part: {int(((layer & ~parted[0]) | (edge & ~parted[1])).sum())}")
    wins = near & (a_core > alpha)
    alpha[wins] = a_core[wins]
    colour[wins] = F_core[wins]
    # a flame's pale paint (what would have been glow or ground) fades in
    # from its colour-to-alpha: alpha a + (1 - a) t, t rising from 1/5 at the
    # box's top row to 1 on its fifth, the colour what that alpha over G
    # gives back (never out of gamut, as the alpha is never under a)
    t = np.ones(L.shape)
    for x0, y0, x1, y1 in FLAME_PAINT:
        t[y0:y1, x0:x1] = np.clip((np.arange(y1 - y0) + 1) / (FLAME_FADE + 1), 0, 1)[:, None]
    pale = flame & (((L > GLOW_L) & (H > GLOW_H[0]) & (H < GLOW_H[1]) & (C < GLOW_C))
                    | ((L >= BARRIER_L) & (C <= BARRIER_C)))
    alpha[pale] = (a_c2a + (1 - a_c2a) * t)[pale]
    colour[pale] = np.clip(G + (rgb - G) / np.maximum(alpha, 1e-6)[..., None], 0, 255)[pale]
    print(f"  ground RGB {G[0]:.0f} {G[1]:.0f} {G[2]:.0f}; exterior {exterior.sum()} px"
          f" (glow {glow.sum()} px, pockets it opened {grown.sum()} px, shadow core {shade.sum()} px),"
          f" effect cores {core.sum()} px, {len(SEALS)} seals")
    if debug:
        debug.mkdir(parents=True, exist_ok=True)
        view = rgb.copy()
        view[exterior] = view[exterior] * 0.3 + np.array([255, 0, 255]) * 0.7
        view[core] = (0, 90, 255)
        view[glow] = (0, 220, 255)
        view[shade] = (255, 200, 0)
        view[seal_mask(L.shape) | flame] = (255, 0, 0)
        Image.fromarray(view.astype(np.uint8)).save(debug / "matte_regions.png")
    return colour, alpha


def recolor(rgb, alpha):
    """Moves the body's green onto the palette, keeping its shading."""
    L, C, H = lch(srgb_to_oklab(rgb))
    off = lambda h0: np.abs((H - h0 + 180) % 360 - 180)
    solid = alpha >= 1
    dark = solid & (L < 0.40)
    interior = solid & (ndi.distance_transform_edt(~dark) > 4)
    body = interior & (off(BODY_H) < 22) & (C > 0.06) & (L < 0.90)
    Lm, Cm, Hm = np.median(L[body]), np.median(C[body]), np.median(H[body])

    # the characters are the pieces over 10,000 px (cut_poses.py's rule);
    # everything else, like the falling leaves, keeps its colour
    art = alpha > 16 / 255
    parts, n = ndi.label(art, structure=np.ones((3, 3)))
    sizes = ndi.sum(art, parts, range(1, n + 1))
    character = np.isin(parts, [i + 1 for i in range(n) if sizes[i] > 10000])

    w = (np.clip((25 - off(Hm)) / (25 - 12), 0, 1) * smooth(0.03, 0.06, C)
         * smooth(0.25, 0.55, L) * (1 - smooth(0.90, 0.94, L)) * character)
    L2 = L + w * (BODY_L - Lm)
    C2 = C * (1 + w * (BODY_C / Cm - 1))
    H2 = H + w * (BODY_H - Hm)
    out = oklab_to_srgb(from_lch(L2, C2, H2))
    rgb2 = np.where((w > 0)[..., None], out, rgb)
    after = lch(srgb_to_oklab(rgb2))
    print(f"  body L {Lm:.3f} C {Cm:.3f} h {Hm:.1f} -> L {np.median(after[0][body]):.3f}"
          f" C {np.median(after[1][body]):.3f} h {np.median(after[2][body]):.1f}"
          f"; {int((w > 0).sum())} px moved")
    return rgb2


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src", type=pathlib.Path, default=SRC)
    ap.add_argument("--out", type=pathlib.Path, default=OUT)
    ap.add_argument("--debug", type=pathlib.Path, default=None, help="a folder for the mask images")
    args = ap.parse_args()
    rgb = np.asarray(Image.open(args.src).convert('RGB')).astype(np.float64)
    colour, alpha = matte(rgb, args.debug)
    colour = recolor(colour, alpha)
    out = np.dstack([np.clip(np.round(colour), 0, 255), np.round(alpha * 255)]).astype(np.uint8)
    Image.fromarray(out).save(args.out, optimize=True)
    print(f"wrote {args.out}")
