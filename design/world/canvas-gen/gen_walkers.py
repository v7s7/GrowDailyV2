"""Generates Walk.dc.html (visiting Khalid, close camera) and Play.dc.html (your own island).

Both run the same little engine: tap the ground or a thing, Doum turns to the
way he goes and walks there with the walk cycle for that direction, lands,
then does what the thing invites (pick a date, take a cutting, water, sit,
push the door) with the action frames from Sheet 10, and says one line.
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic
from gen_together import HEAD, TAIL, PHONE, BACK, HEART, write
COLORS = "{ sky: '#DDF0F1', grass: '#93CC62', sea: '#86CBE6', sand: '#F1D9A4' }"
NAMES = dict((it[0], it[1]) for it in ic.ITEMS)

# the walking engine now lives in island_core (shared with the simple boards)
ENGINE = ic.ENGINE_JS


def taps_markup(spots, u, extra_buttons=''):
    t = (f'<button type="button" onClick="{{{{ground}}}}" aria-label="امشِ هنا" style="position: absolute; left: {48 * u:.0f}px; top: {200 * u:.0f}px; width: {264 * u:.0f}px; height: {120 * u:.0f}px; border: 0; background: transparent; padding: 0; cursor: pointer;"></button>')
    for i, (x, y, k) in enumerate(ic.SPOTS):
        if not spots[i]:
            continue
        t += (f'<button type="button" onClick="{{{{tp.k{i}}}}}" aria-label="{NAMES.get(spots[i], "")}" style="position: absolute; left: {x * u:.0f}px; top: {(y - 36) * u:.0f}px; transform: translate(-50%, -50%); width: {64 * u:.0f}px; height: {68 * u:.0f}px; border: 0; background: transparent; padding: 0; cursor: pointer;"></button>')
    t += (f'<button type="button" onClick="{{{{tp.kpalm}}}}" aria-label="النخلة" style="position: absolute; left: {196 * u:.0f}px; top: {150 * u:.0f}px; transform: translate(-50%, -50%); width: {80 * u:.0f}px; height: {140 * u:.0f}px; border: 0; background: transparent; padding: 0; cursor: pointer;"></button>')
    return t + extra_buttons


# ================================================================ Walk: a visit
S = 760
U = S / 360
KHALID = ['pomegranate', 'coral_house', 'jasmine', 'well', 'lantern_arch', 'bench']
# key: name, story, kind, button, result, takes home, line, stand point
W_INFO = {
    '0': ('رمان', 'نبت عند خالد في المستوى 16، 9 أغسطس', 'cutting', 'خذ عقلة', 'عقلة رمان من خالد صارت في مجموعتك', 'رمان خالد', 'بزرعها عندنا', list(ic.STANDS[0])),
    '1': ('بيت مرجان', 'بناه خالد في المستوى 20، 21 أغسطس', 'house', 'ادخل', '', '', 'ندخل؟', list(ic.STANDS[1])),
    '2': ('فل', 'نبت عنده في المستوى 9، 2 يوليو', 'cutting', 'خذ عقلة', 'عقلة فل من خالد صارت في مجموعتك', 'فل خالد', 'ريحته حلوة', list(ic.STANDS[2])),
    '3': ('بئر', 'بناها خالد في المستوى 8', 'fill', 'عبّ رشاشتك', 'عبّيت رشاشتك من بئر خالد', '', 'عبّيتها', list(ic.STANDS[3])),
    '4': ('قوس فوانيس', 'بناه في المستوى 24، 12 سبتمبر', 'light', 'شغّل الأنوار', 'شفت أنوار خالد', '', 'شوف الأنوار', list(ic.STANDS[4])),
    '5': ('كرسي', 'بناه في المستوى 6', 'seat', 'اجلس', 'قعدت شوي عند خالد', '', 'قعدة حلوة', list(ic.STANDS[5])),
    'palm': ('نخلة خالد', '11 وسام، وتمرها صار رطب', 'dates', 'قطّف رطبة', 'رطبة من نخلة خالد صارت في مجموعتك. تمر الجيران: 3 من 5', 'رطبة خالد', 'رطبة، يا حلوها', list(ic.STANDS['palm'])),
}
w_info_js = json.dumps({k: dict(name=v[0], story=v[1], kind=v[2], act=v[3], result=v[4], takes=v[5], say=v[6], stand=v[7],
                                 spot=(int(k) if k.isdigit() else 'palm')) for k, v in W_INFO.items()}, ensure_ascii=False)

WALK_JS = r"""
class Component extends DCLogic {
__ISLAND__
__ENGINE__
  renderVals() {
    const INFO = __INFO__;
    const U = 760 / 360;
    const SPOTX = __SPOTX__;
    const tx = (it) => (typeof it.spot === 'number' ? SPOTX[it.spot] : 196);
    const demo = this.props.demo === 'palm' ? { sel: 'palm', walk: [224, 262], action: 'dates', say: 'رطبة، يا حلوها', done: { palm: true }, took: { palm: 'رطبة خالد', '2': 'فل خالد' }, arrived: false } : {};
    const st = Object.assign({ sel: null, walk: [112, 306], dir: 'front', flip: false, walking: false, landing: false, carry: false, action: '', say: '',
      poke: -1, n: 0, took: {}, done: {}, watered: false, rain: false, gift: '', liked: false, night: false, photo: false, arrived: true, dur: 0.9 }, demo, this.state || {});
    const set = (p) => this.setState(Object.assign({}, st, p));
    const tp = {};
    Object.keys(INFO).forEach((k) => {
      const it = INFO[k];
      tp['k' + k] = () => this.go(st, it.stand, { sel: k, poke: it.spot, n: st.n + 1, arrived: false }, () => {
        if (it.kind === 'house') this.doAct('door', it.say, 99999, { say: '' }, tx(it));
        else this.setState({ say: '' });
      });
    });
    const ground = (e) => {
      const ox = e && (e.offsetX != null ? e.offsetX : e.nativeEvent && e.nativeEvent.offsetX);
      const oy = e && (e.offsetY != null ? e.offsetY : e.nativeEvent && e.nativeEvent.offsetY);
      if (ox == null || oy == null) return;
      let x = 48 + ox / U, y = 200 + oy / U;
      const dx = (x - 180) / 132, dy = (y - 255) / 50, r = Math.hypot(dx, dy);
      if (r > 0.95) { x = 180 + dx / r * 0.95 * 132; y = 255 + dy / r * 0.95 * 50; }
      this.go(st, [x, y], { sel: null, poke: -1, arrived: false });
    };
    const sel = st.sel ? INFO[st.sel] : null;
    const done = sel && st.done[st.sel];
    const ACTS = { dates: 'dates', cutting: 'cutting', water: 'water', fill: 'fill' };
    const act = () => {
      if (!sel || done) return;
      const d = Object.assign({}, st.done); d[st.sel] = true;
      const took = Object.assign({}, st.took);
      if (sel.takes) took[st.sel] = sel.takes;
      this.setState({ done: d, took });
      if (sel.kind === 'light') {
        this.setState({ night: true, say: sel.say });
        if (this._a) clearTimeout(this._a);
        this._a = setTimeout(() => this.setState({ night: false, say: '' }), 4500);
      } else if (sel.kind === 'seat') {
        // he hops onto his bench and sits until you tap somewhere else
        this.sitOn(Object.assign({}, st, { done: d, took }), __BENCH__, {}, sel.say);
      } else {
        this.doAct(ACTS[sel.kind], sel.say, 3400, null, tx(sel));
      }
    };
    const giveGift = () => {
      if (st.gift) return;
      this.go(st, [292, 278], { sel: null, poke: -1, arrived: false }, () => {
        this.doAct('put', 'هذه لك يا خالد', 700, { action: '', say: 'هذه لك يا خالد', gift: 'harvest_basket' });
        setTimeout(() => this.setState({ say: '' }), 2600);
      }, true);
    };
    const photoOn = () => {
      this.doAct('camera', '', 900, { action: '', photo: true });
    };
    const gifts = [{ name: 'palm_offshoot', from: 'أحمد' }].concat(st.gift ? [{ name: st.gift, from: 'أنت' }] : []);
    const w = this.island({ level: 31, medals: 11, pearls: 3, thirst: 0, quietStyle: 'quiet', sky: st.night ? 'night' : 'day',
      watering: st.rain, fresh: -1, pose: 'auto', colors: __COLORS__, frame: 'rect', detail: 'full', size: 760,
      spots: __SPOTS__, gifts, guestWalks: true, guestName: 'دومك',
      doumState: this.doumState(st),
      walkTo: st.walk, walkDur: st.dur, poke: st.poke, pokeN: st.n,
      sel: sel && typeof sel.spot === 'number' ? sel.spot : -1,
      say: st.say, sayAt: [Math.min(300, Math.max(70, st.walk[0])), st.walk[1] - (st.sit ? 78 : 96)] });
    const camX = -Math.max(0, Math.min(760 - 390, st.walk[0] * U - 195));
    const camY = -Math.max(0, Math.min(844 - 560, st.walk[1] * U - 400));
    const tookList = Object.keys(st.took).map((k) => ({ t: st.took[k] }));
    return {
      w, tp, ground, cam: { x: camX, y: camY, d: (st.dur || 0.9) + 0.15 },
      hasSel: !!sel && !st.photo, noSel: !sel && !st.photo,
      s: sel ? Object.assign({}, sel, { isLink: sel.kind === 'house', isBtn: sel.kind !== 'house',
        btnLabel: done ? (sel.takes ? 'أخذتها اليوم' : 'تم') : sel.act,
        btnBg: done ? '#EEF6EC' : '#2F7A3A', btnFg: done ? '#2F6B3A' : '#FFFFFF', line: done && sel.result ? sel.result : sel.story })
        : { name: '', line: '', act: '', isBtn: false, isLink: false, btnLabel: '', btnBg: '#2F7A3A', btnFg: '#FFFFFF' },
      act, unsel: () => this.go(st, st.walk, { sel: null, action: '', say: '' }),
      arrived: st.arrived,
      water: () => { if (st.watered) return; if (this._r) clearTimeout(this._r); set({ watered: true, rain: true }); this._r = setTimeout(() => this.setState({ rain: false }), 2600); },
      waterLabel: st.watered ? 'سقيتها' : 'اسقِ', waterBg: st.watered ? '#EEF6EC' : '#2F7A3A', waterFg: st.watered ? '#2F6B3A' : '#FFFFFF',
      giveGift, giftLabel: st.gift ? 'تركت سلة' : 'هدية',
      like: () => set({ liked: !st.liked }), likeCount: 14 + (st.liked ? 1 : 0), likeFill: st.liked ? '#F06292' : 'none',
      photoOn, photoOff: () => set({ photo: false }), photo: st.photo,
      took: tookList, noTook: tookList.length === 0
    };
  }
}
"""
walk_js = (WALK_JS.replace('__SPOTX__', json.dumps([x for x, y, k in ic.SPOTS])).replace('__ISLAND__', ic.island_js()).replace('__ENGINE__', ENGINE).replace('__INFO__', w_info_js)
           .replace('__COLORS__', COLORS).replace('__SPOTS__', json.dumps(KHALID)).replace('__BENCH__', json.dumps(list(ic.SPOTS[5]))))
VIEW_H = 560
CAM_BTN = '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#23352A" stroke-width="2" stroke-linejoin="round"><path d="M4 8h3l2-3h6l2 3h3v11H4z"></path><circle cx="12" cy="13" r="3.6"></circle></svg>'
walk = HEAD.format(title='Walk a visit', style=ic.STYLE + '@keyframes wk-in{0%{transform:translate(-50%,-12px);opacity:0}100%{transform:translate(-50%,0);opacity:1}}.wk-in{animation:wk-in .5s ease-out}@keyframes wk-flash{0%{opacity:.9}100%{opacity:0}}.wk-flash{animation:wk-flash .6s ease-out forwards}@media (prefers-reduced-motion: reduce){.wk-in,.wk-flash{animation:none}.wk-flash{opacity:0}}') + f"""<div dir="rtl" style="{PHONE}">
<div dir="ltr" style="position: absolute; left: 0; top: 0; width: 390px; height: {VIEW_H}px; overflow: hidden; background: #DDF0F1;">
<div style="position: absolute; left: 0; top: 0; width: {S}px; height: 844px; transform: translate({{{{cam.x}}}}px, {{{{cam.y}}}}px); transition: transform {{{{cam.d}}}}s cubic-bezier(.4,.1,.4,1);">
{ic.scene('w.')}
{taps_markup(KHALID, U)}
</div>
</div>
<div style="position: absolute; top: 48px; left: 8px; right: 8px; display: flex; align-items: center; justify-content: space-between;">
<a href="Neighbours.dc.html" aria-label="رجوع لجيرانك" style="width: 44px; height: 44px; border-radius: 999px; background: rgba(255,255,255,0.9); display: flex; align-items: center; justify-content: center;">{BACK}</a>
<div style="font-size: 17px; font-weight: 700; background: rgba(255,255,255,0.9); padding: 8px 16px; border-radius: 999px;">واحة خالد · 31</div>
<button type="button" onClick="{{{{photoOn}}}}" aria-label="صوّر" style="width: 44px; height: 44px; border-radius: 999px; border: 0; background: rgba(255,255,255,0.9); display: flex; align-items: center; justify-content: center; cursor: pointer;">{CAM_BTN}</button>
</div>
<sc-if value="{{{{arrived}}}}" hint-placeholder-val="{{{{true}}}}">
<div class="wk-in" style="position: absolute; top: 104px; left: 50%; transform: translateX(-50%); background: #23352A; color: #F5F0E1; font-size: 14px; font-weight: 600; padding: 8px 14px; border-radius: 999px; white-space: nowrap;">وصلت. اضغط الأرض أو أي شي</div>
</sc-if>
<div style="position: absolute; left: 0; right: 0; top: {VIEW_H - 18}px; bottom: 0; background: #F5F0E1; border-radius: 22px 22px 0 0; padding: 14px 16px 0; display: flex; flex-direction: column; gap: 10px;">
<sc-if value="{{{{noSel}}}}" hint-placeholder-val="{{{{true}}}}">
<div style="display: flex; flex-direction: column; gap: 2px;">
<div style="font-size: 17px; font-weight: 700;">تمشّى في واحة خالد</div>
<div style="font-size: 14px; color: #45574B;">كل شي هنا يسوي شي. وتقدر تاخذ معك رطبة وعقلة.</div>
</div>
<div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px;">
<button type="button" onClick="{{{{water}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: {{{{waterFg}}}}; background: {{{{waterBg}}}}; border: 0; border-radius: 14px; min-height: 46px; cursor: pointer;">{{{{waterLabel}}}}</button>
<button type="button" onClick="{{{{giveGift}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #6B4E00; background: #FFF3C4; border: 0; border-radius: 14px; min-height: 46px; cursor: pointer;">{{{{giftLabel}}}}</button>
<button type="button" onClick="{{{{like}}}}" aria-label="أعجبتني" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #C2416B; background: #FDECF1; border: 0; border-radius: 14px; min-height: 46px; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 6px;">{HEART.format(fill="{{likeFill}}")}{{{{likeCount}}}}</button>
</div>
</sc-if>
<sc-if value="{{{{hasSel}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 8px;">
<div style="display: flex; flex-direction: column; gap: 2px;">
<div style="font-size: 18px; font-weight: 700;">{{{{s.name}}}}</div>
<div style="font-size: 14px; color: #45574B; line-height: 1.5;">{{{{s.line}}}}</div>
</div>
<button type="button" onClick="{{{{unsel}}}}" style="font-family: inherit; font-size: 14px; font-weight: 600; color: #45574B; background: transparent; border: 0; min-height: 40px; padding: 0 4px; cursor: pointer; flex-shrink: 0;">رجوع</button>
</div>
<sc-if value="{{{{s.isBtn}}}}" hint-placeholder-val="{{{{true}}}}">
<button type="button" onClick="{{{{act}}}}" style="font-family: inherit; font-size: 16px; font-weight: 700; color: {{{{s.btnFg}}}}; background: {{{{s.btnBg}}}}; border: 0; border-radius: 14px; min-height: 48px; cursor: pointer;">{{{{s.btnLabel}}}}</button>
</sc-if>
<sc-if value="{{{{s.isLink}}}}" hint-placeholder-val="{{{{false}}}}">
<a href="Inside.dc.html" style="font-size: 16px; font-weight: 700; color: #FFFFFF; background: #2F7A3A; border-radius: 14px; min-height: 48px; display: flex; align-items: center; justify-content: center; text-decoration: none;">{{{{s.act}}}}</a>
</sc-if>
</sc-if>
<div style="background: #FFFFFF; border-radius: 16px; padding: 10px 12px; display: flex; flex-wrap: wrap; align-items: center; gap: 6px; font-size: 13px;">
<span style="font-weight: 700;">معك للبيت:</span>
<sc-if value="{{{{noTook}}}}" hint-placeholder-val="{{{{true}}}}"><span style="color: #6B7A6F;">ولا شي بعد. جرّب النخلة أو الفل</span></sc-if>
<sc-for list="{{{{took}}}}" as="t" hint-placeholder-count="0"><span style="background: #EEF6EC; color: #2F6B3A; font-weight: 600; border-radius: 999px; padding: 3px 10px;">{{{{t.t}}}}</span></sc-for>
</div>
</div>
<sc-if value="{{{{photo}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="position: absolute; inset: 0; background: rgba(20,32,26,0.86); display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px;">
<div class="wk-flash" style="position: absolute; inset: 0; background: #FFFFFF; pointer-events: none;"></div>
<div style="background: #FFFFFF; padding: 12px 12px 16px; border-radius: 6px; transform: rotate(-2deg); display: flex; flex-direction: column; gap: 10px; align-items: center; box-shadow: 0 10px 30px rgba(0,0,0,0.35);">
<div style="width: 290px; height: 322px; overflow: hidden;"><dc-import name="Island" frame="rect" level="31" medals="11" pearls="3" spots="pomegranate,coral_house,jasmine,well,lantern_arch,bench" guest="true" guest-name="دومك" size="290" hint-size="290px,322px"></dc-import></div>
<div style="font-size: 16px; font-weight: 700; color: #23352A;">واحة خالد · 3 أكتوبر</div>
</div>
<div style="display: flex; gap: 10px;">
<button type="button" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #23352A; background: #FFFFFF; border: 0; border-radius: 14px; min-height: 46px; padding: 0 22px; cursor: pointer;">احفظ</button>
<button type="button" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #23352A; background: #FFFFFF; border: 0; border-radius: 14px; min-height: 46px; padding: 0 22px; cursor: pointer;">شارك</button>
<button type="button" onClick="{{{{photoOff}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #FFFFFF; background: transparent; border: 2px solid #FFFFFF; border-radius: 14px; min-height: 46px; padding: 0 22px; cursor: pointer;">رجوع</button>
</div>
</div>
</sc-if>
</div>
""" + TAIL.format(js=walk_js)
write('Walk.dc.html', walk)


# ================================================================ Play: your own island
PS = 358
PU = PS / 360
MINE = ['lemon', 'house', 'jasmine', 'well', 'rose', 'vegetables']
MINE_START = ['lemon', 'house', 'jasmine', 'well', 'rose', '']   # the front right place waits for the next level
P_INFO = {
    'palm': ('النخلة نبتت يوم بديت. قطّفت رطبة', 'dates', list(ic.STANDS['palm'])),
    '0': ('الليمون نبت في المستوى 7. سقيته', 'water', list(ic.STANDS[0])),
    '1': ('بيتي. ندخل؟', 'house', list(ic.STANDS[1])),
    '2': ('الفل نبت في المستوى 9. سقيته', 'water', list(ic.STANDS[2])),
    '3': ('البئر بنيتها بـ250 ذهب', 'look', list(ic.STANDS[3])),
    '4': ('الورد نبت في المستوى 13. سقيته', 'water', list(ic.STANDS[4])),
    '5': ('الخضار نبتت في المستوى 17. سقيتها', 'water', list(ic.STANDS[5])),
    'g0': ('هذه الفسيلة من خالد، أمس', 'look', [84, 284]),
    'g1': ('هذه المحارة من يوسف، اليوم', 'look', [280, 290]),
}
p_info_js = json.dumps({k: dict(say=v[0], kind=v[1], stand=v[2], spot=(int(k) if k.isdigit() else ('palm' if k == 'palm' else -1))) for k, v in P_INFO.items()}, ensure_ascii=False)
gift_btns = ''.join(
    f'<button type="button" onClick="{{{{tp.kg{j}}}}}" aria-label="هدية" style="position: absolute; left: {gx * PU:.0f}px; top: {(gy - 14) * PU:.0f}px; transform: translate(-50%, -50%); width: 44px; height: 44px; border: 0; background: transparent; padding: 0; cursor: pointer;"></button>'
    for j, (gx, gy) in enumerate([(58, 270), (300, 274)]))

PLAY_JS = r"""
class Component extends DCLogic {
__ISLAND__
__ENGINE__
  renderVals() {
    const INFO = __INFO__;
    const U = 358 / 360;
    const SPOTS = __SPOTSXY__;
    const tx = (it) => (typeof it.spot === 'number' && it.spot >= 0 ? SPOTS[it.spot][0] : it.spot === 'palm' ? 196 : null);
    const demo = this.props.demo === 'lemon' ? { walk: [140, 248], action: 'water', say: INFO['0'].say, poke: 0, n: 1 } : {};
    const st = Object.assign({ walk: [168, 300], dir: 'front', flip: false, walking: false, landing: false, carry: false, action: '', say: '', sel: null,
      poke: -1, n: 0, night: false, book: false, dur: 0.9, grown: false, growing: false, level: 24 }, demo, this.state || {});
    // the level-up moment: Doum walks to the empty place and plants; the new thing grows in
    const levelUp = () => {
      if (st.grown) return;
      this.go(st, this.plantStand(5), { sel: null, poke: -1 }, () => {
        this.doAct('plant', '', 1300, { action: '', grown: true, growing: true, level: 25, say: 'نبتت الخضار. المستوى 25' }, SPOTS[5][0]);
        setTimeout(() => this.setState({ growing: false }), 2400);
        setTimeout(() => this.setState({ say: '' }), 3800);
      });
    };
    const tp = {};
    Object.keys(INFO).forEach((k) => {
      const it = INFO[k];
      tp['k' + k] = () => this.go(st, it.stand, { sel: k, poke: it.spot, n: st.n + 1 }, () => {
        if (it.kind === 'dates') this.doAct('dates', it.say, 3400, null, tx(it));
        else if (it.kind === 'water') this.doAct('water', it.say, 3400, null, tx(it));
        else if (it.kind === 'house') this.doAct('door', it.say, 99999, { say: '' }, tx(it));
        else this.doAct('', it.say, 3000);
      });
    });
    const ground = (e) => {
      const ox = e && (e.offsetX != null ? e.offsetX : e.nativeEvent && e.nativeEvent.offsetX);
      const oy = e && (e.offsetY != null ? e.offsetY : e.nativeEvent && e.nativeEvent.offsetY);
      if (ox == null || oy == null) return;
      let x = 48 + ox / U, y = 200 + oy / U;
      const dx = (x - 180) / 132, dy = (y - 255) / 50, r = Math.hypot(dx, dy);
      if (r > 0.95) { x = 180 + dx / r * 0.95 * 132; y = 255 + dy / r * 0.95 * 50; }
      this.go(st, [x, y], { sel: null, poke: -1 });
    };
    const w = this.island({ level: st.level, medals: 9, pearls: 2, thirst: 0, quietStyle: 'quiet', sky: st.night ? 'night' : 'day',
      watering: false, fresh: st.growing ? 5 : -1, sel: -1, pose: 'auto', colors: __COLORS__, frame: 'rect', detail: 'full', size: 358,
      spots: st.grown ? __SPOTS__ : __START__, growIn: st.growing ? 5 : -1,
      gifts: [{ name: 'palm_offshoot', from: 'خالد' }, { name: 'shell_pearl', from: 'يوسف' }],
      doumState: this.doumState(st),
      poke: typeof st.poke === 'number' || st.poke === 'palm' ? st.poke : -1, pokeN: st.n, walkTo: st.walk, walkDur: st.dur,
      say: st.say, sayAt: [Math.min(250, Math.max(110, st.walk[0])), st.walk[1] - 92] });
    const house = st.sel === '1';
    return { w, tp, ground, house, notHouse: !house, levelUp, lv: st.level, canGrow: !st.grown, grownNote: st.grown,
      toggleNight: () => this.setState(Object.assign({}, st, { night: !st.night, say: '' })), dayLabel: st.night ? 'نهار' : 'ليل',
      toggleBook: () => this.setState(Object.assign({}, st, { book: !st.book })), bookOpen: st.book, bookClosed: !st.book };
  }
}
"""
play_js = (PLAY_JS.replace('__SPOTSXY__', json.dumps([list(sp) for sp in ic.SPOTS])).replace('__ISLAND__', ic.island_js()).replace('__ENGINE__', ENGINE).replace('__INFO__', p_info_js)
           .replace('__COLORS__', COLORS).replace('__SPOTS__', json.dumps(MINE)).replace('__START__', json.dumps(MINE_START)))
play = HEAD.format(title='Play on your island', style=ic.STYLE) + f"""<div dir="rtl" style="{PHONE} padding: 44px 16px 0; display: flex; flex-direction: column; gap: 8px;">
<div style="display: flex; align-items: flex-end; justify-content: space-between;">
<div style="display: flex; align-items: center; gap: 10px;">
<a href="PlanetPage.dc.html" aria-label="رجوع" style="width: 40px; height: 40px; border-radius: 999px; background: #FFFFFF; display: flex; align-items: center; justify-content: center;">{BACK}</a>
<div style="display: flex; flex-direction: column;">
<h1 style="margin: 0; font-size: 24px; font-weight: 700;">واحتك</h1>
<div style="font-size: 14px; color: #45574B;">اضغط الأرض أو أي شي، ودوم يروح له</div>
</div>
</div>
<button type="button" onClick="{{{{toggleBook}}}}" style="font-family: inherit; font-size: 13px; font-weight: 700; color: #6B5320; background: #FFF3C4; border: 0; border-radius: 999px; padding: 8px 12px; min-height: 36px; cursor: pointer;">زارك 3 اليوم</button>
</div>
<div style="position: relative; width: {PS}px; height: 398px; border-radius: 28px; overflow: hidden; flex-shrink: 0;">
<div dir="ltr" style="position: absolute; left: 0; top: 0; width: {PS}px; height: 398px;">
{ic.scene('w.')}
{taps_markup(MINE, PU, gift_btns)}
</div>
</div>
<sc-if value="{{{{bookOpen}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="background: #FFFFFF; border-radius: 22px; padding: 12px 14px; display: flex; flex-direction: column; gap: 6px;">
<div style="font-size: 15px; font-weight: 700;">زوارك اليوم</div>
<div style="display: flex; justify-content: space-between; font-size: 14px;"><span>خالد سقى واحتك وترك فسيلة</span><span style="color: #6B7A6F;">9:12</span></div>
<div style="display: flex; justify-content: space-between; font-size: 14px;"><span>يوسف ترك محارة</span><span style="color: #6B7A6F;">8:40</span></div>
<div style="display: flex; justify-content: space-between; font-size: 14px;"><span>أحمد أعجبته واحتك</span><span style="color: #6B7A6F;">7:05</span></div>
</div>
</sc-if>
<sc-if value="{{{{bookClosed}}}}" hint-placeholder-val="{{{{true}}}}">
<sc-if value="{{{{house}}}}" hint-placeholder-val="{{{{false}}}}">
<a href="Inside.dc.html" style="font-size: 16px; font-weight: 700; color: #FFFFFF; background: #2F7A3A; border-radius: 14px; min-height: 52px; display: flex; align-items: center; justify-content: center; text-decoration: none;">ادخل بيتك</a>
</sc-if>
<sc-if value="{{{{notHouse}}}}" hint-placeholder-val="{{{{true}}}}">
<div style="background: #FFFFFF; border-radius: 22px; padding: 12px 14px; display: flex; align-items: center; justify-content: space-between; gap: 10px;">
<div style="display: flex; flex-direction: column; gap: 2px;">
<div style="font-size: 15px; font-weight: 700;">المستوى {{{{lv}}}} · إطار ذهب</div>
<div style="font-size: 13px; color: #6B7A6F;">الجاي: قوس قزح في المستوى 35</div>
</div>
<sc-if value="{{{{canGrow}}}}" hint-placeholder-val="{{{{true}}}}">
<button type="button" onClick="{{{{levelUp}}}}" style="font-family: inherit; font-size: 13px; font-weight: 700; color: #6B4E00; background: #FFF3C4; border: 0; border-radius: 999px; min-height: 40px; padding: 0 12px; cursor: pointer; white-space: nowrap;">جرّب: مستوى جديد</button>
</sc-if>
</div>
</sc-if>
</sc-if>
<div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px;">
<a href="Builder.dc.html" style="font-size: 15px; font-weight: 700; color: #FFFFFF; background: #2F7A3A; border-radius: 14px; min-height: 48px; display: flex; align-items: center; justify-content: center; text-decoration: none;">رتّب</a>
<a href="Neighbours.dc.html" style="font-size: 15px; font-weight: 700; color: #23352A; background: #F3EEDF; border-radius: 14px; min-height: 48px; display: flex; align-items: center; justify-content: center; text-decoration: none;">جيرانك</a>
<button type="button" onClick="{{{{toggleNight}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #23352A; background: #F3EEDF; border: 0; border-radius: 14px; min-height: 48px; cursor: pointer;">{{{{dayLabel}}}}</button>
</div>
</div>
""" + TAIL.format(js=play_js)
write('Play.dc.html', play)
