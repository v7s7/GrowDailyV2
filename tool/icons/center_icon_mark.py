#!/usr/bin/env python3
"""Re-centre the gold mark in the app icon on its POT, not on its bounding box.

    python3 tool/icons/center_icon_mark.py            # measure only
    python3 tool/icons/center_icon_mark.py --apply    # measure and rewrite

Needs Pillow (`pip3 install Pillow`). Rewrites assets/images/icon_app.png in
place. Re-run the downstream generators afterwards:

    python3 tool/icons/make_adaptive_foreground.py
    python3 tool/icons/make_ios_appicons.py
    dart run flutter_launcher_icons          # Android only, see pubspec.yaml

Why this exists: the mark is a stem with two deliberately asymmetric leaves
above a rounded square pot. Its bounding box is therefore NOT a centring
reference - the tall right-hand leaf drags the bbox centre 17.5px right of the
canvas centre, while the pot sat 8.7px LEFT of it, giving the pot a 348.2px gap
on its left and a 365.6px gap on its right. The eye anchors a composition like
this on its solid base, so the pot is what has to be centred, and 17.4px of
imbalance under it reads as the whole logo drifting.

HOW THE SHIFT KEEPS THE ART INTACT
The source is two flat colours (plate 15,105,74 and mark 226,163,54) with
roughly one pixel of edge between them, so every pixel is described well enough
by a single number: how much of it the mark covers. Coverage is recovered by
projecting the pixel onto the plate->mark colour axis, which uses all three
channels and so averages away the +/-2 encoding noise.

A plain sub-pixel translation of the bitmap would have to interpolate, and
bilinear interpolation widens a 1px edge to 2px - measurably softer art.
Instead the coverage mask is supersampled SS times, thresholded back to a hard
shape (recovering the edge to 1/SS px), translated by a whole number of
subpixels, and box-filtered back down. Box-filtering SS*SS subpixels is exactly
what one-pixel anti-aliasing means, so the edge comes back out at the width it
went in at - measured at 1.58px either side of the round trip, between coverage
0.10 and 0.90.

One caveat on the numbers this prints. The source is processed generated art and
its edges carry a slight sharpening halo (the pixel just outside the pot
undershoots the plate, the one just inside overshoots the mark), so clamped
coverage is not a physically exact area. That biases the 0.5-crossing estimate of
the offset by up to about 0.05px depending on sub-pixel phase: estimators that
integrate the unclamped edge instead put the original offset near 8.78 rather
than the 8.72 measured here. Both land the pot within 0.03px of centre, well
inside the 0.07px this method can even resolve at SS=14, so the distinction only
matters if someone later tries to reconcile two different measurements.

Only one rectangle is rewritten: the mark's bounding box where it was, unioned
with where it lands, plus a margin. Every pixel outside that window is copied
through byte for byte, which matters because the source plate is not perfectly
clean - it carries up to +/-7 of encoding noise and a very faint one-pixel dotted
arc near each corner, the seam of the rounded-rect mask the art was composited
through. The window is a hard geometric bound rather than a coverage test on
purpose: at the noise levels in this source a coverage test picks up isolated
plate pixels hundreds of px away and quietly flattens the arc.

Idempotent: once the pot is centred the measured shift is ~0 and --apply is a
no-op, so it is safe to re-run as a check.
"""
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "assets/images/icon_app.png"

PLATE = (15, 105, 74)
MARK = (226, 163, 54)

# Rows sampled to locate the pot's vertical sides: solidly inside the pot body,
# clear of the rounded top corners, of the stem that enters at the top, and of
# the rounded bottom corners. Fractions of image height, so this survives a
# change of source resolution.
POT_TOP, POT_BOT = 0.59, 0.78
# Supersampling factor for the shift. 14 puts the reconstructed edge within
# 1/14 px (0.07) of its true position and lands the required 8.720px shift on
# 122 subpixels, i.e. 8.714px - a 0.006px rounding error, 250x smaller than the
# 1.5px that would be visible at any size this icon is ever drawn. Higher
# factors cost memory quadratically for no perceptible gain.
SS = 14
# Margin around the mark's bounding box for the supersampled working region.
# Must exceed the shift so the translated mark cannot run off the region.
MARGIN = 24
# Slack around the mark's bounding box, so the anti-aliased fringe of the old
# position is erased rather than left as a ghost edge. Also has to exceed the
# shift itself, which it does by a wide margin.
MARGIN_REPAINT = 12
# Below this the mark is already centred and rewriting would only churn the file.
DEAD_ZONE = 0.02


def coverage(im):
    """Per-pixel coverage of the mark, 0..1, as a flat list of floats.

    Least-squares projection onto the plate->mark colour axis. Red carries most
    of the signal (211 of 211/58/20) but folding in green and blue divides the
    encoding noise across three channels instead of trusting one.
    """
    w, h = im.size
    px = im.load()
    ax = [MARK[i] - PLATE[i] for i in range(3)]
    norm = float(sum(c * c for c in ax))
    out = [0.0] * (w * h)
    for y in range(h):
        base = y * w
        for x in range(w):
            p = px[x, y]
            t = sum((p[i] - PLATE[i]) * ax[i] for i in range(3)) / norm
            out[base + x] = 0.0 if t <= 0.0 else (1.0 if t >= 1.0 else t)
    return out


def edges(row):
    """Sub-pixel x where coverage crosses 0.5, scanning in from each side."""
    left = right = None
    for x in range(1, len(row)):
        if row[x - 1] < 0.5 <= row[x]:
            left = x - 1 + (0.5 - row[x - 1]) / (row[x] - row[x - 1])
            break
    for x in range(len(row) - 1, 0, -1):
        if row[x] < 0.5 <= row[x - 1]:
            right = x - 1 + (row[x - 1] - 0.5) / (row[x - 1] - row[x])
            break
    return left, right


def measure(cov, w, h):
    lefts, rights = [], []
    for y in range(int(h * POT_TOP), int(h * POT_BOT) + 1):
        left, right = edges(cov[y * w:(y + 1) * w])
        if left is not None and right is not None:
            lefts.append(left)
            rights.append(right)
    if not lefts:
        raise SystemExit("could not find the pot; check POT_TOP/POT_BOT")
    minx, maxx = w, -1
    for y in range(h):
        row = cov[y * w:(y + 1) * w]
        for x in range(w):
            if row[x] >= 0.5:
                if x < minx:
                    minx = x
                if x > maxx:
                    maxx = x
    return (sum(lefts) / len(lefts), sum(rights) / len(rights), len(lefts),
            minx, maxx)


def report(cov, w, h, title):
    left, right, rows, bl, br = measure(cov, w, h)
    centre, canvas = (left + right) / 2.0, (w - 1) / 2.0
    print(f"  {title}")
    print(f"    pot left edge     {left:9.3f}")
    print(f"    pot right edge    {right:9.3f}")
    print(f"    pot width         {right - left:9.3f}   ({rows} rows sampled)")
    print(f"    pot centre        {centre:9.3f}   canvas centre {canvas:9.3f}")
    print(f"    left gap          {left:9.3f}")
    print(f"    right gap         {(w - 1) - right:9.3f}")
    print(f"    L/R asymmetry     {((w - 1) - right) - left:+9.3f} px")
    print(f"    pot off-centre    {centre - canvas:+9.3f} px "
          f"({(centre - canvas) / w * 100:+.4f}% of width)")
    print(f"    mark bbox         {bl} .. {br}  (bbox centre {(bl + br) / 2:.1f}, "
          f"off {(bl + br) / 2 - canvas:+.1f})")
    return centre - canvas, bl, br


def shift_coverage(cov, w, h, bl, br, subpixels):
    """Translate the mark right by subpixels/SS px, preserving 1px edges."""
    x0 = max(0, bl - MARGIN)
    x1 = min(w, br + 1 + MARGIN)
    rw = x1 - x0
    region = Image.new("L", (rw, h))
    region.putdata([int(round(cov[y * w + x] * 255))
                    for y in range(h) for x in range(x0, x1)])

    big = region.resize((rw * SS, h * SS), Image.BILINEAR)
    # Threshold back to a hard shape: this is where the vector edge is recovered
    # at 1/SS px, and it is what lets the shift below be a lossless integer move.
    big = big.point(lambda v: 255 if v >= 128 else 0)

    moved = Image.new("L", big.size, 0)
    moved.paste(big, (subpixels, 0))
    # BOX averages exactly SS*SS subpixels per output pixel, which is the
    # definition of one-pixel anti-aliasing. Hence a 1.00px edge, not 2.00px.
    small = moved.resize((rw, h), Image.BOX)

    out = [0.0] * (w * h)
    sp = small.load()
    for y in range(h):
        base = y * w
        for x in range(rw):
            out[base + x0 + x] = sp[x, y] / 255.0
    return out


def bbox(cov, w, h, thresh=0.5):
    minx, maxx, miny, maxy = w, -1, h, -1
    for y in range(h):
        row = cov[y * w:(y + 1) * w]
        for x in range(w):
            if row[x] >= thresh:
                if x < minx:
                    minx = x
                if x > maxx:
                    maxx = x
                if y < miny:
                    miny = y
                if y > maxy:
                    maxy = y
    return minx, maxx, miny, maxy


def repaint(im, old, new, w, h):
    """Rewrite only the window the mark occupied or now occupies."""
    ox0, ox1, oy0, oy1 = bbox(old, w, h)
    nx0, nx1, ny0, ny1 = bbox(new, w, h)
    x0 = max(0, min(ox0, nx0) - MARGIN_REPAINT)
    x1 = min(w - 1, max(ox1, nx1) + MARGIN_REPAINT)
    y0 = max(0, min(oy0, ny0) - MARGIN_REPAINT)
    y1 = min(h - 1, max(oy1, ny1) + MARGIN_REPAINT)

    out = im.copy()
    px = out.load()
    for y in range(y0, y1 + 1):
        base = y * w
        for x in range(x0, x1 + 1):
            t = new[base + x]
            px[x, y] = tuple(int(round(PLATE[i] + (MARK[i] - PLATE[i]) * t))
                             for i in range(3))
    return out, (x0, x1, y0, y1), (x1 - x0 + 1) * (y1 - y0 + 1)


def main() -> None:
    apply = "--apply" in sys.argv
    im = Image.open(SRC).convert("RGB")
    w, h = im.size
    print(f"{SRC.relative_to(ROOT)}  {w}x{h}")

    cov = coverage(im)
    off, bl, br = report(cov, w, h, "BEFORE")

    if abs(off) < DEAD_ZONE:
        print(f"\n  pot is already centred (|{off:+.3f}| < {DEAD_ZONE}); nothing to do")
        return

    subpixels = int(round(-off * SS))
    print(f"\n  required shift  {-off:+.3f} px")
    if subpixels == 0:
        print(f"  nothing to do: that is under half a subpixel at {SS}x, so the "
              f"mark is already as centred as this method can place it")
        return
    print(f"  applied shift   {subpixels / SS:+.3f} px  "
          f"({subpixels} subpixels at {SS}x, rounding error "
          f"{abs(-off - subpixels / SS):.4f} px)")
    if not apply:
        print("  (dry run - pass --apply to rewrite the PNG)")
        return

    new = shift_coverage(cov, w, h, bl, br, subpixels)
    out, win, touched = repaint(im, cov, new, w, h)
    out.save(SRC)
    print(f"\n  wrote {SRC.relative_to(ROOT)}")
    print(f"  repainted window x {win[0]}..{win[1]}, y {win[2]}..{win[3]}  "
          f"({touched} px, {touched / (w * h) * 100:.1f}%); the other "
          f"{w * h - touched} px are byte-identical")
    print()
    report(coverage(Image.open(SRC).convert("RGB")), w, h, "AFTER")


if __name__ == "__main__":
    main()
