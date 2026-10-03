"""Generates project/Builder.dc.html: build your own oasis, and colour it.

A phone you can play: tap a + on the world, pick what Doum plants there,
tap a planted thing to change it, switch the colours. Item drawings come
from gen_planet so the builder and the planet are the same art.
"""
import math, os, importlib.util

HERE = os.path.dirname(__file__)
spec = importlib.util.spec_from_file_location("gp", os.path.join(HERE, "gen_planet.py"))
gp = importlib.util.module_from_spec(spec); spec.loader.exec_module(gp)

ITEMS = [
    ('palm', 'نخلة', gp.grove_palm, 1.0),
    ('lemon', 'ليمون', gp.lemon, 1.0),
    ('pom', 'رمان', gp.pomegranate, 1.0),
    ('sidr', 'سدرة', gp.sidr, 0.92),
    ('rose', 'ورد', gp.rose, 1.15),
    ('jasmine', 'فل', gp.jasmine, 1.15),
    ('flowers', 'زهور', gp.flowers, 1.2),
    ('well', 'بئر', gp.well, 1.05),
    ('house', 'بيت', gp.house_tower + gp.house + gp.lanterns, 1.05),
    ('hive', 'نحل', gp.hive + gp.bees, 1.15),
    ('bed', 'خضار', gp.bed, 1.15),
]
SLOTS = [-30, 26, -46, 42, -62, 58, -80, 76, -98, 94]
CX, CY, R = 180, 256, 90

def surf(theta, out):
    a = math.radians(theta)
    return CX + (R + out) * math.sin(a), CY - (R + out) * math.cos(a)

slot_svg = ''
for i, th in enumerate(SLOTS):
    for j, (_id, _ar, snip, k) in enumerate(ITEMS):
        slot_svg += (f'<g transform="translate({CX} {CY}) rotate({th}) translate(0 -{R - 1}) scale({k})"'
                     f' style="opacity: {{{{sl.s{i}_{j}}}}}; transition: opacity .45s ease">{snip}</g>')

glow = ''.join(
    f'<circle cx="{surf(th, 26)[0]:.1f}" cy="{surf(th, 26)[1]:.1f}" r="27" fill="#FFF3B0" style="opacity: {{{{gl.g{i}}}}}; transition: opacity .5s ease"></circle>'
    for i, th in enumerate(SLOTS))

sea = ('<g clip-path="url(#builder-clip)">'
       '<circle cx="112" cy="350" r="72" stroke="#1E3A24" stroke-width="2.4" style="fill: {{v.water}}; transition: fill .6s ease"></circle>'
       '<path d="M116 302 q5 -3 10 0 t10 0 M138 322 q5 -3 10 0 t10 0" fill="none" stroke="#FFFFFF" stroke-width="1.6"></path>'
       + ''.join(f'<circle cx="{x}" cy="{y}" r="3.6" fill="#FBF6EC" stroke="#1E3A24" stroke-width="1.4"></circle>' for x, y in [(124, 318), (146, 330), (108, 292)])
       + '</g>')

world_svg = (
    '<svg viewBox="0 0 360 400" width="100%" height="100%" style="position: absolute; left: 0; top: 0;" aria-hidden="true">'
    '<defs><clipPath id="builder-clip"><circle cx="180" cy="256" r="90"></circle></clipPath></defs>'
    '<rect x="0" y="0" width="360" height="400" style="fill: {{v.sky}}; transition: fill .6s ease"></rect>'
    '<g style="opacity: {{v.day}}; transition: opacity .6s ease" stroke="#E2A93B" stroke-width="2.4" stroke-linecap="round">'
    '<path d="M296 46 V50 M296 98 V102 M268 74 H272 M320 74 H324 M276 54 L279 57 M313 91 L316 94 M316 54 L313 57 M279 91 L276 94" fill="none"></path>'
    '<circle cx="296" cy="74" r="15" fill="#F7D774" stroke="#1E3A24" stroke-width="2.2"></circle></g>'
    '<g style="opacity: {{v.night}}; transition: opacity .6s ease" fill="#F6E7A8">'
    + gp.star(70, 70, 4) + gp.star(250, 50, 3.2) + gp.star(320, 160, 3.6) + gp.star(40, 200, 3) + gp.star(140, 40, 3)
    + '<circle cx="300" cy="80" r="14" stroke="#1E3A24" stroke-width="2"></circle><circle cx="306.5" cy="75" r="12.5" style="fill: {{v.sky}}"></circle></g>'
    '<circle cx="180" cy="256" r="90" style="fill: {{v.soil}}; transition: fill .6s ease"></circle>'
    '<g clip-path="url(#builder-clip)"><ellipse cx="180" cy="180" rx="190" ry="150" stroke="#1E3A24" stroke-width="2.4" style="fill: {{v.grass}}; transition: fill .6s ease"></ellipse></g>'
    + sea +
    '<g clip-path="url(#builder-clip)"><path d="M90 256 A90 90 0 1 0 270 256 A90 90 0 1 0 90 256 Z M84 246 A92 92 0 1 1 268 246 A92 92 0 1 1 84 246 Z" fill="#1E3A24" fill-rule="evenodd" style="opacity: .1"></path></g>'
    '<circle cx="180" cy="256" r="90" fill="none" stroke="#1E3A24" stroke-width="3.4"></circle>'
    + glow +
    '<g stroke="#1E3A24" stroke-width="2" stroke-linejoin="round" stroke-linecap="round">'
    f'<g transform="translate({CX} {CY}) rotate(8) translate(0 -{R - 1})"><g transform="scale(0.74)">{gp.hero_palm}</g></g>'
    + slot_svg +
    '</g>'
    '<rect x="0" y="0" width="360" height="400" fill="#14203A" style="opacity: {{v.veil}}; transition: opacity .6s ease"></rect>'
    '</svg>'
)

def preview(snip, k):
    return (f'<svg viewBox="-36 -74 72 78" width="48" height="52" aria-hidden="true">'
            f'<g stroke="#1E3A24" stroke-width="2" stroke-linejoin="round" stroke-linecap="round" transform="scale({min(k, 1.05)})">{snip}</g></svg>')

# item buttons are static markup (the previews are drawings), each with its own handler
item_buttons = ''.join(
    f'<button type="button" onClick="{{{{pick.p{j}}}}}" aria-label="ازرع {ar}" style="font-family: inherit; display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 6px 2px 8px; min-height: 76px; border-radius: 16px; border: 2px solid #E6DFCC; background: #FFFFFF; cursor: pointer;">'
    f'{preview(snip, k)}<span style="font-size: 13px; font-weight: 600; color: #23352A;">{ar}</span></button>'
    for j, (_id, ar, snip, k) in enumerate(ITEMS))

slot_buttons = ''.join(
    f'<sc-if value="{{{{sb.e{i}}}}}" hint-placeholder-val="{{{{true}}}}">'
    f'<button type="button" onClick="{{{{tap.t{i}}}}}" aria-label="مكان فاضي، ازرع هنا" style="position: absolute; left: {surf(th, 18)[0] / 360 * 100:.2f}%; top: {surf(th, 18)[1] / 400 * 100:.2f}%; transform: translate(-50%, -50%); width: 34px; height: 34px; border-radius: 999px; border: 2px dashed #2F7A3A; background: {{{{sb.bg{i}}}}}; color: #2F7A3A; font-family: inherit; font-size: 22px; font-weight: 700; line-height: 1; padding: 0; cursor: pointer; display: flex; align-items: center; justify-content: center;">+</button>'
    f'</sc-if>'
    f'<sc-if value="{{{{sb.f{i}}}}}" hint-placeholder-val="{{{{false}}}}">'
    f'<button type="button" onClick="{{{{tap.t{i}}}}}" aria-label="غيّر اللي مزروع هنا" style="position: absolute; left: {surf(th, 26)[0] / 360 * 100:.2f}%; top: {surf(th, 26)[1] / 400 * 100:.2f}%; transform: translate(-50%, -50%); width: 46px; height: 52px; border-radius: 16px; border: {{{{sb.ring{i}}}}}; background: transparent; padding: 0; cursor: pointer;"></button>'
    f'</sc-if>'
    for i, th in enumerate(SLOTS))

PALETTES = [
    ('doum', 'دوم', '#DDF0F1', '#A3D46F', '#E4BE88', '#5DAE5F', '#4C9A55', '#62B261', '#86CBE6'),
    ('emerald', 'زمرد', '#E3EFE6', '#5FAF73', '#D7B06B', '#2F7D57', '#1F6447', '#3E8E5E', '#7FC0D0'),
    ('pink', 'وردي', '#FCE8EF', '#BFDDA0', '#EDCDB0', '#EE96AC', '#D9708F', '#7DBB72', '#9FD3E6'),
    ('violet', 'بنفسجي', '#E7E1F7', '#B8D08E', '#DCC6A6', '#9C8AD0', '#7A66C2', '#6FAF73', '#9FC3EE'),
    ('desert', 'صحراء', '#F7E6CF', '#D9C77E', '#E8B97E', '#7FA65A', '#5F8C49', '#6DA35F', '#7FC4E2'),
    ('ocean', 'بحري', '#D5EDF3', '#8FD1B4', '#E3C99A', '#3FA58F', '#2C8A78', '#4FAE8E', '#5DB8DA'),
]
pal_js = '{' + ', '.join(f"{p[0]}: {{ name: '{p[1]}', sky: '{p[2]}', grass: '{p[3]}', soil: '{p[4]}', leaf: '{p[5]}', leafDark: '{p[6]}', palm: '{p[7]}', water: '{p[8]}' }}" for p in PALETTES) + '}'
pal_buttons = ''.join(
    f'<button type="button" onClick="{{{{pal.{p[0]}.pick}}}}" aria-label="ألوان {p[1]}" style="font-family: inherit; display: flex; flex-direction: column; align-items: center; gap: 4px; background: transparent; border: 0; padding: 0; cursor: pointer; min-width: 44px;">'
    f'<span style="width: 40px; height: 40px; border-radius: 999px; overflow: hidden; display: flex; flex-direction: column; box-shadow: {{{{pal.{p[0]}.ring}}}};">'
    f'<span style="height: 50%; background: {p[2]};"></span><span style="height: 50%; background: {p[3]}; border-top: 2px solid {p[5]};"></span></span>'
    f'<span style="font-size: 12px; color: #45574B;">{p[1]}</span></button>'
    for p in PALETTES)

N_ITEMS = len(ITEMS)
JS = r"""
class Component extends DCLogic {
  renderVals() {
    const N = 10, NI = __NI__;
    const NAMES = __NAMES__;
    const PAL = __PAL__;
    const st = Object.assign({ slots: [1, 7, 6, -1, -1, -1, -1, -1, -1, -1], sel: -1, pal: 'doum',
      custom: { sky: '#DDF0F1', grass: '#A3D46F', leaf: '#5DAE5F' }, night: false, fresh: -1, plant: false }, this.state || {});
    const set = (patch) => this.setState(Object.assign({}, st, patch));
    const planted = (i, j) => {
      const slots = st.slots.slice(); slots[i] = j;
      if (this._t) clearTimeout(this._t);
      this.setState(Object.assign({}, st, { slots, sel: -1, fresh: j >= 0 ? i : -1, plant: j >= 0 }));
      this._t = setTimeout(() => this.setState({ fresh: -1, plant: false }), 1600);
    };
    const base = st.pal === 'custom'
      ? { sky: st.custom.sky, grass: st.custom.grass, soil: '#E4BE88', leaf: st.custom.leaf, leafDark: st.custom.leaf, palm: st.custom.leaf, water: '#86CBE6' }
      : PAL[st.pal];
    const v = Object.assign({}, base, { sky: st.night ? '#22304A' : base.sky, day: st.night ? 0 : 1, night: st.night ? 1 : 0,
      veil: st.night ? 0.3 : 0, open: 1, bud: 0, dates: '#C9772F' });
    ['#F2C14E', '#D98E3A', '#8B4A2B', '#D98E3A', '#F2C14E'].forEach((c, i) => { v['b' + i] = c; });
    const o = { dates: 1, b0: 1, b1: 1, b2: 1, b3: 1, b4: 1 };
    const sl = {}, gl = {}, sb = {}, tap = {};
    for (let i = 0; i < N; i++) {
      for (let j = 0; j < NI; j++) sl['s' + i + '_' + j] = st.slots[i] === j ? 1 : 0;
      gl['g' + i] = (st.fresh === i || st.sel === i) ? 0.85 : 0;
      sb['e' + i] = st.slots[i] < 0; sb['f' + i] = st.slots[i] >= 0;
      sb['bg' + i] = st.sel === i ? '#FFF3B0' : 'rgba(255,255,255,0.88)';
      sb['ring' + i] = st.sel === i ? '3px solid #2F7A3A' : '0';
      tap['t' + i] = () => set({ sel: st.sel === i ? -1 : i });
    }
    const pick = {};
    for (let j = 0; j < NI; j++) pick['p' + j] = () => { if (st.sel >= 0) planted(st.sel, j); };
    const pal = {};
    Object.keys(PAL).forEach((k) => { pal[k] = { pick: () => set({ pal: k }), ring: st.pal === k ? '0 0 0 3px #23352A' : '0 0 0 1px #D9D1BC' }; });
    const S = 358, k = (64 / 767) * (S / 360);
    const pose = st.plant ? ['239821cb47d27696b528956bd28c88b8', 688, 760, .42] : (st.night ? ['83c02ebb24494b1bec34815440654d97', 850, 679, .5] : ['4fe66825d4a1e1409975aaf4cae25efe', 633, 767, .5]);
    const d = { src: '/_blob/' + pose[0], w: pose[1] * k, h: pose[2] * k, left: 162 * S / 360 - pose[1] * k * pose[3], top: 170 * S / 360 - pose[2] * k };
    const selName = st.sel >= 0 && st.slots[st.sel] >= 0 ? NAMES[st.slots[st.sel]] : '';
    const count = st.slots.filter((x) => x >= 0).length;
    return {
      v, o, sl, gl, sb, tap, pick, pal, d,
      picking: st.sel >= 0, notPicking: st.sel < 0,
      pickTitle: selName ? 'هنا ' + selName + '. تبي شي ثاني؟' : 'وش يزرع دوم هنا؟',
      hasSel: !!selName,
      remove: () => planted(st.sel, -1),
      cancel: () => set({ sel: -1 }),
      line: st.plant ? 'دوم زرعها' : count === N ? 'واحتك كاملة، ما شاء الله' : 'اضغط + وازرع اللي تبيه',
      customOn: st.pal === 'custom' ? '0 0 0 3px #23352A' : '0 0 0 1px #D9D1BC',
      cSky: st.custom.sky, cGrass: st.custom.grass, cLeaf: st.custom.leaf,
      setSky: (e) => set({ pal: 'custom', custom: Object.assign({}, st.custom, { sky: e.target.value }) }),
      setGrass: (e) => set({ pal: 'custom', custom: Object.assign({}, st.custom, { grass: e.target.value }) }),
      setLeaf: (e) => set({ pal: 'custom', custom: Object.assign({}, st.custom, { leaf: e.target.value }) }),
      autoFill: () => {
        const slots = st.slots.map((x, i) => (x >= 0 ? x : (i * 7 + 3) % NI));
        if (this._t) clearTimeout(this._t);
        this.setState(Object.assign({}, st, { slots, sel: -1, plant: true }));
        this._t = setTimeout(() => this.setState({ plant: false }), 1600);
      },
      toggleNight: () => set({ night: !st.night }),
      dayLabel: st.night ? 'نهار' : 'ليل',
      reset: () => set({ slots: Array(N).fill(-1), sel: -1, fresh: -1 })
    };
  }
}
"""
JS = (JS.replace('__NI__', str(N_ITEMS))
        .replace('__NAMES__', '[' + ', '.join(f"'{x[1]}'" for x in ITEMS) + ']')
        .replace('__PAL__', pal_js))

html = f"""<!doctype html>
<html lang="ar">
<head>
<meta charset="utf-8">
<title>Build your oasis</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&amp;display=swap" rel="stylesheet">
<style>
body{{margin:0}}
</style>
</helmet>
<div dir="rtl" style="width: 390px; height: 844px; box-sizing: border-box; background: #F5F0E1; color: #23352A; font-family: 'IBM Plex Sans Arabic', sans-serif; padding: 48px 16px 0; display: flex; flex-direction: column; gap: 10px; overflow: hidden;">

<div style="display: flex; flex-direction: column; gap: 2px;">
<h1 style="margin: 0; font-size: 24px; font-weight: 700;">واحة دوم</h1>
<div style="font-size: 15px; color: #45574B; min-height: 22px;">{{{{line}}}}</div>
</div>

<div style="position: relative; width: 358px; height: 398px; border-radius: 28px; overflow: hidden; flex-shrink: 0;">
{world_svg}
<img src="{{{{d.src}}}}" alt="دوم" style="position: absolute; left: {{{{d.left}}}}px; top: {{{{d.top}}}}px; width: {{{{d.w}}}}px; height: {{{{d.h}}}}px;">
{slot_buttons}
</div>

<sc-if value="{{{{picking}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="background: #FFFFFF; border-radius: 24px; padding: 14px 12px; display: flex; flex-direction: column; gap: 10px;">
<div style="display: flex; align-items: center; justify-content: space-between; gap: 8px;">
<div style="font-size: 17px; font-weight: 700;">{{{{pickTitle}}}}</div>
<button type="button" onClick="{{{{cancel}}}}" style="font-family: inherit; font-size: 15px; font-weight: 600; color: #45574B; background: transparent; border: 0; min-height: 44px; padding: 0 8px; cursor: pointer;">إلغاء</button>
</div>
<div style="display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 8px;">
{item_buttons}
<sc-if value="{{{{hasSel}}}}" hint-placeholder-val="{{{{false}}}}">
<button type="button" onClick="{{{{remove}}}}" style="font-family: inherit; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 4px; min-height: 76px; border-radius: 16px; border: 2px dashed #C9B9A0; background: #FBF8F1; color: #6B5320; font-size: 13px; font-weight: 600; cursor: pointer;">خلّه فاضي</button>
</sc-if>
</div>
</div>
</sc-if>

<sc-if value="{{{{notPicking}}}}" hint-placeholder-val="{{{{true}}}}">
<div style="background: #FFFFFF; border-radius: 24px; padding: 14px 14px 16px; display: flex; flex-direction: column; gap: 12px;">
<div style="font-size: 15px; font-weight: 700;">ألوان الواحة</div>
<div style="display: flex; justify-content: space-between;">{pal_buttons}</div>
<div style="display: flex; align-items: center; gap: 10px;">
<span style="font-size: 14px; font-weight: 700; flex-shrink: 0;">لونك:</span>
<label style="display: flex; flex-direction: column; align-items: center; gap: 2px; font-size: 12px; color: #45574B;"><input type="color" value="{{{{cSky}}}}" onChange="{{{{setSky}}}}" style="width: 44px; height: 32px; border: 0; padding: 0; background: transparent;">السما</label>
<label style="display: flex; flex-direction: column; align-items: center; gap: 2px; font-size: 12px; color: #45574B;"><input type="color" value="{{{{cGrass}}}}" onChange="{{{{setGrass}}}}" style="width: 44px; height: 32px; border: 0; padding: 0; background: transparent;">العشب</label>
<label style="display: flex; flex-direction: column; align-items: center; gap: 2px; font-size: 12px; color: #45574B;"><input type="color" value="{{{{cLeaf}}}}" onChange="{{{{setLeaf}}}}" style="width: 44px; height: 32px; border: 0; padding: 0; background: transparent;">الشجر</label>
</div>
<div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px;">
<button type="button" onClick="{{{{autoFill}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #FFFFFF; background: #2F7A3A; border: 0; border-radius: 14px; min-height: 48px; cursor: pointer;">ازرع لي</button>
<button type="button" onClick="{{{{toggleNight}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #23352A; background: #F3EEDF; border: 0; border-radius: 14px; min-height: 48px; cursor: pointer;">{{{{dayLabel}}}}</button>
<button type="button" onClick="{{{{reset}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #23352A; background: transparent; border: 2px dashed #C9B9A0; border-radius: 14px; min-height: 48px; cursor: pointer;">من جديد</button>
</div>
</div>
</sc-if>

</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":390,"height":844}}}}'>
{JS}
</script>
</body>
</html>
"""
with open(os.path.join(HERE, 'project', 'Builder.dc.html'), 'w') as fh:
    fh.write(html)
print(len(html))
