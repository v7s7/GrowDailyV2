"""Generates project/Builder.dc.html on the new island (real art).

Tap a + to plant, tap a planted thing to change it, pick from two tabs
(grows with XP, built with gold), slide the level to watch the base and
plaque change, switch colours and night.
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic

S = 358
u = S / 360
ART = ic.ART
ITEMS = ic.ITEMS

slot_buttons = ''
for i, (x, y, k) in enumerate(ic.SPOTS):
    w = dict((it[0], it[2]) for it in ITEMS)
    slot_buttons += (
        f'<sc-if value="{{{{sb.e{i}}}}}" hint-placeholder-val="{{{{true}}}}">'
        f'<button type="button" onClick="{{{{tap.t{i}}}}}" aria-label="مكان فاضي، ازرع هنا" style="position: absolute; left: {x * u:.1f}px; top: {(y - 16) * u:.1f}px; transform: translate(-50%, -50%); width: 40px; height: 40px; border-radius: 999px; border: 2.5px dashed #2F7A3A; background: {{{{sb.bg{i}}}}}; color: #2F7A3A; font-family: inherit; font-size: 24px; font-weight: 700; line-height: 1; padding: 0; cursor: pointer; display: flex; align-items: center; justify-content: center; box-shadow: 0 2px 6px rgba(30,58,36,0.18);">+</button>'
        f'</sc-if>'
        f'<sc-if value="{{{{sb.f{i}}}}}" hint-placeholder-val="{{{{false}}}}">'
        f'<button type="button" onClick="{{{{tap.t{i}}}}}" aria-label="غيّر اللي هنا" style="position: absolute; left: {x * u:.1f}px; top: {(y - 34) * u:.1f}px; transform: translate(-50%, -50%); width: 64px; height: 66px; border-radius: 18px; border: {{{{sb.ring{i}}}}}; background: transparent; padding: 0; cursor: pointer;"></button>'
        f'</sc-if>'
    )


def item_button(it):
    name, ar, _w, kind, price, opens = it
    a = ART[name]
    if kind == 'build':
        sub = f'<span style="font-size: 11px; color: #8A6A10; font-weight: 600;">{price} ذهب</span>'
    elif kind == 'rare':
        sub = f'<span style="font-size: 11px; color: {{{{lk.{name}.c}}}}; font-weight: 600;">{{{{lk.{name}.t}}}}</span>'
    else:
        sub = ''
    op = f'opacity: {{{{lk.{name}.o}}}};' if kind == 'rare' else ''
    return (f'<button type="button" onClick="{{{{pick.{name}}}}}" aria-label="{ar}" style="font-family: inherit; display: flex; flex-direction: column; align-items: center; justify-content: flex-start; gap: 1px; padding: 6px 2px 6px; min-height: 80px; border-radius: 16px; border: {{{{cur.{name}}}}}; background: #FFFFFF; cursor: pointer;">'
            f'<img src="{a[0]}" alt="" style="width: 46px; height: 40px; object-fit: contain; {op}">'
            f'<span style="font-size: 12px; font-weight: 600; color: #23352A; line-height: 1.2;">{ar}</span>{sub}</button>')


grow_buttons = ''.join(item_button(it) for it in ITEMS if it[3] == 'grow')
build_buttons = ''.join(item_button(it) for it in ITEMS if it[3] == 'build')
rare_buttons = ''.join(item_button(it) for it in ITEMS if it[3] == 'rare')
empty_button = ('<sc-if value="{{hasSel}}" hint-placeholder-val="{{false}}">'
                '<button type="button" onClick="{{remove}}" style="font-family: inherit; display: flex; align-items: center; justify-content: center; min-height: 80px; border-radius: 16px; border: 2px dashed #C9B9A0; background: #FBF8F1; color: #6B5320; font-size: 12px; font-weight: 700; cursor: pointer; padding: 4px;">خلّه فاضي</button>'
                '</sc-if>')

pal_buttons = ''.join(
    f'<button type="button" onClick="{{{{pal.{p[0]}.pick}}}}" aria-label="ألوان {p[1]}" style="font-family: inherit; display: flex; flex-direction: column; align-items: center; gap: 3px; background: transparent; border: 0; padding: 0; cursor: pointer; min-width: 44px;">'
    f'<span style="width: 40px; height: 40px; border-radius: 999px; overflow: hidden; display: flex; flex-direction: column; box-shadow: {{{{pal.{p[0]}.ring}}}};">'
    f'<span style="height: 40%; background: {p[2]};"></span><span style="height: 30%; background: {p[3]};"></span><span style="height: 30%; background: {p[4]};"></span></span>'
    f'<span style="font-size: 12px; color: #45574B;">{p[1]}</span></button>'
    for p in ic.PALETTES)

ITEM_NAMES = [it[0] for it in ITEMS]
JS = r"""
class Component extends DCLogic {
__ISLAND__
  renderVals() {
    const PAL = __PAL__;
    const NAMES = __NAMES__;
    const LIST = __LIST__;
    const PRICE = __PRICE__;
    const KIND = __KIND__;
    const OPENS = __OPENS__;
    const BASE = { 20: 'إطار ذهب', 35: 'قوس قزح', 50: 'عقد لؤلؤ', 75: 'تاج نجوم' };
    const TIERS = [[1, 'قاعدة رمل'], [5, 'قاعدة حجر'], [10, 'قاعدة مرجان'], [20, 'إطار ذهب'], [35, 'قوس قزح'], [50, 'عقد لؤلؤ'], [75, 'تاج نجوم']];
    const st = Object.assign({ level: 24, spots: ['lemon', '', 'jasmine', 'well', 'rose', ''], sel: -1, tab: 'grow', pal: 'doum',
      custom: { sky: '#DDF0F1', grass: '#93CC62', sea: '#86CBE6' }, night: false, fresh: -1, planting: false }, this.state || {});
    const set = (patch) => this.setState(Object.assign({}, st, patch));
    const planted = (i, name) => {
      const spots = st.spots.slice(); spots[i] = name;
      if (this._t) clearTimeout(this._t);
      this.setState(Object.assign({}, st, { spots, sel: -1, fresh: name ? i : -1, planting: !!name }));
      this._t = setTimeout(() => this.setState({ fresh: -1, planting: false }), 1800);
    };
    const colors = st.pal === 'custom'
      ? { sky: st.custom.sky, grass: st.custom.grass, sea: st.custom.sea, sand: '#F1D9A4' }
      : PAL[st.pal];
    const L = st.level;
    const w = this.island({ level: L, medals: Math.min(20, Math.floor(L / 4)), pearls: Math.min(4, Math.floor(L / 12)), thirst: 0,
      quietStyle: 'quiet', sky: st.night ? 'night' : 'day', watering: false, fresh: st.fresh, sel: st.sel, planting: st.planting,
      pose: 'auto', colors, frame: 'rect', detail: 'full', size: 358, spots: st.spots });
    const sb = {}, tap = {};
    for (let i = 0; i < 6; i++) {
      sb['e' + i] = !st.spots[i]; sb['f' + i] = !!st.spots[i];
      sb['bg' + i] = st.sel === i ? '#FFF3B0' : 'rgba(255,255,255,0.92)';
      sb['ring' + i] = st.sel === i ? '3px solid #2F7A3A' : '0';
      tap['t' + i] = () => set({ sel: st.sel === i ? -1 : i, note: '', tab: st.spots[i] && KIND[st.spots[i]] !== 'grow' ? KIND[st.spots[i]] : st.tab });
    }
    const pick = {}, cur = {}, lk = {};
    for (const n of LIST) {
      const locked = (OPENS[n] || 0) > st.level;
      lk[n] = { o: locked ? 0.35 : 1, t: locked ? 'من ' + OPENS[n] : (PRICE[n] || 0) + ' ذهب', c: locked ? '#8C948D' : '#8A6A10' };
      pick[n] = () => {
        if (st.sel < 0) return;
        if (locked) { set({ note: 'يفتح مع ' + BASE[OPENS[n]] + ' في المستوى ' + OPENS[n] }); return; }
        planted(st.sel, n);
      };
      cur[n] = st.sel >= 0 && st.spots[st.sel] === n ? '3px solid #2F7A3A' : '2px solid #E6DFCC';
    }
    const pal = {};
    Object.keys(PAL).forEach((k) => { pal[k] = { pick: () => set({ pal: k }), ring: st.pal === k ? '0 0 0 3px #23352A' : '0 0 0 1px #D9D1BC' }; });
    let tierName = TIERS[0][1], next = null;
    for (let i = 0; i < TIERS.length; i++) { if (L >= TIERS[i][0]) tierName = TIERS[i][1]; else { next = TIERS[i]; break; } }
    const selName = st.sel >= 0 && st.spots[st.sel] ? NAMES[st.spots[st.sel]] : '';
    const count = st.spots.filter((x) => x).length;
    const setLevel = (e) => set({ level: Math.max(1, Math.min(100, Number(e.target.value) || 1)) });
    return {
      w, sb, tap, pick, cur, pal,
      picking: st.sel >= 0, notPicking: st.sel < 0,
      pickTitle: st.note ? st.note : selName ? 'هنا ' + selName + '. تبي شي ثاني؟' : 'وش يزرع دوم هنا؟',
      hasSel: !!selName,
      growTab: st.tab === 'grow', buildTab: st.tab === 'build',
      rareTab: st.tab === 'rare',
      tabGrow: () => set({ tab: 'grow', note: '' }), tabBuild: () => set({ tab: 'build', note: '' }), tabRare: () => set({ tab: 'rare', note: '' }),
      tabGrowBg: st.tab === 'grow' ? '#FFFFFF' : 'transparent', tabBuildBg: st.tab === 'build' ? '#FFFFFF' : 'transparent', tabRareBg: st.tab === 'rare' ? '#FFF3C4' : 'transparent',
      tabGrowSh: st.tab === 'grow' ? '0 1px 4px rgba(0,0,0,0.12)' : 'none', tabBuildSh: st.tab === 'build' ? '0 1px 4px rgba(0,0,0,0.12)' : 'none', tabRareSh: st.tab === 'rare' ? '0 1px 4px rgba(0,0,0,0.12)' : 'none',
      lk,
      remove: () => planted(st.sel, ''),
      cancel: () => set({ sel: -1, note: '' }),
      line: st.planting ? 'دوم زرعها' : count === 6 ? 'واحتك كاملة، ما شاء الله' : 'اضغط + وازرع اللي تبيه',
      lv: L, tierName, nextLine: next ? 'الجاي: ' + next[1] + ' في المستوى ' + next[0] : 'وصلت آخر شي',
      setLevel,
      customOn: st.pal === 'custom' ? '0 0 0 3px #23352A' : '0 0 0 1px #D9D1BC',
      cSky: st.custom.sky, cGrass: st.custom.grass, cSea: st.custom.sea,
      setSky: (e) => set({ pal: 'custom', custom: Object.assign({}, st.custom, { sky: e.target.value }) }),
      setGrass: (e) => set({ pal: 'custom', custom: Object.assign({}, st.custom, { grass: e.target.value }) }),
      setSea: (e) => set({ pal: 'custom', custom: Object.assign({}, st.custom, { sea: e.target.value }) }),
      autoFill: () => {
        const fill = st.level >= 20 ? ['lemon', 'coral_house', 'pomegranate', 'well', st.level >= 35 ? 'fountain' : 'lantern_arch', 'vegetables'] : ['lemon', 'house', 'pomegranate', 'well', 'rose_arch', 'vegetables'];
        const spots = st.spots.map((x, i) => x || fill[i]);
        if (this._t) clearTimeout(this._t);
        this.setState(Object.assign({}, st, { spots, sel: -1, planting: true }));
        this._t = setTimeout(() => this.setState({ planting: false }), 1800);
      },
      toggleNight: () => set({ night: !st.night }),
      dayLabel: st.night ? 'نهار' : 'ليل',
      reset: () => set({ spots: ['', '', '', '', '', ''], sel: -1, fresh: -1 })
    };
  }
}
"""
JS = (JS.replace('__ISLAND__', ic.island_js())
        .replace('__PAL__', ic.PAL_JS)
        .replace('__NAMES__', ic.NAMES_JS)
        .replace('__LIST__', '[' + ', '.join(f"'{n}'" for n in ITEM_NAMES) + ']')
        .replace('__OPENS__', '{' + ', '.join(f"{it[0]}: {it[5]}" for it in ITEMS) + '}')
        .replace('__PRICE__', '{' + ', '.join(f"{it[0]}: {it[4]}" for it in ITEMS) + '}')
        .replace('__KIND__', '{' + ', '.join(f"{it[0]}: '{it[3]}'" for it in ITEMS) + '}'))

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
{ic.STYLE}
.bl-range{{width: 100%; accent-color: #2F7A3A; height: 28px;}}
</style>
</helmet>
<div dir="rtl" style="width: 390px; height: 844px; box-sizing: border-box; background: #F5F0E1; color: #23352A; font-family: 'IBM Plex Sans Arabic', sans-serif; padding: 36px 16px 0; display: flex; flex-direction: column; gap: 6px; overflow: hidden;">

<div style="display: flex; align-items: flex-end; justify-content: space-between; gap: 8px;">
<div style="display: flex; flex-direction: column; gap: 0;">
<a href="PlanetPage.dc.html" style="font-size: 13px; font-weight: 600; color: #2F7A3A; text-decoration: none; min-height: 24px;">رجوع للواحة</a>
<h1 style="margin: 0; font-size: 24px; font-weight: 700;">واحة دوم</h1>
<div style="font-size: 15px; color: #45574B; min-height: 22px;">{{{{line}}}}</div>
</div>
<a href="Edit.dc.html" style="font-size: 13px; font-weight: 700; color: #6B4E00; background: #FFF3C4; border-radius: 999px; padding: 8px 12px; text-decoration: none; white-space: nowrap;">تعديل حر · 100</a>
</div>

<div style="position: relative; width: 358px; height: 398px; border-radius: 28px; overflow: hidden; flex-shrink: 0;">
<div dir="ltr" style="position: absolute; left: 0; top: 0; width: 358px; height: 398px;">
{ic.scene('w.')}
{slot_buttons}
</div>
</div>

<sc-if value="{{{{picking}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="background: #FFFFFF; border-radius: 24px; padding: 10px 10px 12px; display: flex; flex-direction: column; gap: 8px;">
<div style="display: flex; align-items: center; justify-content: space-between; gap: 8px; padding: 0 4px;">
<div style="font-size: 17px; font-weight: 700;">{{{{pickTitle}}}}</div>
<button type="button" onClick="{{{{cancel}}}}" style="font-family: inherit; font-size: 15px; font-weight: 600; color: #45574B; background: transparent; border: 0; min-height: 44px; padding: 0 8px; cursor: pointer;">إلغاء</button>
</div>
<div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 4px; background: #F1ECDF; border-radius: 14px; padding: 4px;">
<button type="button" onClick="{{{{tabGrow}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: #23352A; background: {{{{tabGrowBg}}}}; box-shadow: {{{{tabGrowSh}}}}; border: 0; border-radius: 10px; min-height: 40px; cursor: pointer;">ينبت</button>
<button type="button" onClick="{{{{tabBuild}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: #23352A; background: {{{{tabBuildBg}}}}; box-shadow: {{{{tabBuildSh}}}}; border: 0; border-radius: 10px; min-height: 40px; cursor: pointer;">بالذهب</button>
<button type="button" onClick="{{{{tabRare}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: #6B4E00; background: {{{{tabRareBg}}}}; box-shadow: {{{{tabRareSh}}}}; border: 0; border-radius: 10px; min-height: 40px; cursor: pointer;">نادر</button>
</div>
<sc-if value="{{{{growTab}}}}" hint-placeholder-val="{{{{true}}}}">
<div style="display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 6px;">{grow_buttons}{empty_button}</div>
</sc-if>
<sc-if value="{{{{buildTab}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 6px;">{build_buttons}{empty_button}</div>
</sc-if>
<sc-if value="{{{{rareTab}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 6px;">{rare_buttons}{empty_button}</div>
</sc-if>
</div>
</sc-if>

<sc-if value="{{{{notPicking}}}}" hint-placeholder-val="{{{{true}}}}">
<div style="background: #FFFFFF; border-radius: 24px; padding: 12px 14px 14px; display: flex; flex-direction: column; gap: 10px;">
<div style="display: flex; flex-direction: column; gap: 2px;">
<div style="display: flex; justify-content: space-between; align-items: baseline; gap: 8px;">
<span style="font-size: 15px; font-weight: 700;">المستوى {{{{lv}}}}: {{{{tierName}}}}</span>
<span style="font-size: 12px; color: #6B7A6F;">{{{{nextLine}}}}</span>
</div>
<input class="bl-range" type="range" min="1" max="100" step="1" value="{{{{lv}}}}" onInput="{{{{setLevel}}}}" onChange="{{{{setLevel}}}}" aria-label="المستوى">
</div>
<div style="display: flex; justify-content: space-between;">{pal_buttons}</div>
<div style="display: flex; align-items: center; gap: 10px;">
<span style="font-size: 14px; font-weight: 700; flex-shrink: 0;">لونك:</span>
<label style="display: flex; flex-direction: column; align-items: center; gap: 2px; font-size: 12px; color: #45574B;"><input type="color" value="{{{{cSky}}}}" onChange="{{{{setSky}}}}" style="width: 44px; height: 30px; border: 0; padding: 0; background: transparent;">السما</label>
<label style="display: flex; flex-direction: column; align-items: center; gap: 2px; font-size: 12px; color: #45574B;"><input type="color" value="{{{{cGrass}}}}" onChange="{{{{setGrass}}}}" style="width: 44px; height: 30px; border: 0; padding: 0; background: transparent;">العشب</label>
<label style="display: flex; flex-direction: column; align-items: center; gap: 2px; font-size: 12px; color: #45574B;"><input type="color" value="{{{{cSea}}}}" onChange="{{{{setSea}}}}" style="width: 44px; height: 30px; border: 0; padding: 0; background: transparent;">البحر</label>
</div>
<div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 8px;">
<button type="button" onClick="{{{{autoFill}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #FFFFFF; background: #2F7A3A; border: 0; border-radius: 14px; min-height: 46px; cursor: pointer;">ازرع لي</button>
<button type="button" onClick="{{{{toggleNight}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #23352A; background: #F3EEDF; border: 0; border-radius: 14px; min-height: 46px; cursor: pointer;">{{{{dayLabel}}}}</button>
<button type="button" onClick="{{{{reset}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #23352A; background: transparent; border: 2px dashed #C9B9A0; border-radius: 14px; min-height: 46px; cursor: pointer;">من جديد</button>
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
