"""The simple oasis (Aziz, 2026-10-03: "too deep with items, hard to use, make it
simple, direct, but nice, and everything has an idea").

Three screens, one reason each:
  Oasis.dc.html    your oasis: what your days grew. Doum lives there on his own
                   (sits on the bench, waters, looks at the sea); tap a thing and
                   he walks to it and tells its story; a new level plants the next thing.
  Arrange.dc.html  tap a place, pick a thing: what you have, what gold builds, what opens later.
  Friends.dc.html  off until you turn it on. Friends from your rooms, highest level first
                   (you are in the list too). Visit one: take a cutting of any plant
                   they have and you don't; it grows in your oasis with their name.
Simple.dc.html is the start board that explains it and holds all three, live.
"""
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic
from gen_together import PHONE, BACK, write

ARB = "'IBM Plex Sans Arabic', sans-serif"
COLORS = "{ sky: '#DDF0F1', grass: '#93CC62', sea: '#86CBE6', sand: '#F1D9A4' }"
CAT = {n: dict(ar=ar, kind=k, price=pr, opens=op) for n, ar, w, k, pr, op in ic.ITEMS}
# the level each plant grew at, for its story
GROW_LV = {'flowers': 2, 'lemon': 7, 'jasmine': 9, 'spring': 11, 'rose': 13, 'pomegranate': 16, 'vegetables': 25,
           'sidr': 18, 'palm': 40}
PS = 358
PU = PS / 360
ISL_H = round(PS * 400 / 360)
FRONT_STAND = [list(ic.STANDS[i]) for i in range(6)]
LEVEL = 24
GOLD = 3250   # about two months of gold for an active user (55 a day)
GOLDEN_PRICE = 2000
# words that take the feminine verb («البئر بنيناها», «نافورة تفتح»)
FEM = ['sidr', 'palm', 'flowers', 'vegetables', 'spring', 'fountain', 'lily_pool', 'well', 'lamp_posts']

HEAD = """<!doctype html>
<html lang="ar">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&amp;display=swap" rel="stylesheet">
<style>
body{{margin:0}}
{style}
</style>
</helmet>
"""


def tail(js, h=844, props=None):
    p = dict(props or {})
    p['$preview'] = {'width': 390, 'height': h}
    return ("</x-dc>\n<script type=\"text/x-dc\" data-dc-script data-props='" + json.dumps(p, ensure_ascii=False) + "'>\n"
            + js + "\n</script>\n</body>\n</html>\n")


COIN = ('<svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9.5" fill="#F2C14E" stroke="#8A5A10" stroke-width="1.8"></circle>'
        '<circle cx="12" cy="12" r="5.6" fill="none" stroke="#B8860B" stroke-width="1.4"></circle></svg>')
LEAF = ('<svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 19 C5 10 11 5 20 5 C20 14 14 19 5 19 Z" fill="#9FD88F" stroke="#2F6B3A" stroke-width="1.8" stroke-linejoin="round"></path>'
        '<path d="M5 19 L13 11" stroke="#2F6B3A" stroke-width="1.8" stroke-linecap="round"></path></svg>')
LOCK = ('<svg width="13" height="13" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="#6B7A6F" stroke-width="2.4" stroke-linecap="round">'
        '<rect x="5" y="11" width="14" height="10" rx="2"></rect><path d="M8 11 V8 a4 4 0 0 1 8 0 V11"></path></svg>')
BTN = "font-family: inherit; font-size: 16px; font-weight: 700; border: 0; border-radius: 14px; min-height: 50px; cursor: pointer; text-decoration: none; display: flex; align-items: center; justify-content: center;"
PRIMARY = BTN + " color: #FFFFFF; background: #2F7A3A;"
SECOND = BTN + " color: #23352A; background: #EDE6D3;"


def top_bar(title, back_href, right=''):
    return ('<div style="display: flex; align-items: center; justify-content: space-between; gap: 10px; min-height: 44px;">'
            '<div style="display: flex; align-items: center; gap: 10px;">'
            f'<a href="{back_href}" aria-label="رجوع" style="width: 40px; height: 40px; border-radius: 999px; background: #FFFFFF; display: flex; align-items: center; justify-content: center; flex-shrink: 0;">{BACK}</a>'
            f'<h1 style="margin: 0; font-size: 24px; font-weight: 700;">{title}</h1></div>{right}</div>')


def gold_chip(hole='{{gold}}'):
    return (f'<div style="display: flex; align-items: center; gap: 6px; background: #FFFFFF; border-radius: 999px; padding: 6px 12px; font-size: 15px; font-weight: 700;">'
            f'{COIN}<span>{hole}</span></div>')


def island_box(taps):
    return (f'<div style="position: relative; width: {PS}px; height: {ISL_H}px; border-radius: 28px; overflow: hidden; flex-shrink: 0;">'
            f'<div dir="ltr" style="position: absolute; left: 0; top: 0; width: {PS}px; height: {ISL_H}px;">'
            + ic.scene('w.') + taps + '</div></div>')


def thing_taps(prefix='tp', palm=True, ground=True):
    """Invisible buttons over the six places and the palm; the ground takes the rest."""
    u = PU
    t = ''
    if ground:
        t += (f'<button type="button" onClick="{{{{ground}}}}" aria-label="امشِ هنا" style="position: absolute; left: {48 * u:.0f}px; top: {200 * u:.0f}px; '
              f'width: {264 * u:.0f}px; height: {120 * u:.0f}px; border: 0; background: transparent; padding: 0; cursor: pointer;"></button>')
    for i, (x, y, k) in enumerate(ic.SPOTS):
        t += (f'<sc-if value="{{{{{prefix}.has{i}}}}}" hint-placeholder-val="{{{{true}}}}"><button type="button" onClick="{{{{{prefix}.k{i}}}}}" aria-label="{{{{{prefix}.n{i}}}}}" '
              f'style="position: absolute; left: {x * u:.0f}px; top: {(y - 34) * u:.0f}px; transform: translate(-50%, -50%); width: {66 * u:.0f}px; height: {70 * u:.0f}px; '
              'border: 0; background: transparent; padding: 0; cursor: pointer;"></button></sc-if>')
    if palm:
        t += (f'<button type="button" onClick="{{{{{prefix}.kpalm}}}}" aria-label="النخلة" style="position: absolute; left: {196 * u:.0f}px; top: {150 * u:.0f}px; '
              f'transform: translate(-50%, -50%); width: {80 * u:.0f}px; height: {140 * u:.0f}px; border: 0; background: transparent; padding: 0; cursor: pointer;"></button>')
    return t


GROUND_JS = r"""
    const ground = (e) => {
      const ox = e && (e.offsetX != null ? e.offsetX : e.nativeEvent && e.nativeEvent.offsetX);
      const oy = e && (e.offsetY != null ? e.offsetY : e.nativeEvent && e.nativeEvent.offsetY);
      if (ox == null || oy == null) return;
      let x = 48 + ox / U, y = 200 + oy / U;
      const dx = (x - 180) / 132, dy = (y - 255) / 50, r = Math.hypot(dx, dy);
      if (r > 0.95) { x = 180 + dx / r * 0.95 * 132; y = 255 + dy / r * 0.95 * 50; }
      this.wake(12000);
      this.go(st, [x, y], { sel: null, poke: -1 });
    };
"""

LIFE_JS = r"""
  // when nobody taps, Doum does small things on his own; a tap pauses this for a while
  wake(ms) {
    if (this._life) clearTimeout(this._life);
    if (this.calm() || this.props.still === 'true') return;
    this._life = setTimeout(() => this.lifeStep(), ms);
  }
  lifeStep() {
    const st = Object.assign({}, this._base, this.state || {});
    const plan = (this._plan || []).filter((p) => !p.need || p.need(st));
    if (st.busy || !plan.length) { this.wake(3000); return; }
    this._li = ((this._li == null ? -1 : this._li) + 1) % plan.length;
    const p = plan[this._li];
    if (p.sit) { this.sitOn(st, p.sit, { sel: null, poke: -1 }); this.wake(p.wait || 9000); return; }
    this.go(st, p.at, { sel: null, poke: -1 }, () => { if (p.act) this.doAct(p.act, '', 3200, null, p.face); });
    this.wake(p.wait || 7000);
  }
"""

# what you own in the demo (Arrange uses the same list)
OWNED_ALL = ['pomegranate', 'jasmine', 'lemon', 'rose', 'flowers', 'spring', 'house', 'well', 'bench']
# ======================================================================= Oasis
START = ['pomegranate', 'house', 'jasmine', 'well', 'bench', '']
AFTER = ['pomegranate', 'house', 'jasmine', 'well', 'bench', 'vegetables']
BENCH = list(ic.SPOTS[4])
O_INFO = {
    'palm': ('نخلتنا. معنا من أول يوم', 'dates', list(ic.STANDS['palm'])),
    '0': ('رمان يوسف. أخذنا شتلته من واحته', 'water', FRONT_STAND[0]),
    '1': ('بيتي. بنيناه بـ 900 ذهب', 'look', FRONT_STAND[1]),
    '2': ('الفل نبت في المستوى 9', 'water', FRONT_STAND[2]),
    '3': ('البئر بنيناها بـ 250 ذهب', 'look', FRONT_STAND[3]),
    '4': ('أرتاح شوي', 'sit', None),
    '5': ('الخضار نبتت في المستوى 25', 'water', FRONT_STAND[5]),
}
o_info_js = json.dumps({k: dict(say=v[0], kind=v[1], stand=v[2], tx=(196 if k == 'palm' else ic.SPOTS[int(k)][0])) for k, v in O_INFO.items()}, ensure_ascii=False)

OASIS_JS = r"""
class Component extends DCLogic {
__ISLAND__
__ENGINE__
__LIFE__
  renderVals() {
    const INFO = __INFO__;
    const U = __PU__;
    const BENCH = __BENCH__;
    const base = { walk: [168, 300], dir: 'front', flip: false, walking: false, landing: false, carry: false, action: '', say: '', sel: null,
      poke: -1, n: 0, dur: 0.9, sit: '', seatZ: 0, seatFront: null, grown: false, growing: false, level: __LEVEL__, news: false, busy: false, ramadan: false };
    this._base = base;
    const st = Object.assign({}, base, this.state || {});
    this._plan = [
      { sit: BENCH, wait: 10000 },
      { at: __STAND0__, act: 'water', face: 114 },
      { at: [160, 298], wait: 6000 },
      { at: __STANDPALM__, act: 'dates', face: 196 },
      { at: [168, 300], wait: 5000 }
    ];
    if (!this._lifeOn) { this._lifeOn = true; this.wake(1500); }
    const spots = st.grown ? __AFTER__ : __START__;
    const tp = {};
    Object.keys(INFO).forEach((k) => {
      const it = INFO[k];
      const i = k === 'palm' ? 'palm' : Number(k);
      tp['k' + k] = () => {
        this.wake(14000);
        if (it.kind === 'sit') { if (st.sit === 'on') this.setState({ say: it.say }); else this.sitOn(st, BENCH, { sel: k, poke: -1 }, it.say); return; }
        this.go(st, it.stand, { sel: k, poke: i, n: st.n + 1 }, () => {
          if (it.kind === 'dates') this.doAct('dates', it.say, 3400, null, it.tx);
          else if (it.kind === 'water') this.doAct('water', it.say, 3400, null, it.tx);
          else this.doAct('', it.say, 3000);
        });
      };
    });
    spots.forEach((s, i) => { tp['has' + i] = !!s; tp['n' + i] = s ? (__NAMES__)[s] : ''; });
__GROUND__
    const levelUp = () => {
      if (st.grown || st.busy) return;
      this.wake(14000);
      const spot = __SPOT5__;
      this.go(st, this.plantStand(5), { sel: null, poke: -1, busy: true }, () => {
        this.doAct('plant', '', 1300, { action: '', grown: true, growing: true, level: __LEVEL__ + 1, say: 'نبتت الخضار' }, spot[0]);
        setTimeout(() => this.setState({ growing: false }), 2400);
        setTimeout(() => this.setState({ say: '', busy: false }), 3800);
      });
    };
    const w = this.island({ level: st.level, medals: 9, pearls: 2, thirst: 0, quietStyle: 'quiet', sky: st.ramadan ? 'night' : 'day', season: st.ramadan ? 'ramadan' : '',
      fresh: st.growing ? 5 : -1, sel: -1, pose: 'auto', colors: __COLORS__, frame: 'rect', detail: 'full', size: __PS__,
      spots, growIn: st.growing ? 5 : -1,
      doumState: this.doumState(st),
      poke: typeof st.poke === 'number' || st.poke === 'palm' ? st.poke : -1, pokeN: st.n, walkTo: st.walk, walkDur: st.dur,
      say: st.say, sayAt: [Math.min(250, Math.max(110, st.walk[0])), st.sit ? st.walk[1] - 70 : st.walk[1] - 86] });
    const lv = st.level;
    return { w, tp, ground, levelUp, canGrow: !st.grown,
      lv, gold: '__GOLDTXT__', pct: (st.grown ? 8 : 64) + '%', canBuild: '__CANBUILD__',
      ramadan: () => this.setState({ ramadan: !st.ramadan }), ramadanLabel: st.ramadan ? 'نهار عادي' : 'ليالي رمضان',
      next: st.grown ? 'الجاي في المستوى 27: عريش عنب' : 'الجاي في المستوى 25: خضار',
      nextSrc: st.grown ? '__VINE__' : '__VEG__',
      news: st.news, showNews: () => this.setState({ news: true }),
      reset: () => { if (this._w) clearTimeout(this._w); if (this._a) clearTimeout(this._a); if (this._s) clearTimeout(this._s); this.setState(Object.assign({}, base)); this.wake(1500); } };
  }
}
"""


def fill(js, **kw):
    js = js.replace('__ISLAND__', ic.island_js()).replace('__ENGINE__', ic.ENGINE_JS).replace('__LIFE__', LIFE_JS)
    js = js.replace('__GROUND__', GROUND_JS).replace('__COLORS__', COLORS).replace('__PS__', str(PS)).replace('__PU__', f'{PU:.6f}')
    js = js.replace('__NAMES__', ic.NAMES_JS).replace('__LEVEL__', str(LEVEL))
    for k, v in kw.items():
        js = js.replace('__' + k + '__', v)
    return js


CAN = [n for n, c in CAT.items() if c['kind'] in ('build', 'rare') and n not in OWNED_ALL and c['opens'] <= LEVEL and c['price'] <= GOLD]
CAN_TXT = (f'{len(CAN)} أشياء تقدر تبنيها بذهبك' if 3 <= len(CAN) <= 10 else 'شيئين تقدر تبنيهم بذهبك' if len(CAN) == 2 else 'شي واحد تقدر تبنيه بذهبك' if len(CAN) == 1 else f'{len(CAN)} شي تقدر تبنيه بذهبك')
oasis_js = fill(OASIS_JS, GOLDTXT=f'{GOLD:,}', CANBUILD=CAN_TXT, STAND0=json.dumps(list(ic.STANDS[0])), STANDPALM=json.dumps(list(ic.STANDS['palm'])), SPOT5=json.dumps(list(ic.SPOTS[5])), VINE=ic.ART['vine'][0], VEG=ic.ART['vegetables'][0], INFO=o_info_js, BENCH=json.dumps(BENCH), START=json.dumps(START), AFTER=json.dumps(AFTER))
TEST_H = 110
oasis = HEAD.format(title='Your oasis', style=ic.STYLE + '@keyframes os-in{0%{transform:translateY(-6px);opacity:0}100%{transform:none;opacity:1}}.os-in{animation:os-in .4s ease-out}@media (prefers-reduced-motion: reduce){.os-in{animation:none}}') + f"""<div style="width: 390px; height: {844 + TEST_H}px; background: #FFFFFF; font-family: {ARB};">
<div dir="rtl" style="{PHONE} padding: 48px 16px 0; display: flex; flex-direction: column; gap: 12px;">
{top_bar('واحتك', 'Profile.dc.html', gold_chip())}
{island_box(thing_taps())}
<div style="background: #FFFFFF; border-radius: 22px; padding: 14px 16px; display: flex; align-items: center; gap: 14px;">
<div style="flex: 1; display: flex; flex-direction: column; gap: 8px;">
<div style="display: flex; align-items: baseline; justify-content: space-between;">
<div style="font-size: 18px; font-weight: 700;">المستوى {{{{lv}}}}</div>
<div style="font-size: 13px; color: #6B7A6F;">تكبر مع عاداتك</div>
</div>
<div style="height: 8px; border-radius: 99px; background: #EDE6D3; overflow: hidden;"><div style="height: 100%; width: {{{{pct}}}}; background: #3F9A4E; border-radius: 99px; transition: width .6s ease;"></div></div>
<div style="font-size: 14px; color: #45574B;">{{{{next}}}}</div>
</div>
<div style="width: 60px; height: 60px; border-radius: 16px; background: #F3EEDF; display: flex; align-items: center; justify-content: center; flex-shrink: 0;"><img src="{{{{nextSrc}}}}" alt="" style="width: 50px; height: 46px; object-fit: contain;"></div>
</div>
<a href="Arrange.dc.html" style="display: flex; align-items: center; justify-content: space-between; gap: 8px; background: #FFFFFF; border-radius: 16px; padding: 10px 14px; min-height: 44px; box-sizing: border-box; text-decoration: none; color: #23352A;">
<span style="display: flex; align-items: center; gap: 8px; font-size: 14px; font-weight: 600;">{COIN}{{{{canBuild}}}}</span>
<span style="font-size: 13px; font-weight: 700; color: #2F7A3A;">رتّب</span></a>
<sc-if value="{{{{news}}}}" hint-placeholder-val="{{{{false}}}}">
<div class="os-in" style="display: flex; align-items: center; gap: 8px; background: #EEF6EC; color: #2F6B3A; border-radius: 16px; padding: 10px 14px; font-size: 14px; font-weight: 600;">{LEAF}<span>أخذ خالد شتلة فل من واحتك</span></div>
</sc-if>
<div style="flex: 1;"></div>
<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px; padding-bottom: 34px;">
<a href="Arrange.dc.html" style="{PRIMARY}">رتّب</a>
<a href="Friends.dc.html" style="{SECOND}">أصحابك</a>
</div>
</div>
<div dir="rtl" style="height: {TEST_H}px; box-sizing: border-box; border-top: 2px dashed #C9C1AC; background: #FAF7EF; padding: 10px 14px; display: flex; flex-direction: column; gap: 8px;">
<div style="font-size: 12px; font-weight: 700; color: #8A7F66;">للتجربة فقط، مو في التطبيق</div>
<div style="display: flex; gap: 6px; flex-wrap: wrap;">
<sc-if value="{{{{canGrow}}}}" hint-placeholder-val="{{{{true}}}}"><button type="button" onClick="{{{{levelUp}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: #6B4E00; background: #FFF3C4; border: 0; border-radius: 12px; min-height: 44px; padding: 0 14px; cursor: pointer;">مستوى جديد</button></sc-if>
<button type="button" onClick="{{{{showNews}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: #2F6B3A; background: #EEF6EC; border: 0; border-radius: 12px; min-height: 44px; padding: 0 14px; cursor: pointer;">صاحبك أخذ شتلة</button>
<button type="button" onClick="{{{{ramadan}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: #F5F0E1; background: #2B3A5C; border: 0; border-radius: 12px; min-height: 44px; padding: 0 12px; cursor: pointer;">{{{{ramadanLabel}}}}</button>
<button type="button" onClick="{{{{reset}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: #45574B; background: #EDE6D3; border: 0; border-radius: 12px; min-height: 44px; padding: 0 12px; cursor: pointer;">من البداية</button>
</div>
</div>
</div>
""" + tail(oasis_js, 844 + TEST_H)
write('Oasis.dc.html', oasis)

# ======================================================================= Arrange
OWNED = OWNED_ALL
FROM = {'pomegranate': 'يوسف'}
BUILD = [n for n, c in CAT.items() if c['kind'] in ('build', 'rare') and n not in OWNED]
BUILD.sort(key=lambda n: (CAT[n]['opens'] > LEVEL, CAT[n]['opens'], CAT[n]['price']))
cat_js = json.dumps({n: dict(ar=c['ar'], kind=c['kind'], price=c['price'], opens=c['opens'], src=ic.ART[n][0], f=n in FEM, size=ic.size_of(n)) for n, c in CAT.items()}, ensure_ascii=False)

ARRANGE_JS = r"""
class Component extends DCLogic {
__ISLAND__
__ENGINE__
  wake() {}
  renderVals() {
    const CAT = __CAT__;
    const U = __PU__;
    const SPOTS = __SPOTS__;
    const STAND = __STAND__;
    const base = { walk: [168, 300], dir: 'front', flip: false, walking: false, landing: false, carry: false, action: '', say: '', n: 0, dur: 0.9,
      sit: '', seatZ: 0, seatFront: null, spots: __START__, owned: __OWNED__, gold: __GOLD__, sel: -1, msg: '', growIn: -1, busy: false, golden: {} };
    const st = Object.assign({}, base, this.state || {});
    const fmt = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    const FROM = __FROM__;
    const placed = {};
    st.spots.forEach((s) => { if (s) placed[s] = true; });
    const tp = {};
    st.spots.forEach((s, i) => {
      tp['has' + i] = true; tp['n' + i] = s ? CAT[s].ar : 'مكان فاضي';
      tp['k' + i] = () => this.setState(Object.assign({}, st, { sel: st.sel === i ? -1 : i, msg: '' }));
    });
    const put = (i, name, cost) => {
      const spots = st.spots.slice(); spots[i] = name;
      const owned = st.owned.indexOf(name) < 0 ? st.owned.concat([name]) : st.owned;
      const gold = st.gold - (cost || 0);
      const msg = cost ? 'بنيت ' + CAT[name].ar + ' بـ ' + fmt(cost) + ' ذهب' : '';
      this.go(st, this.plantStand(i), { sel: -1, msg, busy: true, gold, owned }, () => {
        const grow = CAT[name].kind === 'grow';
        this.doAct(grow ? 'plant' : '', '', grow ? 1300 : 300, { action: '', spots, growIn: i, n: (this.state.n || 0) + 1 }, SPOTS[i][0]);
        setTimeout(() => this.setState({ growIn: -1, busy: false }), (grow ? 1300 : 300) + 1400);
      });
    };
    const choose = {};
    const cards = [];
    // three groups in the tray, each with its heading: yours, built with gold, opening later
    const add = (name, label, kind, act) => { choose[name] = act; cards.push({ name, ar: CAT[name].ar + (FROM[name] ? ' ' + FROM[name] : ''), src: CAT[name].src, label, kind,
      fg: kind === 'have' ? '#2F6B3A' : kind === 'buy' ? '#6B4E00' : kind === 'short' ? '#9A8B6A' : '#6B7A6F',
      bg: kind === 'lock' || kind === 'away' ? '#F1ECDF' : '#FFFFFF', op: kind === 'lock' || kind === 'away' ? 0.45 : 1,
      coin: kind === 'buy' || kind === 'short', lock: kind === 'lock', key: 'c_' + name }); };
    // where things may stand: buildings only in the two back places, tall things back or middle, low things anywhere
    const ROW = [0, 0, 1, 1, 2, 2];
    const fits = (n, i) => (CAT[n].size === 'big' ? ROW[i] === 0 : CAT[n].size === 'tall' ? ROW[i] <= 1 : true);
    const away = (n) => add(n, CAT[n].f ? 'مكانها ورا' : 'مكانه ورا', 'away', () => this.setState(Object.assign({}, st, {
      msg: CAT[n].ar + (CAT[n].f ? ' مكانها ورا، عشان ما تغطي اللي قدّامها' : ' مكانه ورا، عشان ما يغطي اللي قدّامه') })));
    const sel = st.sel;
    if (sel >= 0) {
      st.owned.filter((n) => !placed[n]).forEach((n) => (fits(n, sel) ? add(n, FROM[n] ? 'من ' + FROM[n] : 'عندك', 'have', () => put(sel, n, 0)) : away(n)));
      __BUILD__.forEach((n) => {
        if (st.owned.indexOf(n) >= 0) return;
        const c = CAT[n];
        if (c.opens > __LEVEL__) add(n, 'المستوى ' + c.opens, 'lock', () => this.setState(Object.assign({}, st, { msg: c.ar + (c.f ? ' تفتح' : ' يفتح') + ' في المستوى ' + c.opens })));
        else if (!fits(n, sel)) away(n);
        else if (c.price > st.gold) add(n, fmt(c.price), 'short', () => this.setState(Object.assign({}, st, { msg: 'ناقصك ' + fmt(c.price - st.gold) + ' ذهب' })));
        else add(n, fmt(c.price), 'buy', () => put(sel, n, c.price));
      });
    }
    // a golden version of the thing in this place: the long-term use for gold
    const here = sel >= 0 ? st.spots[sel] : '';
    const isGolden = sel >= 0 && !!st.golden[sel];
    const gild = () => {
      if (sel < 0 || !here || isGolden) return;
      if (st.gold < __GOLDEN__) { this.setState(Object.assign({}, st, { msg: 'ناقصك ' + fmt(__GOLDEN__ - st.gold) + ' ذهب' })); return; }
      const golden = Object.assign({}, st.golden); golden[sel] = true;
      this.setState(Object.assign({}, st, { golden, gold: st.gold - __GOLDEN__, sel: -1, growIn: sel, msg: (CAT[here].f ? 'صارت ' : 'صار ') + CAT[here].ar + ' ذهبي' + (CAT[here].f ? 'ة' : '') }));
      setTimeout(() => this.setState({ growIn: -1 }), 1400);
    };
    const clear = () => {
      if (sel < 0 || !st.spots[sel]) return;
      const spots = st.spots.slice(); spots[sel] = '';
      const golden = Object.assign({}, st.golden); delete golden[sel];
      this.setState(Object.assign({}, st, { spots, golden, sel: -1, msg: (CAT[st.spots[sel]].f ? 'رجعت ' : 'رجع ') + CAT[st.spots[sel]].ar + ' لأغراضك' }));
    };
    const w = this.island({ level: __LEVEL__, medals: 9, pearls: 2, thirst: 0, quietStyle: 'quiet', sky: 'day', fresh: st.growIn, sel: sel,
      pose: 'auto', colors: __COLORS__, frame: 'rect', detail: 'full', size: __PS__, spots: st.spots, growIn: st.growIn, golden: st.golden,
      doumState: this.doumState(st), walkTo: st.walk, walkDur: st.dur, poke: -1 });
    // the + ring marks an empty place, but not while Doum is planting there
    const empty = st.spots.map((s, i) => ({ show: !s && !st.busy, x: SPOTS[i][0] * U, y: (SPOTS[i][1] - 12) * U, on: sel === i ? 1 : 0 }));
    const all = cards.map((c) => Object.assign(c, { pick: choose[c.name] }));
    const have = all.filter((c) => c.kind === 'have'), buy = all.filter((c) => c.kind === 'buy' || c.kind === 'short'), lock = all.filter((c) => c.kind === 'lock'),
      back = all.filter((c) => c.kind === 'away');
    const rowHint = sel < 0 ? '' : ROW[sel] === 0 ? 'مكان ورا: أي شي يركب هنا' : ROW[sel] === 1 ? 'مكان بالنص: كل شي إلا البيوت' : 'مكان قدّام: الأشياء الواطية بس';
    return { w, tp, cards: all, have, buy, lock, back, hasHave: have.length > 0, hasBuy: buy.length > 0, hasLock: lock.length > 0, hasBack: back.length > 0, rowHint, empty,
      gild, canGild: sel >= 0 && !!here && !isGolden, isGolden, goldenPrice: fmt(__GOLDEN__),
      gold: fmt(st.gold), msg: st.msg, hasMsg: !!st.msg, picking: sel >= 0, notPicking: sel < 0,
      selName: sel >= 0 && st.spots[sel] ? CAT[st.spots[sel]].ar : 'مكان فاضي', canClear: sel >= 0 && !!st.spots[sel],
      clear, close: () => this.setState(Object.assign({}, st, { sel: -1, msg: '' })) };
  }
}
"""
arrange_js = fill(ARRANGE_JS, GOLDEN=str(GOLDEN_PRICE), CAT=cat_js, SPOTS=json.dumps([list(s) for s in ic.SPOTS]), STAND=json.dumps(FRONT_STAND),
                  START=json.dumps(START), OWNED=json.dumps(OWNED), GOLD=str(GOLD), FROM=json.dumps(FROM, ensure_ascii=False),
                  BUILD=json.dumps(BUILD))
empty_marks = ('<sc-for list="{{empty}}" as="e" hint-placeholder-count="1"><sc-if value="{{e.show}}" hint-placeholder-val="{{true}}">'
               '<div style="position: absolute; left: {{e.x}}px; top: {{e.y}}px; transform: translate(-50%, -50%); width: 44px; height: 30px; border-radius: 50%; '
               'border: 2.5px dashed #2F6B3A; background: rgba(255,255,255,0.55); display: flex; align-items: center; justify-content: center; '
               'color: #2F6B3A; font-size: 20px; font-weight: 700; z-index: 9300; pointer-events: none;">+</div></sc-if></sc-for>')
arrange = HEAD.format(title='Arrange your oasis', style=ic.STYLE) + f"""<div dir="rtl" style="{PHONE} padding: 48px 16px 0; display: flex; flex-direction: column; gap: 12px;">
{top_bar('رتّب واحتك', 'Oasis.dc.html', gold_chip())}
{island_box(thing_taps(palm=False, ground=False) + empty_marks)}
<sc-if value="{{{{notPicking}}}}" hint-placeholder-val="{{{{true}}}}">
<div style="background: #FFFFFF; border-radius: 22px; padding: 14px 16px; display: flex; flex-direction: column; gap: 4px;">
<div style="font-size: 17px; font-weight: 700;">اضغط أي مكان في الواحة</div>
<div style="font-size: 14px; color: #45574B; line-height: 1.5;">وبعدين اختر شي له: من أغراضك، أو تبنيه بالذهب.</div>
</div>
<sc-if value="{{{{hasMsg}}}}" hint-placeholder-val="{{{{false}}}}"><div style="background: #EEF6EC; color: #2F6B3A; border-radius: 16px; padding: 10px 14px; font-size: 14px; font-weight: 600;">{{{{msg}}}}</div></sc-if>
</sc-if>
<sc-if value="{{{{picking}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="position: absolute; left: 0; right: 0; bottom: 0; top: 452px; background: #FFFFFF; border-radius: 24px 24px 0 0; box-shadow: 0 -6px 20px rgba(35,53,42,0.10); padding: 14px 14px 0; display: flex; flex-direction: column; gap: 10px;">
<div style="display: flex; align-items: center; justify-content: space-between; gap: 8px;">
<div style="display: flex; flex-direction: column; gap: 2px;"><div style="font-size: 17px; font-weight: 700;">{{{{selName}}}}</div><div style="font-size: 13px; color: #6B7A6F;">{{{{rowHint}}}}</div></div>
<div style="display: flex; gap: 6px;">
<sc-if value="{{{{canClear}}}}" hint-placeholder-val="{{{{false}}}}"><button type="button" onClick="{{{{clear}}}}" style="font-family: inherit; font-size: 14px; font-weight: 600; color: #45574B; background: #F3EEDF; border: 0; border-radius: 999px; min-height: 40px; padding: 0 14px; cursor: pointer;">فضّه</button></sc-if>
<button type="button" onClick="{{{{close}}}}" style="font-family: inherit; font-size: 14px; font-weight: 600; color: #45574B; background: transparent; border: 0; min-height: 40px; padding: 0 8px; cursor: pointer;">تم</button>
</div>
</div>
<sc-if value="{{{{hasMsg}}}}" hint-placeholder-val="{{{{false}}}}"><div style="background: #FFF3C4; color: #6B4E00; border-radius: 12px; padding: 8px 12px; font-size: 14px; font-weight: 600;">{{{{msg}}}}</div></sc-if>
<div style="flex: 1; overflow-y: auto; padding-bottom: 24px; display: flex; flex-direction: column; gap: 8px;">
<sc-if value="{{{{canGild}}}}" hint-placeholder-val="{{{{false}}}}">
<button type="button" onClick="{{{{gild}}}}" style="font-family: inherit; display: flex; align-items: center; justify-content: space-between; gap: 8px; background: #FFF8E1; border: 1.5px solid #F2D27A; border-radius: 14px; min-height: 48px; padding: 0 14px; cursor: pointer; color: #6B4E00;">
<span style="font-size: 15px; font-weight: 700;">نسخة ذهبية من هذا</span><span style="display: flex; align-items: center; gap: 4px; font-size: 14px; font-weight: 700;">{COIN.replace('width="18" height="18"', 'width="14" height="14"')}{{{{goldenPrice}}}}</span></button>
</sc-if>
<sc-if value="{{{{hasHave}}}}" hint-placeholder-val="{{{{true}}}}">
<div style="font-size: 13px; font-weight: 700; color: #6B7A6F; margin-top: 4px;">عندك</div>
<div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px;">
<sc-for list="{{{{have}}}}" as="c" hint-placeholder-count="4"><button type="button" onClick="{{{{c.pick}}}}" style="font-family: inherit; display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 8px 2px 6px; border-radius: 16px; border: 1.5px solid #E6DFCC; background: {{{{c.bg}}}}; cursor: pointer; min-height: 100px;">
<img src="{{{{c.src}}}}" alt="" style="width: 58px; height: 48px; object-fit: contain; opacity: {{{{c.op}}}};">
<span style="font-size: 13px; font-weight: 600; color: #23352A; line-height: 1.2; text-align: center;">{{{{c.ar}}}}</span>
<span style="display: flex; align-items: center; gap: 3px; font-size: 12px; font-weight: 700; color: {{{{c.fg}}}};">
<sc-if value="{{{{c.coin}}}}" hint-placeholder-val="{{{{false}}}}">{COIN.replace('width="18" height="18"', 'width="13" height="13"')}</sc-if>
<sc-if value="{{{{c.lock}}}}" hint-placeholder-val="{{{{false}}}}">{LOCK}</sc-if>{{{{c.label}}}}</span>
</button></sc-for>
</div>
</sc-if>
<sc-if value="{{{{hasBuy}}}}" hint-placeholder-val="{{{{true}}}}">
<div style="font-size: 13px; font-weight: 700; color: #6B7A6F; margin-top: 4px;">ابنِ بالذهب</div>
<div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px;">
<sc-for list="{{{{buy}}}}" as="c" hint-placeholder-count="4"><button type="button" onClick="{{{{c.pick}}}}" style="font-family: inherit; display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 8px 2px 6px; border-radius: 16px; border: 1.5px solid #E6DFCC; background: {{{{c.bg}}}}; cursor: pointer; min-height: 100px;">
<img src="{{{{c.src}}}}" alt="" style="width: 58px; height: 48px; object-fit: contain; opacity: {{{{c.op}}}};">
<span style="font-size: 13px; font-weight: 600; color: #23352A; line-height: 1.2; text-align: center;">{{{{c.ar}}}}</span>
<span style="display: flex; align-items: center; gap: 3px; font-size: 12px; font-weight: 700; color: {{{{c.fg}}}};">
<sc-if value="{{{{c.coin}}}}" hint-placeholder-val="{{{{false}}}}">{COIN.replace('width="18" height="18"', 'width="13" height="13"')}</sc-if>
<sc-if value="{{{{c.lock}}}}" hint-placeholder-val="{{{{false}}}}">{LOCK}</sc-if>{{{{c.label}}}}</span>
</button></sc-for>
</div>
</sc-if>
<sc-if value="{{{{hasLock}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="font-size: 13px; font-weight: 700; color: #6B7A6F; margin-top: 4px;">يفتح بعدين</div>
<div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px;">
<sc-for list="{{{{lock}}}}" as="c" hint-placeholder-count="4"><button type="button" onClick="{{{{c.pick}}}}" style="font-family: inherit; display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 8px 2px 6px; border-radius: 16px; border: 1.5px solid #E6DFCC; background: {{{{c.bg}}}}; cursor: pointer; min-height: 100px;">
<img src="{{{{c.src}}}}" alt="" style="width: 58px; height: 48px; object-fit: contain; opacity: {{{{c.op}}}};">
<span style="font-size: 13px; font-weight: 600; color: #23352A; line-height: 1.2; text-align: center;">{{{{c.ar}}}}</span>
<span style="display: flex; align-items: center; gap: 3px; font-size: 12px; font-weight: 700; color: {{{{c.fg}}}};">
<sc-if value="{{{{c.coin}}}}" hint-placeholder-val="{{{{false}}}}">{COIN.replace('width="18" height="18"', 'width="13" height="13"')}</sc-if>
<sc-if value="{{{{c.lock}}}}" hint-placeholder-val="{{{{false}}}}">{LOCK}</sc-if>{{{{c.label}}}}</span>
</button></sc-for>
</div>
</sc-if>
<sc-if value="{{{{hasBack}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="font-size: 13px; font-weight: 700; color: #6B7A6F; margin-top: 4px;">للأماكن اللي ورا</div>
<div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 8px;">
<sc-for list="{{{{back}}}}" as="c" hint-placeholder-count="4"><button type="button" onClick="{{{{c.pick}}}}" style="font-family: inherit; display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 8px 2px 6px; border-radius: 16px; border: 1.5px solid #E6DFCC; background: {{{{c.bg}}}}; cursor: pointer; min-height: 100px;">
<img src="{{{{c.src}}}}" alt="" style="width: 58px; height: 48px; object-fit: contain; opacity: {{{{c.op}}}};">
<span style="font-size: 13px; font-weight: 600; color: #23352A; line-height: 1.2; text-align: center;">{{{{c.ar}}}}</span>
<span style="display: flex; align-items: center; gap: 3px; font-size: 12px; font-weight: 700; color: {{{{c.fg}}}};">
<sc-if value="{{{{c.coin}}}}" hint-placeholder-val="{{{{false}}}}">{COIN.replace('width="18" height="18"', 'width="13" height="13"')}</sc-if>
<sc-if value="{{{{c.lock}}}}" hint-placeholder-val="{{{{false}}}}">{LOCK}</sc-if>{{{{c.label}}}}</span>
</button></sc-for>
</div>
</sc-if>
</div>
</div>
</sc-if>
</div>
""" + tail(arrange_js)
write('Arrange.dc.html', arrange)

# ======================================================================= Friends
MY_PLANTS = ['pomegranate', 'jasmine', 'lemon', 'rose', 'flowers', 'spring']
FRIENDS = [
    # name, level, medals, pearls, spots
    # buildings in the back, tall things back or middle, low things in front
    ('يوسف', 52, 17, 5, ['coral_house', 'sidr', 'fountain', 'vine', 'falaj', 'vegetables']),
    ('خالد', 31, 11, 3, ['coral_house', 'palm', 'lantern_arch', 'well', 'bench', 'flowers']),
    ('عبدالله', 15, 5, 2, ['flowers', 'house', 'rose', '', '', '']),
    ('أحمد', 8, 2, 1, ['flowers', '', '', '', '', '']),
]
fr_js = json.dumps([dict(name=n, level=lv, medals=md, pearls=pr, spots=sp) for n, lv, md, pr, sp in FRIENDS], ensure_ascii=False)

FRIENDS_JS = r"""
class Component extends DCLogic {
__ISLAND__
__ENGINE__
  wake() {}
  renderVals() {
    const F = __FRIENDS__;
    const CAT = __CAT__;
    const GROW_LV = __GROWLV__;
    const MINE = __MINE__;
    const U = __PU__;
    const STAND = __STAND__;
    const SPOTS = __SPOTS__;
    const start = this.props.start === 'list' ? 'list' : this.props.start === 'visit' ? 'visit' : 'off';
    const base = { view: start, who: 0, walk: [212, 302], dir: 'front', flip: false, walking: false, landing: false, carry: false, action: '', say: '',
      sel: null, poke: -1, n: 0, dur: 0.9, sit: '', seatZ: 0, seatFront: null, took: {}, done: '' };
    const st = Object.assign({}, base, this.state || {});
    const fmt = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    const have = (who, name) => MINE.indexOf(name) >= 0 || !!(st.took[who] && st.took[who][name]);
    const fresh = (i) => F[i].spots.filter((s) => s && CAT[s].kind === 'grow' && !have(i, s)).length;
    // a visit: your Doum lands on the sand beside his Doum with a little hop, then goes where you tap
    const visit = (i) => {
      if (this._in) clearTimeout(this._in);
      this.setState(Object.assign({}, st, { view: 'visit', who: i, sel: null, walk: [212, 302], dir: 'front', flip: false, walking: false, landing: true,
        sit: '', seatZ: 0, say: '', action: '', done: '', n: (st.n || 0) + 1 }));
      this._in = setTimeout(() => this.setState({ landing: false }), 340);
    };
    const go = {};
    F.forEach((f, i) => { go['v' + i] = () => visit(i); });
    const rows = {};
    F.forEach((f, i) => { const n = fresh(i); rows['r' + i] = { chip: n === 1 ? 'عنده نبتة ما عندك' : n === 2 ? 'عنده نبتتين ما عندك' : n ? 'عنده ' + n + ' نباتات ما عندك' : '', hasChip: n > 0 }; });
    const f = F[st.who];
    // what a tap on each of their things says, and what it lets you do
    const about = (name) => {
      const c = CAT[name];
      if (c.kind === 'grow') {
        const story = (c.f ? 'نبتت' : 'نبت') + ' عنده في المستوى ' + (GROW_LV[name] || 10);
        if (have(st.who, name)) return { story: st.done === name ? (c.f ? 'صارت عندك. تلقاها' : 'صار عندك. تلقاه') + ' في رتّب، باسم ' + f.name : story + (c.f ? '. وعندك منها' : '. وعندك منه'), cut: false };
        return { story, cut: true, btn: name === 'palm' ? 'خذ فسيلة' : 'خذ شتلة' };
      }
      const build = (c.f ? 'تبنيها' : 'تبنيه') + ' بـ ' + fmt(c.price) + ' ذهب';
      if (c.opens > __LEVEL__) return { story: (c.f ? 'تفتح' : 'يفتح') + ' لك في المستوى ' + c.opens + '، و' + build, cut: false };
      return { story: build, cut: false };
    };
    const tp = {};
    f.spots.forEach((s, i) => {
      tp['has' + i] = !!s; tp['n' + i] = s ? CAT[s].ar : '';
      tp['k' + i] = () => {
        if (!s) return;
        if (s === 'bench') { this.sitOn(st, SPOTS[i], { sel: i, poke: -1, done: '' }, 'قعدة حلوة'); return; }
        this.go(st, STAND[i], { sel: i, poke: i, n: st.n + 1, done: '' });
      };
    });
    tp.kpalm = () => this.go(st, this.standAt('palm'), { sel: 'palm', poke: 'palm', n: st.n + 1, done: '' });
__GROUND__
    const selName = st.sel === 'palm' ? 'palm_tall' : st.sel != null ? f.spots[st.sel] : '';
    let card = { has: false, name: '', story: '', cut: false, btn: '' };
    if (st.sel === 'palm') card = { has: true, name: 'نخلة ' + f.name, story: 'تكبر مع مستواه، وتمرها من أوسمته', cut: false, btn: '' };
    else if (selName) card = Object.assign({ has: true, name: CAT[selName].ar, btn: '' }, about(selName));
    const take = () => {
      if (!card.cut || st.action) return;
      const name = selName;
      this.doAct('cutting', '', 2200, { action: '', say: 'صارت عندك' }, SPOTS[st.sel][0]);
      setTimeout(() => {
        const took = Object.assign({}, st.took); took[st.who] = Object.assign({}, took[st.who] || {}); took[st.who][name] = true;
        this.setState({ took, done: name });
      }, 1000);
      setTimeout(() => this.setState({ say: '' }), 4200);
    };
    const w = st.view === 'visit' ? this.island({ level: f.level, medals: f.medals, pearls: f.pearls, thirst: 0, quietStyle: 'quiet', sky: 'day',
      fresh: -1, sel: typeof st.sel === 'number' ? st.sel : -1, pose: 'auto', colors: __COLORS__, frame: 'rect', detail: 'full', size: __PS__,
      spots: f.spots, guestWalks: true, guestName: 'دومك', doumState: this.doumState(st),
      walkTo: st.walk, walkDur: st.dur, poke: st.poke, pokeN: st.n,
      say: st.say, sayAt: [Math.min(250, Math.max(110, st.walk[0])), st.sit ? st.walk[1] - 70 : st.walk[1] - 86] }) : this.island({ level: 1, colors: __COLORS__, size: 10, spots: ['', '', '', '', '', ''], detail: 'glance' });
    return { w, tp, go, ground, rows, card, take, f,
      isOff: st.view === 'off', isList: st.view === 'list', isVisit: st.view === 'visit',
      turnOn: () => this.setState(Object.assign({}, st, { view: 'list' })),
      turnOff: () => this.setState(Object.assign({}, st, { view: 'off' })),
      toList: () => this.setState(Object.assign({}, base, { view: 'list', took: st.took })),
      hint: !card.has, cutBtn: card.has && card.cut, cutLabel: card.btn || '', busy: !!st.action,
      lv: 'المستوى ' + f.level };
  }
}
"""
friends_js = fill(FRIENDS_JS, FRIENDS=fr_js, CAT=cat_js, GROWLV=json.dumps(GROW_LV), MINE=json.dumps(MY_PLANTS),
                  STAND=json.dumps(FRONT_STAND), SPOTS=json.dumps([list(s) for s in ic.SPOTS]))


def mini(lv, md, pr, spots, size=76):
    h = round(size * 400 / 360)
    return (f'<div style="width: {size}px; height: {h}px; flex-shrink: 0; margin: -8px 0;">'
            f'<dc-import name="Island" detail="glance" frame="none" pose="none" level="{lv}" medals="{md}" pearls="{pr}" spots="{",".join(spots)}" size="{size}" hint-size="{size}px,{h}px"></dc-import></div>')


people = [(n, lv, md, pr, sp, i) for i, (n, lv, md, pr, sp) in enumerate(FRIENDS)] + [('أنت', LEVEL, 9, 2, START, -1)]
people.sort(key=lambda p: -p[1])
list_rows = ''
for n, lv, md, pr, sp, i in people:
    inner = (f'{mini(lv, md, pr, sp)}<div style="display: flex; flex-direction: column; gap: 2px; flex: 1; text-align: right;">'
             f'<div style="font-size: 17px; font-weight: 700;">{n}</div><div style="font-size: 14px; color: #45574B;">المستوى {lv}</div></div>')
    if i < 0:
        list_rows += (f'<a href="Oasis.dc.html" style="display: flex; align-items: center; gap: 12px; background: #EEF6EC; border-radius: 18px; padding: 8px 12px; text-decoration: none; color: inherit; min-height: 72px;">{inner}'
                      '<span style="font-size: 13px; font-weight: 700; color: #2F6B3A;">واحتك</span></a>')
    else:
        list_rows += (f'<button type="button" onClick="{{{{go.v{i}}}}}" style="font-family: inherit; color: inherit; display: flex; align-items: center; gap: 12px; background: #FFFFFF; border: 0; border-radius: 18px; padding: 8px 12px; cursor: pointer; min-height: 72px; text-align: right;">{inner}'
                      f'<sc-if value="{{{{rows.r{i}.hasChip}}}}" hint-placeholder-val="{{{{false}}}}"><span style="display: flex; align-items: center; gap: 4px; font-size: 12px; font-weight: 700; color: #2F6B3A; background: #EEF6EC; border-radius: 999px; padding: 5px 9px; white-space: nowrap;">{LEAF.replace("18", "14")}{{{{rows.r{i}.chip}}}}</span></sc-if></button>')

trio = ''.join(f'<div style="position: absolute; left: {x}px; top: {y}px;">{mini(lv, 3, 1, sp, sz)}</div>'
               for x, y, lv, sp, sz in [(6, 22, 31, ['lemon', 'coral_house', 'palm', '', '', ''], 104), (108, 0, 52, ['sidr', 'coral_house', 'vine', '', '', ''], 128), (226, 26, 15, ['flowers', 'house', '', '', '', ''], 94)])
friends = HEAD.format(title='Friends', style=ic.STYLE) + f"""<div dir="rtl" style="{PHONE} padding: 48px 16px 0; display: flex; flex-direction: column; gap: 12px;">
<sc-if value="{{{{isOff}}}}" hint-placeholder-val="{{{{true}}}}">
{top_bar('أصحابك', 'Oasis.dc.html')}
<div style="background: #FFFFFF; border-radius: 26px; padding: 18px 18px 20px; display: flex; flex-direction: column; gap: 14px;">
<div style="position: relative; height: 150px; border-radius: 18px; background: #DDF0F1; overflow: hidden;">{trio}</div>
<div style="font-size: 20px; font-weight: 700;">واحات أصحابك</div>
<div style="display: flex; flex-direction: column; gap: 10px; font-size: 15px; line-height: 1.55; color: #33463A;">
<div>تشوف واحات اللي معك في الغرف، وتعرف وين وصلوا.</div>
<div>وتاخذ شتلة من أي نبتة عندهم وما عندك، وتكبر عندك باسمهم.</div>
<div>وهم يشوفون واحتك بنفس الطريقة. ما أحد يشوف عادات أحد، وما فيه تنبيهات.</div>
</div>
<button type="button" onClick="{{{{turnOn}}}}" style="{PRIMARY}">شغّلها</button>
<a href="Oasis.dc.html" style="{BTN} color: #45574B; background: transparent; min-height: 44px; font-size: 15px;">مو الحين</a>
</div>
</sc-if>
<sc-if value="{{{{isList}}}}" hint-placeholder-val="{{{{false}}}}">
{top_bar('أصحابك', 'Oasis.dc.html')}
<div style="font-size: 14px; color: #45574B; margin-top: -4px;">من غرفك، الأعلى مستوى أول.</div>
<div style="display: flex; flex-direction: column; gap: 8px;">{list_rows}</div>
<div style="flex: 1;"></div>
<div style="display: flex; align-items: center; justify-content: space-between; gap: 10px; background: #FFFFFF; border-radius: 18px; padding: 12px 14px; margin-bottom: 34px;">
<div style="display: flex; flex-direction: column; gap: 2px;"><div style="font-size: 15px; font-weight: 700;">أظهر واحتي لأصحابي</div><div style="font-size: 13px; color: #6B7A6F;">لو طفيتها، ما تشوفهم ولا يشوفونك</div></div>
<button type="button" role="switch" aria-checked="true" onClick="{{{{turnOff}}}}" aria-label="أظهر واحتي لأصحابي" style="width: 52px; height: 32px; border-radius: 99px; border: 0; background: #3F9A4E; position: relative; cursor: pointer; flex-shrink: 0;"><span style="position: absolute; top: 3px; left: 3px; width: 26px; height: 26px; border-radius: 99px; background: #FFFFFF;"></span></button>
</div>
</sc-if>
<sc-if value="{{{{isVisit}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="display: flex; align-items: center; justify-content: space-between; gap: 10px; min-height: 44px;">
<div style="display: flex; align-items: center; gap: 10px;">
<button type="button" onClick="{{{{toList}}}}" aria-label="رجوع" style="width: 40px; height: 40px; border-radius: 999px; border: 0; background: #FFFFFF; display: flex; align-items: center; justify-content: center; cursor: pointer;">{BACK}</button>
<h1 style="margin: 0; font-size: 24px; font-weight: 700;">واحة {{{{f.name}}}}</h1></div>
<div style="font-size: 14px; font-weight: 700; background: #FFFFFF; border-radius: 999px; padding: 7px 12px;">{{{{lv}}}}</div>
</div>
{island_box(thing_taps())}
<sc-if value="{{{{hint}}}}" hint-placeholder-val="{{{{true}}}}">
<div style="background: #FFFFFF; border-radius: 22px; padding: 14px 16px; display: flex; flex-direction: column; gap: 4px;">
<div style="font-size: 17px; font-weight: 700;">اضغط أي شي تشوفه</div>
<div style="font-size: 14px; color: #45574B; line-height: 1.5;">النباتات اللي ما عندك، تاخذ منها شتلة لواحتك.</div>
</div>
</sc-if>
<sc-if value="{{{{card.has}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="background: #FFFFFF; border-radius: 22px; padding: 14px 16px; display: flex; flex-direction: column; gap: 10px;">
<div style="display: flex; flex-direction: column; gap: 2px;">
<div style="font-size: 18px; font-weight: 700;">{{{{card.name}}}}</div>
<div style="font-size: 14px; color: #45574B; line-height: 1.5;">{{{{card.story}}}}</div>
</div>
<sc-if value="{{{{cutBtn}}}}" hint-placeholder-val="{{{{false}}}}"><button type="button" onClick="{{{{take}}}}" style="{PRIMARY}">{{{{cutLabel}}}}</button></sc-if>
</div>
</sc-if>
</sc-if>
</div>
""" + tail(friends_js)
write('Friends.dc.html', friends)
