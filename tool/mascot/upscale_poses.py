#!/usr/bin/env python3
"""Upscale the cut mascot poses: 4x masters plus the copies the app ships.

    python tool/mascot/upscale_poses.py                           # all 18
    python tool/mascot/upscale_poses.py --only mascot_laptop      # one pose

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
height (see WidgetSprout in GrowDailyWidget.swift), so the character stays
one size between the two. `--only` skips them unless it names their pose.
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


def app_copy(m4, row):
    f = S * ROW_NORM[row] / 4
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
    ap.add_argument("--src", type=pathlib.Path, default=SRC)
    ap.add_argument("--masters", type=pathlib.Path, default=MASTERS)
    ap.add_argument("--app", type=pathlib.Path, default=APP)
    ap.add_argument("--weights", type=pathlib.Path, default=None, help="a local copy of the model file")
    ap.add_argument("--only", nargs="*", default=None, help="pose names to redo")
    args = ap.parse_args()
    poses = json.loads((HERE / "poses.json").read_text())
    net, dev = esrgan.load(args.weights)
    args.masters.mkdir(parents=True, exist_ok=True)
    args.app.mkdir(parents=True, exist_ok=True)
    for pose in poses:
        if args.only and pose['name'] not in args.only:
            continue
        n = np.asarray(Image.open(args.src / f"{pose['name']}.png").convert('RGBA')).astype(np.float64) / 255
        m4 = master(net, dev, n)
        to_png(m4, args.masters / f"{pose['name']}.png")
        a = app_copy(m4, pose['row'])
        to_webp(a, args.app / f"{pose['name']}.webp")
        print(f"{pose['name']:28s} 4x {m4.shape[1]}x{m4.shape[0]}  app {a.shape[1]}x{a.shape[0]}")
    for asset, name in WIDGET_POSES.items():
        if args.only and name not in args.only:
            continue
        write_widget_image(asset, name, args.app)
