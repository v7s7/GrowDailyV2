"""Generates the deeper phones: Walk (a visit you walk through), Edit (level 100), Inside (Doum's room)."""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic
from gen_together import HEAD, TAIL, PHONE, BACK, HEART, write
A = ic.ART
W = dict((it[0], it[2]) for it in ic.ITEMS)
NAMES = dict((it[0], it[1]) for it in ic.ITEMS)
COLORS = "{ sky: '#DDF0F1', grass: '#93CC62', sea: '#86CBE6', sand: '#F1D9A4' }"

# ---------------------------------------------------------------- Edit: level 100, free placement
ES = 390
EU = ES / 360
CELLS = [(104, 220, .74), (146, 220, .74), (252, 220, .74), (292, 220, .74),
         (78, 244, .82), (124, 244, .82), (170, 246, .82), (236, 246, .82), (284, 244, .82),
         (90, 270, .9), (140, 272, .9), (190, 274, .9), (240, 272, .9), (284, 268, .9)]
D1 = ['lantern_arch', 'rose', 'jasmine_pergola', 'lamp_posts', 'lemon', 'fountain', '', 'coral_house', 'well', 'lily_pool', 'majlis', '', 'pearl_chest', 'vegetables']
D2 = ['lamp_posts', 'flowers', 'sidr', 'lamp_posts', 'palm', 'majlis', '', 'frond_hut', 'jasmine', 'flowers', 'bench', '', 'lily_pool', 'lantern_arch']
cell_btns = ''.join(
    f'<button type="button" onClick="{{{{cb.t{i}}}}}" aria-label="مكان {i + 1}" style="position: absolute; left: {x * EU:.0f}px; top: {(y - (26 if True else 0)) * EU:.0f}px; transform: translate(-50%, -50%); width: {{{{cb.w{i}}}}}px; height: {{{{cb.h{i}}}}}px; border-radius: 999px; border: {{{{cb.b{i}}}}}; background: {{{{cb.bg{i}}}}}; color: #2F7A3A; font-family: inherit; font-size: 20px; font-weight: 700; padding: 0; cursor: pointer; display: flex; align-items: center; justify-content: center;">{{{{cb.p{i}}}}}</button>'
    for i, (x, y, k) in enumerate(CELLS))
tray = ''.join(
    f'<button type="button" onClick="{{{{hold.{n}}}}}" aria-label="{ar}" style="font-family: inherit; flex-shrink: 0; width: 64px; display: flex; flex-direction: column; align-items: center; gap: 1px; padding: 6px 2px; border-radius: 14px; border: {{{{hr.{n}}}}}; background: #FFFFFF; cursor: pointer;">'
    f'<img src="{A[n][0]}" alt="" style="width: 42px; height: 36px; object-fit: contain;"><span style="font-size: 11px; font-weight: 600; color: #23352A; white-space: nowrap;">{ar}</span></button>'
    for n, ar, *_ in ic.ITEMS)
EDIT_JS = r"""
class Component extends DCLogic {
__ISLAND__
  renderVals() {
    const CELLS = __CELLS__;
    const W = __W__;
    const NAMES = __NAMES__;
    const blank = () => CELLS.map(() => ({ name: '', flip: false, gold: false }));
    const fromList = (l) => l.map((n, i) => ({ name: n, flip: false, gold: n === 'fountain' && i === 5 }));
    const st = Object.assign({ d: 0, designs: [fromList(__D1__), fromList(__D2__), blank()], hold: '', moveFrom: -1, sel: -1, gold: 18400, note: '' }, this.state || {});
    const set = (p) => this.setState(Object.assign({}, st, p));
    const cur = st.designs[st.d];
    const put = (cells) => { const designs = st.designs.slice(); designs[st.d] = cells; return designs; };
    const cb = {};
    const placing = !!st.hold || st.moveFrom >= 0;
    CELLS.forEach((c, i) => {
      const full = !!cur[i].name;
      cb['t' + i] = () => {
        const cells = cur.map((x) => Object.assign({}, x));
        if (st.hold) { cells[i] = { name: st.hold, flip: false, gold: false }; set({ designs: put(cells), hold: '', sel: i, note: NAMES[st.hold] + ' في مكانها' }); return; }
        if (st.moveFrom >= 0) { const a = cells[st.moveFrom]; cells[st.moveFrom] = cells[i]; cells[i] = a; set({ designs: put(cells), moveFrom: -1, sel: i, note: 'انتقلت' }); return; }
        if (full) { set({ sel: st.sel === i ? -1 : i, note: '' }); return; }
        set({ sel: -1, note: 'اختار شي من تحت، بعدين اضغط هنا' });
      };
      const small = !full || placing;
      cb['w' + i] = full && !placing ? 58 : 34;
      cb['h' + i] = full && !placing ? 66 : 34;
      cb['b' + i] = st.sel === i ? '3px solid #FFFFFF' : full && !placing ? '0' : placing ? '2.5px dashed #2F7A3A' : '2px dashed rgba(47,122,58,0.45)';
      cb['bg' + i] = full && !placing ? 'transparent' : placing ? 'rgba(255,255,255,0.92)' : 'rgba(255,255,255,0.55)';
      cb['p' + i] = full && !placing ? '' : '+';
    });
    const hold = {}, hr = {};
    Object.keys(NAMES).forEach((n) => {
      hold[n] = () => set({ hold: st.hold === n ? '' : n, moveFrom: -1, sel: -1, note: st.hold === n ? '' : 'اضغط مكان على الواحة' });
      hr[n] = st.hold === n ? '3px solid #2F7A3A' : '2px solid #E6DFCC';
    });
    const sel = st.sel >= 0 ? cur[st.sel] : null;
    const edit = (patch, note, cost) => () => {
      const cells = cur.map((x) => Object.assign({}, x));
      Object.assign(cells[st.sel], patch);
      set({ designs: put(cells), note, gold: st.gold - (cost || 0) });
    };
    const extra = [];
    cur.forEach((c, i) => { if (c.name && W[c.name]) extra.push({ name: c.name, x: CELLS[i][0], y: CELLS[i][1], w: W[c.name] * CELLS[i][2], flip: c.flip, gold: c.gold }); });
    const w = this.island({ level: 100, medals: 20, pearls: 4, thirst: 0, quietStyle: 'quiet', sky: 'day', watering: false, fresh: -1, sel: -1,
      pose: 'none', colors: __COLORS__, frame: 'rect', detail: 'full', size: 390, spots: ['', '', '', '', '', ''], extra, noPath: true });
    const tabs = {};
    [0, 1, 2].forEach((k) => { tabs['t' + k] = () => set({ d: k, sel: -1, hold: '', moveFrom: -1, note: '' }); tabs['bg' + k] = st.d === k ? '#2F7A3A' : '#FFFFFF'; tabs['fg' + k] = st.d === k ? '#FFFFFF' : '#23352A'; });
    const count = cur.filter((c) => c.name).length;
    return {
      w, cb, hold, hr, tabs,
      hasSel: !!sel, noSel: !sel,
      selName: sel ? NAMES[sel.name] || '' : '',
      move: () => set({ moveFrom: st.sel, note: 'اضغط المكان الجديد' }),
      flip: sel ? edit({ flip: !sel.flip }, 'انقلبت') : () => {},
      gild: sel && !sel.gold ? edit({ gold: true }, 'صارت ذهب', 2000) : () => {},
      gildLabel: sel && sel.gold ? 'مذهّبة' : 'ذهّبها · 2000',
      remove: sel ? () => { const cells = cur.map((x) => Object.assign({}, x)); cells[st.sel] = { name: '', flip: false, gold: false }; set({ designs: put(cells), sel: -1, note: 'رجعت لمجموعتك' }); } : () => {},
      note: st.note || (count + ' من 14 مكان'),
      gold: st.gold.toLocaleString('en-US')
    };
  }
}
"""
edit_js = (EDIT_JS.replace('__ISLAND__', ic.island_js()).replace('__CELLS__', json.dumps([[x, y, k] for x, y, k in CELLS]))
           .replace('__W__', json.dumps(W)).replace('__NAMES__', json.dumps(NAMES, ensure_ascii=False))
           .replace('__D1__', json.dumps(D1)).replace('__D2__', json.dumps(D2)).replace('__COLORS__', COLORS))
EH = round(ES * 400 / 360)
edit = HEAD.format(title='Edit at level 100', style=ic.STYLE) + f"""<div dir="rtl" style="{PHONE} display: flex; flex-direction: column;">
<div style="padding: 44px 16px 8px; display: flex; align-items: flex-end; justify-content: space-between;">
<div style="display: flex; flex-direction: column;">
<h1 style="margin: 0; font-size: 22px; font-weight: 700;">تعديل الواحة</h1>
<div style="font-size: 13px; color: #45574B;">المستوى 100 · 14 مكان · ذهبك {{{{gold}}}}</div>
</div>
<a href="Play.dc.html" style="font-size: 15px; font-weight: 700; color: #FFFFFF; background: #2F7A3A; border-radius: 12px; padding: 8px 16px; text-decoration: none;">تم</a>
</div>
<div style="padding: 0 16px 8px; display: flex; align-items: center; gap: 8px;">
<span style="font-size: 13px; font-weight: 700; color: #45574B;">تصاميمك:</span>
<button type="button" onClick="{{{{tabs.t0}}}}" style="font-family: inherit; font-size: 13px; font-weight: 700; color: {{{{tabs.fg0}}}}; background: {{{{tabs.bg0}}}}; border: 0; border-radius: 999px; min-height: 34px; padding: 0 14px; cursor: pointer;">الأساسي</button>
<button type="button" onClick="{{{{tabs.t1}}}}" style="font-family: inherit; font-size: 13px; font-weight: 700; color: {{{{tabs.fg1}}}}; background: {{{{tabs.bg1}}}}; border: 0; border-radius: 999px; min-height: 34px; padding: 0 14px; cursor: pointer;">رمضان</button>
<button type="button" onClick="{{{{tabs.t2}}}}" style="font-family: inherit; font-size: 13px; font-weight: 700; color: {{{{tabs.fg2}}}}; background: {{{{tabs.bg2}}}}; border: 0; border-radius: 999px; min-height: 34px; padding: 0 14px; cursor: pointer;">فاضي</button>
</div>
<div dir="ltr" style="position: relative; width: {ES}px; height: {EH}px; flex-shrink: 0;">
{ic.scene('w.')}
{cell_btns}
</div>
<div style="padding: 8px 16px 0; display: flex; flex-direction: column; gap: 8px;">
<sc-if value="{{{{hasSel}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="display: grid; grid-template-columns: 1fr 1fr 1.5fr 1fr; gap: 6px;">
<button type="button" onClick="{{{{move}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: #23352A; background: #FFFFFF; border: 0; border-radius: 12px; min-height: 44px; cursor: pointer;">نقل</button>
<button type="button" onClick="{{{{flip}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: #23352A; background: #FFFFFF; border: 0; border-radius: 12px; min-height: 44px; cursor: pointer;">اقلب</button>
<button type="button" onClick="{{{{gild}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: #4A3200; background: #F2C14E; border: 0; border-radius: 12px; min-height: 44px; cursor: pointer;">{{{{gildLabel}}}}</button>
<button type="button" onClick="{{{{remove}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: #8A4B2B; background: #FFFFFF; border: 0; border-radius: 12px; min-height: 44px; cursor: pointer;">شيل</button>
</div>
</sc-if>
<div style="font-size: 13px; color: #45574B; min-height: 18px;">{{{{note}}}}</div>
<div style="display: flex; gap: 6px; overflow-x: auto; padding-bottom: 6px;">{tray}</div>
</div>
</div>
""" + TAIL.format(js=edit_js)
write('Edit.dc.html', edit)


