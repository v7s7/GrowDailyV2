"""The proposal canvas for friends (2026-10-03): "Doum's Oasis: should we build it?"
https://claude.ai/artifact/CNgeqhi9vJ2Y2GZwc7Ybbw

    python gen_proposal.py            # writes proposal/src (old ids), then proposal/project (this canvas's ids)

Boards: Main (the case and the questions), the click-through phones (ProfileBefore,
Profile, Oasis, Arrange, Friends, Island), Changes (before and after), Wiring (the
diagram), Build (what is done, the waves, the decisions). The phones are the same
files as the design canvas (gen_simple.py); images live per canvas, so every
/_blob/ id is swapped for this canvas's copy through proposal/blob_ids.json
(local file -> id here). Ids that have no copy yet are listed for upload.
"""
import json, os, re, shutil, sys
from datetime import datetime, timezone
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic
from gen_plan import page as plan_page, AR

SRC = os.path.join(HERE, 'proposal', 'src')
OUT = os.path.join(HERE, 'proposal', 'project')
os.makedirs(SRC, exist_ok=True)
os.makedirs(OUT, exist_ok=True)
INK, MUTED, CREAM, CARD_BD, GREEN, GREEN_BG = '#23352A', '#45574B', '#F5F0E1', '#E1D9C4', '#2F7A3A', '#EEF6EC'
LEVEL, GOLD = 24, '3,250'
SPOTS_DEMO = 'pomegranate,house,jasmine,well,bench,'


def ar(t):
    return f'<bdi dir="rtl" style="white-space: nowrap;">{t}</bdi>'


def write(name, html):
    with open(os.path.join(SRC, name), 'w') as fh:
        fh.write(html)


def page(title, body, height):
    return plan_page(title, body, height, style=ic.STYLE)


# ------------------------------------------------------------------ Profile, today and with the card
PROFILE = open(os.path.join(HERE, 'project', 'Profile.dc.html')).read()
VEG = ic.ART['vegetables'][0]


def profile(card):
    s = PROFILE
    # the same numbers as the oasis behind the card: level 24, 64% to 25, 3,250 gold
    s = s.replace('<title>Profile with the planet card</title>', '<title>' + ('Profile with the oasis card' if card else 'Profile today') + '</title>')
    s = s.replace('>12</span>', f'>{LEVEL}</span>').replace('stroke-dasharray="176 245"', 'stroke-dasharray="157 245"')
    s = s.replace('width: 72%;', 'width: 64%;').replace('860/1200 XP للمستوى 13', '1,540/2,400 XP للمستوى 25')
    s = s.replace('<div style="font-size: 20px; font-weight: 700;">380</div>', f'<div style="font-size: 20px; font-weight: 700;">{GOLD}</div>')
    a, b = s.index('<a href="Oasis.dc.html"'), s.index('</a>', s.index('<a href="Oasis.dc.html"')) + 4
    if not card:
        return s[:a] + s[b:]
    new_card = (
        '<a href="Oasis.dc.html" aria-label="واحة دوم" style="text-decoration: none; color: inherit; background: #FFFFFF; border-radius: 22px; padding: 12px 14px 12px 12px; display: flex; gap: 12px; align-items: center; box-shadow: 0 0 0 2px #CFE5C6;">'
        f'<dc-import name="Island" frame="bubble" level="{LEVEL}" medals="9" pearls="2" spots="{SPOTS_DEMO}" size="118" pose="wave" hint-size="118px,131px"></dc-import>'
        '<div style="display: flex; flex-direction: column; gap: 6px; flex-grow: 1; min-width: 0;">'
        '<div style="font-size: 18px; font-weight: 700;">واحة دوم</div>'
        '<div style="font-size: 14px; color: #45574B;">تكبر مع عاداتك</div>'
        '<div style="display: flex; align-items: center; gap: 8px; background: #F7F3E8; border-radius: 12px; padding: 6px 9px;">'
        f'<img src="{VEG}" alt="" style="width: 30px; height: 26px; object-fit: contain;">'
        '<div style="font-size: 13px; line-height: 1.35; color: #45574B;">المستوى 25: <span style="font-weight: 700; color: #23352A;">خضار</span></div>'
        '</div></div>'
        '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#6B7A6F" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" style="flex-shrink: 0;"><polyline points="15 6 9 12 15 18"></polyline></svg>'
        '</a>')
    return s[:a] + new_card + s[b:]


write('ProfileBefore.dc.html', profile(False))
write('Profile.dc.html', profile(True))
for n in ['Oasis', 'Arrange', 'Friends', 'Island']:
    shutil.copy(os.path.join(HERE, 'project', f'{n}.dc.html'), os.path.join(SRC, f'{n}.dc.html'))

# ------------------------------------------------------------------ shared pieces for the pages
CARD = f'background: #FFFFFF; border-radius: 24px; padding: 26px 28px; display: flex; flex-direction: column; gap: 14px;'
H2 = 'margin: 0; font-size: 30px; font-weight: 700;'
LEAD = f'margin: 0; font-size: 18px; line-height: 1.55; color: {MUTED}; max-width: 980px;'
ARROW = ('<svg width="30" height="20" viewBox="0 0 30 20" aria-hidden="true" style="flex-shrink: 0; margin-top: {top}px;">'
         '<path d="M2 10 H24 M17 3 L25 10 L17 17" fill="none" stroke="#9AA79C" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"></path></svg>')


def header(eyebrow, h1, lead):
    return (f'<header style="display: flex; flex-direction: column; gap: 14px; max-width: 1060px;">'
            f'<div style="font-size: 15px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: #3F7A4A;">{eyebrow}</div>'
            f'<h1 style="margin: 0; font-size: 56px; line-height: 1.06; font-weight: 700;">{h1}</h1>'
            f'<p style="margin: 0; font-size: 20px; line-height: 1.5; color: {MUTED};">{lead}</p></header>')


def phone(board, h, sc, cap, attrs=''):
    w = round(390 * sc)
    return (f'<div style="display: flex; flex-direction: column; gap: 10px; width: {w}px; flex-shrink: 0;">'
            f'<div style="width: {w}px; height: {round(h * sc)}px; border-radius: 22px; overflow: hidden; box-shadow: 0 0 0 1px {CARD_BD}, 0 6px 18px rgba(35,53,42,0.08); position: relative; background: {CREAM};">'
            f'<div style="position: absolute; left: 0; top: 0; width: 390px; height: {h}px; transform: scale({sc}); transform-origin: top left;">'
            f'<dc-import name="{board}" {attrs} hint-size="390px,{h}px"></dc-import></div></div>'
            f'<div style="font-size: 15px; line-height: 1.45;">{cap}</div></div>')


def bullets(items, size=17):
    return (f'<ul style="margin: 0; padding-left: 22px; font-size: {size}px; line-height: 1.55; display: flex; flex-direction: column; gap: 6px;">'
            + ''.join(f'<li>{t}</li>' for t in items) + '</ul>')


# ------------------------------------------------------------------ Main: the case, the tour, the questions
TAPS = [
    ('A thing on your oasis', 'Doum walks to it and says when you earned it: ' + ar('«الفل نبت في المستوى 9»'), 'Each thing is a memory of your effort.'),
    ('Nothing at all', 'Doum lives there: sits on his bench, waters, looks at the sea.', 'It feels alive without asking anything.'),
    ('A new level', 'Doum plants the next thing, and it grows in.', 'The one reward moment, and the card shows what comes next.'),
    (ar('«رتّب»') + ', a place', 'What can go there: yours, built with gold, or opening later. Or a golden version. Buildings fit only the two back places.', 'Make it yours; gold gets a use; nothing hides Doum.'),
    (ar('«أصحابك»') + ', a friend', 'Their oasis (Friends is off until you turn it on).', 'See how far friends got; the list is the ranking.'),
    ('A plant you don’t have', ar('«خذ شتلة»') + ': it grows in your oasis with their name.', 'A reason to visit that lasts.'),
]
taps = ''.join(f'<div style="display: grid; grid-template-columns: 220px 1fr 1fr; gap: 18px; padding: 12px 0; border-top: 1px solid #ECE5D3; font-size: 16px; line-height: 1.5;">'
               f'<div style="font-weight: 700;">{a}</div><div>{b}</div><div style="color: #2F6B3A; font-weight: 600;">{c}</div></div>' for a, b, c in TAPS)
QUESTIONS = [
    'Would you open it more than once a week? What would bring you back?',
    'Which of the three screens did you like most, and which would you skip?',
    'Would you turn on Friends? With whom?',
    'Would you pay for seasons (Ramadan and the two Eids) or your own colours?',
    'Was anything confusing, or did anything feel like too much?',
]
main_body = (
    header('GrowDaily · a proposal', 'Doum’s oasis',
           'Every habit you keep grows a small oasis, and Doum lives in it. It is one card on your Profile. '
           'It never sends a notification, and logging a habit stays exactly the same.')
    + '<div style="display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 20px;">'
    + ''.join(f'<section style="{CARD}"><h2 style="margin: 0; font-size: 22px; font-weight: 700;">{t}</h2><p style="margin: 0; font-size: 17px; line-height: 1.55;">{d}</p></section>' for t, d in [
        ('What it is', 'A small island that grows with your level: a palm that gets taller, trees and flowers, then things you build with gold. Doum walks around it, sits on his bench and waters his plants.'),
        ('Why it might matter', 'Today your effort shows as numbers: XP, a level, a streak. Forest grows a tree while you focus and Finch grows a little bird with your self-care; both show that people keep going when they can see what their days made.'),
        ('What it asks of users', 'Nothing. One card on Profile. Friends stays off until you turn it on. No notifications, no streak to lose, and nothing ever dies or gets taken away.'),
    ]) + '</div>'
    + f'<section style="{CARD}"><h2 style="{H2}">Try it</h2>'
      f'<p style="{LEAD}">Start at the Profile, tap the oasis card, then <b>رتّب</b> and <b>أصحابك</b>. Every phone also opens full-window from the row to the right, where it works like the app. The dashed strip under «Your oasis» is for testing only: it jumps a level, shows a friend taking a cutting, and switches on Ramadan nights.</p>'
      '<div style="display: flex; gap: 10px; align-items: flex-start;">'
    + phone('Profile', 844, 0.6, '<b>1. Profile</b><br>One new card.') + ARROW.format(top=240)
    + phone('Oasis', 954, 0.6, '<b>2. Your oasis</b><br>What your days grew.') + ARROW.format(top=240)
    + phone('Arrange', 844, 0.6, '<b>3. Arrange</b><br>Put things where you like.') + ARROW.format(top=240)
    + phone('Friends', 844, 0.6, '<b>4. Friends</b><br>Off until you turn it on.', 'start="list"')
    + '</div></section>'
    + f'<section style="{CARD}"><h2 style="{H2}">Every tap has a reason</h2>'
      '<div style="display: grid; grid-template-columns: 220px 1fr 1fr; gap: 18px; font-size: 13px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: #6B7A6F;"><div>You tap</div><div>What happens</div><div>Why</div></div>'
    + taps + '</section>'
    + '<div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 20px;">'
    + f'<section style="{CARD}"><h2 style="margin: 0; font-size: 24px; font-weight: 700;">What changes in the app</h2>'
    + bullets(['Profile gets one card under the stats.', 'The level-up message also says what grew.', 'Three new screens behind the card: your oasis, arrange, friends.',
               'Maybe: Premium gets a line or two (to decide).', '<b>Unchanged:</b> logging habits, the Grid, rooms, reminders, notifications, widgets.'])
    + '<p style="margin: 0; font-size: 15px; color: #6B7A6F;">Before and after on the board “What changes”.</p></section>'
    + f'<section style="{CARD}"><h2 style="margin: 0; font-size: 24px; font-weight: 700;">The rules it keeps</h2>'
    + bullets(['No notifications from the oasis, ever.', 'Growth is never sold: level and base come only from habits.', 'A visit shows the oasis and the level, never habits or prayers.',
               'Halal art: no people or animals, no faces on things; Doum is the only character.', 'Seasons are Ramadan and the two Eids only.', 'Buildings stand at the back, tall things in the middle, low things in front.'])
    + '</section></div>'
    + '<section style="background: #23352A; color: #F5F0E1; border-radius: 24px; padding: 28px 30px; display: flex; flex-direction: column; gap: 12px;">'
      '<h2 style="margin: 0; font-size: 30px; font-weight: 700;">Five questions for you</h2>'
      '<ol style="margin: 0; padding-left: 24px; font-size: 18px; line-height: 1.6;">' + ''.join(f'<li>{q}</li>' for q in QUESTIONS) + '</ol>'
      '<p style="margin: 0; font-size: 16px; color: #C9D6C9;">Leave a comment on any board, or tell Aziz. The boards “How it’s wired” and “What it takes” are for whoever builds it.</p></section>'
)
write('Main.dc.html', page('Doum’s oasis', main_body, 2720))

# ------------------------------------------------------------------ Changes: before and after
SNACK = ('<div style="display: flex; align-items: center; gap: 12px; background: #23352A; color: #F5F0E1; border-radius: 18px; padding: 12px 14px; min-height: 64px; box-sizing: border-box; direction: rtl; font-family: \'IBM Plex Sans Arabic\', sans-serif;">{inner}</div>')
before_snack = SNACK.format(inner='<span style="font-size: 16px; font-weight: 700;">ارتقاء مستوى  ·  LVL 25</span>')
after_snack = SNACK.format(inner=(f'<img src="{VEG}" alt="" style="width: 44px; height: 40px; object-fit: contain; background: #F5F0E1; border-radius: 12px; padding: 2px;">'
                                  '<span style="display: flex; flex-direction: column; gap: 2px; flex: 1;"><span style="font-size: 16px; font-weight: 700;">ارتقاء مستوى  ·  LVL 25</span>'
                                  '<span style="font-size: 14px; color: #C9D6C9;">نبتت الخضار في واحتك</span></span>'
                                  '<span style="font-size: 14px; font-weight: 700; color: #9FD88F; padding: 8px 4px;">شوف</span>'))
PREMIUM_ROW = ('<div style="display: flex; align-items: flex-start; gap: 12px; direction: rtl; font-family: \'IBM Plex Sans Arabic\', sans-serif; background: #FFFFFF; border-radius: 16px; padding: 12px 14px;">'
               '<img src="{src}" alt="" style="width: 40px; height: 40px; object-fit: contain;"><span style="display: flex; flex-direction: column; gap: 2px;"><span style="font-size: 16px; font-weight: 700;">{t}</span>'
               '<span style="font-size: 14px; color: #45574B;">{d}</span></span></div>')
prem = (PREMIUM_ROW.format(src=ic.ART['lanterns'][0], t='مواسم الواحة', d='زينة رمضان والعيدين، تطلع في وقتها وترجع كل سنة.')
        + PREMIUM_ROW.format(src=ic.ART['flowers'][0], t='ألوان واحتك', d='تختار لون السما والعشب والبحر بنفسك.'))
UNCHANGED = ['Logging a habit: the same taps as today.', 'The Grid, squares and streak rules.', 'Rooms and their scores.', 'Reminders and notifications: nothing new is sent.',
             'Widgets, prayer times, tasks.']


def pair(title, sub, left, right, lcap='Today', rcap='With the oasis'):
    return (f'<section style="{CARD}"><h2 style="{H2}">{title}</h2><p style="{LEAD}">{sub}</p>'
            '<div style="display: flex; gap: 32px; align-items: flex-start; flex-wrap: wrap;">'
            f'<div style="display: flex; flex-direction: column; gap: 10px;"><div style="font-size: 14px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: #6B7A6F;">{lcap}</div>{left}</div>'
            f'<div style="display: flex; flex-direction: column; gap: 10px;"><div style="font-size: 14px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: #2F6B3A;">{rcap}</div>{right}</div>'
            '</div></section>')


def mini_phone(board, sc=0.7):
    w, h = round(390 * sc), round(844 * sc)
    return (f'<div style="width: {w}px; height: {h}px; border-radius: 22px; overflow: hidden; box-shadow: 0 0 0 1px {CARD_BD}; position: relative; background: {CREAM};">'
            f'<div style="position: absolute; left: 0; top: 0; width: 390px; height: 844px; transform: scale({sc}); transform-origin: top left;"><dc-import name="{board}" hint-size="390px,844px"></dc-import></div></div>')


changes_body = (
    header('What changes', 'Two small changes and three new screens', 'Everything a person already does stays the same. The oasis lives behind one card, and the level-up message gets one more line.')
    + pair('1. Profile: one new card', 'Under the stats row. It shows your oasis, small, and what your next level grows. Tapping it opens your oasis.',
           mini_phone('ProfileBefore'), mini_phone('Profile'))
    + pair('2. The level-up message says what grew', 'Today it says only the level. With the oasis it also names what grew, with its picture; «شوف» opens the oasis, where Doum plants it.',
           f'<div style="width: 380px;">{before_snack}</div>', f'<div style="width: 380px;">{after_snack}</div>')
    + f'<section style="{CARD}"><h2 style="{H2}">3. Three new screens, behind the card</h2><p style="{LEAD}">Your oasis, Arrange and Friends. They open only from the card, so nobody meets them by accident. Try them in the row of phones.</p>'
      '<div style="display: flex; gap: 20px;">' + ''.join(mini_phone(b, 0.5) for b in ['Oasis', 'Arrange', 'Friends']) + '</div></section>'
    + '<div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 20px;">'
    + f'<section style="{CARD}"><h2 style="margin: 0; font-size: 24px; font-weight: 700;">Maybe: Premium, a line or two</h2>'
      '<p style="margin: 0; font-size: 16px; line-height: 1.55; color: #45574B;">The recommendation: looks, not speed. Two rows on the Premium screen people already know.</p>'
      f'<div style="display: flex; flex-direction: column; gap: 8px; background: {CREAM}; border-radius: 18px; padding: 10px;">{prem}</div></section>'
    + f'<section style="{CARD}"><h2 style="margin: 0; font-size: 24px; font-weight: 700;">Unchanged</h2>' + bullets(UNCHANGED) + '</section>'
    + '</div>'
)
write('Changes.dc.html', page('What changes', changes_body, 2450))

# ------------------------------------------------------------------ Wiring: a diagram of placed cards and arrows
HEAD_ID = 'dc-arrow-head-filled'
STROKE = '#8a8378'


def arrow_h(x, y, n, left=False):
    d = f'M {n} 4 L 0 4' if left else f'M 0 4 L {n} 4'
    return (f'<svg width="{n}" height="8" viewBox="0 0 {n} 8" preserveAspectRatio="none" style="position: absolute; left: {x}px; top: {y - 4}px; width: {n}px; height: 8px; overflow: visible; fill: none; stroke: {STROKE}; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round">'
            f'<defs><marker id="{HEAD_ID}" orient="auto" markerWidth="5" markerHeight="5" refX="3.2" refY="2" overflow="visible"><path d="M0 0 L4 2 L0 4 Z" fill="{STROKE}" stroke="none" style="fill: context-stroke"/></marker></defs>'
            f'<path d="{d}" marker-end="url(#{HEAD_ID})"></path></svg>')


def arrow_v(x, y, n, up=False):
    d = f'M 4 {n} L 4 0' if up else f'M 4 0 L 4 {n}'
    return (f'<svg width="8" height="{n}" viewBox="0 0 8 {n}" preserveAspectRatio="none" style="position: absolute; left: {x - 4}px; top: {y}px; width: 8px; height: {n}px; overflow: visible; fill: none; stroke: {STROKE}; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round">'
            f'<defs><marker id="{HEAD_ID}" orient="auto" markerWidth="5" markerHeight="5" refX="3.2" refY="2" overflow="visible"><path d="M0 0 L4 2 L0 4 Z" fill="{STROKE}" stroke="none" style="fill: context-stroke"/></marker></defs>'
            f'<path d="{d}" marker-end="url(#{HEAD_ID})"></path></svg>')


def line_h(x, y, n):
    return (f'<svg width="{n}" height="8" viewBox="0 0 {n} 8" preserveAspectRatio="none" style="position: absolute; left: {x}px; top: {y - 4}px; width: {n}px; height: 8px; overflow: visible; fill: none; stroke: {STROKE}; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round"><path d="M 0 4 L {n} 4"></path></svg>')


def line_v(x, y, n):
    return (f'<svg width="8" height="{n}" viewBox="0 0 8 {n}" preserveAspectRatio="none" style="position: absolute; left: {x - 4}px; top: {y}px; width: 8px; height: {n}px; overflow: visible; fill: none; stroke: {STROKE}; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round"><path d="M 4 0 L 4 {n}"></path></svg>')


def card(x, y, w, h, label, kind):
    bg, bd = {'old': ('#F3EEDF', '#D6CDB4'), 'new': ('#EEF6EC', '#A9CF9C'), 'screen': ('#FFFFFF', '#2F7A3A'), 'data': ('#FFFFFF', '#D6D2C4')}[kind]
    return (f'<div style="position: absolute; left: {x}px; top: {y}px; width: {w}px; height: {h}px; box-sizing: border-box; padding: 8px 12px; display: flex; align-items: center; justify-content: center; text-align: center; '
            f'background: {bg}; border: {"2px" if kind == "screen" else "1px"} solid {bd}; border-radius: 12px; font-size: 15px; line-height: 1.35;">{label}</div>')


def text(x, y, w, t, size=14, weight=700, color='#6B7A6F', upper=True):
    tt = 'text-transform: uppercase; letter-spacing: 0.06em;' if upper else ''
    return f'<div style="position: absolute; left: {x}px; top: {y}px; width: {w}px; font-size: {size}px; font-weight: {weight}; color: {color}; {tt}">{t}</div>'


AX, AW, BX, BW, CH = 64, 300, 520, 340, 80
ROWS = [240, 360, 480, 600, 720]
A_LAB = ['<span><b>Habits and tasks</b><br>pay gold, as today</span>', '<span><b>XP and level</b><br>the highest level ever</span>', '<span><b>Medals</b><br>as today</span>',
         '<span><b>7-day streaks</b><br>as today</span>', '<span><b>Rooms</b><br>people who turned Friends on</span>']
B_LAB = ['<span><b>What you build</b><br>and golden versions</span>', '<span><b>What grows, and the base</b><br>sand, stone, coral, gold, rainbow, pearl ring</span>',
         '<span><b>Dates on the palm</b><br>one bunch per medal family</span>', '<span><b>Pearls in the sea</b><br>one per streak week</span>', '<span><b>The friends list</b><br>highest level first</span>']
els = []
# arrows and lines first (paint order), then cards, then labels
for cy in ROWS:
    els.append(arrow_h(AX + AW, cy, BX - (AX + AW) - 2))
    els.append(line_h(BX + BW, cy, 940 - (BX + BW)))
els.append(line_v(940, ROWS[0], ROWS[-1] - ROWS[0]))
CX = 1020
els.append(arrow_h(940, 420, CX - 940 - 2))
# entry points down into the oasis page: many to one
els.append(line_v(1100, 280, 50)); els.append(line_v(1280, 280, 50)); els.append(line_h(1100, 330, 180))
els.append(arrow_v(1190, 330, 380 - 330 - 2))
# the oasis page out to arrange and friends: one to many
els.append(line_v(1190, 460, 50)); els.append(line_h(1100, 510, 180))
els.append(arrow_v(1100, 510, 560 - 510 - 2)); els.append(arrow_v(1280, 510, 560 - 510 - 2))
els.append(arrow_v(1280, 640, 700 - 640 - 2))
for cy, la, lb in zip(ROWS, A_LAB, B_LAB):
    els.append(card(AX, cy - CH // 2, AW, CH, la, 'old'))
    els.append(card(BX, cy - CH // 2, BW, CH, lb, 'new'))
els.append(card(1020, 200, 160, 80, '<span><b>Profile card</b><br>new</span>', 'screen'))
els.append(card(1200, 200, 160, 80, '<span><b>Level-up line</b><br>says what grew</span>', 'screen'))
els.append(card(1020, 380, 340, 80, '<span><b>Your oasis</b><br>Doum lives there; tap a thing for its story</span>', 'screen'))
els.append(card(1020, 560, 160, 80, '<span><b>Arrange</b><br>place, build, gild</span>', 'screen'))
els.append(card(1200, 560, 160, 80, '<span><b>Friends</b><br>off until turned on</span>', 'screen'))
els.append(card(1200, 700, 160, 80, '<span><b>A visit</b><br>take a cutting</span>', 'screen'))
els.append(card(64, 830, 1296, 96, '<span><b>Saved for each person:</b> the six places, what you own (and who gave each cutting), golden things, the Friends switch. '
                                   '<b>Only with Friends on:</b> a short news list («أخذ خالد شتلة فل»). <b>On the server:</b> the level friends see is checked there.</span>', 'data'))
els.append(text(64, 48, 1000, 'How it’s wired', 30, 700, INK, False))
els.append(text(64, 96, 1200, 'The oasis adds no new way to earn. It only reads what the app already counts, and draws it.', 17, 400, MUTED, False))
els.append(text(AX, 160, AW, 'In the app today'))
els.append(text(BX, 160, BW, 'The oasis reads it'))
els.append(text(1020, 160, 340, 'Screens'))
# legend and footer
els.append(text(64, 960, 1296, 'Grey: exists today. Green: new logic, reading what exists. Outlined: new or changed screens. Nothing here sends a notification, and logging a habit does not change.', 15, 600, MUTED, False))
wiring = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>How it’s wired</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&amp;family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&amp;display=swap" rel="stylesheet">
<style>
body{{margin:0}}
</style>
</helmet>
<div style="position: relative; width: 1440px; height: 1040px; background: {CREAM}; color: {INK}; font-family: 'IBM Plex Sans', 'IBM Plex Sans Arabic', sans-serif;">
{''.join(els)}
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1440,"height":1040}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {{}};
  }}
}}
</script>
</body>
</html>
"""
wiring = re.sub(r'>([^<]+)<', lambda m: '>' + AR.sub(lambda a: '<bdi dir="rtl">' + a.group(0) + '</bdi>', m.group(1)) + '<', wiring)
write('Wiring.dc.html', wiring)

# ------------------------------------------------------------------ Build: what is done, the waves, the decisions
DONE = ['All the art: eleven drawn sheets (the palm by level, trees, flowers, built things, showpieces, the room) and Doum’s frames (walking in five directions, standing, sitting, watering, planting, taking a cutting).',
        'Sizes and places: Doum is the yardstick; every thing has a height and a place; nothing hides his hands.',
        'The motion spec: speed, walk cycle, landing, sitting, depth, Reduce Motion.',
        'This prototype, with every tap tested.', 'A playbook with the steps and prompts for adding a new thing or a new Doum move.']
WAVES = [
    ('1', 'Everyone', 'Profile card; your oasis drawn from the level, medals and streak weeks; Doum standing, walking and his small life; tap for a thing’s story; the level-up line and the planting moment.', 'Largest: the island drawing and Doum’s animation'),
    ('2', 'Everyone', 'Arrange: six places, build with gold, golden versions; saved per person.', 'Medium'),
    ('3', 'Only if turned on', 'Friends: the list from rooms, a visit, cuttings, the quiet news line; the server check on the shown level.', 'Medium, with server work'),
    ('4', 'Later', 'Seasons (Ramadan and the two Eids) and the Premium lines, once decided.', 'Small'),
]
waves = ''.join(f'<div style="display: grid; grid-template-columns: 60px 160px 1fr 260px; gap: 16px; padding: 14px 0; border-top: 1px solid #ECE5D3; font-size: 16px; line-height: 1.5;">'
                f'<div style="font-size: 26px; font-weight: 700; color: {GREEN};">{n}</div><div style="font-weight: 700;">{who}</div><div>{what}</div><div style="color: {MUTED};">{size}</div></div>' for n, who, what, size in WAVES)
CALLS = [('Premium: looks, not 2x gold', 'Seasons, your own colours and real palms. Gold is already in surplus (an active person earns about 1,650 a month), so doubling it is a weak reason to pay.'),
         ('Fair rank', 'Free accounts have 10 habits and Premium has no cap. Count at most 10 habits a day toward level, so nobody buys a higher base; tracking stays unlimited.'),
         ('A level the server checks', 'Clock tricks are already blocked, but the phone writes level, XP and gold. Check the level friends see on the server before Friends ships.'),
         ('Plant only on a new highest level', 'Undo takes XP back exactly, so a level can drop. The oasis follows the highest level ever: nothing is taken away, and the planting moment never plays twice.')]
calls = ''.join(f'<div style="display: flex; flex-direction: column; gap: 2px; padding: 12px 0; border-top: 1px solid #ECE5D3;"><div style="font-size: 17px; font-weight: 700;">{i + 1}. {a}</div>'
                f'<div style="font-size: 16px; line-height: 1.5; color: {MUTED};">{b}</div></div>' for i, (a, b) in enumerate(CALLS))
RISKS = [('Older phones', 'Doum’s frames are small WebP pictures (about 50); loaded once with the app, one animation running at a time.'),
         ('It distracts from habits', 'It lives behind one card, sends nothing, and changes nothing about logging.'),
         ('People game the level', 'The daily XP ceiling exists today; add the 10-habit count and the server check above.'),
         ('It grows slowly after month four', 'Gold keeps it moving: building and golden versions, plus medals ripening dates and streak weeks bringing pearls.')]
risks = ''.join(f'<div style="display: grid; grid-template-columns: 240px 1fr; gap: 16px; padding: 12px 0; border-top: 1px solid #ECE5D3; font-size: 16px; line-height: 1.5;"><div style="font-weight: 700;">{a}</div><div>{b}</div></div>' for a, b in RISKS)
build_body = (
    header('What it takes', 'Ready to build, in four waves', 'The design work is done and tested as this prototype. Building is mostly the island drawing and Doum’s animation in the app; everything else reads data the app already has.')
    + f'<section style="{CARD}"><h2 style="{H2}">Already done</h2>' + bullets(DONE) + '</section>'
    + f'<section style="{CARD}"><h2 style="{H2}">The waves</h2>'
      '<div style="display: grid; grid-template-columns: 60px 160px 1fr 260px; gap: 16px; font-size: 13px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: #6B7A6F;"><div>Wave</div><div>Who sees it</div><div>What</div><div>Size</div></div>'
    + waves + '<p style="margin: 0; font-size: 15px; color: #6B7A6F;">Each wave ships on its own; wave 1 alone is a complete feature.</p></section>'
    + f'<section style="{CARD}"><h2 style="{H2}">Four decisions before building</h2>{calls}</section>'
    + f'<section style="{CARD}"><h2 style="{H2}">Risks, and the answer to each</h2>{risks}</section>'
)
write('Build.dc.html', page('What it takes', build_body, 2080))

# ------------------------------------------------------------------ swap image ids for this canvas's copies
BLOBMAP = json.load(open(os.path.join(HERE, 'check', 'blobmap.json')))
IDS_PATH = os.path.join(HERE, 'proposal', 'blob_ids.json')
IDS = json.load(open(IDS_PATH)) if os.path.exists(IDS_PATH) else {}
missing = set()
for name in sorted(os.listdir(SRC)):
    s = open(os.path.join(SRC, name)).read()

    def swap(m):
        old = m.group(1)
        local = BLOBMAP.get(old)
        if local and local in IDS:
            return '/_blob/' + IDS[local]
        missing.add(local or ('?' + old))
        return m.group(0)
    s = re.sub(r'/_blob/([0-9a-f]{32})', swap, s)
    open(os.path.join(OUT, name), 'w').write(s)
open(os.path.join(HERE, 'proposal', 'to_upload.json'), 'w').write(json.dumps(sorted(missing), indent=1))
print(len(os.listdir(OUT)), 'boards;', len(missing), 'images still to upload (proposal/to_upload.json)')

# ------------------------------------------------------------------ the canvas index
NOW = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
idx_path = os.path.join(OUT, 'canvas.json')
created = json.load(open(idx_path))['createdOnFiles'] if os.path.exists(idx_path) else {'v': 1, 'at': NOW}
boards = {
    'Main.dc.html': dict(x=0, y=0, w=1440, h=2720, expand='fill', title='Start here: Doum’s oasis, the proposal'),
    'ProfileBefore.dc.html': dict(x=1560, y=0, w=390, h=844, title='Today: Profile, for comparison'),
    'Profile.dc.html': dict(x=2030, y=0, w=390, h=844, is_interactive=True, title='1. Profile with the oasis card (press Play, start here)'),
    'Oasis.dc.html': dict(x=2500, y=0, w=390, h=954, is_interactive=True, title='2. Your oasis (test buttons under the phone)'),
    'Arrange.dc.html': dict(x=2970, y=0, w=390, h=844, is_interactive=True, title='3. Arrange'),
    'Friends.dc.html': dict(x=3440, y=0, w=390, h=844, is_interactive=True, title='4. Friends'),
    'Island.dc.html': dict(x=3910, y=0, w=360, h=400, is_interactive=True, title='The island drawing every screen uses (Tweaks: level, sky, colours)'),
    'Changes.dc.html': dict(x=1560, y=1500, w=1440, h=2450, expand='fill', title='What changes in the app'),
    'Wiring.dc.html': dict(x=3120, y=1500, w=1440, h=1040, title='How it’s wired'),
    'Build.dc.html': dict(x=4680, y=1500, w=1440, h=2080, expand='fill', title='What it takes'),
}
notes = {
    'rowTry': dict(kind='title1', text='Try it: tap through like the app', x=1560, y=-300, maxW=3210),
    'rowBuild': dict(kind='title1', text='For whoever builds it', x=1560, y=1200, maxW=4560),
    'nTest': dict(fill='green', size='m', w=420, x=4350, y=0, text=(
        'How to test\n\n'
        '1. Press Play on «1. Profile», or open it full-window.\n'
        '2. Tap the oasis card. Wait two seconds: Doum walks to the bench and sits.\n'
        '3. Tap the palm, a plant, the bench. Under the phone (testing only): «مستوى جديد» and «ليالي رمضان».\n'
        '4. «رتّب»: tap the + place and pick ورد (houses and trees only fit further back). Tap the pomegranate: «نسخة ذهبية من هذا».\n'
        '5. «أصحابك»: «شغّلها», Yousef, the sidr, «خذ شتلة».\n\n'
        'Leave a comment on anything.')),
}
index = {'v': 3, 'createdOnFiles': created, 'title': 'Doum’s Oasis: should we build it?', 'launch': {'view': 'canvas'}, 'pages': [],
         'boards': boards, 'order': list(boards), 'notes': notes, 'designSystems': []}
open(idx_path, 'w').write(json.dumps(index, indent=2, ensure_ascii=False))
print('canvas.json', len(boards), 'boards')
