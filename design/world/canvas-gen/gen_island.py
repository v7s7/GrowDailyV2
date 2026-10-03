"""Generates project/Island.dc.html: Doum's oasis drawn with the real art.

Props match Planet where they can, so a board can swap name="Planet" for
name="Island". spots is a comma list of six things (back left, back right,
left, right, front left, front right); empty means the level decides.
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic

PROPS = {
    'level': {'editor': 'range', 'min': 1, 'max': 100, 'step': 1, 'default': 24, 'section': 'Growth'},
    'medals': {'editor': 'range', 'min': 0, 'max': 20, 'step': 1, 'default': 6, 'section': 'Growth'},
    'pearls': {'editor': 'range', 'min': 0, 'max': 6, 'step': 1, 'default': 2, 'section': 'Growth'},
    'spots': {'editor': 'text', 'default': '', 'section': 'Growth'},
    'thirst': {'editor': 'range', 'min': 0, 'max': 3, 'step': 1, 'default': 0, 'section': 'Today'},
    'quietStyle': {'editor': 'enum', 'options': ['thirsty', 'quiet'], 'default': 'thirsty', 'section': 'Today'},
    'sky': {'editor': 'enum', 'options': ['day', 'night', 'rest'], 'default': 'day', 'section': 'Today'},
    'watering': {'editor': 'boolean', 'default': False, 'section': 'Today'},
    'glowing': {'editor': 'boolean', 'default': False, 'section': 'Today'},
    'season': {'editor': 'enum', 'options': ['none', 'ramadan'], 'default': 'none', 'section': 'Today'},
    'gifts': {'editor': 'text', 'default': '', 'section': 'Friends'},
    'guest': {'editor': 'boolean', 'default': False, 'section': 'Friends'},
    'guestName': {'editor': 'text', 'default': '', 'section': 'Friends'},
    'pennant': {'editor': 'boolean', 'default': False, 'section': 'Friends'},
    'fresh': {'editor': 'enum', 'options': ['none', 'palm', '0', '1', '2', '3', '4', '5'], 'default': 'none', 'section': 'Today'},
    'pose': {'editor': 'enum', 'options': ['auto', 'wave', 'water', 'plant', 'sleep', 'sparkles', 'none'], 'default': 'auto', 'section': 'Today'},
    'palette': {'editor': 'enum', 'options': [p[0] for p in ic.PALETTES], 'default': 'doum', 'section': 'Frame'},
    'frame': {'editor': 'enum', 'options': ['rect', 'bubble', 'none'], 'default': 'rect', 'section': 'Frame'},
    'detail': {'editor': 'enum', 'options': ['full', 'glance'], 'default': 'full', 'section': 'Frame'},
    'size': {'editor': 'range', 'min': 60, 'max': 720, 'step': 2, 'default': 360, 'section': 'Frame'},
}

JS = r"""
class Component extends DCLogic {
__ISLAND__
__AUTO__
  renderVals() {
    const P = this.props;
    const num = (v, d) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
    const yes = (v) => v === true || v === 'true';
    const PAL = __PAL__;
    const L = Math.max(1, Math.min(100, Math.round(num(P.level, 24))));
    const given = String(P.spots ?? '').split(',').map((x) => x.trim());
    const spots = given.length === 6 ? given : this.autoSpots(L);
    const fr = String(P.fresh ?? 'none');
    const w = this.island({
      level: L, medals: num(P.medals, 6), pearls: num(P.pearls, 2), thirst: num(P.thirst, 0),
      quietStyle: P.quietStyle ?? 'thirsty', sky: P.sky ?? 'day', watering: yes(P.watering), glowing: yes(P.glowing), season: P.season ?? 'none',
      fresh: fr === 'palm' ? 'palm' : fr === 'none' ? -1 : num(fr, -1), sel: -1, pose: P.pose ?? 'auto',
      colors: PAL[P.palette] || PAL.doum, frame: P.frame ?? 'rect', detail: P.detail ?? 'full',
      size: num(P.size, 360), spots,
      gifts: String(P.gifts ?? '').split(',').filter((x) => x.includes(':')).map((x) => { const [name, from] = x.split(':'); return { name: name.trim(), from: from.trim() }; }),
      guest: yes(P.guest), guestName: P.guestName ?? '', pennant: yes(P.pennant)
    });
    return { w };
  }
}
"""


def build():
    js = (JS.replace('__ISLAND__', ic.island_js()).replace('__AUTO__', ic.AUTO_JS).replace('__PAL__', ic.PAL_JS))
    props = dict(PROPS)
    props['$preview'] = {'width': 360, 'height': 400}
    html = f"""<!doctype html>
<html lang="ar">
<head>
<meta charset="utf-8">
<title>Doum's island</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@500;700&amp;display=swap" rel="stylesheet">
<style>
body{{margin:0}}
{ic.STYLE}
</style>
</helmet>
<div role="img" aria-label="{{{{w.alt}}}}" style="position: relative; width: {{{{w.S}}}}px; height: {{{{w.H}}}}px; overflow: hidden;">
{ic.scene('w.')}
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{json.dumps(props, ensure_ascii=False)}'>
{js}
</script>
</body>
</html>
"""
    with open(os.path.join(HERE, 'project', 'Island.dc.html'), 'w') as fh:
        fh.write(html)
    return html


if __name__ == '__main__':
    print(len(build()))
