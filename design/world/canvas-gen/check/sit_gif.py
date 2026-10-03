"""doum-sits.gif: the sit on the bench, frame by frame, with the engine's own numbers.

    node check/preview2.js project/Oasis.dc.html check/bg.html '{"still":"true"}' '{"walk":[-300,-300]}'
    (headless Chrome at --force-device-scale-factor=2, --window-size=390,948) -> check/bg2x.png
    python check/sit_gif.py

Walk 70 units/s on cubic-bezier(.4,.1,.4,1), a 0.18 s beat facing front, the hop up
(0.42 s, frame changes at 45%), the sway (4.2 s), the hop down (0.38 s), the landing.
It draws Doum over everything, so a thing that stands in front of him in the
app (the boat) shows behind him here; the canvas has the true order.
"""
import json, math
from PIL import Image
ROOT = '/Users/aysha/Documents/GrowDailyV2'
FM = json.load(open(ROOT + '/design/mascot/frames-web/meta.json'))
FR = {k: Image.open(f'{ROOT}/design/mascot/frames-web/{k}.webp').convert('RGBA') for k in FM if not k.startswith(('arm', 'leg', 'foot', 'leaf', 'eyes', 'mouth', 'body', 'belly'))}
bg = Image.open(ROOT + '/design/world/canvas-gen/check/bg2x.png').convert('RGBA')
DS = 2; U = 358 / 360; OX, OY = 16, 104
DH = 66
def P(x, y): return ((OX + x * U) * DS, (OY + y * U) * DS)

def bez(p1x, p1y, p2x, p2y):
    def f(t):
        lo, hi = 0.0, 1.0
        for _ in range(40):
            m = (lo + hi) / 2
            x = 3 * (1 - m) ** 2 * m * p1x + 3 * (1 - m) * m * m * p2x + m ** 3
            lo, hi = (m, hi) if x < t else (lo, m)
        m = (lo + hi) / 2
        return 3 * (1 - m) ** 2 * m * p1y + 3 * (1 - m) * m * m * p2y + m ** 3
    return f
MOVE = bez(.4, .1, .4, 1); EOUT = bez(0, 0, .58, 1); EIN = bez(.42, 0, 1, 1); EIO = bez(.42, 0, .58, 1)

def keyed(t, keys, ease):
    """keys: [(pct, (ty, sx, sy, rot))]; CSS applies the timing function per segment."""
    for (a, va), (b, vb) in zip(keys, keys[1:]):
        if a <= t <= b:
            k = ease((t - a) / (b - a)) if b > a else 1
            return tuple(x + (y - x) * k for x, y in zip(va, vb))
    return keys[-1][1]

N = (0, 1, 1, 0)
def frame_img(name, scale_units, flip=False):
    f = FM[name]; im = FR[name]
    s = scale_units * U * DS
    w, h = max(1, round(im.width * s)), max(1, round(im.height * s))
    im = im.resize((w, h), Image.LANCZOS)
    ax, ay = f['ax'] * s, f['ay'] * s
    if flip: im = im.transpose(Image.FLIP_LEFT_RIGHT); ax = w - ax
    return im, ax, ay

def draw(canvas, name, sc_units, at, tf=N, flip=False, shadow=True):
    ty, sx, sy, rot = tf
    im, ax, ay = frame_img(name, sc_units, flip)
    # transform about the anchor: scale, rotate, then translate up by ty units
    w, h = im.size
    im2 = im.resize((max(1, round(w * sx)), max(1, round(h * sy))), Image.LANCZOS)
    ax2, ay2 = ax * sx, ay * sy
    big = Image.new('RGBA', (im2.width * 3, im2.height * 3))
    big.paste(im2, (im2.width, im2.height))
    cx, cy = im2.width + ax2, im2.height + ay2
    big = big.rotate(-rot, center=(cx, cy), resample=Image.BICUBIC)
    px, py = P(*at)
    if shadow:
        sh = Image.new('RGBA', (int(36 * U * DS), int(36 * 0.3 * U * DS)))
        from PIL import ImageDraw
        d = ImageDraw.Draw(sh); d.ellipse((0, 0, sh.width - 1, sh.height - 1), fill=(30, 43, 26, 70))
        canvas.alpha_composite(sh, (round(px - sh.width / 2), round(py - sh.height * 0.55)))
    canvas.alpha_composite(big, (round(px - cx), round(py - cy + ty * U * DS)))

def sc_walk(d): return DH * {'side': .98, 'front': 1, 'three': .98, 'back': .97, 'back34': .98}[d] / FM['walk_' + d + '_1']['dh']
SC_IDLE = DH / FM['idle_calm']['dh']
SC_ACT = lambda n: DH / (302 * FM[n]['k'])
HOME, FRONT, SEAT = (168, 300), (104, 293), (104, 286 - 15 * 1.06)
HOP = 9
fps = 25
frames = []
def lerp(a, b, k): return (a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k)
def walk_dur(a, b): return max(.45, min(2.6, math.hypot(b[0] - a[0], (b[1] - a[1]) * 1.6) / 70))
W1 = walk_dur(HOME, FRONT)
timeline = [('idle', .5, HOME), ('walk', W1, (HOME, FRONT)), ('beat', .18, FRONT), ('up', .42, None), ('on', 4.2, None), ('down', .38, None), ('land', .32, FRONT), ('idle', .6, FRONT), ('walk', W1, (FRONT, HOME)), ('idle', .5, HOME)]
crop = (*[round(v) for v in P(30, 196)], *[round(v) for v in P(250, 330)])
for kind, dur, arg in timeline:
    n = max(1, round(dur * fps))
    for i in range(n):
        t = i / fps; k = t / dur
        c = bg.copy()
        if kind == 'idle':
            draw(c, 'idle_calm', SC_IDLE, arg, (0, 1 + .012 * math.sin(t / 3.4 * math.pi) ** 2, 1 + .022 * math.sin(t / 3.4 * math.pi) ** 2, 0))
        elif kind == 'walk':
            a, b = arg
            pos = lerp(a, b, MOVE(k))
            fi = int((t % .44) / .11) + 1
            rot = -1.2 + 2.4 * EIO(((t % .44) / .22) if (t % .44) < .22 else 2 - (t % .44) / .22)
            draw(c, f'walk_side_{fi}', sc_walk('side'), pos, (0, 1, 1, rot), flip=b[0] < a[0])
        elif kind in ('beat', 'land'):
            tf = keyed(k, [(0, (0, 1.07, .9, 0)), (.6, (0, .98, 1.03, 0)), (1, N)], EOUT) if kind == 'land' or k < 1 else N
            draw(c, 'idle_calm', SC_IDLE, arg, tf)
        elif kind == 'up':
            pos = lerp(FRONT, SEAT, MOVE(k))
            tf = keyed(k, [(0, N), (.45, (-HOP, .95, 1.06, 0)), (.78, (0, 1.07, .92, 0)), (1, N)], EOUT)
            if k < .45: draw(c, 'idle_calm', SC_IDLE, pos, tf, shadow=False)
            else: draw(c, 'sit_front', SC_ACT('sit_front'), pos, tf, shadow=False)
        elif kind == 'on':
            ph = (t % 4.2) / 4.2
            tf = keyed(ph, [(0, (0, 1, 1, -1.2)), (.5, (0, 1.012, 1.025, 1.2)), (1, (0, 1, 1, -1.2))], EIO)
            draw(c, 'sit_front', SC_ACT('sit_front'), SEAT, tf, shadow=False)
        elif kind == 'down':
            pos = lerp(SEAT, FRONT, MOVE(k))
            tf = keyed(k, [(0, N), (.4, (-HOP * .8, .96, 1.04, 0)), (.8, (0, 1.08, .9, 0)), (1, N)], EIN)
            if k < .45: draw(c, 'sit_front', SC_ACT('sit_front'), pos, tf, shadow=False)
            else: draw(c, 'idle_calm', SC_IDLE, pos, tf, shadow=False)
        frames.append(c.crop(crop).convert('RGB'))
out = ROOT + '/design/world/canvas-gen/doum-sits.gif'
small = [f.resize((f.width * 3 // 4, f.height * 3 // 4), Image.LANCZOS) for f in frames]
# one shared palette keeps the file small and the colours steady
strip = Image.new('RGB', (small[0].width, small[0].height * 6))
for j, idx in enumerate(range(0, len(small), max(1, len(small) // 6))):
    if j < 6: strip.paste(small[idx], (0, j * small[0].height))
pal = strip.quantize(colors=160, method=Image.Quantize.MEDIANCUT)
q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in small]
q[0].save(out, save_all=True, append_images=q[1:], duration=1000 // fps, loop=0, optimize=True)
# a contact sheet of the hop for checking
sheet = Image.new('RGB', (frames[0].width * 6, frames[0].height), 'white')
start = round((.5 + W1) * fps)
for j, idx in enumerate([start - 2, start + 4, start + 7, start + 10, start + 12, start + 16]):
    sheet.paste(frames[idx], (j * frames[0].width, 0))
sheet.save(ROOT + '/design/world/canvas-gen/check/hop_sheet.png')
print(len(frames), 'frames', frames[0].size)
