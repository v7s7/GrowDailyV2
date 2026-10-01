#!/usr/bin/env python3
"""Upscale the cut mascot poses: 4x masters plus the copies the app ships.

    python tool/mascot/upscale_poses.py                           # all 18
    python tool/mascot/upscale_poses.py --only mascot_laptop      # one pose
    python tool/mascot/upscale_poses.py --sheet 2                 # the second sheet
    python tool/mascot/upscale_poses.py --sheet sport             # also streak, ghutra

Needs torch, numpy, scipy and Pillow. Step 3 of 3: reads design/mascot/
poses-native/ (cut_poses.py), writes design/mascot/poses-4x/ (PNG masters,
not bundled) and assets/images/mascot/ (the app copies, lossless WebP: the
same pixels as PNG in 61% of the bytes, and Flutter decodes WebP on every
platform it ships to; lossy WebP would be a fifth of the size but blurs
colour at sharp edges through its chroma subsampling). The first run downloads
the model weights (17.9 MB) into ~/.cache/growdaily/, outside the repo; see
esrgan.py for how they are verified and loaded.

WHY THE ANIME MODEL, AND WHAT IT GETS WRONG
Real-ESRGAN's x4plus_anime_6B is trained on drawn art with ink outlines, which
is what this character is, and it returns crisp outlines and smooth fills
where a plain resize returns blur. Colour and alpha each go through it (alpha
as a grey image). Its one fault here is overshoot: a light ring beside dark
shapes, plainest around the eyes and mouth (L 0.78 to 0.81 on a 0.72 to 0.76
body). Every output value is clamped to the min and max of the 3x3 original
pixels around it, which removes the ring and keeps the sharp edge. Colour
drift after the clamp is at most 0.004 in OKLab, far below what the eye sees.

ONE CHARACTER SIZE IN EVERY APP COPY
The source sheet drew its three rows at different scales. By eye height, eye
spacing and belly width on the front-facing poses, the turnaround row is
1.385x the activity row and the expression row 1.103x (geometric means of the
three). Each app copy is scaled so the character matches across all 18, at 3x
the activity row's original size (about 380 to 850 px, like the app's other
illustrations), with a 12 px margin. Show them with one shared scale, e.g.
Image.asset(path, scale: 4), never one shared height, or tall poses shrink
the character and the sleeping one grows it.

THE HOME SCREEN WIDGET'S TWO
The widget is a separate native target and cannot read Flutter's assets, so
the poses it draws (happy when the day is done, asleep late or on a day with
nothing asked) are written into its own asset catalog as PNGs, from the app
copies (the files already at one shared character scale), at that scale (the front pose would be 230px tall): 240px for
the happy pose, 204px for the sleeping one. SwiftUI draws each at a fixed
height (WidgetSprout in GrowDailyWidget.swift did, until Doum left the
widget on 2026-09-29; the images stay for his return), so the character stays
one size between the two. `--only` skips them unless it names their pose.

THE SECOND SHEET (2026-09-29)
`--sheet 2` reads design/mascot/sheet-2/poses-native/ and writes its masters
to design/mascot/sheet-2/poses-4x/. It drew two sizes: rows 1 and 2 about
11% bigger than rows 3 and 4. Each row's app scale (app px per sheet px) is
set so its character matches the first sheet's app copies, from eye height,
eye spacing, belly width, leaf area and green area on every pose where each
can be measured, and checked by fitting the five poses the sheet repeats from
the first one (front wave, confused, laptop, love heart, sleeping) over their
first-sheet copies: 2.90, 2.93, 3.25 and 3.25. Leaf area alone said 3.66 for
row 4 and green area 2.90; that row draws shorter leaves on a chunkier body,
so row 4 was settled by eye beside the first sheet's poses, where 3.25 matches
(the love heart fit says 3.30). Only poses marked "app" in poses-2.json get an
app copy; the five repeats keep a master only. The widget's two are the first
sheet's.
"""
import argparse
import json
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

import esrgan

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SRC = ROOT / "design/mascot/poses-native"
MASTERS = ROOT / "design/mascot/poses-4x"
APP = ROOT / "assets/images/mascot"
WIDGET_CATALOG = ROOT / "ios/GrowDailyWidget/Assets.xcassets"
WIDGET_POSES = {"SproutHappy": "mascot_happy_sparkles", "SproutSleeping": "mascot_sleeping"}
WIDGET_FRONT_PX = 230            # the front pose's height at the widget's scale

ROW_NORM = {1: 1 / 1.385, 2: 1 / 1.103, 3: 1.0}
S = 3.0                          # app copy: 3x of the activity row's native size
MARGIN = 12

SHEETS = {
    1: dict(poses="poses.json", src=SRC, masters=MASTERS, row_norm=ROW_NORM),
    2: dict(poses="poses-2.json", src=ROOT / "design/mascot/sheet-2/poses-native",
            masters=ROOT / "design/mascot/sheet-2/poses-4x",
            row_norm={1: 2.90 / S, 2: 2.93 / S, 3: 3.25 / S, 4: 3.25 / S}),
    # 2026-09-30: three more sheets, named by what they show. Each writes its
    # app copies to its own folder, and each row's app scale is measured on
    # that sheet against the app copies already shipped.
    # sport: this sheet's size drifts inside its rows as much as between
    # them, so in poses-sport.json "row" is a size class and "sheet_row" the
    # row the pose sits in. Each pose is measured against the shipped app
    # copies' medians: the face (open eye height 79, eye spacing 162 open or
    # 174 shut, cheek spacing 251) and the leaves (square root of their area
    # 254, tip to tip 566), the two as a geometric mean, because some poses
    # draw bigger leaves on the same face (dumbbells: face 2.81, leaves 2.46).
    # In app px per sheet px: dumbbells 2.63, jogging 2.53, water bottle 2.66
    # (face by its shut eyes, a cheek is behind the bottle); jump rope 2.85,
    # sit-ups 2.93, mat rest 2.80, plank 2.78, basketball 2.90, gym bag 2.93;
    # football 3.07, tennis 3.01; boxing 3.21, barbell 3.34; cycling 3.77,
    # treadmill 3.57. The five classes put every pose within -3.2% to +2.8%
    # of its measure; the shipped poses spread 5% (one standard deviation) on
    # the same measure. One scale per row (2.90, 3.00, 3.10) left the jogger
    # 15% and the dumbbells 10% too big, the boxer and the barbell 7% small.
    # Measured again on the app copies, every pose is 0.95 to 1.03 of the
    # shipped median. Settled by eye beside happy sparkles, running, calm,
    # thumbs up, cheer and mug. Then run fix_poses_sport.py: it redoes the
    # racket strings and bike spokes, which the model draws wavy.
    "sport": dict(poses="poses-sport.json", src=ROOT / "design/mascot/sheet-sport/poses-native",
                  masters=ROOT / "design/mascot/sheet-sport/poses-4x", app=APP / "sport",
                  row_norm={1: 2.60 / S, 2: 2.85 / S, 3: 3.05 / S, 4: 3.25 / S, 5: 3.65 / S}),
    # streak: like sport, "row" in poses-streak.json is a size class and
    # "sheet_row" the row the pose sits in. This sheet draws a smaller face on
    # the same body: against the shipped app copies' medians (leaf span 563,
    # square root of leaf area 258 and of green area 394; open eye height 79,
    # eye spacing 160, cheek spacing 249) the front-facing poses' faces say
    # 2.66 to 2.94 app px per sheet px where their silhouettes say 2.42 to
    # 2.50, and by eye the silhouette decides (by the face, body and leaves
    # come out 6 to 19% big). Silhouette = the mean of leaf span, leaf area
    # and green area, green left out where a prop covers the body (phone,
    # watering can, hourglass, the shelter's leaf) and leaf area on lying
    # scribble (its leaves foreshortened). Per pose: worried 2.42, poke 2.49,
    # phone 2.50, broken heart 2.46, blow 2.50, watering can 2.47; lying
    # scribble 2.68, run clock 2.76, shelter 2.70, lying 2.59, hourglass 2.55,
    # scribble 2.71; calendar 2.93, reach 2.88, chase 2.88. The three classes
    # put every pose within -4.8% to +3.1% of its measure; the shipped poses
    # spread 3.5% (one standard deviation) on the same measure. One scale per
    # sheet row (2.40, 2.55, 2.68) left the calendar and the clock runner 13%
    # small, lying scribble 10% and the two flame chasers 7%. Settled by eye beside
    # front wave, running, thumbs up, cheer, mug, calm, shrug and sleeping.
    "streak": dict(poses="poses-streak.json", src=ROOT / "design/mascot/sheet-streak/poses-native",
                   masters=ROOT / "design/mascot/sheet-streak/poses-4x", app=APP / "streak",
                   row_norm={1: 2.45 / S, 2: 2.68 / S, 3: 2.88 / S}),
    # ghutra: matched by face like the winter pictures (open-eye spacing 163
    # and eye height 74.5 on front_wave and cheer, closed-eye spacing 171.9 on
    # mug, calm, headphones, laugh and confetti) and by the agal, the one
    # object every pose draws, against winter_ghutra_cup's (512.5 app px). A
    # ring keeps its width as the head turns; the eyes move with the
    # expression (the laughing faces space theirs 20% wider than the blowing
    # face in the same row). Row means, agal then face: 2.60 and 2.62, 2.68
    # and 2.53, 2.77 and 2.76. Rows 1 and 3 agree, row 2 takes the mean of
    # the two, and row 3 is drawn about 5% smaller. Every pose's agal is
    # within -6% to +7% of winter_ghutra_cup's at its row's scale. Per pose,
    # the geometric mean of agal and face lies within -4.5% to +4.4% of its
    # row's scale in all three rows (row 2: blowing 2.72, warming hands 2.59,
    # heart 2.57, flame up 2.52), so one scale per row stands. By face alone
    # the heart would take 2.45 and the blowing pose 2.75; on a board beside
    # worried, flame hands, laugh, confetti and winter_ghutra_cup that makes
    # the heart's ghutra and bisht visibly smaller and the blowing pose's
    # bigger, as this sheet draws the laughing eyes wider on the same head.
    # Kept at 2.61 by eye (2026-09-30); Aziz may still prefer sizes per pose.
    "ghutra": dict(poses="poses-ghutra.json", src=ROOT / "design/mascot/sheet-ghutra/poses-native",
                   masters=ROOT / "design/mascot/sheet-ghutra/poses-4x", app=APP / "winter",
                   row_norm={1: 2.62 / S, 2: 2.61 / S, 3: 2.75 / S}),
}


def sheet_key(s):
    """--sheet 1, --sheet 2, or a named sheet such as --sheet sport."""
    return int(s) if s.isdigit() else s


def bounds_up(img, size=3):
    """Per-channel min and max of the native size x size neighbourhood, at 4x."""
    lo = ndi.minimum_filter(img, size=(size, size, 1))
    hi = ndi.maximum_filter(img, size=(size, size, 1))
    z = lambda a: ndi.zoom(a, (4, 4, 1), order=1, mode='nearest', grid_mode=True)
    return z(lo), z(hi)


def clean_edges(rgb, a, reach):
    """Semi-transparent pixels within `reach` of solid take the nearest solid
    colour; fully transparent pixels take the nearest visible colour."""
    opaque = a >= 1.0
    d, idx = ndi.distance_transform_edt(~opaque, return_indices=True)
    edge = (a > 0) & ~opaque & (d <= reach)
    rgb[edge] = rgb[idx[0][edge], idx[1][edge]]
    _, idx2 = ndi.distance_transform_edt(~(a > 0), return_indices=True)
    clear = ~(a > 0)
    rgb[clear] = rgb[idx2[0][clear], idx2[1][clear]]
    return rgb


def resize_premult(rgba, w, h):
    """Lanczos on premultiplied colour, so no dark or light fringe at the edge."""
    rgb, a = rgba[..., :3], rgba[..., 3]
    pm = rgb * a[..., None]
    chan = lambda c: np.asarray(Image.fromarray(c.astype(np.float32)).resize((w, h), Image.LANCZOS))
    A = np.clip(chan(a), 0, 1)
    RGB = np.stack([chan(pm[..., i]) for i in range(3)], -1)
    RGB = np.where(A[..., None] > 1e-4, RGB / np.maximum(A[..., None], 1e-4), 0)
    return np.clip(RGB, 0, 1), A


def master(net, dev, n):
    rgb = esrgan.upscale(net, dev, n[..., :3].astype(np.float32)).astype(np.float64)
    al = esrgan.upscale(net, dev, np.repeat(n[..., 3:4], 3, 2).astype(np.float32)).mean(2).astype(np.float64)
    lo, hi = bounds_up(n)
    rgb = np.clip(rgb, lo[..., :3], hi[..., :3])
    al = np.clip(al, lo[..., 3], hi[..., 3])
    al = np.clip((al - 0.02) / (0.98 - 0.02), 0, 1)       # no faint ring, solid body
    return np.dstack([clean_edges(rgb, al, reach=6), al])


def app_copy(m4, row, row_norm=ROW_NORM):
    f = S * row_norm[row] / 4
    w, h = round(m4.shape[1] * f), round(m4.shape[0] * f)
    RGB, A = resize_premult(m4, w, h)
    A = np.where(A >= 0.985, 1.0, np.where(A <= 0.015, 0.0, A))
    RGB = clean_edges(RGB, A, reach=3)
    ys, xs = np.nonzero(A > 0)
    y0, y1, x0, x1 = ys.min() - MARGIN, ys.max() + 1 + MARGIN, xs.min() - MARGIN, xs.max() + 1 + MARGIN
    out = np.zeros((y1 - y0, x1 - x0, 4))
    sy0, sx0, sy1, sx1 = max(y0, 0), max(x0, 0), min(y1, h), min(x1, w)
    out[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0, :3] = RGB[sy0:sy1, sx0:sx1]
    out[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0, 3] = A[sy0:sy1, sx0:sx1]
    out[..., :3] = clean_edges(out[..., :3], out[..., 3], reach=0)
    return out


def write_widget_image(asset, name, app):
    """One pose for the Home Screen widget's own catalog, from its APP copy:
    those are the files already at one shared character scale. The masters
    are not (they keep the sheet's three row sizes), so reading them here put
    the happy sprout at 194px instead of 240px beside a 150px sleeper."""
    src = np.asarray(Image.open(app / f"{name}.webp").convert('RGBA')).astype(np.float64) / 255
    front = np.asarray(Image.open(app / "mascot_front_wave.webp")).shape[0]
    f = WIDGET_FRONT_PX / front
    w, h = round(src.shape[1] * f), round(src.shape[0] * f)
    RGB, A = resize_premult(src, w, h)
    A = np.where(A >= 0.985, 1.0, np.where(A <= 0.015, 0.0, A))
    RGB = clean_edges(RGB, A, reach=3)
    folder = WIDGET_CATALOG / f"{asset}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    to_png(np.dstack([RGB, A]), folder / f"{asset}.png")
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{asset}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    print(f"{asset:28s} widget {w}x{h}")


def to_png(a, path):
    Image.fromarray((a * 255 + 0.5).astype(np.uint8)).save(path, optimize=True)


def to_webp(a, path):
    # exact: libwebp otherwise rewrites the colour under fully transparent
    # pixels to compress better, and that colour is the edge bleed
    # clean_edges put there so scaling never pulls dark into the outline.
    Image.fromarray((a * 255 + 0.5).astype(np.uint8)).save(
        path, 'WEBP', lossless=True, quality=100, method=6, exact=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sheet", type=sheet_key, choices=list(SHEETS), default=1)
    ap.add_argument("--src", type=pathlib.Path, default=None)
    ap.add_argument("--masters", type=pathlib.Path, default=None)
    ap.add_argument("--app", type=pathlib.Path, default=None)
    ap.add_argument("--weights", type=pathlib.Path, default=None, help="a local copy of the model file")
    ap.add_argument("--only", nargs="*", default=None, help="pose names to redo")
    args = ap.parse_args()
    cfg = SHEETS[args.sheet]
    args.src = args.src or cfg["src"]
    args.masters = args.masters or cfg["masters"]
    args.app = args.app or cfg.get("app", APP)
    poses = json.loads((HERE / cfg["poses"]).read_text())
    net, dev = esrgan.load(args.weights)
    args.masters.mkdir(parents=True, exist_ok=True)
    args.app.mkdir(parents=True, exist_ok=True)
    for pose in poses:
        if args.only and pose['name'] not in args.only:
            continue
        n = np.asarray(Image.open(args.src / f"{pose['name']}.png").convert('RGBA')).astype(np.float64) / 255
        m4 = master(net, dev, n)
        to_png(m4, args.masters / f"{pose['name']}.png")
        if not pose.get('app', True):
            print(f"{pose['name']:28s} 4x {m4.shape[1]}x{m4.shape[0]}  (repeats {pose['twin']}: master only)")
            continue
        a = app_copy(m4, pose['row'], cfg["row_norm"])
        to_webp(a, args.app / f"{pose['name']}.webp")
        print(f"{pose['name']:28s} 4x {m4.shape[1]}x{m4.shape[0]}  app {a.shape[1]}x{a.shape[0]}")
    for asset, name in WIDGET_POSES.items():
        if args.sheet != 1 or (args.only and name not in args.only):
            continue
        write_widget_image(asset, name, args.app)
