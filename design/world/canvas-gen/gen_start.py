"""Generates project/Simple.dc.html: the start board for the simple oasis (2026-10-03).

One idea, three live screens (Oasis, Arrange, Friends from gen_simple.py), the
reason behind every tap, the sitting fix before and after, what was cut and why,
and the rules that stay.
"""
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic
from gen_plan import page, header

SC = 0.88
FR = ic.FRAME_META
IDS = ic.FRAME_IDS
CARD = 'background: #FFFFFF; border-radius: 28px; padding: 28px 30px; display: flex; flex-direction: column; gap: 16px;'
H2 = 'margin: 0; font-size: 32px; font-weight: 700;'
LEAD = 'margin: 0; font-size: 18px; line-height: 1.55; color: #45574B; max-width: 980px;'


def ar(t):
    """An Arabic quote inside English text, kept on one line and in one piece."""
    return f'<bdi dir="rtl" style="white-space: nowrap;">{t}</bdi>'


def phone(board, h, title, why, do, attrs=''):
    w = round(390 * SC)
    return (f'<div style="display: flex; flex-direction: column; gap: 12px; width: {w}px; flex-shrink: 0;">'
            f'<div style="width: {w}px; height: {round(h * SC)}px; border-radius: 26px; overflow: hidden; box-shadow: 0 0 0 1px #E1D9C4, 0 8px 22px rgba(35,53,42,0.10); position: relative; background: #F5F0E1;">'
            f'<div style="position: absolute; left: 0; top: 0; width: 390px; height: {h}px; transform: scale({SC}); transform-origin: top left;">'
            f'<dc-import name="{board}" {attrs} hint-size="390px,{h}px"></dc-import></div></div>'
            f'<div style="font-size: 20px; font-weight: 700;">{title}</div>'
            f'<div style="font-size: 15px; line-height: 1.5;"><b>Why it is there.</b> {why}</div>'
            f'<div style="font-size: 15px; line-height: 1.5; color: #45574B;"><b style="color: #23352A;">What you do.</b> {do}</div></div>')


ARROW = ('<svg width="34" height="24" viewBox="0 0 34 24" aria-hidden="true" style="flex-shrink: 0; margin-top: 360px;">'
         '<path d="M2 12 H28 M20 4 L29 12 L20 20" fill="none" stroke="#9AA79C" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"></path></svg>')

# ---- the sitting fix: the same bench, before and after, at 3 px per island unit
PX = 3


def bench_scene(doum, anchor_up, live):
    """A bench on a patch of grass with Doum placed by his anchor; anchor_up = units above the bench's ground."""
    bw, bh = ic.ART['bench'][1], ic.ART['bench'][2]
    H = 40 * PX
    W = H * bw / bh
    gx, gy = 150, 222
    f = FR[doum]
    k = ic.DOUM_H / (302 * f['k']) * PX
    ax, ay = gx, gy - anchor_up * PX
    img = (f'<img src="/_blob/{IDS[doum]}" alt="" style="position: absolute; left: {-f["ax"] * k:.1f}px; top: {-f["ay"] * k:.1f}px; '
           f'width: {f["w"] * k:.1f}px; height: {f["h"] * k:.1f}px; max-width: none;">')
    return (f'<div style="position: relative; width: 300px; height: 260px; border-radius: 22px; overflow: hidden; background: #DDF0F1; flex-shrink: 0;">'
            f'<div style="position: absolute; left: -40px; right: -40px; top: 150px; height: 180px; border-radius: 50%; background: #93CC62; border: 2px solid #1E3A24;"></div>'
            f'<img src="{ic.ART["bench"][0]}" alt="" style="position: absolute; left: {gx - W / 2:.1f}px; top: {gy - H:.1f}px; width: {W:.1f}px; height: {H:.1f}px;">'
            f'<div class="{"isl-sit" if live else ""}" style="position: absolute; left: {ax}px; top: {ay}px; width: 0; height: 0; transform-origin: 0 0;">{img}</div></div>')


before = bench_scene('sit_bench', -4, False)
after = bench_scene('sit_front', 15, True)
steps = [
    ('1', 'Walks to the front of the bench', 'Same walk as everywhere: turns to his heading, 70 units a second.'),
    ('2', 'Hops up, 0.42 s', 'He rises a little, the picture changes at the top of the hop, and he lands on the seat with a small squash.'),
    ('3', 'Sits', 'Front-on, between the armrests, feet over the edge, in front of the backrest. A slow sway every 4.2 s; his eyes are the happy closed ones.'),
    ('4', 'Hops down, 0.38 s', 'Before he walks anywhere else, he hops down in front of the bench, then goes.'),
]
steps_html = ''.join(
    f'<div style="display: flex; gap: 12px; align-items: flex-start;"><span style="width: 28px; height: 28px; border-radius: 99px; background: #23352A; color: #F5F0E1; font-size: 14px; font-weight: 700; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0;">{n}</span>'
    f'<div style="display: flex; flex-direction: column; gap: 2px;"><div style="font-size: 17px; font-weight: 700;">{t}</div><div style="font-size: 15px; line-height: 1.5; color: #45574B;">{d}</div></div></div>'
    for n, t, d in steps)

TAPS = [
    ('Your oasis: a plant', 'Doum walks over, waters it, and says when it grew: ' + ar('«الفل نبت في المستوى 9»') + '.', 'Every thing is a memory of a level you reached.'),
    ('Your oasis: the bench', 'Doum hops up and sits: ' + ar('«أرتاح شوي»') + '.', 'A calm moment, on a seat you built for him.'),
    ('Your oasis: the palm', 'He picks dates and says the palm has been with you since day one.', 'The palm is your level; its dates are your medals.'),
    ('Your oasis: nothing', 'He lives there on his own: sits, waters, looks at the sea.', 'It feels alive without asking anything of you.'),
    ('A new level', 'He walks to an empty place and plants; the new thing grows in.', 'The one moment of reward, and the card shows what comes next.'),
    (ar('«رتّب»') + ' then a place', 'What can stand there: yours, built with gold, or opening at a level. Buildings fit only the two back places.', 'Make it yours; gold has a use.'),
    (ar('«أصحابك»') + ' then a friend', 'His oasis. Your Doum walks in.', 'See how far he got. The list itself is the ranking.'),
    ('His plant you lack', ar('«خذ شتلة»') + ' (a palm gives ' + ar('«فسيلة»') + '). It grows in your oasis with his name: ' + ar('«رمان يوسف»') + '.', 'A reason to visit that lasts: your oasis keeps your friends.'),
    ('His built thing', 'Its price, or the level it opens at.', 'Something to aim for.'),
    ('«رتّب» then a thing you have', 'A golden version of it, for 2,000 gold.', 'The long-term use for gold, which piles up after month five.'),
]
taps_html = ''.join(
    f'<div style="display: grid; grid-template-columns: 260px 1fr 1fr; gap: 20px; padding: 14px 0; border-top: 1px solid #ECE5D3; font-size: 16px; line-height: 1.5;">'
    f'<div style="font-weight: 700;">{a}</div><div style="color: #33463A;">{b}</div><div style="color: #2F6B3A; font-weight: 600;">{c}</div></div>'
    for a, b, c in TAPS)

CUT = [
    ('The room inside the house', 'A second place to decorate: a whole new layer of screens. Sheet 7 stays drawn for later.'),
    ('Gifts, likes, watering a friend, the visitors’ book', 'Four small buttons that left nothing behind. One cutting that grows in your oasis replaces them.'),
    ('Picking dates and taking photos on a visit', 'Fun once, no reason to come back.'),
    ('The weekly show and votes', 'Needs a leader, a schedule and a vote. Later, if rooms ask for it.'),
    ('Free editing at level 100', 'Fourteen places, flip, golden versions. Later, for the few who reach 100.'),
    ('A Premium page for the oasis', 'Premium stays a line or two on the Premium screen people already know. What it gives is your call, above.'),
]
cut_html = ''.join(f'<div style="display: flex; flex-direction: column; gap: 2px; padding: 12px 0; border-top: 1px solid #ECE5D3;"><div style="font-size: 17px; font-weight: 700;">{a}</div>'
                   f'<div style="font-size: 15px; line-height: 1.5; color: #45574B;">{b}</div></div>' for a, b in CUT)

RULES = ['No notifications from the oasis, ever. News waits as one quiet line on the oasis page.',
         'Friends is off until the person turns it on. Turning it off hides them both ways.',
         'A visit never shows habits, prayers or quiet days. Only the oasis and the level.',
         'Growth is never sold. Gold buys made things and golden versions of them.',
         'Seasons are Ramadan and the two Eids only, and they come back every year.',
         'No random boxes. Nothing dies, nothing is taken away.',
         'Halal art: no people, animals, birds or insects, no faces on things. Doum is the only character.',
         'Logging a habit takes exactly as many taps as today.']
rules_html = ''.join(f'<li style="margin: 0 0 8px;">{r}</li>' for r in RULES)

TRY = ['Open <b>Your oasis</b> full-window. Wait two seconds: Doum walks to the bench, hops up and sits. Wait again: he hops down and waters the jasmine.',
       'Tap the palm, the pomegranate, the bench. Under the phone (test buttons, not in the app): <b>مستوى جديد</b> plants the next thing; <b>صاحبك أخذ شتلة</b> shows the quiet line; <b>ليالي رمضان</b> shows the season.',
       '<b>رتّب</b>: tap the empty front place (the + ring), pick <b>ورد</b> (a house or a tree would show under <b>للأماكن اللي ورا</b>: big things stand at the back). Tap the pomegranate: <b>نسخة ذهبية من هذا</b>. Tap the well: try <b>نافورة</b> (opens later), <b>قوس فوانيس</b> (build it), then <b>بيت مرجان</b> (not enough gold now).',
       '<b>أصحابك</b>: <b>شغّلها</b>, tap Yousef, tap the sidr, <b>خذ شتلة</b>. Go back: his chip changes. Tap Khalid, sit on his bench, then his palm: <b>خذ فسيلة</b>.']
try_html = ''.join(f'<li style="margin: 0 0 10px;">{t}</li>' for t in TRY)

ECON_ROWS = [('Level 10', 'about 1 month'), ('Level 20', 'about 4.5 months'), ('Level 35, rainbow', 'about 14 months'),
             ('Level 50, pearl ring', 'about 2.4 years'), ('Level 75, star crown', 'about 5.4 years'), ('Level 100', 'about 10 years')]
econ_rows = ''.join(f'<div style="display: flex; justify-content: space-between; gap: 12px; padding: 8px 0; border-top: 1px solid #ECE5D3; font-size: 16px;"><span style="font-weight: 600;">{a}</span><span style="color: #45574B;">{b}</span></div>' for a, b in ECON_ROWS)
CALLS = [('Premium: looks, not 2x gold', 'Seasons (Ramadan and the two Eids), your own colours, real palms. Gold is already in surplus (the app’s own code calls it the oversupplied currency), so doubling it is a weak reason to pay.'),
         ('Fair rank', 'Free accounts have 10 habits, Premium has no cap: 30 tiny habits reach the rainbow in about four months. Count at most 10 habits a day toward level; Premium still tracks as many as it likes.'),
         ('A level the server checks', 'Clock tricks are already blocked by the server rules, but the phone writes level, XP and gold. Before friends see each other’s level, check it on the server.'),
         ('Plant only on a new highest level', 'Undo takes XP back exactly, so the level can drop. The oasis follows the highest level ever: nothing is taken away, and the planting moment never plays twice.')]
calls_html = ''.join(f'<div style="display: flex; flex-direction: column; gap: 2px; padding: 12px 0; border-top: 1px solid #ECE5D3;"><div style="font-size: 17px; font-weight: 700;">{i + 1}. {a}</div><div style="font-size: 15px; line-height: 1.5; color: #45574B;">{b}</div></div>' for i, (a, b) in enumerate(CALLS))

body = (
    header('Start here · the simple version', 'One idea, three screens',
           'Your days grow it. Friends from your rooms can take a cutting of your plants, and it grows in their oasis with your name. '
           'Every tap has one reason, and nothing pings. The boards further down are the earlier, deeper thinking, kept for reference.')
    + f'<section style="{CARD}"><h2 style="{H2}">The three screens, live</h2>'
      f'<p style="{LEAD}">Tap inside them right here, or open each one full-window from the row to the right. The dashed strip under the first phone is for testing only.</p>'
      '<div style="display: flex; gap: 14px; align-items: flex-start;">'
    + phone('Oasis', 954, '1. Your oasis', 'Proof of your days. Every thing on it came from a level you reached or gold you earned.',
            'Watch Doum live there. Tap a thing: he walks to it and says when you got it. The card shows what your habits grow next.')
    + ARROW
    + phone('Arrange', 844, '2. Arrange', 'Make it yours, and give gold a use.',
            'Tap a place, pick a thing: what you have, what gold builds, what opens at a later level.')
    + ARROW
    + phone('Friends', 844, '3. Friends', 'See where your friends are (the list is the ranking), and a reason to visit: plants they have that you don’t.',
            'Off until you turn it on. Tap a friend, tap a plant, <b>خذ شتلة</b>. It grows in your oasis with his name.', 'start="list"')
    + '</div></section>'
    + f'<section style="{CARD}"><h2 style="{H2}">Every tap has a reason</h2>'
      '<div style="display: grid; grid-template-columns: 260px 1fr 1fr; gap: 20px; font-size: 13px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: #6B7A6F;"><div>Tap</div><div>What happens</div><div>Why</div></div>'
    + taps_html + '</section>'
    + f'<section style="{CARD}"><h2 style="{H2}">Sitting, fixed</h2>'
      f'<p style="{LEAD}">The bench pose from Sheet 10 came with its own side-on stool, so on the island bench he showed two seats and floated. '
      'Now he is the front-on sitting Doum from the cushion pose with the cushions taken away, set on the bench’s own seat.</p>'
      '<div style="display: flex; gap: 28px; align-items: flex-start; flex-wrap: wrap;">'
      f'<div style="display: flex; flex-direction: column; gap: 8px;">{before}<div style="font-size: 15px; font-weight: 700; color: #9A4A2E;">Before: two seats, side-on</div></div>'
      f'<div style="display: flex; flex-direction: column; gap: 8px;">{after}<div style="font-size: 15px; font-weight: 700; color: #2F6B3A;">After: on the bench, front-on (live sway)</div></div>'
      f'<div style="display: flex; flex-direction: column; gap: 14px; flex: 1; min-width: 380px;">{steps_html}</div>'
      '</div></section>'
    + f'<section style="{CARD}"><h2 style="{H2}">Gold and XP, the real numbers</h2>'
      f'<p style="{LEAD}">From the app’s code. A habit pays 15 to 40 XP and 5 to 15 gold (sometimes half again), a task 10 XP and 4 gold (15 a day at most), and the next level needs your level × 100 XP. An active person (5 habits, 3 tasks) earns about 140 XP and 55 gold a day.</p>'
      '<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 28px;">'
      f'<div><div style="font-size: 13px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: #6B7A6F; padding-bottom: 6px;">When the bases come</div>{econ_rows}</div>'
      '<div style="display: flex; flex-direction: column; gap: 10px; font-size: 16px; line-height: 1.55;">'
      '<div><b>What this means.</b> The oasis changes fast in the first months, then a new level comes every two or three weeks. Gold comes at about 1,650 a month; everything you can build by level 20 costs about 5,200, so by month five gold piles up.</div>'
      '<div><b>Now on the canvas.</b> A golden version of anything you own (2,000 gold, in «رتّب») is the long-term use for gold. The oasis page says how many things your gold can build. Seasons come back every year: try «ليالي رمضان» under the first phone.</div>'
      '</div></div>'
      '<h3 style="margin: 12px 0 0; font-size: 22px; font-weight: 700;">Four calls for you</h3>'
      f'{calls_html}</section>'
    + '<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 28px;">'
      f'<section style="{CARD}"><h2 style="{H2}">Cut for now</h2><p style="{LEAD}">Each one added a screen or a button without a reason that lasts. The art stays; any of them can come back.</p>{cut_html}</section>'
      f'<section style="{CARD}"><h2 style="{H2}">Rules that stay</h2><ul style="margin: 0; padding-left: 22px; font-size: 16px; line-height: 1.55;">{rules_html}</ul></section>'
      '</div>'
    + '<section style="background: #23352A; color: #F5F0E1; border-radius: 28px; padding: 28px 30px; display: flex; flex-direction: column; gap: 12px;">'
      '<h2 style="margin: 0; font-size: 28px; font-weight: 700;">Try it</h2>'
      f'<ol style="margin: 0; padding-left: 24px; font-size: 17px; line-height: 1.6;">{try_html}</ol></section>'
)
html = page('The simple oasis', body, 5150, style=ic.STYLE)
open(os.path.join(HERE, 'project', 'Simple.dc.html'), 'w').write(html)
print('Simple.dc.html', len(html))
