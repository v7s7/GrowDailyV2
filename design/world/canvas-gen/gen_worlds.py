"""Generates the other directions as components beside Planet.dc.html:

  Tree.dc.html  kind=tree: one tree from a seed to a great tree
                kind=palm: a date palm from a shoot to a grove
  Farm.dc.html  35 plots, one planted per level

They share the planet's sky layer and its props (level, thirst, sky,
season, medals, pearls as weeks in a row, watering, glowing, pose,
frame, size) so every direction can be dropped into the same phone.
"""
import math, os, importlib.util

HERE = os.path.dirname(__file__)
spec = importlib.util.spec_from_file_location("gp", os.path.join(HERE, "gen_planet.py"))
gp = importlib.util.module_from_spec(spec); spec.loader.exec_module(gp)  # also rewrites Planet.dc.html
SKY = gp.sky_svg
FILL = gp.FILL
star = gp.star

def opk(key):
    return f' style="opacity: {{{{o.{key}}}}}; transition: opacity .6s ease"'

def blob(cx, cy, rx, ry, n=9, bulge=1.16, rot=0.0):
    pts, ctr = [], []
    for i in range(n):
        a = rot + 2 * math.pi * i / n
        b = rot + 2 * math.pi * (i + .5) / n
        pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
        ctr.append((cx + rx * bulge * math.cos(b), cy + ry * bulge * math.sin(b)))
    d = f"M{pts[0][0]:.1f} {pts[0][1]:.1f} "
    for i in range(n):
        p = pts[(i + 1) % n]; c = ctr[i]
        d += f"Q{c[0]:.1f} {c[1]:.1f} {p[0]:.1f} {p[1]:.1f} "
    return d + "Z"

# 20 spots inside a unit disc, spread out (fruit and dates for medals)
UNIT = []
golden = math.pi * (3 - math.sqrt(5))
for i in range(20):
    r = math.sqrt((i + .6) / 20.6) * .78
    a = i * golden
    UNIT.append((r * math.cos(a), r * math.sin(a)))
FRUIT = ["#F4D35E", "#D9534F", "#F29B38", "#7E5AA8", "#C9772F"]  # lemon, pomegranate, orange, fig, date

def fruits(cx, cy, rx, ry, r=3.4):
    s = '<g stroke-width="1">'
    for i, (ux, uy) in enumerate(UNIT):
        s += (f'<circle cx="{cx + ux * rx:.1f}" cy="{cy + uy * ry:.1f}" r="{r}" fill="{FRUIT[i % 5]}"'
              f' style="opacity: {{{{o.m{i}}}}}; transition: opacity .6s ease"></circle>')
    return s + '</g>'

def bird(x, y, key, flip=False):
    """A week in a row: a small lantern hung in the branches (was a bird: no animals, halal art)."""
    return (f'<g transform="translate({x} {y + 22})" stroke-width="1"{opk(key)}>'
            '<path d="M0 -12 V-5" fill="none"></path>'
            '<path d="M-2.6 -5 H2.6 L3.2 3 H-3.2 Z" fill="#F2C14E"></path>'
            '<path d="M-1.6 -6.6 H1.6" fill="none" stroke-width="1.6"></path>'
            '</g>')

LEAF = FILL("leaf")
DARK = FILL("leafDark")

# ------------------------------------------------------------ ground (shared by tree and palm)
GROUND = (
    f'<path d="M-20 420 L-20 336 C70 300 290 300 380 336 L380 420 Z" stroke="#1E3A24" stroke-width="2.6" {FILL("grass")}></path>'
    f'<path d="M-20 420 L-20 374 C100 360 260 360 380 374 L380 420 Z" stroke="#1E3A24" stroke-width="2" {FILL("soil")}></path>'
    '<path d="M60 330 l3 -5 l3 5 M300 334 l3 -5 l3 5 M170 342 l3 -5 l3 5 M240 352 l3 -5 l3 5" fill="none" stroke="#1E3A24" stroke-width="1.2" style="opacity: .35"></path>'
)
G_ITEMS = []
G_ITEMS.append(f'<g transform="translate(250 312)"{opk("stones")}>' + gp.stones + '</g>')
G_ITEMS.append(f'<g transform="translate(146 316) scale(1.1)"{opk("flowers")}>' + gp.flowers + '</g>')
G_ITEMS.append(f'<g transform="translate(296 322) scale(1.1)"{opk("jasmine")}>' + gp.jasmine + '</g>')
G_ITEMS.append(f'<g transform="translate(176 352) scale(1.1)"{opk("pond")}>' + gp.pond + '</g>')
G_ITEMS.append(
    f'<g transform="translate(262 330)"{opk("bench")}>'
    '<path d="M-14 0 V-8 M14 0 V-8 M-12 -8 V-17 M12 -8 V-17" fill="none" stroke-width="2"></path>'
    '<rect x="-16" y="-10" width="32" height="4" rx="1.5" fill="#B07A4A"></rect>'
    '<rect x="-14" y="-19" width="28" height="4" rx="1.5" fill="#B07A4A"></rect></g>')
G_ITEMS.append(f'<g transform="translate(326 340)"{opk("hive")}>' + gp.hive + gp.bees + '</g>')

# ------------------------------------------------------------ the tree's stages
BASE = "translate(200 311)"
mound = '<ellipse cx="0" cy="0" rx="16" ry="5" fill="#9C6B43"></ellipse>'
s0 = mound + (
    '<path d="M0 -2 V-14" fill="none"></path>'
    f'<g {LEAF}><path d="M0 -14 C-8 -14 -12 -20 -10 -24 C-4 -23 0 -19 0 -14 Z"></path>'
    '<path d="M0 -14 C8 -14 12 -20 10 -24 C4 -23 0 -19 0 -14 Z"></path></g>')
s1 = mound + (
    '<path d="M0 -2 C-2 -14 2 -28 0 -44" fill="none" stroke-width="2.4"></path>'
    f'<g {LEAF}>'
    + ''.join(f'<path d="M0 {y} C-{w} {y} -{w * 1.5:.0f} {y - w * .8:.0f} -{w * 1.3:.0f} {y - w * 1.3:.0f} C-{w * .5:.0f} {y - w * 1.2:.0f} 0 {y - w * .6:.0f} 0 {y} Z"></path>'
              f'<path d="M0 {y} C{w} {y} {w * 1.5:.0f} {y - w * .8:.0f} {w * 1.3:.0f} {y - w * 1.3:.0f} C{w * .5:.0f} {y - w * 1.2:.0f} 0 {y - w * .6:.0f} 0 {y} Z"></path>'
              for y, w in [(-16, 7), (-29, 8), (-43, 9)])
    + '</g>')
s2 = (
    '<path d="M-13 2 L-10 -52" fill="none" stroke="#8B6A4A" stroke-width="3"></path>'
    '<path d="M-3 0 C-2 -20 -2 -40 -1.5 -60 L1.5 -60 C2 -40 2 -20 3 0 Z" fill="#A9774A"></path>'
    '<path d="M-11 -40 L-1 -40" fill="none" stroke-width="1.4"></path>'
    f'<path d="{blob(0, -78, 26, 22, 8)}" {LEAF}></path>' + mound)
s3 = (
    '<path d="M-6 0 C-5 -30 -4 -60 -3 -90 L3 -90 C4 -60 5 -30 6 0 Z" fill="#9C6B43"></path>'
    f'<path d="{blob(0, -118, 50, 38, 9)}" {LEAF}></path>'
    f'<path d="{blob(4, -110, 34, 22, 7, 1.1, .4)}" style="opacity: .18" fill="#1E3A24" stroke="none"></path>'
    + fruits(0, -118, 44, 32, 3.2))
s4 = (
    '<path d="M-9 0 C-8 -36 -8 -70 -6 -100 L-26 -124 L-19 -129 L-3 -112 L-2 -132 L3 -132 L4 -112 L20 -130 L27 -125 L7 -100 C8 -70 8 -36 9 0 Z" fill="#8E6040"></path>'
    f'<path d="{blob(0, -158, 82, 54, 11)}" {DARK}></path>'
    f'<path d="{blob(8, -148, 56, 34, 9, 1.1, .3)}" style="opacity: .16" fill="#1E3A24" stroke="none"></path>'
    + fruits(0, -160, 74, 46, 3.6)
    + bird(-50, -205, "w0") + bird(44, -207, "w1", True) + bird(-78, -166, "w2"))
s5_tree = (
    '<path d="M-16 2 C-13 -40 -13 -80 -11 -120 L-36 -150 L-27 -156 L-5 -134 L-3 -176 L4 -176 L6 -134 L28 -158 L37 -152 L13 -120 C13 -80 13 -40 16 2 Z" fill="#8E6040"></path>'
    '<path d="M-16 1 C-24 3 -30 6 -34 8 M16 1 C24 3 30 6 34 8" fill="none" stroke-width="2.6"></path>'
    '<path d="M-11 -110 C-30 -112 -52 -112 -72 -108" fill="none" stroke="#8E6040" stroke-width="6" stroke-linecap="round"></path>'
    '<path d="M-11 -110 C-30 -112 -52 -112 -72 -108" fill="none" stroke-width="1.6" style="opacity: .6"></path>'
    f'<path d="{blob(0, -200, 116, 72, 13)}" {DARK}></path>'
    f'<path d="{blob(10, -188, 82, 46, 11, 1.1, .3)}" style="opacity: .15" fill="#1E3A24" stroke="none"></path>'
    '<g stroke-width="1" style="opacity: {{o.blossom}}; transition: opacity .6s ease">'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="3.2" fill="#F7C6D0"></circle>'
              for x, y in [(-90, -200), (-70, -236), (-36, -256), (0, -262), (36, -256), (70, -238), (92, -206), (-20, -214), (24, -224), (56, -186)])
    + '</g>'
    + fruits(0, -202, 104, 62, 4)
    # swing on the low branch
    + f'<g{opk("swing")}><path d="M-64 -108 V-46 M-48 -110 V-46" fill="none" stroke-width="1.3"></path>'
    '<rect x="-68" y="-48" width="24" height="4" rx="1.5" fill="#C8754F" stroke-width="1.2"></rect></g>'
    # nest on the right branch
    + f'<g{opk("nest")}><path d="M84 -128 L98 -120" fill="none" stroke="#8E6040" stroke-width="4" stroke-linecap="round"></path>'
    '<rect x="84" y="-124" width="28" height="4" rx="1" fill="#B07A4A" stroke-width="1.3"></rect>'
    '<path d="M87 -124 V-136 H109 V-124 M85 -136 L98 -145 L111 -136 Z" fill="#E6CF9F" stroke-width="1.3"></path>'
    '<rect x="95" y="-133" width="5" height="7" rx="1" fill="#8B5E3C" stroke-width="1"></rect></g>'
    + bird(-74, -262, "w0") + bird(-20, -276, "w1") + bird(30, -276, "w2", True)
    + bird(84, -260, "w3", True) + bird(-108, -224, "w4") + bird(112, -222, "w5", True)
)

# ------------------------------------------------------------ the palm's stages
def frond(a_deg, L, droop=0.0, w=0.2):
    a = math.radians(a_deg)
    tx, ty = L * math.cos(a), L * math.sin(a) + droop
    mx, my = L * .5 * math.cos(a), L * .5 * math.sin(a) - L * .18
    nx, ny = -math.sin(a) * L * w, math.cos(a) * L * w
    return (f'<path d="M0 0 Q{mx + nx:.1f} {my + ny:.1f} {tx:.1f} {ty:.1f} Q{mx - nx:.1f} {my - ny:.1f} 0 0 Z"></path>'
            f'<path d="M0 0 Q{mx:.1f} {my:.1f} {tx:.1f} {ty:.1f}" fill="none" stroke-width="0.9"></path>')

def crown(L, n=9, spread=(200, 340)):
    s = f'<g {FILL("palm")}>'
    for i in range(n):
        a = spread[0] + (spread[1] - spread[0]) * i / (n - 1)
        droop = L * .25 * abs(math.cos(math.radians(a)))
        s += frond(a, L, droop)
    return s + '</g>'

def palm_trunk(h, w0=7, w1=5):
    rings = ''.join(f'<path d="M{-w0 + (w0 - w1) * y / h:.1f} {-y} L{w0 - (w0 - w1) * y / h:.1f} {-y + 3}" fill="none" stroke-width="1.1"></path>'
                    for y in range(8, int(h), 9))
    return (f'<path d="M-{w0} 0 C-{w0 - 1} -{h * .4:.0f} -{w1 + 1} -{h * .8:.0f} -{w1} -{h} L{w1} -{h} '
            f'C{w1 + 1} -{h * .8:.0f} {w0 - 1} -{h * .4:.0f} {w0} 0 Z" fill="#B07A4A"></path>' + rings)

def date_clusters(y, spread=30):
    """Medals as dates: four bunches under the crown, five dates each."""
    cols = ["#C9772F", "#B5651D", "#D98E3A", "#A0522D", "#E0A24C"]
    centres = [(-spread * .45, y + 6), (spread * .45, y + 6), (-spread * .9, y + 2), (spread * .9, y + 2)]
    offs = [(0, 0), (-2.6, 3.4), (2.6, 3.4), (0, 6.8), (0, 10)]
    s = '<g stroke-width="0.8">'
    for i in range(20):
        cx, cy = centres[i % 4]; ox, oy = offs[i // 4]
        s += (f'<circle cx="{cx + ox:.1f}" cy="{cy + oy:.1f}" r="2.3" fill="{cols[i % 5]}"'
              f' style="opacity: {{{{o.m{i}}}}}; transition: opacity .6s ease"></circle>')
    return s + '</g>'

p1 = (f'<g transform="translate(0 -2)">{crown(30, 7, (195, 345))}</g>' + mound)
p2 = (palm_trunk(64, 7, 5) + f'<g transform="translate(0 -64)">{crown(44, 9)}</g>'
      + date_clusters(-62, 18))
p3 = (palm_trunk(158, 9, 6) + f'<g transform="translate(0 -158)">{crown(74, 11)}</g>'
      + date_clusters(-156, 28)
      + f'<g stroke-width="1"{opk("lanterns")}>'
      + ''.join(f'<path d="M{x} {y - 12} V{y - 5}" fill="none"></path>'
                f'<path d="M{x - 2.4} {y - 5} H{x + 2.4} L{x + 3} {y + 3} H{x - 3} Z" fill="#F2C14E"></path>'
                for x, y in [(-44, -128), (48, -126)])
      + '</g>'
      + bird(-66, -196, "w0") + bird(70, -194, "w1", True) + bird(-30, -222, "w2")
      + bird(34, -224, "w3", True) + bird(-92, -170, "w4") + bird(96, -168, "w5", True))

def grove_palm(x, y, k, key):
    return (f'<g transform="translate({x} {y}) scale({k})"{opk(key)}>' + palm_trunk(130, 8, 5)
            + f'<g transform="translate(0 -130)">{crown(60, 9)}</g></g>')

TREE_MAIN = (
    grove_palm(118, 318, .62, "grove") + grove_palm(300, 324, .55, "grove")
    + f'<g transform="{BASE}">'
    + f'<g{opk("t0")}>{s0}</g>'
    + f'<g{opk("t1")}>{s1}</g>'
    + f'<g{opk("t2")}>{s2}</g>'
    + f'<g{opk("t3")}>{s3}</g>'
    + f'<g{opk("t4")}>{s4}</g>'
    + f'<g{opk("t5")}><g transform="{{{{v.bigScale}}}}">{s5_tree}</g></g>'
    + f'<g{opk("p1")}>{p1}</g>'
    + f'<g{opk("p2")}>{p2}</g>'
    + f'<g{opk("p3")}><g transform="{{{{v.bigScale}}}}">{p3}</g></g>'
    + f'<g transform="translate(-30 0) scale(.9)"{opk("off1")}>' + crown(22, 6, (200, 340)) + '</g>'
    + f'<g transform="translate(34 2) scale(.8)"{opk("off2")}>' + crown(22, 6, (200, 340)) + '</g>'
    + '</g>'
)

FALLEN = ''.join(
    f'<ellipse cx="{x}" cy="{y}" rx="4" ry="2" transform="rotate({r} {x} {y})" stroke-width="1" style="fill: {{{{v.leaf}}}}; opacity: {{{{v.fall{i // 3}}}}}; transition: opacity .8s ease"></ellipse>'
    for i, (x, y, r) in enumerate([(232, 318, 20), (170, 320, -30), (214, 326, 60), (120, 330, 10), (276, 330, -20),
                                   (190, 334, 40), (250, 340, -50), (150, 344, 25), (226, 348, -15)]))

BUTTER = gp.butterflies.replace('(118, 150', '(110, 150')

def scene_svg(main, ground_items, extra=''):
    return (
        '<svg viewBox="0 0 360 400" width="100%" height="100%" style="position: absolute; left: 0; top: 0;" aria-hidden="true">'
        '<defs><clipPath id="doum-world-clip"><circle cx="180" cy="205" r="{{f.clipR}}"></circle></clipPath></defs>'
        '<g clip-path="url(#doum-world-clip)">'
        + GROUND
        + '<g stroke="#1E3A24" stroke-width="2" stroke-linejoin="round" stroke-linecap="round">'
        + main + ''.join(ground_items) + FALLEN + extra
        + '</g>'
        + gp.butterflies
        + '<ellipse cx="200" cy="{{v.ringY}}" rx="150" ry="104" fill="none" stroke="#F2C14E" stroke-width="3" stroke-dasharray="1 9" stroke-linecap="round" style="opacity: {{o.halo}}"></ellipse>'
        + '<g style="opacity: {{v.veil}}; transition: opacity 1s ease" fill="#14203A"><rect x="0" y="0" width="360" height="400"></rect></g>'
        + '</g></svg>'
    )

GLOW = (
    '<svg viewBox="0 0 360 400" width="100%" height="100%" style="position: absolute; left: 0; top: 0; pointer-events: none;" aria-hidden="true">'
    '<g fill="#FFE08A" style="opacity: {{v.lampGlow}}; transition: opacity 1s ease">'
    '<circle cx="{{g.ax}}" cy="{{g.ay}}" r="8" style="opacity: .5"></circle><circle cx="{{g.bx}}" cy="{{g.by}}" r="8" style="opacity: .5"></circle><circle cx="{{g.cx}}" cy="{{g.cy}}" r="8" style="opacity: .5"></circle>'
    '<circle cx="{{g.ax}}" cy="{{g.ay}}" r="3"></circle><circle cx="{{g.bx}}" cy="{{g.by}}" r="3"></circle><circle cx="{{g.cx}}" cy="{{g.cy}}" r="3"></circle></g>'
    '<g fill="#F2C14E" stroke="#1E3A24" stroke-width="1.2" style="opacity: {{v.sparkle}}; transition: opacity .6s ease">'
    + star(70, 170, 7) + star(300, 150, 6) + star(320, 250, 6) + star(46, 250, 5) + star(250, 90, 4.5)
    + '</g>'
    '<g fill="#6FB7DB" stroke="#1E3A24" stroke-width="1" style="opacity: {{v.drops}}; transition: opacity .5s ease">'
    '<path d="M{{g.dx}} 296 c2 4 3 6 0 8 c-3 -2 -2 -4 0 -8 Z"></path>'
    '<path d="M{{g.dx2}} 306 c2 4 3 6 0 8 c-3 -2 -2 -4 0 -8 Z"></path>'
    '</g></svg>'
)

COMMON_JS = r"""
    const P = this.props;
    const num = (v, d) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
    const yes = (v) => v === true || v === 'true';
    const L = Math.max(1, Math.min(100, Math.round(num(P.level, 12))));
    const sky = P.sky ?? 'day';
    const night = sky === 'night', rest = sky === 'rest';
    const season = P.season ?? 'none';
    const t = rest ? 0 : Math.max(0, Math.min(3, Math.round(num(P.thirst, 0))));
    const watering = yes(P.watering), glowing = yes(P.glowing);
    const S = num(P.size, 360), H = S * 400 / 360;
    const ct = (P.quietStyle ?? 'thirsty') === 'quiet' ? 0 : t;
    const frame = P.frame ?? 'bubble';
    const on = (b) => (b ? 1 : 0);
    const has = (n) => on(L >= n);
    const span = (a, b) => on(L >= a && L < b);
    const flyers = on(t < 2 && !night && !rest);
    const weeks = Math.max(0, Math.min(6, Math.round(num(P.pearls, 2))));
    const medals = Math.max(0, Math.min(20, Math.round(num(P.medals, 5))));
    const skyDay = season === 'winter' ? ['#DCE7F2', '#E4EBEA', '#ECEADF', '#F1E6D2'] : ['#DDF0F1', '#E7F0E5', '#EFEBDA', '#F4E5CB'];
    const skyCol = night ? '#22304A' : rest ? '#E5E6EE' : skyDay[ct];
    const v = {
      sky: skyCol, moonCover: frame === 'none' ? (P.bg ?? '#F5F0E1') : skyCol,
      soil: ['#C99A62', '#CFA36C', '#D5AD78', '#DBB785'][ct],
      grass: ['#A3D46F', '#B3CF72', '#C4C97D', '#D2C28A'][ct],
      leaf: ['#5DAE5F', '#78AE60', '#94AE66', '#AAAD70'][ct],
      leafDark: ['#4C9A55', '#669D57', '#829F5E', '#999F68'][ct],
      palm: ['#62B261', '#7DB063', '#98AF68', '#ADAC72'][ct],
      water: ['#86CBE6', '#93CDE2', '#A9CFD9', '#C4D2C8'][ct],
      open: on(t < 2), bud: on(t >= 2), head: t >= 2 ? 'scale(0.6)' : 'scale(1)',
      fall0: on(ct >= 1), fall1: on(ct >= 2), fall2: on(ct >= 3),
      sun: on(!night && !rest), sunR: season === 'summer' ? 19 : season === 'winter' ? 12 : 15,
      restClouds: on(rest), stars1: on(night), stars2: on(night && L >= 30),
      moon: on(L >= 26 || season === 'ramadan' || night), rain: on(watering && L >= 27),
      veil: night ? 0.34 : 0, lampGlow: on(night && L >= 26), sparkle: on(glowing && !night), drops: on(watering),
      rainbow: on((P.visitor ?? 'none') === 'rainbow' && !night), shoot: on((P.visitor ?? 'none') === 'star' && night)
    };
    const f = { bubble: on(frame === 'bubble'), rect: on(frame === 'rect'), none: on(frame === 'none'), clipR: frame === 'bubble' ? 176 : 600 };
    const o = { cloud: has(27), halo: has(100), blossom: has(75), butterflies: has(7) * flyers,
      stones: has(3), flowers: has(4), jasmine: has(8), pond: has(11), bench: has(16), hive: has(19), bees: has(19) * flyers };
    for (let i = 0; i < 20; i++) o['m' + i] = on(i < medals);
    for (let i = 0; i < 6; i++) o['w' + i] = on(i < weeks) * on(t < 2);
    const POSES = {
      wave: ['4fe66825d4a1e1409975aaf4cae25efe', 633, 767, .5], three: ['bda45ed574b609786b0ad5e6f32cc9c1', 597, 750, .5],
      water: ['ff0714f75ca540d6b9e854eb7ec643f0', 825, 824, .46], plant: ['239821cb47d27696b528956bd28c88b8', 688, 760, .42],
      sleep: ['83c02ebb24494b1bec34815440654d97', 850, 679, .5], sparkles: ['f54c56f0458a9bc4ac82dc5d45c2870f', 700, 802, .5],
      lantern: ['4fa5d30b3b6336e626650625981d86c7', 816, 742, .5], campfire: ['9c5ba12e77d19a5133b9fd4ec083faae', 949, 671, .4],
      jump: ['01a0919e008df49374de250038e990bb', 856, 798, .5], heart: ['1b550d444d0dfca059dcdb1c7813cd9f', 649, 784, .5],
      stretch: ['731fcb2d865e54dac2b4bc291fcdd834', 709, 752, .5], shades: ['5a2a333e3f11af16ca86594b10860e0b', 640, 792, .5],
      reading: ['d7da928b4416045e8827a7fbc17d0196', 641, 793, .5], checklist: ['9c76ee772c36eb0fa8ed51ab66ce89d0', 679, 778, .5],
      lamp: ['461bdb5cccdd5ae5ce8903c53c32573f', 928, 809, .45], flag: ['5b4aafdce4a2e380b9f1c852f6271550', 943, 904, .45],
    };
    let pose = P.pose ?? 'auto';
    if (pose === 'auto') {
      if (night && season === 'ramadan') pose = 'lantern';
      else if (night || rest) pose = 'sleep';
      else if (watering || t >= 1) pose = 'water';
      else if (glowing) pose = 'sparkles';
      else pose = 'wave';
    }
    const pd = POSES[pose];
    const k = (64 / 767) * (S / 360);
    const doum = (bx, by) => pd
      ? { show: true, src: '/_blob/' + pd[0], w: pd[1] * k, h: pd[2] * k, left: bx * S / 360 - pd[1] * k * pd[3], top: by * S / 360 - pd[2] * k }
      : { show: false, src: '', w: 0, h: 0, left: 0, top: 0 };
"""

def page(title, svg_main, js_specific, props_extra=''):
    PROPS = ('{' + props_extra + '"quietStyle":{"editor":"enum","options":["thirsty","quiet"],"default":"thirsty","section":"Today"},"visitor":{"editor":"enum","options":["none","rainbow","star"],"default":"none","section":"Today"},' +
             '"level":{"editor":"range","min":1,"max":100,"step":1,"default":12,"section":"Growth"},'
             '"medals":{"editor":"range","min":0,"max":20,"step":1,"default":5,"section":"Growth"},'
             '"pearls":{"editor":"range","min":0,"max":6,"step":1,"default":2,"section":"Growth"},'
             '"thirst":{"editor":"range","min":0,"max":3,"step":1,"default":0,"section":"Today"},'
             '"watering":{"editor":"boolean","default":false,"section":"Today"},'
             '"glowing":{"editor":"boolean","default":false,"section":"Today"},'
             '"sky":{"editor":"enum","options":["day","night","rest"],"default":"day","section":"Today"},'
             '"season":{"editor":"enum","options":["none","ramadan","winter","summer"],"default":"none","section":"Today"},'
             '"pose":{"editor":"enum","options":["auto","wave","three","water","plant","sleep","sparkles","lantern","campfire","jump","heart","stretch","shades","reading","checklist","lamp","flag","none"],"default":"auto","section":"Doum"},'
             '"frame":{"editor":"enum","options":["bubble","rect","none"],"default":"bubble","section":"Frame"},'
             '"bg":{"editor":"color","default":"#F5F0E1","section":"Frame"},'
             '"size":{"editor":"int","default":360,"section":"Frame"},'
             '"$preview":{"width":360,"height":400}}')
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
</style>
</helmet>
<div role="img" aria-label="{{{{alt}}}}" style="position: relative; width: {{{{S}}}}px; height: {{{{H}}}}px; overflow: hidden; border-radius: {{{{radius}}}}; font-family: 'IBM Plex Sans', sans-serif; color: #23352A;">
{SKY}
{svg_main}
<sc-if value="{{{{d.show}}}}" hint-placeholder-val="{{{{true}}}}">
<img src="{{{{d.src}}}}" alt="" style="position: absolute; left: {{{{d.left}}}}px; top: {{{{d.top}}}}px; width: {{{{d.w}}}}px; height: {{{{d.h}}}}px;">
</sc-if>
{GLOW}
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{PROPS}'>
class Component extends DCLogic {{
  renderVals() {{
{COMMON_JS}
{js_specific}
  }}
}}
</script>
</body>
</html>
"""

TREE_JS = r"""
    const palm = (P.kind ?? 'tree') === 'palm';
    const tree = !palm;
    const stage = L >= 20 ? 5 : L >= 15 ? 4 : L >= 10 ? 3 : L >= 5 ? 2 : L >= 2 ? 1 : 0;
    const pst = L >= 20 ? 3 : L >= 10 ? 2 : L >= 2 ? 1 : 0;
    o.t0 = on(tree && stage === 0 || palm && pst === 0);
    o.t1 = on(tree && stage === 1); o.t2 = on(tree && stage === 2); o.t3 = on(tree && stage === 3);
    o.t4 = on(tree && stage === 4); o.t5 = on(tree && stage === 5);
    o.p1 = on(palm && pst === 1); o.p2 = on(palm && pst === 2); o.p3 = on(palm && pst === 3);
    o.off1 = on(palm && L >= 25); o.off2 = on(palm && L >= 30); o.grove = on(palm && L >= 35);
    o.swing = has(22); o.nest = has(24); o.lanterns = has(26);
    let bs = 0.86;
    for (const [lv, s] of [[25, .89], [30, .92], [35, .95], [50, .98], [75, 1.01], [100, 1.04]]) if (L >= lv) bs = s;
    v.bigScale = 'translate(0 0) scale(' + bs + ')';
    v.ringY = palm ? 311 - 150 * bs : 311 - 196 * bs;
    const lp = palm ? [[-44, -128], [48, -126], [-44, -128]] : [[-34, -116], [8, -112], [62, -120]];
    const g = { ax: 200 + lp[0][0] * bs, ay: 311 + lp[0][1] * bs, bx: 200 + lp[1][0] * bs, by: 311 + lp[1][1] * bs,
      cx: 200 + lp[2][0] * bs, cy: 311 + lp[2][1] * bs, dx: 150, dx2: 160 };
    const d = doum(100, 316);
    const radius = frame === 'rect' ? '0' : '0';
    return { o, v, f, g, d, S, H, radius, alt: (palm ? 'Doum’s palm' : 'Doum’s tree') + ' at level ' + L };
"""

tree_svg = scene_svg(TREE_MAIN, G_ITEMS)
tree_html = page("Doum's tree", tree_svg, TREE_JS,
                 '"kind":{"editor":"enum","options":["tree","palm"],"default":"tree","section":"Growth"},')

# ------------------------------------------------------------ the farm
FX0, FY0, COLS, ROWS, PW, PH, GAP = 110, 172, 7, 5, 24, 24, 4
CROPS = ["sprout", "lettuce", "carrot", "flower", "tomato", "sunflower", "corn",
         "strawberry", "pumpkin", "lavender", "lemon", "well", "pepper", "rose",
         "palm", "melon", "mint", "hive", "grapes", "flower", "pomegranate",
         "lettuce", "carrot", "tomato", "sunflower", "fig", "corn", "strawberry",
         "pumpkin", "jasmine", "lemon", "palm", "rose", "melon", "date"]

def crop(kind):
    L_ = f'style="fill: {{{{v.leaf}}}}; transition: fill 1.2s ease"'
    if kind == "sprout":
        return f'<path d="M0 4 V-2" fill="none" stroke-width="1.4"></path><g {L_} stroke-width="1"><ellipse cx="-3" cy="-3" rx="3.4" ry="1.8" transform="rotate(-25 -3 -3)"></ellipse><ellipse cx="3" cy="-3" rx="3.4" ry="1.8" transform="rotate(25 3 -3)"></ellipse></g>'
    if kind in ("lettuce", "mint"):
        return f'<circle cx="0" cy="0" r="8" {L_} stroke-width="1.2"></circle><path d="M-4 -2 Q0 2 4 -2 M-3 3 Q0 5 3 3" fill="none" stroke-width="0.9"></path>'
    if kind == "carrot":
        return f'<path d="M-3 2 L0 9 L3 2 Z" fill="#F29B38" stroke-width="1"></path><g {L_} stroke-width="1"><path d="M0 2 C-5 -4 -5 -8 -3 -9 C-1 -6 0 -2 0 2 Z"></path><path d="M0 2 C5 -4 5 -8 3 -9 C1 -6 0 -2 0 2 Z"></path></g>'
    if kind in ("flower", "rose", "jasmine"):
        col = {"flower": "#F49AB0", "rose": "#E2687C", "jasmine": "#FFFFFF"}[kind]
        return (f'<path d="M0 8 V0" fill="none" stroke-width="1.2"></path><g style="opacity: {{{{v.open}}}}">'
                + gp.petals(0, -2, col, 2.6) + '</g>'
                f'<g style="opacity: {{{{v.bud}}}}"><ellipse cx="0" cy="-2" rx="2.4" ry="3.4" fill="{col}" stroke-width="1"></ellipse></g>')
    if kind in ("tomato", "strawberry", "pepper"):
        col = {"tomato": "#E0574F", "strawberry": "#D94A5C", "pepper": "#E2A33B"}[kind]
        return (f'<circle cx="0" cy="0" r="8" {L_} stroke-width="1.2"></circle>'
                + ''.join(f'<circle cx="{x}" cy="{y}" r="2" fill="{col}" stroke-width="0.8"></circle>' for x, y in [(-3, -2), (3, 1), (-1, 4), (4, -4)]))
    if kind == "sunflower":
        return '<path d="M0 9 V0" fill="none" stroke-width="1.4"></path><circle cx="0" cy="-3" r="6" fill="#F2C14E" stroke-width="1"></circle><circle cx="0" cy="-3" r="2.6" fill="#8B5E3C" stroke-width="0.8"></circle>'
    if kind == "corn":
        return f'<g {L_} stroke-width="1"><path d="M-2 9 C-6 0 -6 -6 -4 -10 C-2 -4 -1 2 -2 9 Z"></path><path d="M2 9 C6 0 6 -6 4 -10 C2 -4 1 2 2 9 Z"></path></g><ellipse cx="0" cy="-2" rx="2.6" ry="6" fill="#F4D35E" stroke-width="1"></ellipse>'
    if kind in ("pumpkin", "melon"):
        col = "#F29B38" if kind == "pumpkin" else "#7CB86A"
        return f'<ellipse cx="0" cy="2" rx="8" ry="6" fill="{col}" stroke-width="1.2"></ellipse><path d="M0 -4 V2 M-4 -2 Q-5 2 -4 6 M4 -2 Q5 2 4 6" fill="none" stroke-width="0.9"></path>'
    if kind == "lavender":
        return ''.join(f'<path d="M{x} 9 V-2" fill="none" stroke-width="1"></path><ellipse cx="{x}" cy="-5" rx="1.8" ry="4" fill="#9C8AD0" stroke-width="0.8"></ellipse>' for x in (-4, 0, 4))
    if kind in ("lemon", "pomegranate", "fig"):
        col = {"lemon": "#F4D35E", "pomegranate": "#D9534F", "fig": "#7E5AA8"}[kind]
        return (f'<path d="M-1.4 10 L-1 -1 L1 -1 L1.4 10 Z" fill="#A9774A" stroke-width="1"></path>'
                f'<circle cx="0" cy="-5" r="8.5" {L_} stroke-width="1.2"></circle>'
                + ''.join(f'<circle cx="{x}" cy="{y}" r="1.8" fill="{col}" stroke-width="0.7"></circle>' for x, y in [(-4, -6), (3, -8), (2, -2), (-2, -10)]))
    if kind in ("palm", "date"):
        s = '<path d="M-1.6 10 L-1 -4 L1 -4 L1.6 10 Z" fill="#B07A4A" stroke-width="1"></path>'
        s += f'<g transform="translate(0 -4)" stroke-width="1">' + crown(11, 6, (200, 340)) + '</g>'
        if kind == "date":
            s += '<g stroke-width="0.6"><circle cx="-2" cy="-1" r="1.5" fill="#C9772F"></circle><circle cx="2" cy="-1" r="1.5" fill="#C9772F"></circle></g>'
        return s
    if kind == "well":
        return f'<g transform="translate(0 9) scale(.6)">' + gp.well + '</g>'
    if kind == "hive":
        return f'<g transform="translate(0 8) scale(.9)">' + gp.hive + '</g>'
    if kind == "grapes":
        return '<path d="M0 -8 V-4" fill="none" stroke-width="1.2"></path>' + ''.join(f'<circle cx="{x}" cy="{y}" r="2" fill="#7E5AA8" stroke-width="0.8"></circle>' for x, y in [(-3, -2), (0, -2), (3, -2), (-1.5, 1), (1.5, 1), (0, 4)])
    return ''

plots = ''
for i in range(COLS * ROWS):
    r, c = divmod(i, COLS)
    x = FX0 + c * (PW + GAP); y = FY0 + r * (PH + GAP)
    plots += (f'<g transform="translate({x} {y})">'
              f'<rect x="0" y="2" width="{PW}" height="{PH}" rx="7" fill="#8E6A45" stroke="none" style="opacity: .5"></rect>'
              f'<rect x="0" y="0" width="{PW}" height="{PH}" rx="7" stroke-width="1.6" style="fill: {{{{v.soil}}}}; transition: fill 1.2s ease"></rect>'
              f'<path d="M5 {PH - 6} l4 -3 l3 3 M{PW - 10} 7 l3 3 l4 -2" fill="none" stroke-width="1" style="opacity: {{{{v.cracks}}}}; transition: opacity .8s ease"></path>'
              f'<g transform="translate({PW / 2} {PH / 2 - 1}) scale(.82)"{opk(f"c{i}")}>' + crop(CROPS[i]) + '</g>'
              f'<circle cx="{PW / 2}" cy="{PH / 2}" r="1.6" fill="#7A5A3A" stroke="none" style="opacity: {{{{o.e{i}}}}}"></circle>'
              '</g>')
FW = COLS * PW + (COLS - 1) * GAP; FH = ROWS * PH + (ROWS - 1) * GAP
FARM_MAIN = (
    f'<path d="M-20 420 L-20 128 C100 118 260 118 380 128 L380 420 Z" stroke="#1E3A24" stroke-width="2.6" {FILL("grass")}></path>'
    f'<rect x="{FX0 - 10}" y="{FY0 - 10}" width="{FW + 20}" height="{FH + 20}" rx="12" fill="#B48A5E" stroke-width="2"></rect>'
    + plots
    + f'<path d="M{FX0 - 14} {FY0 - 14} H{FX0 + FW + 14} V{FY0 + FH + 14} H{FX0 - 14} Z" fill="none" stroke="#B07A4A" stroke-width="2.4" stroke-dasharray="3 7"></path>'
    # medal flowers along the hedge above the field
    + ''.join(f'<g transform="translate({FX0 - 4 + i * (FW + 8) / 19:.1f} {FY0 - 18})"{opk(f"m{i}")}>' + gp.bloom(gp.BLOOM_KINDS[i]) + '</g>'
              for i in range(20))
    # baskets for weeks in a row, stacked by Doum
    + ''.join(f'<g transform="translate({128 + (i % 3) * 18} {352 - (i // 3) * 14})"{opk(f"w{i}")}>'
              '<path d="M-8 -8 L8 -8 L6 0 L-6 0 Z" fill="#C8954F" stroke-width="1.4"></path>'
              '<path d="M-6 -8 C-6 -14 6 -14 6 -8" fill="none" stroke-width="1.2"></path>'
              f'<circle cx="-3" cy="-9" r="2.2" fill="{["#E0574F", "#F29B38", "#7E5AA8", "#F4D35E", "#D9534F", "#7CB86A"][i]}" stroke-width="0.8"></circle>'
              f'<circle cx="2" cy="-9.4" r="2.2" fill="{["#F29B38", "#E0574F", "#F4D35E", "#7E5AA8", "#7CB86A", "#D9534F"][i]}" stroke-width="0.8"></circle></g>'
              for i in range(6))
    # a barn after level 35
    + f'<g transform="translate(58 170)"{opk("barn")}>'
    '<path d="M-24 0 V-26 L0 -42 L24 -26 V0 Z" fill="#C8754F"></path>'
    '<path d="M-8 0 V-16 H8 V0 Z" fill="#8B5E3C"></path><path d="M-8 -16 L8 0 M8 -16 L-8 0" fill="none" stroke-width="1.2"></path>'
    '<path d="M-27 -24 L0 -45 L27 -24" fill="none" stroke-width="3"></path></g>'
)
FARM_JS = r"""
    for (let i = 0; i < 35; i++) { o['c' + i] = on(L >= i + 1); o['e' + i] = on(L < i + 1); }
    o.barn = has(35);
    v.cracks = ct >= 2 ? 0.7 : 0;
    v.ringY = -100;
    const g = { ax: -50, ay: -50, bx: -50, by: -50, cx: -50, cy: -50, dx: 80, dx2: 92 };
    const d = doum(66, 306);
    return { o, v, f, g, d, S, H, radius: '0', alt: 'Doum’s farm at level ' + L };
"""
farm_svg = scene_svg(FARM_MAIN, [])
# the farm has no tree ring or fallen leaves near a trunk: keep the shared scene, it is harmless
farm_html = page("Doum's farm", farm_svg, FARM_JS)

with open(os.path.join(HERE, "project", "Tree.dc.html"), "w") as fh:
    fh.write(tree_html)
with open(os.path.join(HERE, "project", "Farm.dc.html"), "w") as fh:
    fh.write(farm_html)
print(len(tree_html), len(farm_html))
