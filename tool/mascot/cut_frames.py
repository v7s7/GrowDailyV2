#!/usr/bin/env python3
"""Cut Doum's animation sheets into frames that line up exactly.

    python tool/mascot/cut_frames.py --sheet walk     # also walk2, acts, parts
        # writes design/mascot/sheet-<name>/frames/<frame>.png and frames.json
    python tool/mascot/cut_frames.py --sheet acts --web   # also the web-size frames

Needs numpy, scipy and Pillow. For the oasis canvas (2026-10-03): Sheets 8
to 11 from the prompts on its "Before we build" board, drawn as 4 x 3 grids
of 384 x 341 cells on a 1536 x 1024 sheet. ChatGPT painted a blurred dark
green backdrop behind them, so the ground comes off with the world cutter's
blur_matte, and Doum's paint moves onto the palette with recolor_sheets_oct's
recolor (body #74C878, cream #F5F0E1).

WHY A FRAME TOOL
A walk cycle only looks smooth when every frame is the same size and stands
on the same ground. ChatGPT drifts a few pixels and a few percent between
cells, so each row of a cycle is normalised:
  - the ground is the lowest painted pixel (a foot on the floor in every
    frame of a walk);
  - the centre is the middle of the painted columns in the lower 55% of the
    figure (the body), so a leaf leaning back does not pull it sideways;
  - the size is the painted height; a frame more than 2% off its row's median
    is scaled to the median, and anything more than 8% off is reported, since
    that is a frame worth redrawing rather than stretching;
  - every frame of the row is then pasted on one canvas with its centre and
    ground at the same point.
Single poses (the "acts" sheet and the idle row) keep their own size and get
the same anchor rule. frames.json records each frame's canvas, anchor and
painted height so the app and the canvas can place them by Doum's height.

SITTING ON THINGS ON THE ISLAND
The bench pose on Sheet 10 came with its own side-on stool, so laid over the
island's bench it showed two seats (Aziz, 2026-10-03: "make the sitting
better, more accurate"). The cushion pose is front-on, so the "acts" sheet
also writes sit_front: that pose with the cushions taken away (their reds and
warm beige go, the piece holding Doum's middle stays, the mouth and cheeks
inside him are filled back). Its anchor is the SEAT POINT, the bottom of his
body between the feet, so it can be set on any seat (the bench seat is 15
units over the ground at scale 1).

PROPS THAT CLASH WITH THE ISLAND (2026-10-03, "fix everything that has animation")
Some Sheet 10 poses carry their own props, which double up with the real
thing Doum stands next to. The "acts" sheet now strips them:
  - can_pour: the little sapling and its soil go, the water stays, so the
    stream falls on the real plant;
  - door_push: the door goes, his arm stays, so he pushes the house's door.
snip keeps its sapling (it overlaps his body and cannot come off cleanly);
taking a cutting uses reach, then hold_cutting, instead.

PLANTING FRAMES FROM SHEET 1
The old planting pose holds a pot. --work writes plant_dig and plant_pat
(Sheet 1's digging and patting a sprout, already cut into
assets/images/mascot/work/) into frames-web at the same scale as the other
frames: the standing height of the Sheet 1 set (work_big_seed) counts as a
standing Doum.

WEB SIZE
--web also writes design/mascot/frames-web/<frame>.webp (at most 300 px) and
merges w, h, k (the scale from the cut frame), ax, ay and dh into its meta.json.

PARTS
The parts sheet (Doum taken apart for a code rig) gives the body, belly,
leaves, arms and feet. Its eyes, mouth and cheeks came back as dark shapes on
a dark glow that cannot be parted cleanly; the face is drawn in code instead,
which also makes blinking exact.
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
sys.path.insert(0, str(ROOT / "tool/world"))
sys.path.insert(0, str(HERE))
from cut_world_sheet import blur_matte  # noqa: E402
from recolor_sheets_oct import recolor  # noqa: E402

EIGHT = np.ones((3, 3))
SHEETS = {
    # Sheet 8: walk cycles, four frames each
    "walk": dict(src="ورقة حركات مشي لشخصية نباتية لطيفة.png",
                 rows=[("walk_side", "cycle"), ("walk_front", "cycle"), ("walk_back", "cycle")]),
    # Sheet 9: three-quarter walks, then standing still (calm, blink, look left, look right)
    "walk2": dict(src="ورقة شخصيات نباتية لطيفة متحركة.png",
                  rows=[("walk_three", "cycle"), ("walk_back34", "cycle"),
                        (["idle_calm", "idle_blink", "idle_look_l", "idle_look_r"], "cycle")]),
    # Sheet 10: things he does on visits, one pose per cell
    "acts": dict(src="ملصقات سليل النخيل اللطيف.png",
                 rows=[(["reach", "hold_dates", "snip", "hold_cutting"], "single"),
                       (["can_tilt", "can_pour", "sit_bench", "sit_cushions"], "single"),
                       (["carry_basket", "put_basket", "camera", "door_push"], "single")]),
    # Sheet 11: Doum in parts (the face cells are cut but not used)
    "parts": dict(src="ورقة أجزاء شخصية كرتونية معيارية.png", fill=True,
                  rows=[(["body", "belly", "leaf_l", "leaf_r"], "part"),
                        (["arm_l", "arm_r", "foot_l", "foot_r"], "part"),
                        (["eyes_open", "eyes_closed", "mouth_smile", "mouth_open"], "part")]),
}


def cells_of(A, min_area=400):
    """Label the art and give each piece to the cell its centre falls in."""
    h, w = A.shape
    art, n = ndi.label(A > 16, structure=EIGHT)
    cells = {}
    for i, sl in enumerate(ndi.find_objects(art)):
        m = art[sl] == i + 1
        if m.sum() < min_area:
            continue
        cy, cx = ndi.center_of_mass(m)
        r = min(2, int((sl[0].start + cy) // (h / 3)))
        c = min(3, int((sl[1].start + cx) // (w / 4)))
        cells.setdefault(r * 4 + c, []).append(i + 1)
    return art, cells


def anchor(a):
    """Ground (lowest painted row) and body centre (middle of painted columns, lower 55%)."""
    ys, xs = np.nonzero(a > 16)
    top, bottom = ys.min(), ys.max()
    low = a[top + int((bottom - top) * 0.45):bottom + 1] > 16
    cols = np.nonzero(low.any(0))[0]
    return (cols.min() + cols.max()) / 2, bottom, bottom - top + 1


def crop(rgba, keep_mask):
    ys, xs = np.nonzero(keep_mask)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    out = rgba[y0:y1, x0:x1].copy()
    out[..., 3] = np.where(keep_mask[y0:y1, x0:x1], out[..., 3], 0)
    return out


def hue_sat(rgb):
    """Hue in degrees and saturation, for rgb in 0..255."""
    c = rgb / 255.0
    mx, mn = c.max(-1), c.min(-1)
    d = mx - mn
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    h = np.zeros_like(mx)
    m = d > 1e-6
    i = m & (mx == r)
    h[i] = ((g - b)[i] / d[i]) % 6
    i = m & (mx == g) & (mx != r)
    h[i] = (b - r)[i] / d[i] + 2
    i = m & (mx == b) & (mx != r) & (mx != g)
    h[i] = (r - g)[i] / d[i] + 4
    return h * 60, np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)


def uncushion(t):
    """sit_cushions without the cushions: Doum alone, seated, front-on. Anchor = seat point."""
    a = t[..., 3]
    h, s = hue_sat(t[..., :3])
    cushion = ((((h < 20) | (h > 335)) & (s > 0.45)) | ((h >= 15) & (h <= 38) & (s > 0.2))) & (a > 16)
    lab, _ = ndi.label((a > 16) & ~cushion, structure=EIGHT)
    ys, xs = np.nonzero(a > 16)
    middle = lab[int(ys.min() + (ys.max() - ys.min()) * 0.55), int((xs.min() + xs.max()) / 2)]
    keep = ndi.binary_fill_holes(ndi.binary_opening(lab == middle, iterations=1))
    out = crop(t, keep)
    oa = out[..., 3] > 16
    oy, ox = np.nonzero(oa)
    top, bottom = oy.min(), oy.max()
    cols = np.nonzero(oa[top + int((bottom - top) * 0.45):].any(0))[0]
    cx = (cols.min() + cols.max()) / 2
    # the seat point: the lowest painted pixel in the middle columns, between the feet
    mid = oa[:, int(cx) - 4:int(cx) + 5]
    seat = max(np.nonzero(mid[:, j])[0].max() for j in range(mid.shape[1]))
    return out, cx, seat, bottom - top + 1


def web(out_dir, name, t, ax, ay, dh):
    """WebP at most 300 px with its anchor, merged into frames-web/meta.json."""
    web_dir = ROOT / "design/mascot/frames-web"
    k = min(1.0, 300 / max(t.shape[0], t.shape[1]))
    im = Image.fromarray(t.astype(np.uint8))
    im = im.resize((round(t.shape[1] * k), round(t.shape[0] * k)), Image.LANCZOS)
    im.save(web_dir / f"{name}.webp", quality=92, method=6)
    meta_path = web_dir / "meta.json"
    meta = json.loads(meta_path.read_text())
    meta[name] = dict(w=im.size[0], h=im.size[1], k=k, ax=round(ax * k, 1), ay=round(ay * k, 1), dh=round(dh * k, 1))
    meta_path.write_text(json.dumps(meta, indent=1) + "\n")


def strip_region(t, keep, region):
    """Clear the pixels inside region (a mask) that keep() does not want."""
    h, sat = hue_sat(t[..., :3])
    val = t[..., :3].max(-1) / 255.0
    drop = region & ~keep(h, sat, val) & (t[..., 3] > 0)
    out = t.copy()
    out[..., 3] = np.where(drop, 0, out[..., 3])
    # small crumbs left behind (anti-aliased edges of what was taken away)
    lab, n = ndi.label(out[..., 3] > 16, structure=EIGHT)
    if n > 1:
        sizes = ndi.sum(np.ones(lab.shape), lab, range(1, n + 1))
        for i, sz in enumerate(sizes):
            if sz < 60:
                out[..., 3][lab == i + 1] = 0
    return out


def unprop(name, t):
    """Take away the props that would double up with the island's own things."""
    H, W = t.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    if name == "can_pour":
        # below and right of the spout: keep the water (blue, and its white highlights)
        region = ((xx >= 205) & (yy >= 216)) | ((xx >= 196) & (yy >= 240))
        out = strip_region(t, lambda h, s, v: ((h >= 170) & (h <= 240) & (s > 0.12)) | ((s < 0.18) & (v > 0.8)), region)
        # the stream ended in the sapling; now it fades as it reaches the ground (the real plant)
        fade = np.clip((286 - yy) / 40.0, 0, 1)
        out[..., 3] = np.where((yy > 246) & (xx >= 208), out[..., 3] * fade, out[..., 3])
        return out
    if name == "door_push":
        # right of his body: keep only his arm and hand, with their own dark outline
        region = xx >= 214
        h, sat = hue_sat(t[..., :3])
        val = t[..., :3].max(-1) / 255.0
        green = (h >= 75) & (h <= 160) & (val > 0.12) & (t[..., 3] > 16)
        near = ndi.binary_dilation(green, iterations=3)
        hand = green | (near & (val < 0.35))
        return strip_region(t, lambda h2, s2, v2: hand, region)
    return t


def work_frames():
    """plant_dig and plant_pat from Sheet 1, sized like the rest of Doum's frames."""
    work = ROOT / "assets/images/mascot/work"
    ref = np.asarray(Image.open(work / "work_big_seed.webp").convert("RGBA")).astype(np.float64)
    ys = np.nonzero((ref[..., 3] > 16).any(1))[0]
    stand = ys.max() - ys.min() + 1           # a standing Doum in the Sheet 1 set
    for name, src in [("plant_dig", "work_digging.webp"), ("plant_pat", "work_patting_sprout.webp")]:
        t = np.asarray(Image.open(work / src).convert("RGBA")).astype(np.float64)
        h, s = hue_sat(t[..., :3])
        green = (t[..., 3] > 16) & (h >= 75) & (h <= 160) & (s > 0.2)
        # Doum is the biggest green piece; the sprout he pats is not him
        lab, n = ndi.label(green, structure=EIGHT)
        sizes = ndi.sum(np.ones(lab.shape), lab, range(1, n + 1))
        green = lab == (int(np.argmax(sizes)) + 1)
        gy, gx = np.nonzero(green)
        top, bottom = gy.min(), gy.max()
        # the centre from his torso (40 to 60% down): the spade and the sprout are lower
        torso = green[top + int((bottom - top) * 0.4):top + int((bottom - top) * 0.6)]
        cols = np.nonzero(torso.any(0))[0]
        cx = (cols.min() + cols.max()) / 2
        # k is the frame's size against a standing Doum of 302 px, like the acts sheet
        web(None, name, t, cx, bottom, bottom - top + 1)
        meta_path = ROOT / "design/mascot/frames-web/meta.json"
        meta = json.loads(meta_path.read_text())
        f = min(1.0, 300 / max(t.shape[0], t.shape[1]))
        meta[name]["k"] = stand * f / 302
        meta_path.write_text(json.dumps(meta, indent=1) + "\n")
        print(f"{name:14s} from {src}, standing height {stand}px, ground {bottom}, centre {cx:.0f}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sheet", choices=list(SHEETS))
    ap.add_argument("--web", action="store_true", help="also write web-size frames into design/mascot/frames-web")
    ap.add_argument("--work", action="store_true", help="write the planting frames from Sheet 1 into frames-web")
    args = ap.parse_args()
    if args.work:
        work_frames()
        return
    if not args.sheet:
        ap.error("--sheet or --work")
    cfg = SHEETS[args.sheet]
    base = ROOT / f"design/mascot/sheet-{args.sheet}"
    src = base / f"sheet-{args.sheet}-original.png"
    rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float64)
    rgb, A = blur_matte(rgb)
    if cfg.get("fill"):
        # parts are solid shapes: the body's smooth green middle looks like
        # ground to blur_matte, so fill every closed outline back in
        A = np.maximum(A, ndi.binary_fill_holes(A > 16) * 255.0)
    if cfg.get("recolor", True):
        rgb = recolor(rgb, A)
    rgba = np.dstack([np.clip(np.round(rgb), 0, 255), np.clip(np.round(A), 0, 255)])
    art, cells = cells_of(A)
    out_dir = base / "frames"
    out_dir.mkdir(exist_ok=True)
    meta = {}
    for r, (names, kind) in enumerate(cfg["rows"]):
        if isinstance(names, str):
            names = [f"{names}_{i + 1}" for i in range(4)]
        tiles = []
        for c in range(4):
            keep = np.isin(art, cells.get(r * 4 + c, []))
            keep = ndi.binary_dilation(keep, iterations=2) & (A > 0)
            # props that would double up with the island come off before the anchor is measured
            tiles.append(unprop(names[c] if c < len(names) else "", crop(rgba, keep)) if keep.any() else None)
        if kind == "part":
            for name, t in zip(names, tiles):
                if t is None:
                    print(f"{name:14s} nothing that could be parted from the ground (drawn in code instead)")
                    continue
                Image.fromarray(t.astype(np.uint8)).save(out_dir / f"{name}.png", optimize=True)
                meta[name] = dict(size=[t.shape[1], t.shape[0]])
                print(f"{name:14s} {t.shape[1]}x{t.shape[0]}")
            continue
        anchors = [anchor(t[..., 3]) for t in tiles]
        heights = np.array([a[2] for a in anchors], float)
        med = float(np.median(heights))
        scaled = []
        for name, t, (cx, gy, hh) in zip(names, tiles, anchors):
            k = 1.0
            if kind == "cycle" and abs(hh / med - 1) > 0.02:
                k = med / hh
            if kind == "cycle" and abs(hh / med - 1) > 0.08:
                print(f"  ! {name}: {hh / med - 1:+.0%} against the row; worth redrawing")
            if k != 1.0:
                im = Image.fromarray(t.astype(np.uint8)).resize((round(t.shape[1] * k), round(t.shape[0] * k)), Image.LANCZOS)
                t = np.asarray(im).astype(np.float64)
                cx, gy = cx * k, gy * k
            scaled.append((name, t, cx, gy, hh * k))
        if kind == "cycle":
            left = max(cx for _, _, cx, _, _ in scaled)
            right = max(t.shape[1] - cx for _, t, cx, _, _ in scaled)
            up = max(gy for _, _, _, gy, _ in scaled)
            W, H = int(np.ceil(left + right)) + 8, int(np.ceil(up)) + 8
            for name, t, cx, gy, hh in scaled:
                canvas = Image.new("RGBA", (W, H))
                canvas.paste(Image.fromarray(t.astype(np.uint8)), (round(4 + left - cx), round(4 + up - gy)))
                canvas.save(out_dir / f"{name}.png", optimize=True)
                meta[name] = dict(size=[W, H], anchor=[round(4 + left), round(4 + up)], height=round(hh))
                print(f"{name:14s} {W}x{H}  height {hh:.0f}")
                if args.web:
                    web(out_dir, name, np.asarray(canvas).astype(np.float64), 4 + left, 4 + up, hh)
        else:
            for name, t, cx, gy, hh in scaled:
                Image.fromarray(t.astype(np.uint8)).save(out_dir / f"{name}.png", optimize=True)
                meta[name] = dict(size=[t.shape[1], t.shape[0]], anchor=[round(cx), round(gy)], height=round(hh))
                print(f"{name:14s} {t.shape[1]}x{t.shape[0]}  height {hh:.0f}")
                if args.web:
                    web(out_dir, name, t, round(cx), gy, hh)
                if name == "sit_cushions":
                    t2, sx, sy, sh = uncushion(t)
                    Image.fromarray(t2.astype(np.uint8)).save(out_dir / "sit_front.png", optimize=True)
                    meta["sit_front"] = dict(size=[t2.shape[1], t2.shape[0]], anchor=[round(sx), round(sy)], height=round(sh), seat=True)
                    print(f"{'sit_front':14s} {t2.shape[1]}x{t2.shape[0]}  height {sh:.0f}, seat point {sx:.0f},{sy}")
                    if args.web:
                        web(out_dir, "sit_front", t2, sx, sy, sh)
    (out_dir / "frames.json").write_text(json.dumps(meta, indent=1) + "\n")


if __name__ == "__main__":
    main()
