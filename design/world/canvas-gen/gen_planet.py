"""Generates project/Planet.dc.html: Doum's planet as one reusable component.

Everything that varies (level, thirst, sky, season) is a style or attribute
hole, so the SVG never needs a loop. Items are drawn in local coordinates
with their base at (0, 0) growing up (negative y), then placed on the
planet's surface by a rotation about its centre (180, 250), radius 100.
"""
import math, os

ROOT = os.path.join(os.path.dirname(__file__), "project")

K = 1.15  # item scale on the surface

def at(theta, inner, extra="", k=K):
    sc = f' scale({k})' if k != 1 else ''
    return (f'<g transform="translate(180 256) rotate({theta}) translate(0 -89){sc}"{extra}>'
            f'{inner}</g>')

def op(key):
    return f' style="opacity: {{{{o.{key}}}}}; transition: opacity .6s ease"'

FILL = lambda k: f'style="fill: {{{{v.{k}}}}}; transition: fill 1.2s ease"'

# ---------------------------------------------------------------- items
sprouts = (
    '<path d="M-8 1 V-6" fill="none"></path>'
    '<path d="M3 1 V-9" fill="none"></path>'
    f'<g {FILL("leaf")}>'
    '<path d="M-8 -6 C-12 -6 -14 -9 -13 -11 C-10 -11 -8 -9 -8 -6 Z"></path>'
    '<path d="M-8 -6 C-4 -6 -2 -9 -3 -11 C-6 -11 -8 -9 -8 -6 Z"></path>'
    '<path d="M3 -9 C-1 -9 -3 -12 -2 -14 C1 -14 3 -12 3 -9 Z"></path>'
    '<path d="M3 -9 C7 -9 9 -12 8 -14 C5 -14 3 -12 3 -9 Z"></path>'
    '</g>'
)

stones = (
    '<ellipse cx="-11" cy="-2" rx="5" ry="3" fill="#D6CCBA"></ellipse>'
    '<ellipse cx="0" cy="-2.6" rx="5.6" ry="3.4" fill="#CFC4B0"></ellipse>'
    '<ellipse cx="11" cy="-2" rx="4.6" ry="2.9" fill="#D6CCBA"></ellipse>'
)

pond = (
    f'<ellipse cx="0" cy="-2" rx="15" ry="5" {FILL("water")}></ellipse>'
    '<path d="M-8 -3 Q-5 -5 -2 -3" fill="none" stroke="#FFFFFF" stroke-width="1.4"></path>'
    '<ellipse cx="-17" cy="-2" rx="4.4" ry="3" fill="#D6CCBA"></ellipse>'
    '<ellipse cx="17" cy="-2" rx="4.4" ry="3" fill="#D6CCBA"></ellipse>'
)

arch = (
    '<path d="M-19 -3 C-19 -34 19 -34 19 -3" fill="none" stroke-width="5.5"></path>'
    f'<path d="M-19 -3 C-19 -34 19 -34 19 -3" fill="none" stroke-width="3" {FILL("leafDark").replace("fill:", "stroke:").replace("fill 1.2s", "stroke 1.2s")}></path>'
    '<g stroke-width="1" style="opacity: {{v.open}}; transition: opacity .8s ease">'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="2.6" fill="#E2687C"></circle>'
              for x, y in [(-17, -16), (-12, -24), (-4, -28), (5, -28), (12, -24), (17, -15)])
    + '</g>'
)

def petals(cx, cy, col, r=2.4):
    pts = [(0, -3), (2.9, -0.9), (1.8, 2.4), (-1.8, 2.4), (-2.9, -0.9)]
    s = f'<g transform="translate({cx} {cy})" stroke-width="1">'
    s += ''.join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{col}"></circle>' for x, y in pts)
    s += '<circle cx="0" cy="0" r="1.6" fill="#F2C14E"></circle></g>'
    return s

flowers = (
    '<path d="M-8 0 V-11 M0 0 V-15 M8 0 V-10" fill="none" stroke-width="1.6"></path>'
    '<g style="opacity: {{v.open}}; transition: opacity .8s ease">'
    + petals(-8, -13, "#F49AB0") + petals(0, -17, "#F7C6D0") + petals(8, -12, "#F49AB0")
    + '</g><g stroke-width="1" style="opacity: {{v.bud}}; transition: opacity .8s ease">'
    '<ellipse cx="-8" cy="-12" rx="2" ry="3" fill="#E9A3B3"></ellipse>'
    '<ellipse cx="0" cy="-16" rx="2" ry="3" fill="#EFBFC9"></ellipse>'
    '<ellipse cx="8" cy="-11" rx="2" ry="3" fill="#E9A3B3"></ellipse></g>'
)

well = (
    '<path d="M-6 -12 V-27 M6 -12 V-27" fill="none" stroke-width="2.2"></path>'
    '<path d="M-10.5 -25 L0 -33 L10.5 -25 Z" fill="#C8754F"></path>'
    '<path d="M0 -25 V-19" fill="none" stroke-width="1.2"></path>'
    '<rect x="-2.4" y="-19" width="4.8" height="4" rx="1" fill="#A0703F" stroke-width="1.2"></rect>'
    '<path d="M-10 0 V-12 H10 V0 Z" fill="#D9C3A0"></path>'
    '<path d="M-10 -6 H10 M-4 -12 V-6 M4 -6 V0" fill="none" stroke-width="1.1"></path>'
    f'<ellipse cx="0" cy="-12" rx="10" ry="2.6" {FILL("water")}></ellipse>'
)

hoopoe = (  # level 24: a brass telescope beside the well (no animals: halal art)
    '<g transform="translate(17 0)" stroke-width="1.3">'
    '<path d="M0 -12 L-5 0 M0 -12 L5 0 M0 -12 L0 0" fill="none"></path>'
    '<path d="M-1.6 -11 L-12 -21.5 L-9 -24.5 L1.4 -14 Z" fill="#C9A23A"></path>'
    '<ellipse cx="-10.6" cy="-23" rx="2.2" ry="3" transform="rotate(-45 -10.6 -23)" fill="#8FCBE0"></ellipse>'
    '</g>'
)

PALM_TRUNK = '<path d="M-3 0 C-2 -16 0 -30 2 -44 L6 -44 C4 -30 3 -16 4 0 Z" fill="#B07A4A"></path>'
PALM_RINGS = '<path d="M-2.4 -8 H3.6 M-1.6 -16 H3.6 M-0.8 -24 H3.8 M0.2 -32 H4.4 M1.2 -39 H5.2" fill="none" stroke-width="1.1"></path>'
PALM_CROWN = (
    f'<g {FILL("palm")}>'
    '<path d="M4 -44 C-6 -50 -16 -46 -20 -36 C-12 -42 -4 -43 4 -42 Z"></path>'
    '<path d="M4 -44 C-4 -56 -14 -58 -21 -53 C-11 -52 -3 -49 4 -44 Z"></path>'
    '<path d="M4 -44 C3 -56 8 -63 14 -65 C9 -58 6 -51 5 -44 Z"></path>'
    '<path d="M4 -44 C12 -56 23 -58 29 -52 C19 -52 11 -49 4 -44 Z"></path>'
    '<path d="M4 -44 C14 -50 24 -46 28 -36 C20 -42 12 -43 4 -42 Z"></path>'
    '</g>'
)
palm = PALM_TRUNK + PALM_RINGS + PALM_CROWN + (
    '<g stroke-width="1" style="opacity: {{o.dates}}; transition: opacity .6s ease">'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="2.3" style="fill: {{{{v.dates}}}}"></circle>'
              for x, y in [(0, -40), (2.6, -37.2), (-2.2, -36.8), (8, -40), (10.4, -37), (5.8, -36.8)])
    + '</g>'
)
sapling = '<g transform="scale(0.42)" stroke-width="4.6">' + PALM_TRUNK + PALM_CROWN + '</g>'
grove_palm = '<g transform="scale(0.82)" stroke-width="2.4">' + PALM_TRUNK + PALM_RINGS + PALM_CROWN + '</g>'

bed = (
    '<path d="M-8 -5 V-10 M0 -5 V-11 M8 -5 V-10" fill="none" stroke-width="1.4"></path>'
    f'<g stroke-width="1.2" {FILL("leaf")}>'
    + ''.join(f'<ellipse cx="{x - 2.2}" cy="{y}" rx="2.6" ry="1.5" transform="rotate(-25 {x - 2.2} {y})"></ellipse>'
              f'<ellipse cx="{x + 2.2}" cy="{y}" rx="2.6" ry="1.5" transform="rotate(25 {x + 2.2} {y})"></ellipse>'
              for x, y in [(-8, -10), (0, -11), (8, -10)])
    + '</g><rect x="-14" y="-5" width="28" height="5" rx="1.5" fill="#9C6B43"></rect>'
)
farm = (
    '<path d="M-21 0 V-11 M-7 0 V-11 M7 0 V-11 M21 0 V-11 M-21 -8 H21" fill="none" stroke-width="1.3"></path>'
    f'<g {FILL("leaf")}>'
    '<circle cx="-11" cy="-9" r="4.6"></circle><circle cx="0" cy="-10.5" r="5.2"></circle><circle cx="11" cy="-9" r="4.6"></circle>'
    '</g><g stroke-width="0.8">'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="1.7" fill="#E0574F"></circle>'
              for x, y in [(-12, -8), (-9, -11), (1, -9), (-2, -13), (10, -10), (12, -7)])
    + '</g><rect x="-17" y="-5" width="34" height="5" rx="1.5" fill="#9C6B43"></rect>'
)

jasmine = (
    f'<path d="M-12 0 C-16 -8 -10 -17 -3 -15 C0 -21 10 -19 10 -12 C16 -10 15 0 10 0 Z" {FILL("leafDark")}></path>'
    '<g stroke-width="0.8" style="opacity: {{v.open}}; transition: opacity .8s ease">'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="1.8" fill="#FFFFFF"></circle>'
              for x, y in [(-8, -8), (-3, -13), (4, -15), (8, -9), (1, -7), (-6, -3), (10, -4)])
    + '</g>'
)


# ---- farm mode: crop rows on the surface, furrows on the planet's face
ROW_STRIP = ('<path d="M-17 1 Q0 -3 17 1 L17 -3.4 Q0 -7.4 -17 -3.4 Z" fill="#9C6B43"></path>'
             '<path d="M-13 -4.4 Q0 -7 13 -4.4" fill="none" stroke-width="0.9" style="opacity: .5"></path>')

def _lettuce(x):
    return (f'<g transform="translate({x} -9)"><circle cx="0" cy="0" r="4.6" {FILL("leaf")} stroke-width="1.1"></circle>'
            '<path d="M-2.4 -1 Q0 1.4 2.4 -1" fill="none" stroke-width="0.8"></path></g>')

def _carrot(x):
    return (f'<g transform="translate({x} -6)"><path d="M-1.8 0 L0 4 L1.8 0 Z" fill="#F29B38" stroke-width="0.9"></path>'
            f'<g {FILL("leaf")} stroke-width="0.9"><path d="M0 0 C-3.4 -4 -3.4 -7 -2 -8 C-0.6 -5.6 0 -3 0 0 Z"></path>'
            '<path d="M0 0 C3.4 -4 3.4 -7 2 -8 C0.6 -5.6 0 -3 0 0 Z"></path></g></g>')

def _tomato(x):
    return (f'<g transform="translate({x} -10)"><path d="M0 6 V-2" fill="none" stroke-width="1.1"></path>'
            f'<circle cx="0" cy="-2" r="5" {FILL("leaf")} stroke-width="1.1"></circle>'
            '<g style="opacity: {{v.open}}; transition: opacity .8s ease" stroke-width="0.7">'
            '<circle cx="-2" cy="-2" r="1.7" fill="#E0574F"></circle><circle cx="2.2" cy="0" r="1.7" fill="#E0574F"></circle><circle cx="1" cy="-4.4" r="1.5" fill="#E0574F"></circle></g></g>')

row_lettuce = ROW_STRIP + ''.join(_lettuce(x) for x in (-11, 0, 11))
row_carrot = ROW_STRIP + ''.join(_carrot(x) for x in (-11, -4, 4, 11))
row_tomato = ROW_STRIP + ''.join(_tomato(x) for x in (-10, 0, 10))

def _arc(r, a0=-58, a1=58):
    x0 = 180 + r * math.sin(math.radians(a0)); y0 = 256 - r * math.cos(math.radians(a0))
    x1 = 180 + r * math.sin(math.radians(a1)); y1 = 256 - r * math.cos(math.radians(a1))
    return f'M{x0:.1f} {y0:.1f} A{r} {r} 0 0 1 {x1:.1f} {y1:.1f}'

def _row(y):
    w = math.sqrt(90 ** 2 - (y - 256) ** 2) - 14
    return f'M{180 - w:.1f} {y} Q180 {y + 11} {180 + w:.1f} {y}', w

FURROWS = ('<g style="opacity: {{o.furrows}}; transition: opacity .6s ease" fill="none">'
           + ''.join(f'<path d="{_row(y)[0]}" stroke="#1E3A24" stroke-width="9" stroke-linecap="round"></path>'
                     f'<path d="{_row(y)[0]}" stroke="#A8784A" stroke-width="6.4" stroke-linecap="round"></path>'
                     for y in (198, 220, 242))
           + '<g style="opacity: {{o.seedlings}}">'
           + ''.join(f'<circle cx="{180 + f * _row(y)[1]:.1f}" cy="{y + 5.5 * (1 - f * f) - 2:.1f}" r="2.5" stroke="#1E3A24" stroke-width="0.9" style="fill: {{{{v.leaf}}}}; transition: fill 1.2s ease"></circle>'
                     for y in (198, 220, 242) for f in (-0.75, -0.45, -0.15, 0.15, 0.45, 0.75))
           + '</g></g>')

def tree_trunk(h=20, w=2.6, col="#A9774A"):
    return (f'<path d="M-{w} 0 C-{w*0.8:.1f} -{h*0.4:.0f} -{w*0.8:.1f} -{h*0.7:.0f} -{w*0.6:.1f} -{h} '
            f'L{w*0.6:.1f} -{h} C{w*0.8:.1f} -{h*0.7:.0f} {w*0.8:.1f} -{h*0.4:.0f} {w} 0 Z" fill="{col}"></path>')

lemon = (
    tree_trunk(20)
    + f'<path d="M-14 -24 C-18 -32 -10 -44 0 -43 C10 -44 18 -34 14 -24 C12 -18 -12 -18 -14 -24 Z" {FILL("leaf")}></path>'
    '<g stroke-width="1">'
    + ''.join(f'<ellipse cx="{x}" cy="{y}" rx="2.7" ry="2.1" fill="#F4D35E"></ellipse>'
              for x, y in [(-7, -29), (6, -33), (2, -24), (-2, -37), (9, -25)])
    + '</g>'
)
bulbul = (  # level 12: a basket of lemons at the tree's foot
    '<g stroke-width="1.1">'
    '<path d="M7 -7 L20 -7 L18 0 L9 0 Z" fill="#C8954F"></path>'
    '<path d="M8.5 -4 H18.6" fill="none" stroke-width="0.8"></path>'
    '<ellipse cx="10.5" cy="-8.4" rx="2.4" ry="1.9" fill="#F4D35E"></ellipse><ellipse cx="14" cy="-9.2" rx="2.4" ry="1.9" fill="#F4D35E"></ellipse><ellipse cx="17.4" cy="-8.4" rx="2.4" ry="1.9" fill="#F4D35E"></ellipse>'
    '</g>'
)

rose = (
    f'<path d="M-10 0 C-14 -7 -9 -16 -2 -14 C2 -19 11 -16 10 -9 C14 -6 12 0 9 0 Z" {FILL("leafDark")}></path>'
    '<g stroke-width="1" style="opacity: {{v.open}}; transition: opacity .8s ease">'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="2.9" fill="#E2687C"></circle>'
              f'<path d="M{x - 1} {y} A1.2 1.2 0 1 1 {x + 1} {y}" fill="none" stroke-width="0.8"></path>'
              for x, y in [(-5, -9), (3, -12), (6, -5), (-1, -4)])
    + '</g><g stroke-width="1" style="opacity: {{v.bud}}; transition: opacity .8s ease">'
    + ''.join(f'<ellipse cx="{x}" cy="{y}" rx="1.6" ry="2.2" fill="#C96677"></ellipse>'
              for x, y in [(-5, -9), (3, -12), (6, -5), (-1, -4)])
    + '</g>'
)

pomegranate = (
    tree_trunk(19)
    + f'<path d="M-15 -22 C-20 -32 -12 -44 -2 -42 C8 -46 18 -36 15 -24 C13 -17 -12 -16 -15 -22 Z" {FILL("leafDark")}></path>'
    '<g stroke-width="1">'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="3.1" fill="#D9534F"></circle>'
              f'<path d="M{x - 1} {y - 3} L{x} {y - 4.4} L{x + 1} {y - 3}" fill="none" stroke-width="0.9"></path>'
              for x, y in [(-7, -26), (5, -31), (9, -22), (-3, -35)])
    + '</g>'
)

house_tower = (
    '<path d="M-13 -21 V-41 H-2 V-21 Z" fill="#E6CF9F"></path>'
    '<path d="M-14 -41 H-1 V-44 H-14 Z" fill="#E0C694"></path>'
    '<path d="M-10 -38 V-27 M-7.5 -38 V-27 M-5 -38 V-27" fill="none" stroke-width="1.3"></path>'
)
house = (
    '<path d="M-14 0 V-21 H14 V0 Z" fill="#EBD5AA"></path>'
    '<path d="M-15 -21 V-25 L-12.5 -23 L-10 -25 L-7.5 -23 L-5 -25 L-2.5 -23 L0 -25 L2.5 -23 L5 -25 L7.5 -23 L10 -25 L12.5 -23 L15 -25 V-21 Z" fill="#E0C694"></path>'
    '<path d="M-4 0 V-8 A4 4 0 0 1 4 -8 V0 Z" fill="#8B5E3C"></path>'
    '<rect x="-12" y="-18" width="4.4" height="4.4" rx="1" fill="#7FB5D2" stroke-width="1.4"></rect>'
    '<rect x="7.6" y="-18" width="4.4" height="4.4" rx="1" fill="#7FB5D2" stroke-width="1.4"></rect>'
)
lanterns = (
    '<g stroke-width="1">'
    '<path d="M-7.6 -13 V-11.6 M7.6 -13 V-11.6" fill="none"></path>'
    '<path d="M-9.4 -11.6 H-5.8 L-5.4 -6.6 H-9.8 Z" fill="#F2C14E"></path>'
    '<path d="M5.8 -11.6 H9.4 L9.8 -6.6 H5.4 Z" fill="#F2C14E"></path>'
    '</g>'
)
vine = (
    f'<path d="M-15 -21 C-10 -17 -6 -23 0 -20 C6 -17 10 -23 15 -21" fill="none" stroke-width="2.4" {FILL("leaf").replace("fill:", "stroke:").replace("fill 1.2s", "stroke 1.2s")}></path>'
    f'<g stroke-width="1" {FILL("leaf")}>'
    '<ellipse cx="-10" cy="-19" rx="2.6" ry="1.8"></ellipse><ellipse cx="0" cy="-20" rx="2.6" ry="1.8"></ellipse><ellipse cx="10" cy="-19" rx="2.6" ry="1.8"></ellipse>'
    '</g><g stroke-width="0.7">'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="1.4" fill="#7E5AA8"></circle>'
              for x, y in [(-6, -17), (-5, -15), (-7, -15.4), (6, -17), (5, -15), (7, -15.4)])
    + '</g>'
)
doves = (  # level 32: a wooden bench beside the house
    '<g stroke-width="1.2">'
    '<path d="M18 0 V-6 M30 0 V-6 M19 -6 V-12 M29 -6 V-12" fill="none"></path>'
    '<rect x="16.5" y="-7.4" width="15" height="2.6" rx="1" fill="#B07A4A"></rect>'
    '<rect x="17.5" y="-13.4" width="13" height="2.6" rx="1" fill="#B07A4A"></rect>'
    '</g>'
)

sidr = (
    '<path d="M-4.5 0 C-3.5 -10 -4 -18 -10 -26 L-6 -27.5 C-3 -22 -1 -20.5 0 -20.5 C1 -20.5 3 -22 6 -27.5 L10 -26 C4 -18 3.5 -10 4.5 0 Z" fill="#8E6040"></path>'
    f'<path d="M-25 -29 C-29 -37 -19 -47 -7 -45 C-1 -51 14 -49 18 -43 C28 -43 31 -33 23 -29 C15 -25 -17 -24 -25 -29 Z" {FILL("leafDark")}></path>'
    '<g stroke-width="0.8">'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="1.7" fill="#E0A24C"></circle>'
              for x, y in [(-14, -35), (-3, -41), (9, -38), (17, -33), (3, -31), (-9, -30)])
    + '</g>'
)
swing = (
    '<path d="M12 -27 V-9 M19 -27 V-9" fill="none" stroke-width="1.1"></path>'
    '<rect x="10.4" y="-9.6" width="10.2" height="2.6" rx="1" fill="#C8754F" stroke-width="1.1"></rect>'
)

hive = (
    '<path d="M-7 0 C-8 -9 -4 -14 0 -14 C4 -14 8 -9 7 0 Z" fill="#F2C14E"></path>'
    '<path d="M-6.8 -4 H6.8 M-6.2 -8 H6.2 M-4 -11.6 H4" fill="none" stroke-width="1.1"></path>'
    '<ellipse cx="0" cy="-2" rx="2" ry="1.6" fill="#5A3D22" stroke-width="1"></ellipse>'
)
bees = ''  # the hive is drawn without bees: no animals in the world (halal art)

boat = (
    '<path d="M0 -6 V-31" fill="none"></path>'
    '<path d="M1 -30 L15 -9 L1 -9 Z" fill="#F5F0E1"></path>'
    '<path d="M-1 -26 L-9 -10 L-1 -10 Z" fill="#F5F0E1"></path>'
    '<path d="M-16 -6.5 L16 -6.5 L11.5 1 L-11.5 1 Z" fill="#A0703F"></path>'
)

gazelle = (  # level 34: a falaj, a little stone channel of water
    '<g stroke-width="1.3">'
    '<path d="M-16 0 L-16 -6 L16 -6 L16 0 Z" fill="#D6CCBA"></path>'
    '<path d="M-14 -4 H14" fill="none" stroke-width="2.6" style="stroke: {{v.water}}"></path>'
    '<path d="M-8 -6 V0 M0 -6 V0 M8 -6 V0" fill="none" stroke-width="0.8" style="opacity: .5"></path>'
    '</g>'
)

flamingo = ''  # (was an animal; the visitor is now a passing dhow, drawn in the planet's sea)
great_tree = (
    '<path d="M-8 1 C-7 -20 -9 -38 -20 -54 L-12 -57 C-6 -48 -2 -44 0 -44 C2 -44 6 -48 12 -57 L20 -54 C9 -38 7 -20 8 1 Z" fill="#9A6B45"></path>'
    f'<path d="M-48 -66 C-58 -80 -46 -98 -31 -96 C-29 -114 -7 -123 4 -113 C14 -125 39 -117 39 -100 C55 -100 61 -80 49 -68 C41 -55 -40 -53 -48 -66 Z" {FILL("leafDark")}></path>'
    f'<path d="M-30 -76 C-34 -90 -18 -100 -6 -94 C2 -104 26 -100 26 -86 C34 -80 28 -70 18 -72 C6 -64 -22 -64 -30 -76 Z" fill="#1E3A24" stroke="none" style="opacity: .14"></path>'
    '<g stroke-width="1" style="opacity: {{o.blossom}}; transition: opacity .6s ease">'
    + ''.join(f'<circle cx="{x}" cy="{y}" r="2.8" fill="#F7C6D0"></circle>'
              for x, y in [(-38, -78), (-22, -102), (-6, -110), (12, -108), (30, -96), (44, -82), (-10, -86), (20, -80), (-30, -66), (34, -68)])
    + '</g>'
)

# Medal flowers: five kinds, one per achievement family.
def bloom(kind):
    stem = '<path d="M0 0 V-7" fill="none" stroke-width="1.3"></path>'
    if kind == "sun":
        head = ('<circle cx="0" cy="0" r="4.2" fill="#F2C14E" stroke-width="1"></circle>'
                '<circle cx="0" cy="0" r="1.9" fill="#8B5E3C" stroke-width="0.8"></circle>')
    elif kind == "daisy":
        head = ''.join(f'<ellipse cx="{x}" cy="{y}" rx="1.7" ry="1.7" fill="#FFFFFF" stroke-width="0.8"></ellipse>'
                       for x, y in [(0, -2.6), (2.5, -0.8), (1.5, 2.1), (-1.5, 2.1), (-2.5, -0.8)]) + \
               '<circle cx="0" cy="0" r="1.4" fill="#F2C14E" stroke-width="0.6"></circle>'
    elif kind == "lavender":
        head = ''.join(f'<ellipse cx="0" cy="{y}" rx="1.9" ry="1.5" fill="#9C8AD0" stroke-width="0.8"></ellipse>'
                       for y in (2.4, 0, -2.4, -4.6))
    elif kind == "tulip":
        head = '<path d="M-3.2 -2.6 L-1.6 -0.6 L0 -3 L1.6 -0.6 L3.2 -2.6 C3.4 2 1.6 3.2 0 3.2 C-1.6 3.2 -3.4 2 -3.2 -2.6 Z" fill="#E8708A" stroke-width="1"></path>'
    else:  # desert rose
        head = ('<circle cx="0" cy="0" r="3.4" fill="#E39BB0" stroke-width="1"></circle>'
                '<path d="M-1.2 0 A1.2 1.2 0 1 1 1.2 0" fill="none" stroke-width="0.7"></path>')
    return stem + f'<g transform="translate(0 -9)"><g transform="{{{{v.head}}}}" style="transition: transform .8s ease">{head}</g></g>'

BLOOM_ANGLES = [-31, 43, -46, 61, -63, 77, -80, 91, -96, 106, -112, 121, -19, 24, -40, 58, -56, 128, -86, 98]
BLOOM_KINDS = ["lavender", "sun", "daisy", "tulip", "lavender", "sun", "daisy", "tulip", "lavender", "sun",
               "daisy", "tulip", "rose", "rose", "lavender", "sun", "daisy", "tulip", "rose", "rose"]

PEARLS = [(124, 318), (146, 330), (108, 292), (156, 306), (132, 294), (166, 336)]

STARS1 = [(110, 60), (232, 50), (56, 170), (300, 150)]
STARS2 = [(150, 44), (200, 38), (90, 132), (320, 248), (40, 230), (268, 112)]

def star(x, y, r):
    return (f'<path d="M{x} {y - r} L{x + r * .3:.1f} {y - r * .3:.1f} L{x + r} {y} L{x + r * .3:.1f} {y + r * .3:.1f} '
            f'L{x} {y + r} L{x - r * .3:.1f} {y + r * .3:.1f} L{x - r} {y} L{x - r * .3:.1f} {y - r * .3:.1f} Z"></path>')

CLOUD = 'M-18 6 C-25 6 -25 -4 -16 -4 C-15 -12 -4 -14 0 -8 C4 -14 16 -12 15 -3 C23 -3 23 6 17 6 Z'

# ---------------------------------------------------------------- layers
sky_svg = (
    '<svg viewBox="0 0 360 400" width="100%" height="100%" style="position: absolute; left: 0; top: 0;" aria-hidden="true">'
    '<g style="opacity: {{f.bubble}}"><circle cx="180" cy="205" r="176" style="fill: {{v.sky}}; transition: fill 1.2s ease"></circle></g>'
    '<g style="opacity: {{f.rect}}"><rect x="0" y="0" width="360" height="400" style="fill: {{v.sky}}; transition: fill 1.2s ease"></rect></g>'
    # sun
    '<g style="opacity: {{v.sun}}; transition: opacity .8s ease" stroke="#E2A93B" stroke-width="2.4" stroke-linecap="round">'
    '<path d="M280 58 V62 M280 110 V114 M252 86 H256 M304 86 H308 M260 66 L263 69 M297 103 L300 106 M300 66 L297 69 M263 103 L260 106" fill="none"></path>'
    '<circle cx="280" cy="86" r="{{v.sunR}}" fill="#F7D774" stroke="#1E3A24" stroke-width="2.2"></circle></g>'
    # rest clouds
    f'<g style="opacity: {{{{v.restClouds}}}}; transition: opacity .8s ease" stroke="#1E3A24" stroke-width="2" fill="#F7F7FA">'
    f'<path transform="translate(108 92) scale(1.2)" d="{CLOUD}"></path><path transform="translate(250 80)" d="{CLOUD}"></path></g>'
    # stars
    '<g fill="#F6E7A8" style="opacity: {{v.stars1}}; transition: opacity .8s ease">' + ''.join(star(x, y, 4) for x, y in STARS1) + '</g>'
    '<g fill="#F6E7A8" style="opacity: {{v.stars2}}; transition: opacity .8s ease">' + ''.join(star(x, y, 3.2) for x, y in STARS2) + '</g>'
    # moon (crescent: a disc with a sky-coloured disc over it)
    '<g style="opacity: {{v.moon}}; transition: opacity .8s ease">'
    '<circle cx="66" cy="110" r="13" fill="#F6E7A8" stroke="#1E3A24" stroke-width="2"></circle>'
    '<circle cx="72.5" cy="105" r="11.5" style="fill: {{v.moonCover}}; transition: fill 1.2s ease"></circle></g>'
    '<g fill="none" stroke-width="6" style="opacity: {{v.rainbow}}; transition: opacity 1s ease"><path d="M18.5 209.7 A168 168 0 0 1 341.5 209.7" stroke="#E57C6B" style="opacity: .6"></path><path d="M24.3 211.3 A162 162 0 0 1 335.7 211.3" stroke="#F2B84B" style="opacity: .6"></path><path d="M30.0 213.0 A156 156 0 0 1 330.0 213.0" stroke="#F4D35E" style="opacity: .6"></path><path d="M35.8 214.7 A150 150 0 0 1 324.2 214.7" stroke="#8CCB6E" style="opacity: .6"></path><path d="M41.6 216.3 A144 144 0 0 1 318.4 216.3" stroke="#6FB7DB" style="opacity: .6"></path></g>'
    '<g style="opacity: {{v.shoot}}; transition: opacity 1s ease"><path d="M302 58 L246 92" stroke="#F6E7A8" stroke-width="2.4" stroke-linecap="round" fill="none" style="opacity: .7"></path><path d="M302 52 L304 56 L308 58 L304 60 L302 64 L300 60 L296 58 L300 56 Z" fill="#FFF6C9"></path></g>'
    # rain cloud (level 27)
    f'<g style="opacity: {{{{o.cloud}}}}; transition: opacity .6s ease"><path transform="translate(118 66)" d="{CLOUD}" fill="#FFFFFF" stroke="#1E3A24" stroke-width="2"></path>'
    '<g style="opacity: {{v.rain}}; transition: opacity .5s ease" stroke="#5AA7D6" stroke-width="2" stroke-linecap="round">'
    '<path d="M106 80 L103 89 M118 82 L115 91 M130 80 L127 89" fill="none"></path></g></g>'
    '</svg>'
)


# ---- oasis mode: one date palm at the crown that grows from level 1
def _frond(a_deg, L, droop=0.0, w=0.2):
    a = math.radians(a_deg)
    tx, ty = L * math.cos(a), L * math.sin(a) + droop
    mx, my = L * .5 * math.cos(a), L * .5 * math.sin(a) - L * .18
    nx, ny = -math.sin(a) * L * w, math.cos(a) * L * w
    return (f'<path d="M0 0 Q{mx + nx:.1f} {my + ny:.1f} {tx:.1f} {ty:.1f} Q{mx - nx:.1f} {my - ny:.1f} 0 0 Z"></path>'
            f'<path d="M0 0 Q{mx:.1f} {my:.1f} {tx:.1f} {ty:.1f}" fill="none" stroke-width="0.9"></path>')

def _crown(L, n=11, spread=(195, 345)):
    out = f'<g {FILL("palm")}>'
    for i in range(n):
        a = spread[0] + (spread[1] - spread[0]) * i / (n - 1)
        out += _frond(a, L, L * .25 * abs(math.cos(math.radians(a))))
    return out + '</g>'

_HERO_RINGS = ''.join(f'<path d="M{-5 + 5 * y / 92:.1f} {-y} L{6.8 - 0.8 * y / 92:.1f} {-y + 2.6}" fill="none" stroke-width="1.1"></path>'
                      for y in range(8, 90, 9))
_BUNCH = [(-12, -86), (17, -86), (-25, -82), (30, -82), (3, -80)]
hero_offshoot = '<g transform="translate(0 -1)">' + _crown(24, 7, (198, 342)) + '</g>'
hero_palm = (
    '<path d="M-5 0 C-4 -30 -2 -60 0 -92 L6.4 -92 C6.4 -60 6.6 -30 7 0 Z" fill="#B07A4A"></path>' + _HERO_RINGS
    + '<g transform="translate(3 -92)">' + _crown(54) + '</g>'
    + ''.join(f'<g stroke-width="0.8" style="opacity: {{{{o.b{i}}}}}; transition: opacity .6s ease">'
              + ''.join(f'<circle cx="{x + dx}" cy="{y + dy}" r="2.6" style="fill: {{{{v.b{i}}}}}; transition: fill .8s ease"></circle>'
                        for dx, dy in [(0, 0), (-2.8, 3.4), (2.8, 3.4), (0, 6.8), (-1.4, 10), (1.4, 10)])
              + '</g>' for i, (x, y) in enumerate(_BUNCH))
)

items = []
# behind everything on the ground: the great tree, at its own scale
items.append(at(0, f'<g transform="{{{{v.treeScale}}}}">{great_tree}</g>', op("tree"), k=1))
items.append(at(8, f'<g transform="{{{{v.heroScale}}}}">{hero_offshoot}</g>', op("heroShoot"), k=1))
items.append(at(8, f'<g transform="{{{{v.heroScale}}}}">{hero_palm}</g>', op("heroPalm"), k=1))
items.append(at(-95, grove_palm, op("grove")))
items.append(at(-80, grove_palm, op("grove")))
items.append(at(-88, sapling, op("sapling")))
items.append(at(-88, palm, op("palm")))
items.append(at(-71, house_tower, op("tower")))
items.append(at(-71, house, op("house")))
items.append(at(-71, lanterns, op("lanterns")))
items.append(at(-71, vine, op("vine")))
items.append(at(-71, doves, op("doves")))
items.append(at(-104, bed, op("bed")))
items.append(at(-104, farm, op("farm")))
items.append(at(-125, boat, op("boat")))
items.append(at(-114, flamingo, op("flamingo")))
items.append(at(-54, rose, op("rose")))
items.append(at(-54, row_carrot, op("rowC")))
items.append(at(-39, flowers, op("flowers")))
items.append(at(-39, row_lettuce, op("rowL")))
items.append(at(-25, sprouts, op("sprouts")))
items.append(at(51, stones, op("stones")))
items.append(at(51, pond, op("pond")))
items.append(at(51, arch, op("arch")))
items.append(at(31, well, op("well")))
items.append(at(31, hoopoe, op("hoopoe")))
items.append(at(70, jasmine, op("jasmine")))
items.append(at(70, row_tomato, op("rowT")))
items.append(at(85, lemon, op("lemon")))
items.append(at(85, bulbul, op("bulbul")))
items.append(at(99, pomegranate, op("pom")))
items.append(at(116, sidr, op("sidr")))
items.append(at(116, swing, op("swing")))
items.append(at(130, hive, op("hive")))
items.append(at(130, bees, op("bees")))
items.append(at(143, gazelle, op("gazelle")))
for i, (a, k) in enumerate(zip(BLOOM_ANGLES, BLOOM_KINDS)):
    items.append(at(a, bloom(k), op(f"m{i}")))

butterflies = (  # level 7: a kite on a string (no animals: halal art); key kept as 'butterflies'
    '<g stroke="#1E3A24" stroke-width="1.4" stroke-linejoin="round" style="opacity: {{o.butterflies}}; transition: opacity .6s ease">'
    '<path d="M250 126 C232 140 214 150 204 158" fill="none" stroke-width="0.9" style="opacity: .6"></path>'
    '<path d="M250 96 L264 113 L250 128 Z" fill="#F2C14E"></path><path d="M250 96 L236 113 L250 128 Z" fill="#E57C6B"></path>'
    '<path d="M236 113 H264" fill="none" stroke-width="0.9"></path>'
    '<path d="M250 128 C254 136 246 142 251 150 C255 156 249 160 252 166" fill="none" stroke-width="1"></path>'
    '<path d="M249 141 L254 138 L254 144 Z M248 155 L253 152 L253 158 Z" fill="#E57C6B" stroke-width="0.8"></path>'
    '</g>'
)

planet_svg = (
    '<svg viewBox="0 0 360 400" width="100%" height="100%" style="position: absolute; left: 0; top: 0;" aria-hidden="true">'
    '<defs><clipPath id="doum-planet-clip"><circle cx="180" cy="256" r="90"></circle></clipPath></defs>'
    # halo at level 100
    '<circle cx="180" cy="256" r="104" fill="none" stroke="#F2C14E" stroke-width="3" stroke-dasharray="1 9" stroke-linecap="round" style="opacity: {{o.halo}}"></circle>'
    # the planet body
    '<circle cx="180" cy="256" r="90" style="fill: {{v.soil}}; transition: fill 1.2s ease"></circle>'
    '<g clip-path="url(#doum-planet-clip)">'
    '<g fill="#C99A62" style="opacity: .55">'
    '<ellipse cx="150" cy="306" rx="7" ry="3"></ellipse><ellipse cx="206" cy="326" rx="9" ry="3.4"></ellipse>'
    '<ellipse cx="238" cy="296" rx="6" ry="2.6"></ellipse><ellipse cx="184" cy="310" rx="5" ry="2.2"></ellipse>'
    '<ellipse cx="226" cy="268" rx="5" ry="2.2"></ellipse></g>'
    '<ellipse cx="180" cy="{{v.grassCy}}" rx="190" ry="150" stroke="#1E3A24" stroke-width="2.4" style="fill: {{v.grass}}; transition: fill 1.2s ease"></ellipse>'
    '<g style="opacity: {{v.patches}}; transition: opacity .6s ease"><g style="opacity: .5; fill: {{v.leaf}}; transition: fill 1.2s ease"><ellipse cx="150" cy="214" rx="16" ry="6"></ellipse><ellipse cx="214" cy="236" rx="20" ry="7"></ellipse><ellipse cx="170" cy="268" rx="14" ry="5"></ellipse><ellipse cx="236" cy="208" rx="10" ry="4"></ellipse></g>'
    '<path d="M138 198 l3 -5 l3 5 M206 192 l3 -5 l3 5 M124 240 l3 -5 l3 5 M240 252 l3 -5 l3 5 M188 238 l3 -5 l3 5 M160 290 l3 -5 l3 5" fill="none" stroke="#1E3A24" stroke-width="1.2" style="opacity: .35"></path></g>'
    + FURROWS +
    '<g style="opacity: {{o.sea}}; transition: opacity .6s ease">'
    '<circle cx="112" cy="350" r="72" fill="#7FC4E2" stroke="#1E3A24" stroke-width="2.4"></circle>'
    '<path d="M116 302 q5 -3 10 0 t10 0 M138 322 q5 -3 10 0 t10 0" fill="none" stroke="#FFFFFF" stroke-width="1.6"></path>'
    '</g>'
    '<g transform="translate(134 324) scale(0.62)" stroke="#1E3A24" stroke-width="2" stroke-linejoin="round" style="opacity: {{o.flamingo}}; transition: opacity .6s ease">'
    '<path d="M0 -6 V-31" fill="none"></path><path d="M1 -30 L15 -9 L1 -9 Z" fill="#F5F0E1"></path>'
    '<path d="M-16 -6.5 L16 -6.5 L11.5 1 L-11.5 1 Z" fill="#A0703F"></path></g>'
    + ''.join(f'<g style="opacity: {{{{o.p{i}}}}}; transition: opacity .6s ease"><circle cx="{x}" cy="{y}" r="3.6" fill="#FBF6EC" stroke="#1E3A24" stroke-width="1.4"></circle>'
              f'<circle cx="{x - 1.2}" cy="{y - 1.2}" r="1" fill="#FFFFFF"></circle></g>'
              for i, (x, y) in enumerate(PEARLS))
    + '<path d="M90 256 A90 90 0 1 0 270 256 A90 90 0 1 0 90 256 Z M84 246 A92 92 0 1 1 268 246 A92 92 0 1 1 84 246 Z" fill="#1E3A24" fill-rule="evenodd" style="opacity: .1"></path>'
    '<path d="M90 256 A90 90 0 1 1 270 256 A90 90 0 1 1 90 256 Z M100 268 A88 88 0 1 1 276 268 A88 88 0 1 1 100 268 Z" fill="#FFFFFF" fill-rule="evenodd" style="opacity: .18"></path>'
    '</g>'
    '<circle cx="180" cy="256" r="90" fill="none" stroke="#1E3A24" stroke-width="3.4"></circle>'
    # spotlight behind a new item
    '<circle cx="{{s.x}}" cy="{{s.y}}" r="{{s.r}}" fill="#FFF3B0" style="opacity: {{s.o}}"></circle>'
    '<g stroke="#1E3A24" stroke-width="2" stroke-linejoin="round" stroke-linecap="round">'
    + ''.join(items)
    + '</g>'
    + butterflies
    # night: one dim veil over the drawing, shaped like the frame
    + '<g style="opacity: {{v.veil}}; transition: opacity 1s ease" fill="#14203A">'
    '<g style="opacity: {{f.bubble}}"><circle cx="180" cy="205" r="176"></circle></g>'
    '<g style="opacity: {{f.rect}}"><rect x="0" y="0" width="360" height="400"></rect></g>'
    '<g style="opacity: {{f.none}}"><circle cx="180" cy="256" r="90"></circle></g>'
    '</g>'
    '</svg>'
)

def sparkle(x, y, r):
    return star(x, y, r)

glow_svg = (
    '<svg viewBox="0 0 360 400" width="100%" height="100%" style="position: absolute; left: 0; top: 0; pointer-events: none;" aria-hidden="true">'
    '<g fill="#FFE08A" style="opacity: {{v.lampGlow}}; transition: opacity 1s ease">'
    '<circle cx="{{g.ax}}" cy="{{g.ay}}" r="7" style="opacity: .55"></circle><circle cx="{{g.bx}}" cy="{{g.by}}" r="7" style="opacity: .55"></circle>'
    '<circle cx="{{g.ax}}" cy="{{g.ay}}" r="3"></circle><circle cx="{{g.bx}}" cy="{{g.by}}" r="3"></circle></g>'
    '<g fill="#F2C14E" stroke="#1E3A24" stroke-width="1.2" style="opacity: {{v.sparkle}}; transition: opacity .6s ease">'
    + sparkle(96, 150, 7) + sparkle(270, 150, 6) + sparkle(306, 236, 7) + sparkle(56, 250, 5) + sparkle(220, 104, 4.5)
    + '</g>'
    '<g fill="#F2C14E" stroke="#1E3A24" stroke-width="1.2" style="opacity: {{s.o}}">'
    '<path d="M{{s.k1}}"></path><path d="M{{s.k2}}"></path><path d="M{{s.k3}}"></path></g>'
    '<g fill="#6FB7DB" stroke="#1E3A24" stroke-width="1" style="opacity: {{v.drops}}; transition: opacity .5s ease">'
    '<path d="M214 136 C216 140 217 142 214 144 C211 142 212 140 214 136 Z"></path>'
    '<path d="M224 146 C226 150 227 152 224 154 C221 152 222 150 224 146 Z"></path>'
    '<path d="M206 152 C208 156 209 158 206 160 C203 158 204 156 206 152 Z"></path>'
    '</g>'
    '</svg>'
)

JS = r"""
class Component extends DCLogic {
  renderVals() {
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
    const ct = (P.quietStyle ?? 'thirsty') === 'quiet' ? 0 : t;  // colour step: the quiet style keeps colours healthy
    const frame = P.frame ?? 'bubble';
    const on = (b) => (b ? 1 : 0);
    const has = (n) => on(L >= n);
    const span = (a, b) => on(L >= a && L < b);
    const flyers = on(t < 2 && !night && !rest);
    const pearls = Math.max(0, Math.min(6, Math.round(num(P.pearls, 2))));
    const medals = Math.max(0, Math.min(20, Math.round(num(P.medals, 5))));

    const skyDay = season === 'winter'
      ? ['#DCE7F2', '#E4EBEA', '#ECEADF', '#F1E6D2']
      : ['#DDF0F1', '#E7F0E5', '#EFEBDA', '#F4E5CB'];
    const skyCol = night ? '#22304A' : rest ? '#E5E6EE' : skyDay[ct];

    let ts = 0.001;
    for (const [lv, s] of [[35, .7], [40, .76], [45, .82], [50, .88], [60, .93], [70, .97], [75, 1], [80, 1.03], [90, 1.06], [100, 1.1]]) if (L >= lv) ts = s;

    const mode = P.mode ?? 'garden';
    let hs = 0;
    const oasis = mode === 'oasis';
    const farm = mode === 'farm' || oasis;
    const glance = (P.detail ?? 'full') === 'glance';
    const o = {
      sprouts: 1, stones: span(3, 11), pond: has(11), arch: has(33), flowers: has(4), well: has(5),
      hoopoe: has(24), sapling: span(6, 21), palm: has(21), dates: has(23), grove: has(25),
      butterflies: has(7) * flyers, jasmine: has(8), bed: span(9, 29), farm: has(29), lemon: has(10),
      bulbul: has(12), rose: has(13), pom: has(14), house: has(15), tower: has(16), lanterns: has(17),
      sidr: has(18), hive: has(19), bees: has(19) * flyers, sea: has(20), boat: has(22),
      cloud: has(27), swing: has(28), vine: has(31), doves: has(32), gazelle: has(34),
      tree: has(35), blossom: has(75), halo: has(100),
      flamingo: on(L >= 20 && (P.visitor ?? 'none') === 'dhow')
    };
    for (let i = 0; i < 6; i++) o['p' + i] = on(L >= 20 && i < pearls);
    if (farm) {
      o.rowL = o.flowers; o.rowC = o.rose; o.rowT = o.jasmine;
      o.flowers = 0; o.rose = 0; o.jasmine = 0;
    } else { o.rowL = 0; o.rowC = 0; o.rowT = 0; }
    o.furrows = on(farm); o.seedlings = on(farm && L >= 6);
    // oasis: one palm at the crown is the hero from level 1; medals ripen its dates
    o.heroShoot = on(oasis && L < 5); o.heroPalm = on(oasis && L >= 5);
    if (oasis) {
      o.sapling = 0; o.palm = 0; o.dates = 0; o.grove = 0; o.tree = 0; o.blossom = 0;
      for (let i = 0; i < 20; i++) o['m' + i] = 0;
    }
    const RIPE = ['#9CC46A', '#F2C14E', '#D98E3A', '#8B4A2B'];  // hababou, khalal, rutab, tamr
    const bunch = {};
    for (let fam = 0; fam < 5; fam++) {
      const tier = Math.max(0, Math.min(4, Math.ceil((medals - fam) / 5)));
      o['b' + fam] = on(oasis && tier > 0);
      bunch[fam] = RIPE[Math.max(0, tier - 1)];
    }
    // glance: the card and the widget keep only the big shapes
    if (glance) {
      for (const key of ['sprouts', 'stones', 'pond', 'arch', 'flowers', 'well', 'hoopoe', 'jasmine', 'bed', 'farm', 'lemon', 'bulbul',
        'rose', 'pom', 'house', 'tower', 'lanterns', 'sidr', 'swing', 'hive', 'bees', 'boat', 'gazelle', 'vine', 'doves', 'butterflies',
        'rowL', 'rowC', 'rowT', 'seedlings', 'flamingo', 'sapling', 'grove', 'palm', 'dates']) o[key] = 0;
      for (let i = 0; i < 20; i++) o['m' + i] = 0;
    }
    for (let i = 0; i < 20; i++) o['m' + i] = on(i < medals && !oasis && !glance);

    const grassBottom = 174 + Math.min(L - 1, 19) / 19 * 160;
    const v = {
      sky: skyCol,
      moonCover: frame === 'none' ? (P.bg ?? '#F5F0E1') : skyCol,
      soil: ['#E4BE88', '#E7C590', '#EACB99', '#EDD2A4'][ct],
      grass: ['#A3D46F', '#B3CF72', '#C4C97D', '#D2C28A'][ct],
      leaf: ['#5DAE5F', '#78AE60', '#94AE66', '#AAAD70'][ct],
      leafDark: ['#4C9A55', '#669D57', '#829F5E', '#999F68'][ct],
      palm: ['#62B261', '#7DB063', '#98AF68', '#ADAC72'][ct],
      water: ['#86CBE6', '#93CDE2', '#A9CFD9', '#C4D2C8'][ct],
      dates: season === 'summer' ? '#D2692B' : '#C9772F',
      open: on(t < 2), bud: on(t >= 2),
      head: t >= 2 ? 'scale(0.6)' : 'scale(1)',
      grassCy: grassBottom - 150,
      patches: on(L >= 16),
      treeScale: 'scale(' + ts + ')',
      sun: on(!night && !rest), sunR: season === 'summer' ? 19 : season === 'winter' ? 12 : 15,
      restClouds: on(rest), stars1: on(night), stars2: on(night && L >= 30),
      moon: on(L >= 26 || season === 'ramadan' || night),
      rain: on(watering && L >= 27),
      veil: night ? 0.34 : 0,
      lampGlow: on(night && L >= 17),
      sparkle: on(glowing && !night),
      drops: on(watering),
      rainbow: on((P.visitor ?? 'none') === 'rainbow' && !night),
      shoot: on((P.visitor ?? 'none') === 'star' && night)
    };
    for (let fam = 0; fam < 5; fam++) v['b' + fam] = bunch[fam];
    hs = 0.6 + Math.min(L - 1, 3) * 0.13;
    if (L >= 5) { hs = 0.42; for (const [lv, sc] of [[10, .5], [15, .57], [20, .65], [25, .7], [35, .78], [50, .84], [75, .89], [100, .93]]) if (L >= lv) hs = sc; }
    v.heroScale = 'scale(' + hs + ')';
    const f = { bubble: on(frame === 'bubble'), rect: on(frame === 'rect'), none: on(frame === 'none') };

    // where a surface point lands once rotated onto the planet
    const place = (theta, x, y) => {
      const a = theta * Math.PI / 180, yy = y - 89;
      return [180 + x * Math.cos(a) - yy * Math.sin(a), 256 + x * Math.sin(a) + yy * Math.cos(a)];
    };
    const K = 1.15;
    const [ax, ay] = place(-71, -7.6 * K, -9 * K), [bx, by] = place(-71, 7.6 * K, -9 * K);
    const g = { ax, ay, bx, by };

    // spotlight on the item a level just added
    const SPOT = { 1: [-25, 8], 3: [51, 4], 4: [-39, 10], 5: [31, 16], 6: [-88, 10], 8: [70, 9], 9: [-104, 6],
      10: [85, 26], 11: [51, 4], 12: [85, 46], 13: [-54, 8], 14: [99, 26], 15: [-71, 14], 16: [-71, 32],
      17: [-71, 10], 18: [116, 30], 19: [130, 8], 21: [-88, 36], 22: [-125, 14], 23: [-88, 38],
      24: [31, 40], 25: [-88, 30], 28: [116, 16], 29: [-104, 6], 31: [-71, 18], 32: [-71, 28], 33: [51, 16],
      34: [143, 14] };
    const ABS = { 7: [182, 146], 20: [134, 312], 26: [66, 110], 27: [118, 66], 30: [160, 60] };
    const sp = Math.round(num(P.spot, 0));
    let s = { x: -100, y: -100, r: 1, o: 0, k1: '0 0', k2: '0 0', k3: '0 0' };
    let c = null;
    if (SPOT[sp]) c = place(SPOT[sp][0], 0, -SPOT[sp][1] * K);
    else if (ABS[sp]) c = ABS[sp];
    else if (sp >= 35) c = place(0, 0, -96 * ts);
    if (oasis && sp > 0 && (sp % 5 === 0 || sp < 5)) c = place(8, 0, -60 * hs);
    if (c) {
      const star = (x, y, r) => `${x} ${y - r} L${x + r * .3} ${y - r * .3} L${x + r} ${y} L${x + r * .3} ${y + r * .3} L${x} ${y + r} L${x - r * .3} ${y + r * .3} L${x - r} ${y} L${x - r * .3} ${y - r * .3} Z`;
      s = { x: c[0], y: c[1], r: 30, o: 0.85, k1: star(c[0] - 30, c[1] - 22, 6), k2: star(c[0] + 31, c[1] - 12, 5), k3: star(c[0] + 6, c[1] - 38, 4) };
    }

    const POSES = {
      wave: ['4fe66825d4a1e1409975aaf4cae25efe', 633, 767, .5],
      three: ['bda45ed574b609786b0ad5e6f32cc9c1', 597, 750, .5],
      water: ['ff0714f75ca540d6b9e854eb7ec643f0', 825, 824, .46],
      plant: ['239821cb47d27696b528956bd28c88b8', 688, 760, .42],
      sleep: ['83c02ebb24494b1bec34815440654d97', 850, 679, .5],
      sparkles: ['f54c56f0458a9bc4ac82dc5d45c2870f', 700, 802, .5],
      lantern: ['4fa5d30b3b6336e626650625981d86c7', 816, 742, .5],
      campfire: ['9c5ba12e77d19a5133b9fd4ec083faae', 949, 671, .4],
      jump: ['01a0919e008df49374de250038e990bb', 856, 798, .5],
      heart: ['1b550d444d0dfca059dcdb1c7813cd9f', 649, 784, .5],
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
      else pose = farm ? 'plant' : 'wave';
    }
    const pd = POSES[pose];
    const k = (64 / 767) * (S / 360);
    const d = pd
      ? { show: true, src: '/_blob/' + pd[0], w: pd[1] * k, h: pd[2] * k, left: (oasis ? 162 : 180) * S / 360 - pd[1] * k * pd[3], top: (oasis ? 170 : 169) * S / 360 - pd[2] * k }
      : { show: false, src: '', w: 0, h: 0, left: 0, top: 0 };

    return { o, v, f, g, s, d, S, H, alt: 'Doum’s planet at level ' + L };
  }
}
"""

PROPS = ('{"quietStyle":{"editor":"enum","options":["thirsty","quiet"],"default":"thirsty","section":"Today"},"visitor":{"editor":"enum","options":["none","rainbow","dhow","star"],"default":"none","section":"Today"},"mode":{"editor":"enum","options":["garden","farm","oasis"],"default":"garden","section":"Growth"},"detail":{"editor":"enum","options":["full","glance"],"default":"full","section":"Frame"},'
         '"level":{"editor":"range","min":1,"max":100,"step":1,"default":12,"section":"Growth"},'
         '"medals":{"editor":"range","min":0,"max":20,"step":1,"default":5,"section":"Growth"},'
         '"pearls":{"editor":"range","min":0,"max":6,"step":1,"default":2,"section":"Growth"},'
         '"thirst":{"editor":"range","min":0,"max":3,"step":1,"default":0,"section":"Today"},'
         '"watering":{"editor":"boolean","default":false,"section":"Today"},'
         '"glowing":{"editor":"boolean","default":false,"section":"Today"},'
         '"sky":{"editor":"enum","options":["day","night","rest"],"default":"day","section":"Today"},'
         '"season":{"editor":"enum","options":["none","ramadan","winter","summer"],"default":"none","section":"Today"},'
         '"pose":{"editor":"enum","options":["auto","wave","three","water","plant","sleep","sparkles","lantern","campfire","jump","heart","stretch","shades","reading","checklist","lamp","flag","none"],"default":"auto","section":"Doum"},'
         '"spot":{"editor":"int","default":0,"section":"Doum"},'
         '"frame":{"editor":"enum","options":["bubble","rect","none"],"default":"bubble","section":"Frame"},'
         '"bg":{"editor":"color","default":"#F5F0E1","section":"Frame"},'
         '"size":{"editor":"int","default":360,"section":"Frame"},'
         '"$preview":{"width":360,"height":400}}')

html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Doum's planet</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
</style>
</helmet>
<div role="img" aria-label="{{{{alt}}}}" style="position: relative; width: {{{{S}}}}px; height: {{{{H}}}}px; font-family: 'IBM Plex Sans', sans-serif; color: #23352A;">
{sky_svg}
{planet_svg}
<sc-if value="{{{{d.show}}}}" hint-placeholder-val="{{{{true}}}}">
<img src="{{{{d.src}}}}" alt="" style="position: absolute; left: {{{{d.left}}}}px; top: {{{{d.top}}}}px; width: {{{{d.w}}}}px; height: {{{{d.h}}}}px;">
</sc-if>
{glow_svg}
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{PROPS}'>
{JS}
</script>
</body>
</html>
"""

os.makedirs(ROOT, exist_ok=True)
with open(os.path.join(ROOT, "Planet.dc.html"), "w") as fh:
    fh.write(html)
print(len(html), "bytes")
