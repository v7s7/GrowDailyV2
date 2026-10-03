"""Generates the "together" phones: Neighbours (map + visit), Play, Show, OasisPremium."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic
A = ic.ART
ARB = "'IBM Plex Sans Arabic', sans-serif"

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
TAIL = """</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":390,"height":844}}}}'>
{js}
</script>
</body>
</html>
"""
PHONE = f"width: 390px; height: 844px; box-sizing: border-box; background: #F5F0E1; color: #23352A; font-family: {ARB}; overflow: hidden; position: relative;"
BACK = '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#23352A" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 6 15 12 9 18"></polyline></svg>'
HEART = '<svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true" style="fill: {fill}; stroke: #C2416B; stroke-width: 2;"><path d="M12 21s-7.5-4.6-9.6-9.2C.9 8.4 3 5 6.5 5c2 0 3.6 1.1 4.5 2.6l1 1.6 1-1.6C13.9 6.1 15.5 5 17.5 5 21 5 23.1 8.4 21.6 11.8 19.5 16.4 12 21 12 21z"></path></svg>'


def write(name, html):
    with open(os.path.join(HERE, 'project', name), 'w') as fh:
        fh.write(html)
    print(name, len(html))


# ---------------------------------------------------------------- Neighbours
FRIENDS = [
    # name, level, medals, pearls, spots, gifts already there, likes, pennant, box x, box y, size
    ('خالد', 31, 11, 3, 'pomegranate,coral_house,jasmine,well,lantern_arch,rose', 'palm_offshoot:أحمد', 14, True, 6, 8, 154),
    ('يوسف', 52, 17, 5, 'sidr,coral_house,vine,falaj,fountain,pearl_chest', '', 9, False, 196, 0, 186),
    ('أحمد', 8, 2, 1, '', '', 3, False, 2, 206, 122),
    ('عبدالله', 15, 5, 2, '', 'shell_pearl:خالد', 5, False, 258, 214, 130),
]
ME = ('أنت', 24, 9, 2, 122, 368, 146)
MAP_TOP = 104

map_islands = ''
for i, (n, lv, md, pr, spots, gifts, likes, pen, x, y, sz) in enumerate(FRIENDS):
    h = round(sz * 400 / 360)
    map_islands += (
        f'<div style="position: absolute; left: {x}px; top: {y}px; width: {sz}px; height: {h}px;">'
        f'<dc-import name="Island" detail="glance" frame="none" pose="none" level="{lv}" medals="{md}" pearls="{pr}" spots="{spots}" pennant="{"true" if pen else "false"}" size="{sz}" hint-size="{sz}px,{h}px"></dc-import></div>'
        f'<button type="button" onClick="{{{{go.v{i}}}}}" aria-label="زيارة واحة {n}" style="position: absolute; left: {x}px; top: {y + h * 0.3:.0f}px; width: {sz}px; height: {h * 0.72:.0f}px; background: transparent; border: 0; padding: 0; cursor: pointer;"></button>'
        f'<div style="position: absolute; left: {x + sz / 2:.0f}px; top: {y + h - 4}px; transform: translateX(-50%); display: flex; align-items: center; gap: 6px; background: rgba(255,255,255,0.92); border-radius: 999px; padding: 3px 10px; font-size: 13px; font-weight: 700; white-space: nowrap; pointer-events: none;">'
        f'{n}<span style="display: inline-flex; align-items: center; gap: 2px; font-weight: 600; color: #C2416B; font-size: 12px;">{HEART.format(fill="#F7A8BE").replace("18", "13")}{{{{lk.c{i}}}}}</span></div>'
    )
mx, my, msz = ME[4], ME[5], ME[6]
mh = round(msz * 400 / 360)
map_islands += (
    f'<div style="position: absolute; left: {mx}px; top: {my}px; width: {msz}px; height: {mh}px;">'
    f'<dc-import name="Island" frame="none" pose="wave" level="24" medals="9" pearls="2" gifts="palm_offshoot:خالد,shell_pearl:يوسف" size="{msz}" hint-size="{msz}px,{mh}px"></dc-import></div>'
    f'<a href="Play.dc.html" aria-label="واحتك" style="position: absolute; left: {mx}px; top: {my + mh * 0.3:.0f}px; width: {msz}px; height: {mh * 0.72:.0f}px;"></a>'
    f'<div style="position: absolute; left: {mx + msz / 2:.0f}px; top: {my + mh - 4}px; transform: translateX(-50%); background: #2F7A3A; color: #FFFFFF; border-radius: 999px; padding: 3px 12px; font-size: 13px; font-weight: 700; pointer-events: none;">واحتك</div>'
)
# lantern ropes between islands: team days won this week, 5 of 7 lit
ropes = [((83, 150), (182, 420)), ((289, 160), (226, 420)), ((63, 300), (150, 452)), ((323, 300), (250, 452))]
rope_svg = ''
for (x1, y1), (x2, y2) in ropes:
    cx, cy = (x1 + x2) / 2, max(y1, y2) - 10
    rope_svg += f'<path d="M{x1} {y1} Q{cx} {cy} {x2} {y2}" fill="none" stroke="#8B6A3E" stroke-width="2" stroke-dasharray="1 0" style="opacity: .55"></path>'
    for k in range(1, 8):
        t = k / 8
        px = (1 - t) ** 2 * x1 + 2 * (1 - t) * t * cx + t * t * x2
        py = (1 - t) ** 2 * y1 + 2 * (1 - t) * t * cy + t * t * y2
        lit = k <= 5
        rope_svg += (f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{5 if lit else 3.4}" fill="#FFE08A" style="opacity: .5"></circle>' if lit else '') + \
                    f'<circle cx="{px:.1f}" cy="{py:.1f}" r="2.6" fill="{"#F2C14E" if lit else "#E4DDCB"}" stroke="#6B5320" stroke-width="1"></circle>'

waves = ''.join(f'<path d="M{x} {y} q6 -4 12 0 t12 0" fill="none" stroke="#FFFFFF" stroke-width="1.8" stroke-linecap="round" style="opacity: .55"></path>'
                for x, y in [(30, 60), (300, 240), (180, 200), (60, 380), (320, 400), (200, 330), (20, 500), (330, 520), (150, 20)])

gift_opts = [('palm_offshoot', 'فسيلة'), ('harvest_basket', 'سلة فواكه'), ('shell_pearl', 'محارة')]
gift_btns = ''.join(
    f'<button type="button" onClick="{{{{give.{k}}}}}" style="font-family: inherit; flex: 1; display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 8px 4px; border-radius: 16px; border: 2px solid #E6DFCC; background: #FFFFFF; cursor: pointer; min-height: 76px;">'
    f'<img src="{A[k][0]}" alt="" style="width: 40px; height: 36px; object-fit: contain;"><span style="font-size: 13px; font-weight: 600; color: #23352A;">{ar}</span></button>'
    for k, ar in gift_opts)

NB_JS = r"""
class Component extends DCLogic {
  renderVals() {
    const F = __FRIENDS__;
    const st = Object.assign({ view: this.props.view === 'visit' ? 'visit' : 'map', who: Number(this.props.who || 0), watered: {}, gifted: {}, liked: {}, picking: false, rain: false }, this.state || {});
    const set = (p) => this.setState(Object.assign({}, st, p));
    const go = {}, lk = {};
    F.forEach((f, i) => { go['v' + i] = () => set({ view: 'visit', who: i, picking: false }); lk['c' + i] = f.likes + (st.liked[i] ? 1 : 0); });
    const f = F[st.who];
    const w = st.watered[st.who], g = st.gifted[st.who], l = st.liked[st.who];
    const gifts = [f.gifts, g ? g + ':أنت' : ''].filter((x) => x).join(',');
    const GN = { palm_offshoot: 'فسيلة', harvest_basket: 'سلة فواكه', shell_pearl: 'محارة' };
    const book = f.book.slice();
    if (w) book.unshift('أنت سقيتها');
    if (g) book.unshift('أنت تركت له ' + GN[g]);
    if (l) book.unshift('أنت أعجبتك');
    const give = {};
    Object.keys(GN).forEach((k) => { give[k] = () => { const gifted = Object.assign({}, st.gifted); gifted[st.who] = k; set({ gifted, picking: false }); }; });
    const TIER = (L) => (L >= 75 ? 'تاج نجوم' : L >= 50 ? 'عقد لؤلؤ' : L >= 35 ? 'قوس قزح' : L >= 20 ? 'إطار ذهب' : L >= 10 ? 'قاعدة مرجان' : L >= 5 ? 'قاعدة حجر' : 'قاعدة رمل');
    return {
      isMap: st.view === 'map', isVisit: st.view === 'visit',
      go, lk, give,
      f: Object.assign({}, f, { gifts, rain: st.rain ? 'true' : 'false', pen: f.pennant ? 'true' : 'false', tier: TIER(f.level) }),
      back: () => set({ view: 'map', picking: false }),
      water: () => {
        if (w) return;
        const watered = Object.assign({}, st.watered); watered[st.who] = true;
        if (this._t) clearTimeout(this._t);
        this.setState(Object.assign({}, st, { watered, rain: true }));
        this._t = setTimeout(() => this.setState({ rain: false }), 2600);
      },
      waterLabel: w ? 'سقيتها اليوم' : 'اسقِ',
      waterBg: w ? '#EEF6EC' : '#2F7A3A', waterFg: w ? '#2F6B3A' : '#FFFFFF',
      openGift: () => { if (!g) set({ picking: !st.picking }); },
      giftLabel: g ? 'أهديته اليوم' : 'هدية',
      giftBg: g ? '#EEF6EC' : '#FFF3C4',
      picking: st.picking,
      like: () => { const liked = Object.assign({}, st.liked); liked[st.who] = !l; set({ liked }); },
      likeCount: f.likes + (l ? 1 : 0), likeFill: l ? '#F06292' : 'none',
      book: book.map((t) => ({ t })),
      winner: !!f.pennant
    };
  }
}
"""
friends_js = '[' + ', '.join(
    "{ name: '%s', level: %d, medals: %d, pearls: %d, spots: '%s', gifts: '%s', likes: %d, pennant: %s, book: %s }" % (
        n, lv, md, pr, spots, gifts, likes, 'true' if pen else 'false',
        "['أحمد سقاها', 'يوسف أعجبته']" if i == 0 else "['خالد سقاها']" if i == 1 else "[]")
    for i, (n, lv, md, pr, spots, gifts, likes, pen, x, y, sz) in enumerate(FRIENDS)) + ']'

nb = HEAD.format(title='Neighbours', style=ic.STYLE + '@keyframes nb-sail{0%{transform:translate(40px,330px) scaleX(1)}45%{transform:translate(300px,176px) scaleX(1)}50%{transform:translate(300px,176px) scaleX(-1)}95%{transform:translate(40px,330px) scaleX(-1)}100%{transform:translate(40px,330px) scaleX(1)}}.nb-sail{animation:nb-sail 26s ease-in-out infinite}@media (prefers-reduced-motion: reduce){.nb-sail{animation:none;transform:translate(40px,330px)}}') + f"""<div dir="rtl" style="{PHONE}">

<sc-if value="{{{{isMap}}}}" hint-placeholder-val="{{{{true}}}}">
<div style="padding: 48px 16px 0; display: flex; align-items: flex-end; justify-content: space-between;">
<div style="display: flex; flex-direction: column;">
<h1 style="margin: 0; font-size: 24px; font-weight: 700;">جيرانك</h1>
<div style="font-size: 14px; color: #45574B;">غرفة الصباح · 5 أشخاص</div>
</div>
<div style="font-size: 13px; font-weight: 600; color: #6B5320; background: #FFF3C4; border-radius: 999px; padding: 6px 12px;">أيام الفريق: 5 من 7</div>
</div>
<div dir="ltr" style="position: absolute; left: 0; top: {MAP_TOP}px; width: 390px; height: 560px; background: #CDEBF3; overflow: hidden;">
<svg viewBox="0 0 390 560" width="390" height="560" style="position: absolute; left: 0; top: 0;" aria-hidden="true">{waves}{rope_svg}</svg>
<img src="{A['dhow'][0]}" alt="" class="nb-sail" style="position: absolute; left: 0; top: 0; width: 46px; height: 40px;">
{map_islands}
</div>
<div style="position: absolute; left: 16px; right: 16px; bottom: 22px; background: #FFFFFF; border-radius: 22px; padding: 12px 14px; display: flex; flex-direction: column; gap: 8px;">
<div style="font-size: 15px; font-weight: 700;">اليوم عند واحتك</div>
<div style="display: flex; flex-direction: column; gap: 4px; font-size: 14px; color: #45574B;">
<span>خالد سقى واحتك وترك لك فسيلة</span>
<span>يوسف ترك لك محارة</span>
</div>
<a href="Show.dc.html" style="font-size: 14px; font-weight: 700; color: #2F7A3A; text-decoration: none; min-height: 32px; display: flex; align-items: center;">معرض الأسبوع: صوّت قبل السبت</a>
</div>
</sc-if>

<sc-if value="{{{{isVisit}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="position: relative; width: 390px; height: 433px; background: #DDF0F1;">
<dc-import name="Island" frame="rect" guest="true" guest-name="دومك" level="{{{{f.level}}}}" medals="{{{{f.medals}}}}" pearls="{{{{f.pearls}}}}" spots="{{{{f.spots}}}}" gifts="{{{{f.gifts}}}}" watering="{{{{f.rain}}}}" pennant="{{{{f.pen}}}}" size="390" hint-size="390px,433px"></dc-import>
<div style="position: absolute; top: 48px; left: 8px; right: 8px; display: flex; align-items: center; justify-content: space-between;">
<button type="button" onClick="{{{{back}}}}" aria-label="رجوع لجيرانك" style="width: 44px; height: 44px; border-radius: 999px; border: 0; background: rgba(255,255,255,0.9); display: flex; align-items: center; justify-content: center; cursor: pointer;">{BACK}</button>
<div style="font-size: 17px; font-weight: 700; background: rgba(255,255,255,0.9); padding: 8px 16px; border-radius: 999px;">واحة {{{{f.name}}}}</div>
<div style="width: 44px;"></div>
</div>
</div>
<div style="padding: 10px 16px 0; display: flex; flex-direction: column; gap: 10px;">
<div style="display: flex; justify-content: space-between; align-items: baseline;">
<div style="font-size: 16px; font-weight: 700;">المستوى {{{{f.level}}}} · {{{{f.tier}}}}</div>
<sc-if value="{{{{winner}}}}" hint-placeholder-val="{{{{false}}}}"><div style="font-size: 12px; font-weight: 600; color: #6B5320; background: #FFF3C4; border-radius: 999px; padding: 3px 10px;">علم المعرض الأسبوع الماضي</div></sc-if>
</div>
<div style="display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 8px;">
<button type="button" onClick="{{{{water}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: {{{{waterFg}}}}; background: {{{{waterBg}}}}; border: 0; border-radius: 14px; min-height: 48px; cursor: pointer;">{{{{waterLabel}}}}</button>
<button type="button" onClick="{{{{openGift}}}}" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #6B4E00; background: {{{{giftBg}}}}; border: 0; border-radius: 14px; min-height: 48px; cursor: pointer;">{{{{giftLabel}}}}</button>
<button type="button" onClick="{{{{like}}}}" aria-label="أعجبتني" style="font-family: inherit; font-size: 15px; font-weight: 700; color: #C2416B; background: #FDECF1; border: 0; border-radius: 14px; min-height: 48px; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 6px;">{HEART.format(fill="{{likeFill}}")}{{{{likeCount}}}}</button>
</div>
<a href="Walk.dc.html" style="font-size: 15px; font-weight: 700; color: #23352A; background: #FFFFFF; border: 2px solid #2F7A3A; border-radius: 14px; min-height: 46px; display: flex; align-items: center; justify-content: center; text-decoration: none;">انزل وتمشّى في واحته</a>
<sc-if value="{{{{picking}}}}" hint-placeholder-val="{{{{false}}}}">
<div style="background: #FFFFFF; border-radius: 20px; padding: 10px; display: flex; flex-direction: column; gap: 8px;">
<div style="font-size: 14px; font-weight: 700; padding: 0 4px;">وش تترك له؟ تبقى عنده أسبوع باسمك</div>
<div style="display: flex; gap: 8px;">{gift_btns}</div>
</div>
</sc-if>
<div style="background: #FFFFFF; border-radius: 20px; padding: 12px 14px; display: flex; flex-direction: column; gap: 6px;">
<div style="font-size: 15px; font-weight: 700;">دفتر الزوار اليوم</div>
<sc-for list="{{{{book}}}}" as="b" hint-placeholder-count="2"><div style="font-size: 14px; color: #45574B;">{{{{b.t}}}}</div></sc-for>
</div>
<div style="font-size: 12px; color: #6B7A6F; text-align: center;">الزيارة تشوف الواحة بس. ما تبين عادات ولا صلوات ولا أيام هادية.</div>
</div>
</sc-if>

</div>
""" + TAIL.format(js=NB_JS.replace('__FRIENDS__', friends_js))
write('Neighbours.dc.html', nb)


# ---------------------------------------------------------------- Show (weekly vote)
ENTRIES = [('خالد', 31, 11, 3, 'pomegranate,coral_house,jasmine,well,lantern_arch,rose'),
           ('يوسف', 52, 17, 5, 'sidr,coral_house,vine,falaj,fountain,pearl_chest'),
           ('أحمد', 8, 2, 1, ''), ('عبدالله', 15, 5, 2, 'lemon,house,flowers,well,rose,bench')]
cards = ''
for i, (n, lv, md, pr, spots) in enumerate(ENTRIES):
    cards += (f'<div style="background: #FFFFFF; border-radius: 20px; padding: 8px; display: flex; flex-direction: column; gap: 6px; box-shadow: {{{{vt.r{i}}}}};">'
              f'<div style="border-radius: 14px; overflow: hidden; width: 155px; height: 172px; align-self: center;"><dc-import name="Island" frame="rect" pose="none" level="{lv}" medals="{md}" pearls="{pr}" spots="{spots}" size="155" hint-size="155px,172px"></dc-import></div>'
              f'<div style="display: flex; align-items: center; justify-content: space-between; padding: 0 4px;"><span style="font-size: 15px; font-weight: 700;">{n}</span><span style="font-size: 12px; color: #6B7A6F;">المستوى {lv}</span></div>'
              f'<button type="button" onClick="{{{{vt.v{i}}}}}" style="font-family: inherit; font-size: 14px; font-weight: 700; color: {{{{vt.fg{i}}}}}; background: {{{{vt.bg{i}}}}}; border: 0; border-radius: 12px; min-height: 40px; cursor: pointer;">{{{{vt.t{i}}}}}</button></div>')
SHOW_JS = r"""
class Component extends DCLogic {
  renderVals() {
    const st = Object.assign({ vote: 1 }, this.state || {});
    const vt = {};
    for (let i = 0; i < 4; i++) {
      const on = st.vote === i;
      vt['v' + i] = () => this.setState({ vote: on ? -1 : i });
      vt['t' + i] = on ? 'صوّتّ لها' : 'صوّت';
      vt['bg' + i] = on ? '#2F7A3A' : '#F3EEDF';
      vt['fg' + i] = on ? '#FFFFFF' : '#23352A';
      vt['r' + i] = on ? '0 0 0 3px #2F7A3A' : 'none';
    }
    return { vt };
  }
}
"""
show = HEAD.format(title='The weekly show', style='') + f"""<div dir="rtl" style="{PHONE} padding: 48px 16px 0; display: flex; flex-direction: column; gap: 10px;">
<div style="display: flex; flex-direction: column; gap: 2px;">
<h1 style="margin: 0; font-size: 24px; font-weight: 700;">معرض الأسبوع</h1>
<div style="font-size: 14px; color: #45574B; line-height: 1.5;">غرفة الصباح. صوّت لأحلى واحة، صوت واحد، ومو لواحتك. النتيجة يوم السبت.</div>
</div>
<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">{cards}</div>
<div style="background: #23352A; color: #F5F0E1; border-radius: 20px; padding: 12px 14px; display: flex; align-items: center; gap: 12px;">
<svg width="34" height="40" viewBox="0 0 34 40" aria-hidden="true"><line x1="8" y1="4" x2="8" y2="38" stroke="#F5F0E1" stroke-width="2.6" stroke-linecap="round"></line><path d="M9 5 L32 12 L9 20 Z" fill="#F2C14E" stroke="#F5F0E1" stroke-width="1.6" stroke-linejoin="round"></path></svg>
<div style="display: flex; flex-direction: column;"><span style="font-size: 15px; font-weight: 700;">الأسبوع الماضي: علم المعرض لخالد</span><span style="font-size: 13px; color: #C9D6C9;">يرفرف على واحته أسبوع، ويشوفه كل من يزوره</span></div>
</div>
</div>
""" + TAIL.format(js=SHOW_JS)
write('Show.dc.html', show)


# ---------------------------------------------------------------- Premium rows for the oasis
rows = [
    ('ذهب مضاعف', 'كل عادة تعطيك 16 ذهب بدل 8، فتبني أسرع. المستوى والقاعدة يبقون بجهدك أنت.', '2x'),
    ('نخلة حقيقية', 'بـ2500 ذهب يزرع دوم نخلة حقيقية مع شريك زراعة، وتطلع لوحة بعددها في واحتك.', A['palm_young'][0]),
    ('مواسم الواحة', 'زينة رمضان والعيدين، تطلع في وقتها وتروح بعده.', A['lanterns'][0]),
    ('ألوانك', 'اختار لون السما والعشب والبحر بنفسك.', ''),
]
row_html = ''
for t, d, ic_ in rows:
    if ic_ == '2x':
        icon = '<div style="width: 46px; height: 46px; border-radius: 14px; background: #FFF3C4; color: #6B4E00; font-weight: 700; font-size: 17px; display: flex; align-items: center; justify-content: center;">2x</div>'
    elif ic_:
        icon = f'<div style="width: 46px; height: 46px; border-radius: 14px; background: #EEF6EC; display: flex; align-items: center; justify-content: center;"><img src="{ic_}" alt="" style="width: 36px; height: 36px; object-fit: contain;"></div>'
    else:
        icon = '<div style="width: 46px; height: 46px; border-radius: 14px; overflow: hidden; display: flex; flex-direction: column;"><span style="flex: 1; background: #F7E3C8;"></span><span style="flex: 1; background: #9CC65E;"></span><span style="flex: 1; background: #4FB2DA;"></span></div>'
    row_html += (f'<div style="display: flex; gap: 12px; align-items: flex-start;">{icon}'
                 f'<div style="display: flex; flex-direction: column; gap: 2px; flex: 1;"><span style="font-size: 16px; font-weight: 700;">{t}</span>'
                 f'<span style="font-size: 13px; line-height: 1.5; color: #45574B;">{d}</span></div></div>')
prem = HEAD.format(title='Premium rows for the oasis', style=ic.STYLE) + f"""<div dir="rtl" style="{PHONE} display: flex; flex-direction: column;">
<div style="position: relative; width: 390px; height: 340px; background: #22304A; overflow: hidden; flex-shrink: 0;">
<div style="position: absolute; left: 32px; top: 0;"><dc-import name="Island" frame="none" sky="night" season="ramadan" level="31" medals="12" pearls="3" spots="pomegranate,coral_house,jasmine,well,lantern_arch,rose" size="326" hint-size="326px,362px"></dc-import></div>
<div style="position: absolute; top: 52px; right: 16px; display: flex; align-items: center; gap: 6px; background: rgba(255,255,255,0.92); border-radius: 999px; padding: 5px 12px 5px 6px; font-size: 13px; font-weight: 700;"><img src="{A['palm_young'][0]}" alt="" style="width: 22px; height: 22px; object-fit: contain;">نخيلك الحقيقية: 2</div>
</div>
<div style="padding: 16px 16px 0; display: flex; flex-direction: column; gap: 14px;">
<div style="display: flex; flex-direction: column; gap: 2px;">
<div style="font-size: 22px; font-weight: 700;">واحتك مع بريميوم</div>
<div style="font-size: 14px; color: #45574B;">أسطر جديدة في صفحة بريميوم اللي عندك</div>
</div>
{row_html}
<div style="font-size: 12px; color: #6B7A6F; line-height: 1.5;">ما ينباع: المستوى، القاعدة، الأوسمة، ولا صناديق حظ.</div>
</div>
</div>
""" + TAIL.format(js="class Component extends DCLogic {\n  renderVals() {\n    return {};\n  }\n}")
write('OasisPremium.dc.html', prem)
