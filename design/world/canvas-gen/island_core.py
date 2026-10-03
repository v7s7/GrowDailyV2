"""Shared island drawing for Island.dc.html and Builder.dc.html.

The island is a round diorama: a sea disc on a thick base, a sand beach and
a grass top. Things stand upright on it (the ChatGPT art is drawn front-on),
sorted back to front. The base changes with level so anyone can read it from
far away: sand, stone, coral, gold trim, rainbow, pearl ring, star crown.
"""
import json, math, os

ART_IDS = {
    'palm_shoot': '260387f762f6bce69df17aedbffb0b34', 'palm_young': 'c7747457bdcd8291e5819c4d9d471de9',
    'palm_medium': 'd7cb0d02d8eb07c67673f45cf13b9094', 'palm_tall': 'e0ca7ba6b848761fba0461c9e1d9744e',
    'palm_lanterns': '1b340a9b1a3bcfcd00583313d43ac19f', 'palm_offshoot': '0cee6124734b07c8c772d2366cde5402',
    'dates_hababou': 'd188ef26ef07c818ebadf4a1f9c1f69f', 'dates_khalal': 'b7d4ceefa7c34b8036e2ced1675fa3a2',
    'dates_rutab': '8724a836e5587534fa3851088c77fdda', 'dates_tamr': '2faa62daa5625e6a69f11413eb956d20',
    'lemon': 'b56137ff3eaa4ae51911e75b2d9d155d', 'pomegranate': '257651793f2b9bb04b5126f179f3a962',
    'sidr': '9a6cf3f5b66b2f1f9a32929e07801a85', 'rose': '33cd79552567c1ae0a5e42782420a7d3',
    'jasmine': '3547e0f23d6f98cc6173257aa130f387', 'flowers': 'c443aac3954b192eea4e36bb1f277cd1',
    'vegetables': 'e6c8af5716c886d8920d5ea62459686d', 'spring': '729455ca4949722d382d4d03b1f9c6f8',
    'well': 'fc674afe64ffc93096871354f4e9f25d', 'house': 'f8718c8ad6f05e35eacceb367efffd82',
    'palm': '519fc7506da0610fffe637b84150a5f3', 'bench': 'd08b35f4b958ee1c232cf8f6247ee4f4',
    'dhow': '5bc05dbc12582308dc68cc3b6a07b3eb', 'falaj': '8798590b8a39c08e7cdbcea5ae82dc62',
    'kite': 'b69ca4a045ef4f9ba598e5500e881961', 'lanterns': 'd0b78bb70183a0f2d110cdd9cbc5dcbd',
    'rainbow': '5e6e154b8a64aaab35dfd692b47a2002', 'rose_arch': 'fe033cc9c103c337fb7fccd451c917d9',
    'stones': '3f1f5ccf15580a651550f570f53815e5', 'telescope': '0efc035035311e7f4f7efcd97c17d58e',
    'vine': '6ca35975d84ad164c2590b3893ad0554', 'rain_cloud': 'cf606bbf6321edde09c2a0e7541b295c',
    'swing': '1f3e1a9ccb832b66a4d85a2e40b8a476', 'sparkle': 'c7361882cea29eb288525558a1146858',
    'shell_pearl': 'a49c7ffccd1ddf967df2aa50ebbe2677', 'pearl': '7fcdc9f010f24d6db60fdb830b24d2d7',
    'harvest_basket': '2557a407d95e0e763235579d01395cde', 'drops': '0d28f0816eb416ba52c2e7397b92010c',
    'water_arc': '777c18ae7ccff11536511bbc6eaca467',
    'coral_house': '4c45ede7d8907b9af32eff3ba9b8251b', 'fountain': '84cf6fdf1c697a858216f96a82b026a1',
    'golden_palm': 'a3ddcb0a0a020596f3eb405acc1c5399', 'lantern_arch': '91333cf6706b098feb031c23e6461186',
    'pearl_chest': '6cb587359dcf29b486be1f5355517d5e', 'big_dhow': 'f0dccb628564371a840b7c96dcc42bcf',
    'majlis': '860e280c4b11d50ea170b913271f21a5', 'frond_hut': 'cdbebb4a4e34c35b77f615928b6ef8e5',
    'lighthouse': 'f0d251c2988bb6430a4914b0efcc7fd0', 'lamp_posts': '931be95bfb9171ff4e0d5e676f2e8557',
    'lily_pool': '3f7a9af0733965acfdeec830d1cdcf94', 'jasmine_pergola': 'ce94af88c7af6c55b97472bf17fb2977',
    'mandoos': 'fe07d9d089d54a2f0023ed6be01bc0f6', 'dallah_set': '890855ec8a80f97fc2d4777581b6ef25',
    'mabkhara': '74686b7e5a2133e8cd57dbd577ffe254', 'cushions': 'a7090a03f1447c4dce022d9af76927c2',
    'low_table': '8f6d4b889d36a597d8ee1924ea5fb92c', 'carved_door': '3567dacea781f1a1eab80251936fe5f6',
    'lattice_window': '430e34ad9a859f5d9ea6e24501472693', 'shelf': '83620128be446127a5eecffffd9c3904',
    'hanging_lantern': '286895fd1b71980bdc8453533160af18', 'potted_palm': 'ce0bba5dca827712dbec0d4c9912a97c',
    'pattern_frame': '22865baec9cb49353adcfeb21d69e991', 'frond_mat': '5e71438b280a771b0c18ec0d5169e775',
}
META = json.load(open('/Users/aysha/Documents/GrowDailyV2/design/world/island/meta.json'))
META['pearl_chest']['base'] = 0.5  # spilled pearls pull the measured base left
ART = {k: ['/_blob/' + v, META[k]['w'], META[k]['h'], META[k]['base']] for k, v in ART_IDS.items()}

# name, Arabic, width at scale 1, kind (grow | build | rare), gold price, opens at level (rare only)
ITEMS = [
    ('lemon', 'ليمون', 88, 'grow', 0), ('pomegranate', 'رمان', 88, 'grow', 0), ('sidr', 'سدرة', 106, 'grow', 0),
    ('palm', 'نخلة', 86, 'grow', 0), ('rose', 'ورد', 78, 'grow', 0), ('jasmine', 'فل', 78, 'grow', 0),
    ('flowers', 'زهور', 74, 'grow', 0), ('vegetables', 'خضار', 86, 'grow', 0), ('spring', 'عين ماء', 96, 'grow', 0),
    ('house', 'بيت دوم', 116, 'build', 900), ('well', 'بئر', 72, 'build', 250), ('bench', 'كرسي', 68, 'build', 150),
    ('telescope', 'منظار', 52, 'build', 350), ('rose_arch', 'قوس ورد', 84, 'build', 400), ('falaj', 'فلج', 90, 'build', 450),
    ('vine', 'عريش عنب', 92, 'build', 300), ('frond_hut', 'برستي', 100, 'build', 500),
    ('lantern_arch', 'قوس فوانيس', 90, 'rare', 700, 20), ('coral_house', 'بيت مرجان', 118, 'rare', 1200, 20),
    ('fountain', 'نافورة', 92, 'rare', 800, 35), ('lily_pool', 'بركة لوتس', 104, 'rare', 700, 35),
    ('jasmine_pergola', 'عريش فل', 94, 'rare', 600, 35), ('pearl_chest', 'صندوق لؤلؤ', 74, 'rare', 900, 50),
    ('majlis', 'مجلس', 110, 'rare', 1000, 75), ('lamp_posts', 'أعمدة نور', 74, 'rare', 500, 75),
]
ITEMS = [it if len(it) == 6 else it + (0,) for it in ITEMS]

# Scale system (2026-10-03 polish): Doum is 66 tall; everything is sized by its HEIGHT
# against him. Trees about 1.45 Doum, buildings 1.6, flower beds 0.85, small things 0.6.
DOUM_H = 66
HEIGHTS = {
    'lemon': 96, 'pomegranate': 96, 'sidr': 90, 'palm': 102, 'rose': 58, 'jasmine': 60, 'flowers': 56, 'vegetables': 52,
    'spring': 48, 'house': 104, 'well': 76, 'bench': 40, 'telescope': 62, 'rose_arch': 92, 'falaj': 60, 'vine': 90,
    'frond_hut': 98, 'lantern_arch': 96, 'coral_house': 118, 'fountain': 90, 'lily_pool': 52, 'jasmine_pergola': 96,
    'pearl_chest': 54, 'majlis': 90, 'lamp_posts': 84,
}
ITEMS = [(n, ar, round(HEIGHTS[n] * META[n]['w'] / META[n]['h']) if n in HEIGHTS else w, k, pr, op) for n, ar, w, k, pr, op in ITEMS]
ITEM_JS = '{' + ', '.join(f"{i[0]}: {i[2]}" for i in ITEMS) + '}'

NAMES_JS = '{' + ', '.join(f"{i[0]}: '{i[1]}'" for i in ITEMS) + '}'

# ground point (x, y) and scale of each of the six places, back to front
SPOTS = [(114, 226, .92), (264, 226, .92), (70, 256, 1.0), (294, 256, 1.0), (104, 286, 1.06), (254, 286, 1.06)]
# Where Doum stands to act on each place (2026-10-03 animation pass): never behind a front-row thing,
# or the can, the water and his hands are hidden. Back places: beside them, by the palm; middle
# places: on the outer sand; front places: in the open gap between them. He turns to face the place.
STANDS = {0: (160, 238), 1: (220, 238), 2: (52, 266), 3: (308, 266), 4: (140, 300), 5: (218, 300), 'palm': (172, 256)}
# Where he stands to plant: the sprout in the patting picture is about 30 units to his side,
# so it lands on the place itself. Every stand is inside the sand ring ((x-180)/136)^2 + ((y-255)/52)^2 < 0.95
PLANT_STANDS = [(144, 236), (234, 236), (50, 262), (308, 262), (134, 296), (224, 296)]
# Where things may stand (Aziz, 2026-10-03: "big building only in the back"). The island reads
# front to back like a stage: buildings in the two back places, tall things (trees, the well,
# arches, the fountain) in the back or middle row, low things anywhere. Nothing hides Doum.
BIG = {'house', 'coral_house', 'frond_hut', 'majlis'}
TALL = {'lemon', 'pomegranate', 'sidr', 'palm', 'well', 'rose_arch', 'lantern_arch', 'jasmine_pergola', 'vine', 'fountain', 'lamp_posts'}
ROW = [0, 0, 1, 1, 2, 2]   # back, middle, front


def size_of(name):
    return 'big' if name in BIG else 'tall' if name in TALL else 'low'


def fits(name, place):
    s = size_of(name)
    return ROW[place] == 0 if s == 'big' else ROW[place] <= 1 if s == 'tall' else True

POSES_JS = """{
      wave: ['/_blob/4fe66825d4a1e1409975aaf4cae25efe', 633, 767, .5],
      heart: ['/_blob/1b550d444d0dfca059dcdb1c7813cd9f', 649, 784, .5],
      shades: ['/_blob/5a2a333e3f11af16ca86594b10860e0b', 640, 792, .5],
      jump: ['/_blob/01a0919e008df49374de250038e990bb', 856, 798, .5],
      three: ['/_blob/bda45ed574b609786b0ad5e6f32cc9c1', 597, 750, .5],
      side: ['/_blob/849b0f3a4cabaa0a51bb604bab372a65', 399, 752, .5],
      back: ['/_blob/c071aa42c55495bc0d61a18f02290280', 591, 743, .5],
      back34: ['/_blob/5769be82ddef0c2a10f9174a2a60ef37', 576, 750, .5],
      water: ['/_blob/ff0714f75ca540d6b9e854eb7ec643f0', 825, 824, .46],
      plant: ['/_blob/239821cb47d27696b528956bd28c88b8', 688, 760, .42],
      sleep: ['/_blob/83c02ebb24494b1bec34815440654d97', 850, 679, .5],
      sparkles: ['/_blob/f54c56f0458a9bc4ac82dc5d45c2870f', 700, 802, .5],
      lantern: ['/_blob/4fa5d30b3b6336e626650625981d86c7', 816, 742, .5]
    }"""

FRAME_IDS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'frame_ids.json')))
FRAME_META = json.load(open('/Users/aysha/Documents/GrowDailyV2/design/mascot/frames-web/meta.json'))
FRAMES_JS = '{' + ', '.join(
    f"{k}: ['/_blob/{v}', {FRAME_META[k]['w']}, {FRAME_META[k]['h']}, {FRAME_META[k].get('ax', 0)}, {FRAME_META[k].get('ay', 0)}, {FRAME_META[k].get('dh', 0)}, {FRAME_META[k]['k']:.4f}]"
    for k, v in FRAME_IDS.items()) + '}'

CX, CY, RX, RY, SIDE = 180, 262, 168, 70, 30


def arc_pts(dy, a0=0, a1=180, n=1):
    """Points on the lower half of the sea ellipse, moved down by dy."""
    return [(CX + RX * math.cos(math.radians(a)), CY + dy + RY * math.sin(math.radians(a))) for a in range(a0, a1 + 1, n)]


def lower_arc(dy):
    return f'M{CX - RX} {CY + dy} A{RX} {RY} 0 0 0 {CX + RX} {CY + dy}'


def seams(rows=2):
    """Block joints on the side band, two staggered courses."""
    d = ''
    h = SIDE / rows
    for r in range(rows):
        for a in range(8 + 9 * r, 180, 18):
            x = CX + RX * math.cos(math.radians(a))
            y = CY + RY * math.sin(math.radians(a)) + r * h
            d += f'M{x:.1f} {y:.1f} V{y + h:.1f} '
    return d


def star(x, y, r):
    return (f'M{x} {y - r} L{x + r * .3:.2f} {y - r * .3:.2f} L{x + r} {y} L{x + r * .3:.2f} {y + r * .3:.2f} '
            f'L{x} {y + r} L{x - r * .3:.2f} {y + r * .3:.2f} L{x - r} {y} L{x - r * .3:.2f} {y - r * .3:.2f} Z')


def star5(x, y, r):
    pts = []
    for i in range(10):
        a = math.radians(-90 + i * 36)
        rr = r if i % 2 == 0 else r * .48
        pts.append(f'{x + rr * math.cos(a):.1f} {y + rr * math.sin(a):.1f}')
    return 'M' + ' L'.join(pts) + ' Z'


def ring(front):
    """Pearl ring around the base; the back half is drawn before the island."""
    out = ''
    for i in range(36):
        a = math.radians(i * 10)
        x, y = CX + 186 * math.cos(a), 300 + 84 * math.sin(a)
        if (math.sin(a) > 0) == front:
            r = 4.6 + 1.2 * math.sin(a)
            out += (f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="#FFFDF4" stroke="#B89A5A" stroke-width="1.2"></circle>'
                    f'<circle cx="{x - r * .35:.1f}" cy="{y - r * .35:.1f}" r="{r * .3:.1f}" fill="#FFFFFF"></circle>')
    return out


def base_svg(p):
    """The world under the things: sky, base, sea, beach, grass, plaque. p is the hole prefix."""
    side = f'M{CX - RX} {CY} L{CX - RX} {CY + SIDE} A{RX} {RY} 0 0 0 {CX + RX} {CY + SIDE} L{CX + RX} {CY} A{RX} {RY} 0 0 1 {CX - RX} {CY} Z'
    crown = ''.join(f'<path d="{star5(x, y, r)}"></path>' for x, y, r in [(108, 58, 7), (136, 36, 8.5), (180, 26, 11), (224, 36, 8.5), (252, 58, 7)])
    waves = ''.join(f'<path d="M{x} {y} q4 -3 8 0 t8 0" fill="none" stroke="#FFFFFF" stroke-width="1.6" stroke-linecap="round" style="opacity: .8"></path>'
                    for x, y in [(30, 262), (316, 250), (58, 230), (290, 226), (210, 318), (120, 322)])
    tufts = ''.join(f'<path d="M{x} {y} l-2 -5 M{x} {y} l0 -6 M{x} {y} l2 -5" fill="none" style="stroke: {{{{{p}v.grassEdge}}}}" stroke-width="1.4" stroke-linecap="round"></path>'
                    for x, y in [(96, 244), (150, 270), (262, 268), (206, 236), (300, 246), (170, 222)])
    gold_glints = ''.join(f'<path d="{star(x, y, r)}"></path>' for x, y, r in [(140, 340, 4), (222, 352, 3.4), (60, 318, 3), (300, 322, 3)])
    return (
        '<svg viewBox="0 0 360 400" width="100%" height="100%" style="position: absolute; left: 0; top: 0;" aria-hidden="true">'
        '<defs><radialGradient id="isl-aura" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#FFE39A" stop-opacity="1"></stop>'
        '<stop offset="0.6" stop-color="#FFE39A" stop-opacity="0.45"></stop><stop offset="1" stop-color="#FFE39A" stop-opacity="0"></stop></radialGradient></defs>'
        f'<g style="opacity: {{{{{p}f.bubble}}}}"><circle cx="180" cy="205" r="178" style="fill: {{{{{p}v.sky}}}}; transition: fill .8s ease"></circle></g>'
        f'<g style="opacity: {{{{{p}f.rect}}}}"><rect x="0" y="0" width="360" height="400" style="fill: {{{{{p}v.sky}}}}; transition: fill .8s ease"></rect></g>'
        # sun
        f'<g style="opacity: {{{{{p}v.sun}}}}; transition: opacity .8s ease" stroke="#E2A93B" stroke-width="2.4" stroke-linecap="round">'
        '<path d="M300 40 V45 M300 95 V100 M270 70 H275 M325 70 H330 M279 49 L283 53 M317 87 L321 91 M321 49 L317 53 M283 87 L279 91" fill="none"></path>'
        '<circle cx="300" cy="70" r="17" fill="#F7D774" stroke="#1E3A24" stroke-width="2.2"></circle></g>'
        # clouds
        f'<g fill="#FFFFFF" style="opacity: {{{{{p}v.clouds}}}}; transition: opacity .8s ease">'
        '<path d="M28 168 a12 12 0 0 1 22 -8 a15 15 0 0 1 28 4 a10 10 0 0 1 4 18 h-50 a8 8 0 0 1 -4 -14 Z" style="opacity: .9"></path>'
        '<path d="M268 150 a10 10 0 0 1 18 -6 a12 12 0 0 1 22 4 a8 8 0 0 1 2 14 h-40 a7 7 0 0 1 -2 -12 Z" style="opacity: .8"></path></g>'
        # moon and stars
        f'<g style="opacity: {{{{{p}v.moon}}}}; transition: opacity .8s ease" fill="#F6E7A8">'
        + ''.join(f'<path d="{star(x, y, r)}"></path>' for x, y, r in [(60, 60, 4), (250, 40, 3.2), (330, 160, 3.6), (30, 200, 3), (140, 30, 3), (94, 120, 2.6)])
        + f'<circle cx="300" cy="72" r="16" stroke="#1E3A24" stroke-width="2"></circle><circle cx="307" cy="66" r="14" style="fill: {{{{{p}v.sky}}}}"></circle></g>'
        # aura for gold and up
        f'<ellipse cx="180" cy="222" rx="210" ry="176" fill="url(#isl-aura)" style="opacity: {{{{{p}tr.aura}}}}; transition: opacity .8s ease"></ellipse>'
        # star crown at 100
        f'<g fill="#F2C14E" stroke="#8A5A10" stroke-width="1.6" stroke-linejoin="round" style="opacity: {{{{{p}tr.crown}}}}">{crown}</g>'
        # pearl ring, back half
        f'<g style="opacity: {{{{{p}tr.ring}}}}">{ring(False)}</g>'
        # the base: side band
        f'<path d="{side}" stroke="#1E2B1A" stroke-width="2.4" stroke-linejoin="round" style="fill: {{{{{p}pl.side}}}}; transition: fill .8s ease"></path>'
        f'<path d="{lower_arc(SIDE / 2)}" fill="none" stroke="#C99A62" stroke-width="1.6" stroke-dasharray="6 7" style="opacity: {{{{{p}tr.sand}}}}"></path>'
        f'<g fill="none" stroke-width="1.4" style="stroke: {{{{{p}pl.seam}}}}; opacity: {{{{{p}tr.blocks}}}}"><path d="{lower_arc(SIDE / 2)} {seams()}"></path></g>'
        f'<path d="{lower_arc(SIDE / 2)}" fill="none" stroke="#5FA8C8" stroke-width="3.2" style="opacity: {{{{{p}tr.coral}}}}"></path>'
        f'<g fill="none" stroke="#E9B949" stroke-width="5" style="opacity: {{{{{p}tr.gold}}}}"><path d="{lower_arc(4)}"></path><path d="{lower_arc(SIDE - 3)}"></path></g>'
        f'<path d="{side}" fill="none" stroke="#1E2B1A" stroke-width="2.4" stroke-linejoin="round"></path>'
        f'<g fill="#FFF6D0" stroke="#B88A1C" stroke-width="1" style="opacity: {{{{{p}tr.gold}}}}">{gold_glints}</g>'
        # sea
        f'<ellipse cx="{CX}" cy="{CY}" rx="{RX}" ry="{RY}" stroke="#1E2B1A" stroke-width="2.4" style="fill: {{{{{p}v.sea}}}}; transition: fill .8s ease"></ellipse>'
        f'<ellipse cx="{CX}" cy="{CY - 4}" rx="{RX - 14}" ry="{RY - 10}" style="fill: {{{{{p}v.seaHi}}}}; transition: fill .8s ease"></ellipse>'
        + waves +
        # beach with a little thickness
        f'<ellipse cx="180" cy="260" rx="136" ry="52" style="fill: {{{{{p}v.sandDark}}}}"></ellipse>'
        f'<ellipse cx="180" cy="255" rx="136" ry="52" stroke="#1E2B1A" stroke-width="2.2" style="fill: {{{{{p}v.sand}}}}; transition: fill .8s ease"></ellipse>'
        # grass
        f'<ellipse cx="180" cy="248" rx="122" ry="43" stroke="#1E2B1A" stroke-width="2.2" style="fill: {{{{{p}v.grass}}}}; transition: fill .8s ease"></ellipse>'
        f'<ellipse cx="166" cy="240" rx="94" ry="28" style="fill: {{{{{p}v.grassHi}}}}; transition: fill .8s ease"></ellipse>'
        + tufts +
        # pearl ring, front half
        f'<g style="opacity: {{{{{p}tr.ring}}}}">{ring(True)}</g>'
        # plaque with the level
        f'<rect x="150" y="{CY + RY + 3}" width="60" height="25" rx="8" stroke-width="2.2" style="fill: {{{{{p}pl.bg}}}}; stroke: {{{{{p}pl.bd}}}}"></rect>'
        f'<text x="180" y="{CY + RY + 21}" text-anchor="middle" font-family="IBM Plex Sans Arabic, IBM Plex Sans, sans-serif" font-size="17" font-weight="700" style="fill: {{{{{p}pl.fg}}}}">{{{{{p}pl.n}}}}</text>'
        # highlight under a new or chosen thing
        f'<ellipse cx="{{{{{p}fx.gx}}}}" cy="{{{{{p}fx.gy}}}}" rx="40" ry="13" fill="#FFF3B0" stroke="#F2C14E" stroke-width="2" style="opacity: {{{{{p}fx.go}}}}; transition: opacity .4s ease"></ellipse>'
        '</svg>'
    )


def layers(p):
    """Everything that stands on the island, back to front, then glows and the sparkle."""
    return (
        f'<sc-for list="{{{{{p}items}}}}" as="it" hint-placeholder-count="10">'
        '<img src="{{it.src}}" alt="" class="{{it.cls}}" style="position: absolute; left: {{it.x}}px; top: {{it.y}}px; width: {{it.w}}px; height: {{it.h}}px; filter: {{it.f}}; scale: {{it.sc}}; z-index: {{it.zi}}; pointer-events: none; transition: filter .8s ease; transform-origin: 50% 100%;">'
        '</sc-for>'
        f'<sc-if value="{{{{{p}dm.show}}}}" hint-placeholder-val="{{{{false}}}}">'
        f'<div style="position: absolute; left: {{{{{p}dm.x}}}}px; top: {{{{{p}dm.y}}}}px; width: 0; height: 0; z-index: {{{{{p}dm.zi}}}}; pointer-events: none; transition: left {{{{{p}dm.dur}}}}s cubic-bezier(.4,.1,.4,1), top {{{{{p}dm.dur}}}}s cubic-bezier(.4,.1,.4,1);">'
        f'<div style="position: absolute; left: {{{{{p}dm.shl}}}}px; top: {{{{{p}dm.sht}}}}px; width: {{{{{p}dm.shw}}}}px; height: {{{{{p}dm.shh}}}}px; border-radius: 50%; background: radial-gradient(closest-side, rgba(30,43,26,0.32), rgba(30,43,26,0));"></div>'
        f'<div class="{{{{{p}dm.inner}}}}" style="position: absolute; left: 0; top: 0; width: 0; height: 0; scale: {{{{{p}dm.sc}}}}; transform-origin: 0 0; --hop: {{{{{p}dm.hop}}}}px;">'
        f'<sc-for list="{{{{{p}dm.imgs}}}}" as="im" hint-placeholder-count="4">'
        '<img src="{{im.src}}" alt="" class="{{im.cls}}" style="position: absolute; left: {{im.x}}px; top: {{im.y}}px; width: {{im.w}}px; height: {{im.h}}px; max-width: none; filter: {{im.f}};">'
        '</sc-for></div></div>'
        '</sc-if>'
        f'<sc-for list="{{{{{p}bursts}}}}" as="b" hint-placeholder-count="0">'
        '<img src="{{b.src}}" alt="" class="{{b.cls}}" style="position: absolute; z-index: 9000; left: {{b.x}}px; top: {{b.y}}px; width: {{b.w}}px; height: {{b.w}}px; pointer-events: none;">'
        '</sc-for>'
        f'<sc-for list="{{{{{p}tags}}}}" as="t" hint-placeholder-count="0">'
        '<div dir="rtl" style="position: absolute; z-index: 9100; left: {{t.x}}px; top: {{t.y}}px; transform: translate(-50%, 0); background: rgba(35,53,42,0.86); color: #F5F0E1; font-family: \'IBM Plex Sans Arabic\', sans-serif; font-size: {{t.fs}}px; font-weight: 600; line-height: 1.2; padding: 2px 7px; border-radius: 999px; white-space: nowrap; pointer-events: none;">{{t.text}}</div>'
        '</sc-for>'
        f'<sc-if value="{{{{{p}pennant.show}}}}" hint-placeholder-val="{{{{false}}}}">'
        f'<svg viewBox="0 0 360 400" width="100%" height="100%" style="position: absolute; left: 0; top: 0; z-index: 8800; pointer-events: none;" aria-hidden="true">'
        '<g class="isl-flag" style="transform-origin: 330px 196px;"><line x1="330" y1="196" x2="330" y2="262" stroke="#1E2B1A" stroke-width="2.4" stroke-linecap="round"></line>'
        '<path d="M331 197 L356 205 L331 214 Z" fill="#F2C14E" stroke="#1E2B1A" stroke-width="2" stroke-linejoin="round"></path>'
        '<circle cx="330" cy="194" r="3" fill="#F2C14E" stroke="#1E2B1A" stroke-width="1.6"></circle></g></svg>'
        '</sc-if>'
        f'<sc-if value="{{{{{p}say.show}}}}" hint-placeholder-val="{{{{false}}}}">'
        f'<div dir="rtl" class="isl-pop" style="position: absolute; z-index: 9200; left: {{{{{p}say.x}}}}px; top: {{{{{p}say.y}}}}px; transform: translate(-50%, -100%); max-width: 72%; background: #FFFFFF; color: #23352A; font-family: \'IBM Plex Sans Arabic\', sans-serif; font-size: {{{{{p}say.fs}}}}px; font-weight: 600; line-height: 1.35; padding: 7px 11px; border-radius: 14px; box-shadow: 0 2px 8px rgba(30,58,36,0.2); pointer-events: none; text-align: center;">{{{{{p}say.text}}}}</div>'
        '</sc-if>'
        f'<sc-for list="{{{{{p}glows}}}}" as="g" hint-placeholder-count="3">'
        '<div style="position: absolute; z-index: 8900; left: {{g.x}}px; top: {{g.y}}px; width: {{g.d}}px; height: {{g.d}}px; border-radius: 999px; background: radial-gradient(circle, rgba(255,214,110,0.85) 0%, rgba(255,214,110,0.35) 40%, rgba(255,214,110,0) 70%); pointer-events: none;"></div>'
        '</sc-for>'
        f'<sc-if value="{{{{{p}fx.spark}}}}" hint-placeholder-val="{{{{false}}}}">'
        f'<img src="{ART["sparkle"][0]}" alt="" class="isl-twinkle" style="position: absolute; z-index: 9000; left: {{{{{p}fx.sx}}}}px; top: {{{{{p}fx.sy}}}}px; width: {{{{{p}fx.sw}}}}px; height: {{{{{p}fx.sw}}}}px; pointer-events: none;">'
        '</sc-if>'
    )


def scene(p):
    """Ground and everything on it, in its own stacking context, so buttons placed after it sit on top."""
    return ('<div style="position: absolute; left: 0; top: 0; width: 100%; height: 100%; isolation: isolate;">'
            + base_svg(p) + layers(p) + '</div>')


STYLE = ('@keyframes isl-twinkle{0%,100%{transform:scale(.82) rotate(-6deg);opacity:.75}50%{transform:scale(1.08) rotate(6deg);opacity:1}}'
         '.isl-twinkle{animation:isl-twinkle 1.6s ease-in-out infinite}'
         '@keyframes isl-hop-a{0%{transform:none}25%{transform:translateY(-9%) scale(1.04,.97)}45%{transform:none}60%{transform:rotate(-3deg)}75%{transform:rotate(3deg)}100%{transform:none}}'
         '@keyframes isl-hop-b{0%{transform:none}25%{transform:translateY(-9%) scale(1.04,.97)}45%{transform:none}60%{transform:rotate(-3deg)}75%{transform:rotate(3deg)}100%{transform:none}}'
         '.isl-hop-a{animation:isl-hop-a .9s ease-out}.isl-hop-b{animation:isl-hop-b .9s ease-out}'
         '@keyframes isl-rise-a{0%{transform:translateY(10px) scale(.5);opacity:0}30%{opacity:1}100%{transform:translateY(-34px) scale(1);opacity:0}}'
         '@keyframes isl-rise-b{0%{transform:translateY(10px) scale(.5);opacity:0}30%{opacity:1}100%{transform:translateY(-34px) scale(1);opacity:0}}'
         '.isl-rise-a{animation:isl-rise-a 1.3s ease-out forwards;opacity:0}.isl-rise-b{animation:isl-rise-b 1.3s ease-out forwards;opacity:0}'
         '@keyframes isl-pop{0%{transform:translate(-50%,-90%) scale(.8);opacity:0}100%{transform:translate(-50%,-100%) scale(1);opacity:1}}'
         '.isl-pop{animation:isl-pop .25s ease-out}'
         '@keyframes isl-flag{0%,100%{transform:skewY(0)}50%{transform:skewY(-4deg)}}.isl-flag{animation:isl-flag 2.4s ease-in-out infinite}'
         '@keyframes isl-walk{0%{transform:translateY(0) rotate(-3.5deg)}25%{transform:translateY(-5%) rotate(0deg) scale(.98,1.03)}50%{transform:translateY(0) rotate(3.5deg)}75%{transform:translateY(-5%) rotate(0deg) scale(.98,1.03)}100%{transform:translateY(0) rotate(-3.5deg)}}'
         '.isl-walk{animation:isl-walk .46s ease-in-out infinite}'
         '@keyframes isl-land{0%{transform:scale(1.07,.9)}60%{transform:scale(.98,1.03)}100%{transform:none}}.isl-land{animation:isl-land .32s ease-out}'
         '@keyframes isl-breathe{0%,100%{transform:none}50%{transform:scale(1.012,1.022)}}.isl-breathe{animation:isl-breathe 3.4s ease-in-out infinite}'
         '@keyframes isl-fr{0%{opacity:1}25%{opacity:0}100%{opacity:0}}'
         '.isl-fr{opacity:0;animation:isl-fr .44s step-end infinite}.isl-fr0{animation-delay:0s}.isl-fr1{animation-delay:-.33s}.isl-fr2{animation-delay:-.22s}.isl-fr3{animation-delay:-.11s}'
         '@keyframes isl-sway-s{0%,100%{transform:rotate(-1.2deg)}50%{transform:rotate(1.2deg)}}.isl-sway-s{animation:isl-sway-s .44s ease-in-out infinite}'
         '@keyframes isl-sway{0%,100%{transform:translateY(0) rotate(-2.5deg)}25%,75%{transform:translateY(-4px)}50%{transform:rotate(2.5deg)}}.isl-sway{animation:isl-sway .44s ease-in-out infinite}'
         '@keyframes isl-blink{0%,93%{opacity:0}94%,97%{opacity:1}98%,100%{opacity:0}}.isl-blink{opacity:0;animation:isl-blink 5.3s linear infinite 1.2s}'
         '@keyframes isl-lookl{0%,58%{opacity:0}60%,72%{opacity:1}74%,100%{opacity:0}}.isl-lookl{opacity:0;animation:isl-lookl 12s linear infinite 3s}'
         '@keyframes isl-lookr{0%,80%{opacity:0}82%,92%{opacity:1}94%,100%{opacity:0}}.isl-lookr{opacity:0;animation:isl-lookr 12s linear infinite 3s}'
         '@keyframes isl-act1{0%,99%{opacity:1}100%{opacity:0}}.isl-act1{animation:isl-act1 .5s linear forwards}'
         '@keyframes isl-act2{0%,99%{opacity:0}100%{opacity:1}}.isl-act2{opacity:0;animation:isl-act2 .5s linear forwards}'
         '@keyframes isl-grow{0%{transform:scale(.15);opacity:0}55%{transform:scale(1.12);opacity:1}75%{transform:scale(.95)}100%{transform:none}}.isl-grow{animation:isl-grow .9s cubic-bezier(.3,.7,.4,1) both}'
         '@keyframes isl-act1b{0%,99%{opacity:1}100%{opacity:0}}.isl-act1b{animation:isl-act1b .5s linear forwards}'
         '@keyframes isl-act2b{0%,99%{opacity:0}100%{opacity:1}}.isl-act2b{opacity:0;animation:isl-act2b .5s linear forwards}'
         # sitting (2026-10-03): a hop onto the seat with the frame swapped at the top, a slow content sway, a hop down
         '@keyframes isl-hopup{0%{transform:none}45%{transform:translateY(calc(var(--hop) * -1)) scale(.95,1.06)}78%{transform:scale(1.07,.92)}100%{transform:none}}'
         '@keyframes isl-hopupb{0%{transform:none}45%{transform:translateY(calc(var(--hop) * -1)) scale(.95,1.06)}78%{transform:scale(1.07,.92)}100%{transform:none}}'
         '.isl-hopup{animation:isl-hopup .42s ease-out}.isl-hopupb{animation:isl-hopupb .42s ease-out}'
         '@keyframes isl-hopdn{0%{transform:none}40%{transform:translateY(calc(var(--hop) * -0.8)) scale(.96,1.04)}80%{transform:scale(1.08,.9)}100%{transform:none}}'
         '@keyframes isl-hopdnb{0%{transform:none}40%{transform:translateY(calc(var(--hop) * -0.8)) scale(.96,1.04)}80%{transform:scale(1.08,.9)}100%{transform:none}}'
         '.isl-hopdn{animation:isl-hopdn .38s ease-in}.isl-hopdnb{animation:isl-hopdnb .38s ease-in}'
         '@keyframes isl-swo{0%,44%{opacity:1}45%,100%{opacity:0}}@keyframes isl-swob{0%,44%{opacity:1}45%,100%{opacity:0}}'
         '@keyframes isl-swi{0%,44%{opacity:0}45%,100%{opacity:1}}@keyframes isl-swib{0%,44%{opacity:0}45%,100%{opacity:1}}'
         '.isl-swo{animation:isl-swo .42s linear forwards}.isl-swob{animation:isl-swob .42s linear forwards}'
         '.isl-swi{opacity:0;animation:isl-swi .42s linear forwards}.isl-swib{opacity:0;animation:isl-swib .42s linear forwards}'
         '@keyframes isl-sit{0%,100%{transform:rotate(-1.2deg)}50%{transform:rotate(1.2deg) scale(1.012,1.025)}}.isl-sit{animation:isl-sit 4.2s ease-in-out infinite}'
         '@media (prefers-reduced-motion: reduce){.isl-grow,.isl-twinkle,.isl-hop-a,.isl-hop-b,.isl-pop,.isl-flag,.isl-walk,.isl-land,.isl-breathe,.isl-sway,.isl-sway-s{animation:none}.isl-rise-a,.isl-rise-b,.isl-blink,.isl-lookl,.isl-lookr{animation:none;opacity:0}.isl-fr{animation:none}.isl-fr0{opacity:1}.isl-act1,.isl-act1b{animation:none;opacity:0}.isl-act2,.isl-act2b{animation:none;opacity:1}.isl-hopup,.isl-hopupb,.isl-hopdn,.isl-hopdnb,.isl-sit{animation:none}.isl-swo,.isl-swob,.isl-swi,.isl-swib{animation:none}.isl-swo,.isl-swob{opacity:0}.isl-swi,.isl-swib{opacity:1}}')

# JS method shared by both components: island(o) returns everything the markup needs.
ISLAND_JS = r"""
  island(o) {
    const ART = __ART__;
    const W = __ITEMW__;
    const SPOTS = __SPOTS__;
    const POSES = __POSES__;
    const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
    const hex = (c) => { const n = parseInt(String(c).slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; };
    const mix = (a, b, k) => { const x = hex(a), y = hex(b); return '#' + x.map((v, i) => Math.round(v + (y[i] - v) * k).toString(16).padStart(2, '0')).join(''); };
    const L = clamp(Math.round(o.level), 1, 100);
    const S = o.size, u = S / 360, H = S * 400 / 360;
    const night = o.sky === 'night', rest = o.sky === 'rest';
    const t = rest ? 0 : clamp(Math.round(o.thirst || 0), 0, 3);
    const ct = o.quietStyle === 'quiet' ? 0 : t;
    const glance = o.detail === 'glance';
    const tier = L >= 75 ? 6 : L >= 50 ? 5 : L >= 35 ? 4 : L >= 20 ? 3 : L >= 10 ? 2 : L >= 5 ? 1 : 0;
    const c = o.colors;
    const grass = mix(c.grass, '#C9B676', ct * 0.27);
    const sky = night ? '#22304A' : rest ? '#E5E6EE' : mix(c.sky, '#F4E5CB', ct * 0.22);
    const v = {
      sky, grass, grassHi: mix(grass, '#FFFFFF', 0.2), grassEdge: mix(grass, '#1E3A24', 0.35),
      sea: night ? mix(c.sea, '#22304A', 0.4) : c.sea, seaHi: mix(night ? mix(c.sea, '#22304A', 0.4) : c.sea, '#FFFFFF', 0.25),
      sand: c.sand, sandDark: mix(c.sand, '#8B5E3C', 0.3),
      sun: night || rest || o.frame === 'none' ? 0 : 1, moon: night && o.frame !== 'none' ? 1 : 0, clouds: night || o.frame === 'none' ? 0 : 1
    };
    const on = (b) => (b ? 1 : 0);
    const tr = { sand: on(tier === 0), blocks: on(tier >= 1), coral: on(tier >= 2), gold: on(tier >= 3),
      ring: on(tier >= 5), crown: on(tier >= 6), aura: L >= 100 ? 1 : tier >= 6 ? 0.8 : tier >= 3 ? 0.45 : 0 };
    const PL = [
      ['#E3BF86', '#B07D47', '#7A5228', '#FFF6E2', '#C99A62'],
      ['#D3C8B2', '#8F8576', '#5E5649', '#FFFFFF', '#A89A80'],
      ['#F4EEE0', '#3F86A8', '#2B6480', '#FFFFFF', '#CFC4AE'],
      ['#F4EEE0', '#F2C14E', '#A87D12', '#4A3200', '#CFC4AE'],
      ['#F4EEE0', '#F2C14E', '#A87D12', '#4A3200', '#CFC4AE'],
      ['#FBF7EE', '#FFFDF6', '#D9A930', '#7A5608', '#D8CDB6'],
      ['#FBF7EE', '#FFFDF6', '#D9A930', '#7A5608', '#D8CDB6']
    ][tier];
    const pl = { side: PL[0], bg: PL[1], bd: PL[2], fg: PL[3], seam: PL[4], n: String(L) };
    const f = { bubble: on(o.frame === 'bubble'), rect: on(o.frame === 'rect') };

    const dim = night ? 'brightness(0.78) saturate(0.9)' : rest ? 'saturate(0.85)' : ct >= 2 ? 'saturate(0.8)' : 'none';
    const items = [], made = [];
    const add = (name, x, y, w, z, src) => {
      const a = ART[name]; const h = w * a[2] / a[1];
      const box = { x: x - w * a[3], y: y - h, w, h, name };
      items.push({ src: src || a[0], x: box.x * u, y: box.y * u, w: w * u, h: h * u, z: z == null ? y : z, f: dim, cls: '', sc: '1 1' });
      items[items.length - 1].zi = Math.round(((z == null ? y : z) + 50) * 4);
      box.i = items.length - 1;
      made.push(box);
      return box;
    };

    // the rainbow stands behind everything, its feet on the far shore
    if (tier >= 4 && !night && !rest) add('rainbow', 180, 214, 300, -10);
    if (L >= 4 && !night && !rest && !glance && t < 2) add('kite', 54, 132, 40, -5);

    // the palm, always at the back middle, growing with level
    const pName = L >= 75 ? 'golden_palm' : L >= 12 ? 'palm_lanterns' : L >= 10 ? 'palm_medium' : L >= 5 ? 'palm_young' : 'palm_shoot';
    const pH = L < 5 ? 58 : L < 10 ? 96 : L < 12 ? 122 : L < 20 ? 128 : L < 35 ? 150 : L < 50 ? 158 : L < 75 ? 164 : L < 100 ? 146 : 152;
    const pa = ART[pName];
    const pb = add(pName, 196, 228, pH * pa[1] / pa[2]);
    const CROWN = { palm_young: [0.5, 0.46], palm_medium: [0.5, 0.39], palm_lanterns: [0.5, 0.3] };
    // Ramadan nights (a season that comes back every year; Ramadan and the two Eids only):
    // two lanterns hang on chains from the palm's fronds, and glow at night
    const lanternsHung = [];
    if (o.season === 'ramadan' && !glance && L >= 5) {
      const hl = ART.hanging_lantern, lh = Math.max(14, pH * 0.12), lw = lh * hl[1] / hl[2];
      [[0.16, 0.36], [0.86, 0.4]].forEach(([fx, fy], j) => {
        const cx = pb.x + pb.w * fx, top = pb.y + pb.h * fy;
        lanternsHung.push(add('hanging_lantern', cx - lw * (0.5 - hl[3]), top + lh, lw, 228.6 + j * 0.01));
      });
    }
    const medals = clamp(Math.round(o.medals || 0), 0, 20);
    if (medals > 0 && CROWN[pName]) {
      const ripe = ['dates_hababou', 'dates_khalal', 'dates_rutab', 'dates_tamr'][medals > 15 ? 3 : medals > 10 ? 2 : medals > 5 ? 1 : 0];
      const off = [[-0.12, 0.04], [0.12, 0.04], [-0.25, 0.01], [0.25, 0.01], [0, 0.08]];
      const bh = pH * 0.15, da = ART[ripe], bw = bh * da[1] / da[2];
      for (let i = 0; i < Math.min(5, medals); i++) {
        const cx = pb.x + pb.w * (CROWN[pName][0] + off[i][0]), top = pb.y + pb.h * (CROWN[pName][1] + off[i][1]);
        add(ripe, cx - bw * (0.5 - da[3]), top + bh, bw, 228.5 + i * 0.01);
      }
    }

    // the six places; a golden version gets a warm tint and a soft glow
    const GOLD = 'sepia(0.5) saturate(1.9) hue-rotate(-14deg) brightness(1.06) drop-shadow(0 0 3px rgba(255,214,110,0.95))';
    const spots = o.spots;
    const boxes = [];
    for (let i = 0; i < 6; i++) {
      const name = spots[i];
      const s = SPOTS[i];
      boxes.push(name && W[name] ? add(name, s[0], s[1], W[name] * s[2]) : null);
      if (boxes[i] && o.golden && o.golden[i]) items[boxes[i].i].f = GOLD;
    }
    if (o.growIn != null && o.growIn >= 0 && boxes[o.growIn]) items[boxes[o.growIn].i].cls = 'isl-grow';

    // free placement: [{ name, x, y, w, flip, gold }] in island units
    const extraBoxes = (o.extra || []).map((e) => {
      if (!ART[e.name]) return null;
      const b = add(e.name, e.x, e.y, e.w);
      if (e.flip) items[b.i].sc = '-1 1';
      if (e.gold) items[b.i].f = GOLD;
      return b;
    });
    if (!glance) {
      if (L >= 3 && !o.noPath) add('stones', 212, 308, 40);
      if (L >= 50) { add('big_dhow', 74, 318, 72); add('lighthouse', 334, 262, 42); }
      else if (L >= 22) add('dhow', 72, 316, 58);
      const sp = [[296, 312], [314, 300], [276, 320], [330, 288]];
      for (let i = 0; i < Math.min(4, o.pearls || 0); i++) add('shell_pearl', sp[i][0], sp[i][1], 20);
    }
    // gifts from friends sit on the sand, each with the giver's name
    const tags = [];
    const GP = [[58, 270], [300, 274], [128, 306]];
    (o.gifts || []).slice(0, 3).forEach((g, i) => {
      add(g.name, GP[i][0], GP[i][1], g.name === 'harvest_basket' ? 34 : g.name === 'shell_pearl' ? 26 : 32);
      if (!glance && g.from && o.giftTags) tags.push({ x: GP[i][0] * u, y: (GP[i][1] + 2) * u, text: 'من ' + g.from, fs: Math.max(9, 10 * u) });
    });
    // a visiting Doum on the right sand
    if (o.guest && !glance && !o.guestWalks) {
      const gp = POSES.heart, k = (__DH__ - 6) / 767, w = gp[1] * k, h = gp[2] * k;
      items.push({ src: gp[0], x: (262 - w * gp[3]) * u, y: (302 - h) * u, w: w * u, h: h * u, z: 302, f: dim, cls: '', sc: '1 1' });
      if (o.guestName) tags.push({ x: 262 * u, y: (302 - h - 16) * u, text: o.guestName, fs: Math.max(9, 11 * u) });
    }
    if (o.watering) add('rain_cloud', 236, 112, 70, 400);

    // Doum stands in front of his palm
    let pose = o.pose || 'auto';
    if (pose === 'auto') pose = night && o.season === 'ramadan' ? 'lantern' : night ? 'sleep' : rest ? 'sleep' : o.planting ? 'plant' : (o.watering || t >= 1) ? 'water' : (o.glowing || (o.fresh != null && o.fresh !== -1)) ? 'sparkles' : 'wave';
    const pd = !glance && POSES[pose];
    const FR = __FRAMES__;
    const DIRH = { side: 0.98, front: 1, back: 0.97, three: 0.98, back34: 0.98 };
    // two-step actions change picture at 0.5. Planting digs, then pats the sprout in (Sheet 1, no pot);
    // a cutting is reach, then hold (the snip pose carries its own sapling)
    const ACT = { dates: ['reach', 'hold_dates'], cutting: ['reach', 'hold_cutting'], water: ['can_tilt', 'can_pour'], fill: ['can_tilt'],
      carry: ['carry_basket'], put: ['put_basket'], camera: ['camera'], door: ['door_push'],
      plant: ['plant_dig', 'plant_pat'] };
    // Doum as a sprite standing on his ground point: walk cycles, actions, or standing with blinks
    const sprite = (ds) => {
      const img = (n, cls, sc) => { const f = FR[n]; return { src: f[0], cls, x: -f[3] * sc * u, y: -f[4] * sc * u, w: f[1] * sc * u, h: f[2] * sc * u, f: dim }; };
      if (ds.walking && ds.carry) {
        return { imgs: [img('carry_basket', '', __DH__ / (302 * FR.carry_basket[6]))], inner: 'isl-sway' };
      }
      if (ds.walking) {
        const d = DIRH[ds.dir] ? ds.dir : 'front';
        const sc = (__DH__ * DIRH[d]) / FR['walk_' + d + '_1'][5];
        return { imgs: [1, 2, 3, 4].map((k, i) => img('walk_' + d + '_' + k, 'isl-fr isl-fr' + i, sc)), inner: ds.carry ? 'isl-sway' : 'isl-sway-s' };
      }
      if (ds.sit) {
        // on a seat: hop up (standing frame until the top of the hop, then the seated one), sit, hop down
        const ss = __DH__ / (302 * FR.sit_front[6]), si = __DH__ / FR.idle_calm[5], par = ds.parity ? 'b' : '';
        if (ds.sit === 'on') return { imgs: [img('sit_front', '', ss)], inner: 'isl-sit' };
        const up = ds.sit === 'up';
        return { imgs: [img('idle_calm', (up ? 'isl-swo' : 'isl-swi') + par, si), img('sit_front', (up ? 'isl-swi' : 'isl-swo') + par, ss)],
          inner: (up ? 'isl-hopup' : 'isl-hopdn') + par };
      }
      if (ds.action && ACT[ds.action]) {
        const seq = ACT[ds.action];
        return { imgs: seq.map((n, i) => img(n, seq.length > 1 ? 'isl-act' + (i + 1) + (ds.parity ? 'b' : '') : '', __DH__ / (302 * FR[n][6]))), inner: ds.landing ? 'isl-land' : 'isl-breathe' };
      }
      const sc = __DH__ / FR.idle_calm[5];
      return { imgs: [img('idle_calm', '', sc), img('idle_blink', 'isl-blink', sc), img('idle_look_l', 'isl-lookl', sc), img('idle_look_r', 'isl-lookr', sc)],
        inner: ds.landing ? 'isl-land' : 'isl-breathe' };
    };
    let dm = { show: false, x: 0, y: 0, zi: 0, dur: 0.9, sc: '1 1', imgs: [], inner: '', shl: 0, sht: 0, shw: 0, shh: 0, hop: 9 };
    const at = o.walkTo || [168, 300];
    const doumAt = (p, xy) => {
      const k = __DH__ / 767, w = p[1] * k, h = p[2] * k;
      return { src: p[0], x: (xy[0] - w * p[3]) * u, y: (xy[1] - h) * u, w: w * u, h: h * u, z: xy[1], f: dim, cls: '', sc: '1 1' };
    };
    if (o.guestWalks) {
      // a visit: the host's Doum waves where he lives, yours walks around
      if (pd) items.push(doumAt(POSES.wave, [168, 300]));
      dm = Object.assign(dm, { show: !glance, x: at[0] * u, y: at[1] * u }, sprite(o.doumState || {}));
      dm.sc = (o.doumState || {}).flip ? '-1 1' : '1 1';
      dm.y0 = at[1] * u - ((o.doumState || {}).sit ? 52 : __DH__) * u;
      if (o.guestName && !glance) tags.push({ x: at[0] * u, y: dm.y0 - 30 * Math.min(u, 1.4), text: o.guestName, fs: Math.min(14, Math.max(10, 11 * u)) });
    } else if (pd) {
      if (o.walkTo) {
        dm = Object.assign(dm, { show: true, x: at[0] * u, y: at[1] * u }, sprite(o.doumState || {}));
        dm.sc = (o.doumState || {}).flip ? '-1 1' : '1 1';
      } else if (pose === 'plant' && FR.plant_pat) {
        // planting at home: patting a sprout in (the old planting pose held a pot)
        const f = FR.plant_pat, sc = __DH__ / (302 * f[6]);
        items.push({ src: f[0], x: (at[0] - f[3] * sc) * u, y: (at[1] - f[4] * sc) * u, w: f[1] * sc * u, h: f[2] * sc * u, z: at[1], f: dim, cls: '', sc: '1 1' });
      } else items.push(doumAt(pd, at));
    }

    // a tap makes a thing hop and lets something rise from it
    const bursts = [];
    let pokedBox = null;
    if (o.poke != null && o.poke !== -1) {
      const all = { palm: pb };
      boxes.forEach((b, i) => { if (b) all[i] = b; });
      pokedBox = all[o.poke] || null;
      if (pokedBox) {
        const par = (o.pokeN || 0) % 2 ? 'b' : 'a';
        items[pokedBox.i].cls = 'isl-hop-' + par;
        const WET = { fountain: 1, lily_pool: 1, spring: 1, well: 1, falaj: 1 };
        const src = WET[pokedBox.name] ? ART.drops[0] : ART.sparkle[0];
        [-0.22, 0.05, 0.28].forEach((dx, j) => bursts.push({ src, cls: 'isl-rise-' + par,
          x: (pokedBox.x + pokedBox.w * (0.5 + dx) - 9) * u, y: (pokedBox.y + 6 + j * 4) * u, w: 18 * u }));
      }
    }
    // the walking Doum: depth by z-index, speed-based timing, waddle while walking, a shadow
    if (dm.show) {
      const ds = o.doumState || {};
      // on a seat he stands in front of it whatever his height on screen
      dm.zi = ds.sit && ds.seatZ ? Math.round((ds.seatZ + 50) * 4) + 2 : Math.round((at[1] + 50) * 4) + 1;
      dm.dur = o.walkDur || 0.9;
      const sw = ds.sit ? 0 : 36 * u;
      dm.shw = sw; dm.shh = sw * 0.3; dm.shl = -sw / 2; dm.sht = -dm.shh * 0.55;
      dm.hop = Math.round(9 * u);
    }
    items.forEach((it) => { if (it.zi == null) it.zi = Math.round((it.z + 50) * 4); });
    items.sort((a, b) => a.z - b.z);

    // lanterns glow at night
    const glows = [];
    const LIGHTS = { palm_lanterns: [[0.24, 0.7], [0.38, 0.57], [0.78, 0.54]], lantern_arch: [[0.3, 0.42], [0.5, 0.33], [0.7, 0.48]],
      lamp_posts: [[0.2, 0.12], [0.78, 0.12]], jasmine_pergola: [[0.35, 0.3], [0.65, 0.3]], lighthouse: [[0.5, 0.12]], golden_palm: [[0.3, 0.55], [0.72, 0.55]] };
    if (night) {
      for (const b of lanternsHung) glows.push({ x: (b.x + b.w * 0.5 - 17) * u, y: (b.y + b.h * 0.68 - 17) * u, d: 34 * u });
      for (const b of made) {
        if (!b || !LIGHTS[b.name]) continue;
        for (const [gx, gy] of LIGHTS[b.name]) {
          const d = 30;
          glows.push({ x: (b.x + b.w * gx - d / 2) * u, y: (b.y + b.h * gy - d / 2) * u, d: d * u });
        }
      }
    }

    // a new or chosen thing gets a glow under it and a sparkle above it
    const target = (o.fresh === 'palm' || (o.glowing && !(o.fresh >= 0))) && !glance ? { box: pb, gx: 196, gy: 228 } : (o.fresh >= 0 && boxes[o.fresh]) ? { box: boxes[o.fresh], gx: SPOTS[o.fresh][0], gy: SPOTS[o.fresh][1] } : null;
    const chosen = o.sel >= 0 ? { gx: SPOTS[o.sel][0], gy: SPOTS[o.sel][1] } : null;
    const g = chosen || target;
    const fx = { gx: g ? g.gx : 0, gy: g ? g.gy : 0, go: g ? 0.9 : 0, spark: !!target,
      sx: target ? (target.box.x + target.box.w - 14) * u : 0, sy: target ? (target.box.y - 10) * u : 0, sw: 30 * u };

    const say = o.say ? { show: true, text: o.say, x: (o.sayAt ? o.sayAt[0] : at[0]) * u, y: ((o.sayAt ? o.sayAt[1] : at[1] - __DH__ - 10)) * u, fs: Math.min(16, Math.max(11, 13 * u)) }
      : { show: false, text: '', x: 0, y: 0, fs: 13 };
    const pennant = { show: !!o.pennant && !glance };
    return { S, H, u, v, tr, pl, f, items, glows, fx, tier, dm, bursts, tags, say, pennant, boxes, pbox: pb, extraBoxes,
      alt: 'واحة دوم، المستوى ' + L };
  }
"""


def island_js():
    global ISLAND_JS
    ISLAND_JS = ISLAND_JS.replace('__FRAMES__', FRAMES_JS).replace('__DH__', str(DOUM_H))
    art = '{' + ', '.join(f"{k}: ['{v[0]}', {v[1]}, {v[2]}, {v[3]}]" for k, v in ART.items()) + '}'
    spots = '[' + ', '.join(f'[{x}, {y}, {k}]' for x, y, k in SPOTS) + ']'
    return (ISLAND_JS.replace('__ART__', art).replace('__ITEMW__', ITEM_JS)
            .replace('__SPOTS__', spots).replace('__POSES__', POSES_JS))


AUTO_JS = r"""
  autoSpots(L) {
    // buildings in the back two places, tall things in the back or middle, low things anywhere
    const AUTO = [[2, 4, 'flowers'], [6, 5, 'bench'], [7, 0, 'lemon'], [8, 3, 'well'], [9, 2, 'jasmine'],
      [13, 4, 'rose'], [15, 1, 'house'], [16, 0, 'pomegranate'], [17, 5, 'vegetables'],
      [20, 1, 'coral_house'], [24, 3, 'rose_arch'], [27, 2, 'vine'], [35, 2, 'fountain'], [40, 3, 'palm'],
      [50, 4, 'pearl_chest'], [75, 0, 'majlis']];
    const s = ['', '', '', '', '', ''];
    for (const [lv, i, name] of AUTO) if (L >= lv) s[i] = name;
    return s;
  }
"""

PALETTES = [
    ('doum', 'دوم', '#DDF0F1', '#93CC62', '#86CBE6', '#F1D9A4'),
    ('evening', 'عصر', '#F7E3C8', '#9CC65E', '#7FC0D8', '#F0D29A'),
    ('pink', 'وردي', '#FCE6EE', '#A6D27A', '#9FD3E6', '#F4DDB8'),
    ('violet', 'بنفسجي', '#E6E0F6', '#9BCB78', '#93BFEA', '#EED9B4'),
    ('emerald', 'زمرد', '#DCEFE6', '#6FBF7A', '#6CC0C8', '#EAD3A0'),
    ('ocean', 'بحري', '#D3ECF4', '#8ED39A', '#4FB2DA', '#F2DDAE'),
]
PAL_JS = '{' + ', '.join(f"{p[0]}: {{ name: '{p[1]}', sky: '{p[2]}', grass: '{p[3]}', sea: '{p[4]}', sand: '{p[5]}' }}" for p in PALETTES) + '}'


# The walking engine every board with a moving Doum shares (methods of the component).
# go: turn to the heading, walk at 70 units/s, land. sitOn: walk to the front of a
# seat, hop up, sit. A Doum who is sitting hops down before he walks anywhere.
ENGINE_JS = r"""
  heading(from, to) {
    const dx = to[0] - from[0], dy = to[1] - from[1];
    const deg = Math.atan2(dy * 2.6, dx) * 180 / Math.PI;
    if (deg > 67.5 && deg < 112.5) return { dir: 'front', flip: false };
    if (deg >= 22.5 && deg <= 157.5) return { dir: 'three', flip: dx < 0 };
    if (deg < -67.5 && deg > -112.5) return { dir: 'back', flip: false };
    if (deg <= -22.5 && deg >= -157.5) return { dir: 'back34', flip: dx > 0 };
    return { dir: 'side', flip: dx < 0 };
  }
  go(st, to, extra, then, carry) {
    if (this._w) clearTimeout(this._w);
    if (this._a) clearTimeout(this._a);
    if (this._s) clearTimeout(this._s);
    if (st.sit) {
      // hop down in front of the seat first, then go on
      const front = st.seatFront || [st.walk[0], st.walk[1] + 22];
      this.setState(Object.assign({}, st, extra, { sit: 'down', walk: front, dur: 0.38, n: (st.n || 0) + 1, action: '', say: '' }));
      this._s = setTimeout(() => {
        this.setState({ sit: '', seatZ: 0, seatFront: null, landing: true });
        this.go(Object.assign({}, st, extra, this.state, { sit: '', walk: front }), to, {}, then, carry);
      }, 380);
      return;
    }
    const from = st.walk;
    const dist = Math.hypot(to[0] - from[0], (to[1] - from[1]) * 1.6);
    if (dist < 3) {
      this.setState(Object.assign({}, st, extra, { walking: false, carry: false }));
      if (then) then();
      return;
    }
    const h = this.heading(from, to);
    const dur = Math.max(0.45, Math.min(2.6, dist / (this._speed || 70)));
    this.setState(Object.assign({}, st, extra, { walk: to, dir: h.dir, flip: h.flip, dur, walking: true, landing: false, carry: !!carry, action: '', say: '' }));
    this._w = setTimeout(() => {
      this.setState({ walking: false, carry: false, landing: true, flip: carry ? h.flip : false });
      this._w = setTimeout(() => this.setState({ landing: false }), 340);
      if (then) then();
    }, dur * 1000);
  }
  sitOn(st, seat, extra, say) {
    // seat: [x, y, scale] of the bench's ground point; the seat itself is 15 units up
    const front = [seat[0], seat[1] + 7], top = [seat[0], seat[1] - 15 * seat[2]];
    this.go(st, front, extra, () => {
      // a short beat facing you, then the hop
      this.setState({ dir: 'front', flip: false });
      this._s = setTimeout(() => {
        const n = ((this.state && this.state.n) || 0) + 1;
        this.setState({ landing: false, sit: 'up', seatZ: seat[1], seatFront: front, walk: top, dur: 0.42, n, say: '' });
        this._s = setTimeout(() => this.setState({ sit: 'on', say: say || '' }), 430);
      }, 180);
    });
  }
  doAct(action, say, ms, after, faceX) {
    // faceX: the thing he acts on; the action pictures face right, so he turns to it
    if (this._a) clearTimeout(this._a);
    const p = { action, say, landing: false };
    if (faceX != null) p.flip = faceX < ((this.state && this.state.walk) || [0])[0];
    this.setState(p);
    this._a = setTimeout(() => { this.setState(after || { action: '', say: '' }); }, ms || 3200);
  }
  plantStand(i) {
    // the patted sprout is drawn about 30 units to his side: stand there, facing the place
    return __PLANT_STANDS__[i];
  }
  standAt(i) {
    return (__STANDS__)[i];
  }
  doumState(st) {
    return { walking: st.walking, carry: st.carry, dir: st.dir, flip: st.flip, landing: st.landing, action: st.action,
      parity: (st.n || 0) % 2, sit: st.sit || '', seatZ: st.seatZ || 0 };
  }
  calm() {
    try { return !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches); } catch (e) { return false; }
  }
"""
ENGINE_JS = (ENGINE_JS.replace('__PLANT_STANDS__', json.dumps([list(p) for p in PLANT_STANDS]))
             .replace('__STANDS__', json.dumps({str(k): list(v) for k, v in STANDS.items()})))
