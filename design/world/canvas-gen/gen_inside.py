"""Generates project/Inside.dc.html: the room inside Doum's coral house, furnished from Sheet 7."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic
from gen_together import HEAD, TAIL, PHONE, BACK, write
A = ic.ART

AR = {'mandoos': 'مندوس', 'dallah_set': 'دلّة', 'mabkhara': 'مبخرة', 'cushions': 'مساند', 'low_table': 'طاولة',
      'carved_door': 'باب', 'lattice_window': 'شبّاك', 'shelf': 'رف', 'hanging_lantern': 'فانوس', 'potted_palm': 'نخلة صغيرة',
      'pattern_frame': 'لوحة', 'frond_mat': 'سجادة خوص', 'pearl_chest': 'صندوق لؤلؤ', 'harvest_basket': 'سلة', 'telescope': 'منظار'}

# id, kind, x, y, width, anchor (bottom: y is where it stands; top: y is where it hangs from; center)
SLOTS = [
    ('rug', 'rug', 190, 482, 244, 'bottom'),
    ('door', 'wallfloor', 50, 332, 74, 'bottom'),
    ('frame', 'wall', 236, 160, 60, 'center'),
    ('win', 'wall', 330, 190, 78, 'center'),
    ('hangL', 'hang', 150, 61, 28, 'top'),
    ('hangR', 'hang', 290, 61, 28, 'top'),
    ('incense', 'back', 118, 352, 40, 'bottom'),
    ('seat', 'back', 216, 352, 168, 'bottom'),
    ('chest', 'back', 340, 354, 84, 'bottom'),
    ('plant', 'front', 54, 476, 84, 'bottom'),
    ('table', 'table', 304, 468, 116, 'bottom'),
    ('top', 'top', 304, 426, 72, 'bottom'),
]
OPTS = {
    'rug': ['frond_mat'],
    'wallfloor': ['carved_door', 'shelf'],
    'wall': ['pattern_frame', 'lattice_window'],
    'hang': ['hanging_lantern'],
    'back': ['cushions', 'mandoos', 'mabkhara', 'shelf', 'potted_palm', 'pearl_chest'],
    'front': ['potted_palm', 'mabkhara', 'harvest_basket', 'telescope', 'mandoos'],
    'table': ['low_table'],
    'top': ['dallah_set', 'harvest_basket', 'mabkhara'],
}
START = {'rug': 'frond_mat', 'door': 'carved_door', 'frame': 'pattern_frame', 'win': 'lattice_window', 'hangL': 'hanging_lantern',
         'hangR': 'hanging_lantern', 'incense': 'mabkhara', 'seat': 'cushions', 'chest': 'mandoos', 'plant': 'potted_palm',
         'table': 'low_table', 'top': 'dallah_set'}
all_names = sorted({n for v in OPTS.values() for n in v})
art_js = json.dumps({k: A[k] for k in all_names})
WALKS = [f'walk_{d}_{i}' for d in ('side', 'front', 'back', 'three', 'back34') for i in range(1, 5)]
FR = {k: ['/_blob/' + ic.FRAME_IDS[k], ic.FRAME_META[k]['w'], ic.FRAME_META[k]['h'], ic.FRAME_META[k]['ax'], ic.FRAME_META[k]['ay'],
          ic.FRAME_META[k]['dh'], ic.FRAME_META[k]['k']]
      for k in ['idle_calm', 'idle_blink', 'idle_look_l', 'idle_look_r', 'sit_front'] + WALKS}
# the room's cushions: seat surface 30 px over their base, 86 px between the bolsters (seated Doum is 67)
SEAT = [216, 352, 30.5 / 15]
HOME = [186, 466]

beams = ''.join(f'<line x1="0" y1="{y}" x2="390" y2="{y}" stroke="#8B5E3C" stroke-width="3" stroke-linecap="round"></line>' for y in range(8, 52, 7))
naqsh = ''.join(f'<path d="M{x} 100 l7 -7 l7 7 l-7 7 Z" fill="#3F86A8"></path><circle cx="{x + 21}" cy="100" r="2.6" fill="#E9B949"></circle>' for x in range(4, 390, 28))
room_svg = (
    '<svg viewBox="0 0 390 480" width="390" height="480" style="position: absolute; left: 0; top: 0;" aria-hidden="true">'
    '<rect x="0" y="0" width="390" height="332" fill="#F3E7D3"></rect>'
    f'<rect x="0" y="0" width="390" height="54" fill="#C9A27A"></rect>{beams}'
    '<rect x="0" y="52" width="390" height="9" fill="#6B4426"></rect>'
    f'{naqsh}'
    # one arched window in the wall; its sky follows day and night
    '<path d="M112 250 V182 a32 32 0 0 1 64 0 V250 Z" stroke="#6B4426" stroke-width="6" style="fill: {{win}}; transition: fill .6s ease"></path>'
    '<g style="opacity: {{stars}}; transition: opacity .6s ease" fill="#F6E7A8"><circle cx="130" cy="180" r="2"></circle><circle cx="158" cy="196" r="1.6"></circle><circle cx="140" cy="222" r="1.8"></circle></g>'
    '<path d="M144 150 V250 M112 206 H176" stroke="#6B4426" stroke-width="3"></path>'
    '<path d="M0 332 H390 V480 H0 Z" fill="#D9B58A"></path>'
    '<path d="M0 332 H390" stroke="#B48A5E" stroke-width="4"></path>'
    '</svg>')

slot_btns = ''
for i, (sid, kind, x, y, w, anc) in enumerate(SLOTS):
    if anc == 'bottom':
        cy = y - 30 if kind not in ('rug',) else y - 30
    elif anc == 'top':
        cy = y + 40
    else:
        cy = y
    slot_btns += (f'<button type="button" onClick="{{{{sl.t{i}}}}}" aria-label="مكان" style="position: absolute; z-index: 3002; left: {x}px; top: {cy}px; transform: translate(-50%, -50%); '
                  f'width: {{{{sl.w{i}}}}}px; height: {{{{sl.h{i}}}}}px; border-radius: 999px; border: {{{{sl.b{i}}}}}; background: {{{{sl.bg{i}}}}}; color: #2F7A3A; font-family: inherit; font-size: 20px; font-weight: 700; padding: 0; cursor: pointer;">{{{{sl.p{i}}}}}</button>')

pick_btns = ''.join(
    f'<sc-if value="{{{{pk.show_{n}}}}}" hint-placeholder-val="{{{{false}}}}"><button type="button" onClick="{{{{pk.{n}}}}}" aria-label="{AR[n]}" style="font-family: inherit; flex-shrink: 0; width: 66px; display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 6px 2px; border-radius: 14px; border: 2px solid #E6DFCC; background: #FFFFFF; cursor: pointer;">'
    f'<img src="{A[n][0]}" alt="" style="width: 42px; height: 38px; object-fit: contain;"><span style="font-size: 11px; font-weight: 600; color: #23352A; white-space: nowrap;">{AR[n]}</span></button></sc-if>'
    for n in all_names)

JS = r"""
class Component extends DCLogic {
__ENGINE__
  renderVals() {
    const SLOTS = __SLOTS__;
    const ART = __ART__;
    const OPTS = __OPTS__;
    this._speed = 119;   // 70 island units a second, in room pixels (Doum is 112 here, 66 on the island)
    const base = { fill: __START__, sel: -1, night: false, walk: __HOME__, dir: 'front', flip: false, walking: false, landing: false,
      action: '', say: '', n: 0, dur: 0.9, sit: '', seatZ: 0, seatFront: null };
    const st = Object.assign({}, base, this.state || {});
    const set = (p) => this.setState(Object.assign({}, st, p));
    const items = [], glows = [];
    SLOTS.forEach((s, i) => {
      const n = st.fill[s[0]]; if (!n || !ART[n]) return;
      // the coffee set only sits on a table
      if (s[0] === 'top' && st.fill.table !== 'low_table') return;
      const a = ART[n], w = s[4], h = w * a[2] / a[1];
      const y = s[5] === 'bottom' ? s[3] - h : s[5] === 'top' ? s[3] : s[3] - h / 2;
      const z = s[1] === 'rug' ? -2 : s[1] === 'wall' || s[1] === 'wallfloor' ? -1 : s[1] === 'hang' ? 0 : s[0] === 'top' ? s[3] + 50 : s[3];
      items.push({ src: a[0], x: s[2] - w / 2, y, w, h, z, cls: '', zi: Math.round((z + 50) * 4) });
      if (st.night && n === 'hanging_lantern') glows.push({ x: s[2] - 34, y: y + h * 0.72 - 34, d: 68 });
    });
    // Doum, with the island's engine: walks, a beat, hops onto the room's own cushions, sits, hops down
    const FR = __FR__;
    const DH = 112;
    const DIRH = { side: 0.98, front: 1, back: 0.97, three: 0.98, back34: 0.98 };
    const img = (n, cls, sc) => { const f = FR[n]; return { src: f[0], cls, x: -f[3] * sc, y: -f[4] * sc, w: f[1] * sc, h: f[2] * sc }; };
    const sprite = (ds) => {
      if (ds.sit) {
        const ss = DH / (302 * FR.sit_front[6]), si = DH / FR.idle_calm[5], par = ds.parity ? 'b' : '';
        if (ds.sit === 'on') return { imgs: [img('sit_front', '', ss)], inner: 'isl-sit' };
        const up = ds.sit === 'up';
        return { imgs: [img('idle_calm', (up ? 'isl-swo' : 'isl-swi') + par, si), img('sit_front', (up ? 'isl-swi' : 'isl-swo') + par, ss)], inner: (up ? 'isl-hopup' : 'isl-hopdn') + par };
      }
      if (ds.walking) {
        const d = DIRH[ds.dir] ? ds.dir : 'front', sc = (DH * DIRH[d]) / FR['walk_' + d + '_1'][5];
        return { imgs: [1, 2, 3, 4].map((k, i) => img('walk_' + d + '_' + k, 'isl-fr isl-fr' + i, sc)), inner: 'isl-sway-s' };
      }
      const sc = DH / FR.idle_calm[5];
      return { imgs: [img('idle_calm', '', sc), img('idle_blink', 'isl-blink', sc), img('idle_look_l', 'isl-lookl', sc), img('idle_look_r', 'isl-lookr', sc)],
        inner: ds.landing ? 'isl-land' : 'isl-breathe' };
    };
    const ds = this.doumState(st);
    const sw = ds.sit ? 0 : 60;
    const dm = Object.assign({ x: st.walk[0], y: st.walk[1], dur: st.dur || 0.9, sc: st.flip ? '-1 1' : '1 1', hop: 15,
      zi: ds.sit && ds.seatZ ? Math.round((ds.seatZ + 50) * 4) + 2 : Math.round((st.walk[1] + 50) * 4) + 1,
      shw: sw, shh: sw * 0.3, shl: -sw / 2, sht: -sw * 0.3 * 0.55 }, sprite(ds));
    const SEAT = __SEAT__, HOME = __HOME__;
    const sitting = !!st.sit;
    const sit = () => {
      if (sitting) this.go(st, HOME, { sel: -1 });
      else if (st.fill.seat === 'cushions') this.sitOn(st, SEAT, { sel: -1 });
    };
    items.sort((a, b) => a.z - b.z);
    const sl = {};
    SLOTS.forEach((s, i) => {
      const full = !!st.fill[s[0]];
      const on = st.sel === i;
      sl['t' + i] = () => set({ sel: on ? -1 : i });
      sl['w' + i] = full ? Math.min(90, Math.max(48, s[4] * 0.8)) : 38;
      sl['h' + i] = full ? Math.min(90, Math.max(48, s[4] * 0.8)) : 38;
      sl['b' + i] = on ? '3px solid #2F7A3A' : full ? '0' : '2.5px dashed #2F7A3A';
      sl['bg' + i] = on && full ? 'rgba(255,243,176,0.35)' : full ? 'transparent' : 'rgba(255,255,255,0.85)';
      sl['p' + i] = full ? '' : '+';
    });
    const pk = {};
    const kind = st.sel >= 0 ? SLOTS[st.sel][1] : '';
    Object.keys(ART).forEach((n) => {
      pk['show_' + n] = st.sel >= 0 && OPTS[kind].includes(n);
      pk[n] = () => {
        const fill = Object.assign({}, st.fill); fill[SLOTS[st.sel][0]] = n;
        // swapping the cushions away while he sits: he stands where he was
        const off = SLOTS[st.sel][0] === 'seat' && sitting && n !== 'cushions' ? { sit: '', seatZ: 0, walk: st.seatFront || HOME } : {};
        set(Object.assign({ fill, sel: -1 }, off));
      };
    });
    return { items, glows, sl, pk, dm, picking: st.sel >= 0, notPicking: st.sel < 0,
      sitLabel: sitting ? 'قوم' : 'اجلس', sit, canSit: st.fill.seat === 'cushions',
      clear: () => {
        const fill = Object.assign({}, st.fill); fill[SLOTS[st.sel][0]] = '';
        const off = SLOTS[st.sel][0] === 'seat' && sitting ? { sit: '', seatZ: 0, walk: st.seatFront || HOME } : {};
        set(Object.assign({ fill, sel: -1 }, off));
      },
      cancel: () => set({ sel: -1 }),
      win: st.night ? '#22304A' : '#CFEAF2', stars: st.night ? 1 : 0, shade: st.night ? 0.24 : 0,
      toggle: () => set({ night: !st.night }), dayLabel: st.night ? 'نهار' : 'ليل' };
  }
}
"""
js = (JS.replace('__ENGINE__', ic.ENGINE_JS).replace('__SEAT__', json.dumps(SEAT)).replace('__HOME__', json.dumps(HOME)).replace('__SLOTS__', json.dumps(SLOTS)).replace('__ART__', art_js).replace('__OPTS__', json.dumps(OPTS))
      .replace('__START__', json.dumps(START)).replace('__FR__', json.dumps(FR)))

html = HEAD.format(title='Inside the house', style=ic.STYLE) + f"""<div dir="rtl" style="{PHONE}">
<div dir="ltr" style="position: absolute; left: 0; top: 0; width: 390px; height: 480px; overflow: hidden; isolation: isolate;">
{room_svg}
<sc-for list="{{{{items}}}}" as="it" hint-placeholder-count="12"><img src="{{{{it.src}}}}" alt="" class="{{{{it.cls}}}}" style="position: absolute; left: {{{{it.x}}}}px; top: {{{{it.y}}}}px; width: {{{{it.w}}}}px; height: {{{{it.h}}}}px; z-index: {{{{it.zi}}}}; pointer-events: none;"></sc-for>
<div style="position: absolute; left: {{{{dm.x}}}}px; top: {{{{dm.y}}}}px; width: 0; height: 0; z-index: {{{{dm.zi}}}}; pointer-events: none; transition: left {{{{dm.dur}}}}s cubic-bezier(.4,.1,.4,1), top {{{{dm.dur}}}}s cubic-bezier(.4,.1,.4,1);">
<div style="position: absolute; left: {{{{dm.shl}}}}px; top: {{{{dm.sht}}}}px; width: {{{{dm.shw}}}}px; height: {{{{dm.shh}}}}px; border-radius: 50%; background: radial-gradient(closest-side, rgba(60,40,20,0.30), rgba(60,40,20,0));"></div>
<div class="{{{{dm.inner}}}}" style="position: absolute; left: 0; top: 0; width: 0; height: 0; scale: {{{{dm.sc}}}}; transform-origin: 0 0; --hop: {{{{dm.hop}}}}px;">
<sc-for list="{{{{dm.imgs}}}}" as="im" hint-placeholder-count="4"><img src="{{{{im.src}}}}" alt="" class="{{{{im.cls}}}}" style="position: absolute; left: {{{{im.x}}}}px; top: {{{{im.y}}}}px; width: {{{{im.w}}}}px; height: {{{{im.h}}}}px; max-width: none;"></sc-for>
</div></div>
<div style="position: absolute; inset: 0; z-index: 3000; background: #14203A; opacity: {{{{shade}}}}; pointer-events: none; transition: opacity .6s ease;"></div>
<sc-for list="{{{{glows}}}}" as="g" hint-placeholder-count="0"><div style="position: absolute; z-index: 3001; left: {{{{g.x}}}}px; top: {{{{g.y}}}}px; width: {{{{g.d}}}}px; height: {{{{g.d}}}}px; border-radius: 999px; background: radial-gradient(circle, rgba(255,214,110,0.8) 0%, rgba(255,214,110,0.3) 40%, rgba(255,214,110,0) 70%); pointer-events: none;"></div></sc-for>
{slot_btns}
</div>
<div style="position: absolute; top: 48px; left: 8px; right: 8px; display: flex; align-items: center; justify-content: space-between;">
<a href="Walk.dc.html" aria-label="اطلع" style="width: 44px; height: 44px; border-radius: 999px; background: rgba(255,255,255,0.9); display: flex; align-items: center; justify-content: center;">{BACK}</a>
<div style="font-size: 17px; font-weight: 700; background: rgba(255,255,255,0.9); padding: 8px 16px; border-radius: 999px;">داخل بيت المرجان</div>
<div style="width: 44px;"></div>
</div>
<div style="position: absolute; left: 0; right: 0; top: 470px; bottom: 0; background: #F5F0E1; border-radius: 22px 22px 0 0; padding: 14px 16px 0; display: flex; flex-direction: column; gap: 10px;">
<sc-if value="{{{{notPicking}}}}" hint-placeholder-val="{{{{true}}}}">
<div style="display: flex; flex-direction: column; gap: 2px;">
<div style="font-size: 18px; font-weight: 700;">مجلس دوم</div>
<div style="font-size: 14px; color: #45574B; line-height: 1.5;">اضغط أي شي تغيّره، أو + تحط شي جديد. الضيوف يدخلون ويشوفونه بس.</div>
</div>
<div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px;">
<button type="button" onClick="{{{{sit}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #6B4E00; background: #FFF3C4; border: 0; border-radius: 14px; min-height: 46px; cursor: pointer;">{{{{sitLabel}}}}</button>
<button type="button" onClick="{{{{toggle}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #23352A; background: #F3EEDF; border: 0; border-radius: 14px; min-height: 46px; cursor: pointer;">{{{{dayLabel}}}}</button>
<a href="Edit.dc.html" style="font-size: 15px; font-weight: 700; color: #FFFFFF; background: #2F7A3A; border-radius: 14px; min-height: 46px; display: flex; align-items: center; justify-content: center; text-decoration: none;">عدّل برّا</a>
</div>
</sc-if>
<sc-if value="{{{{picking}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="display: flex; align-items: center; justify-content: space-between;">
<div style="font-size: 16px; font-weight: 700;">وش تحط هنا؟</div>
<button type="button" onClick="{{{{cancel}}}}" style="font-family: inherit; font-size: 14px; font-weight: 600; color: #45574B; background: transparent; border: 0; min-height: 40px; cursor: pointer;">إلغاء</button>
</div>
<div style="display: flex; gap: 6px; flex-wrap: wrap;">{pick_btns}
<button type="button" onClick="{{{{clear}}}}" style="font-family: inherit; flex-shrink: 0; width: 66px; min-height: 68px; border-radius: 14px; border: 2px dashed #C9B9A0; background: #FBF8F1; color: #6B5320; font-size: 12px; font-weight: 700; cursor: pointer;">فاضي</button></div>
</sc-if>
</div>
</div>
""" + TAIL.format(js=js)
write('Inside.dc.html', html)
