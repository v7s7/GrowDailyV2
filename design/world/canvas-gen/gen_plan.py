"""Generates project/Plan.dc.html (the plan in one page) and project/Deeper.dc.html (visits and level 100)."""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic
A = ic.ART
H2 = 'margin: 0; font-size: 34px; font-weight: 700;'
LEAD = 'margin: 0; font-size: 18px; line-height: 1.55; color: #45574B; max-width: 1000px;'
AR = re.compile(r'«?[؀-ۿ][؀-ۿ\s:0-9،]*[؀-ۿ0-9]»?|«[؀-ۿ]»')


def page(title, body, height, style=''):
    html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&amp;family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&amp;display=swap" rel="stylesheet">
<style>
body{{margin:0}}
{style}
</style>
</helmet>
<div style="background: #F5F0E1; color: #23352A; font-family: 'IBM Plex Sans', sans-serif; min-height: 100vh;">
<div style="max-width: 1440px; margin: 0 auto; box-sizing: border-box; padding: 64px 48px 88px; display: flex; flex-direction: column; gap: 56px;">
{body}
</div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1440,"height":{height}}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {{}};
  }}
}}
</script>
</body>
</html>
"""
    return re.sub(r'>([^<]+)<', lambda m: '>' + AR.sub(lambda a: '<bdi dir="rtl">' + a.group(0) + '</bdi>', m.group(1)) + '<', html)


def header(eyebrow, h1, intro):
    return (f'<header style="display: flex; flex-direction: column; gap: 16px; max-width: 1060px;">'
            f'<div style="font-size: 15px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: #3F7A4A;">{eyebrow}</div>'
            f'<h1 style="margin: 0; font-size: 56px; line-height: 1.06; font-weight: 700;">{h1}</h1>'
            f'<p style="margin: 0; font-size: 20px; line-height: 1.5; color: #45574B; text-wrap: pretty;">{intro}</p></header>')


def phones(lst, scale=0.7):
    w, h = round(390 * scale), round(844 * scale)
    return ''.join(
        f'<div style="display: flex; flex-direction: column; gap: 10px; align-items: center;">'
        f'<div style="width: {w}px; height: {h}px; border-radius: 26px; overflow: hidden; box-shadow: 0 0 0 1px #E1D9C4; position: relative; background: #F5F0E1;">'
        f'<div style="position: absolute; left: 0; top: 0; width: 390px; height: 844px; transform: scale({scale}); transform-origin: top left;">'
        f'<dc-import name="{n}" hint-size="390px,844px"></dc-import></div></div>'
        f'<div style="font-size: 15px; color: #45574B; text-align: center; max-width: {w}px;">{c}</div></div>'
        for n, c in lst)


# ================================================================ Plan
depths = [
    ('0', 'Everyone', 'Without doing anything', ['A card on Profile with their island. It grows with their level.', 'One extra line in the level-up message they already get: what grew.', 'Nothing else changes: habits, the Grid, tasks and rooms work exactly as today.'], 'Nothing to do', '#FFFFFF'),
    ('1', 'People who tap the card', 'The oasis page', ['Tap things and they react; Doum walks over and says when they grew.', 'Build with gold, choose what stands out, rare pieces at each base, colours, the collection.', 'Edit any time, at any level, even at 100.'], 'Tap the card', '#FFFFFF'),
    ('2', 'People who want friends in it', 'Neighbours', ['A map of friends’ islands: people in your rooms who also turned it on.', 'Walk around a friend’s island, water it, leave a gift, like it, take a date or a cutting home, take a photo, go inside.', 'The weekly show, only in rooms where the leader turns it on.'], 'One switch «الجيران» on the oasis page. Off until they turn it on.', '#EEF6EC'),
    ('3', 'People who pay', 'Premium', ['2x gold: build twice as fast. The level stays earned.', 'Real palms, seasonal looks, own colours.'], 'Premium, which already exists', '#FFF3C4'),
]
def lis(items):
    return ''.join('<li style="margin-bottom: 6px;">' + x + '</li>' for x in items)


depth_cards = ''.join(
    f'<div style="background: {bg}; border-radius: 24px; padding: 22px; display: flex; flex-direction: column; gap: 10px;">'
    f'<div style="display: flex; align-items: center; gap: 10px;"><span style="width: 36px; height: 36px; border-radius: 99px; background: #23352A; color: #F5F0E1; font-weight: 700; font-size: 17px; display: flex; align-items: center; justify-content: center;">{n}</span>'
    f'<div style="display: flex; flex-direction: column;"><span style="font-size: 20px; font-weight: 700;">{who}</span><span style="font-size: 14px; color: #6B7A6F;">{what}</span></div></div>'
    f'<ul style="margin: 0; padding: 0 0 0 18px; font-size: 15px; line-height: 1.55; color: #45574B;">{lis(items)}</ul>'
    f'<div style="margin-top: auto; font-size: 14px; font-weight: 700; color: #2F6B3A;">How: {how}</div></div>'
    for n, who, what, items, how, bg in depths)

never = ['Notifications of any kind, including “someone visited you”', 'Screens or sheets that open by themselves', 'Red dots or badges', 'Messages about a thirsty island',
         'Visit streaks, daily login gifts, anything you lose by not coming', 'Chat or typed messages', 'Ranking strangers', 'Selling the level or anything that grows', 'Random boxes']
never_html = ''.join(f'<li style="display: flex; gap: 10px; align-items: baseline; padding: 6px 0;"><span style="color: #C24E3A; font-weight: 700;">✕</span><span>{x}</span></li>' for x in never)

defaults = [
    ('Island card on Profile', 'Shown', '«أخفِ الواحة» in the card’s menu removes it'),
    ('What grew, in the level-up message', 'Shown', 'Goes away with the card'),
    ('Quiet days', 'Colours stay the same', 'Admin switch for the thirsty look'),
    ('Neighbours (visits, gifts, likes)', 'Off', 'The person turns it on, on the oasis page'),
    ('Island next to your name in rooms', 'Off', 'Only with Neighbours on'),
    ('Weekly show', 'Off', 'A room leader turns it on in room settings'),
    ('Home Screen widget', 'Not added', 'The person adds it'),
    ('App icon stages', 'Not changed', 'The icon picker that exists'),
    ('Notifications', 'None, ever', 'Nothing to turn off'),
]
def_rows = ''.join(f'<div style="display: grid; grid-template-columns: 1.3fr 1fr 1.5fr; gap: 16px; padding: 12px 0; border-bottom: 1px solid #EFE9DA; font-size: 16px;"><span style="font-weight: 700;">{a}</span><span style="color: {"#2F7A3A" if b in ("Off", "None, ever", "Not added", "Not changed") else "#23352A"}; font-weight: 600;">{b}</span><span style="color: #45574B;">{c}</span></div>' for a, b, c in defaults)

phases = [
    ('1', 'The quiet island', 'Profile card, oasis page, Builder (grow, gold, rare), the line in the level-up message.', 'Watch: how many open the oasis page once a week.'),
    ('2', 'Neighbours', 'The switch, the map, visits with water, likes and the visitors’ book.', 'Watch: how many turn it on, and whether they visit back.'),
    ('3', 'Deeper visits', 'Walking, taking a date or cutting home, gifts, photo, inside the house (needs Sheet 7), weekly show, team lanterns.', 'Watch: visits per person who turned Neighbours on.'),
    ('4', 'Premium and level 100', '2x gold, seasons, own colours; editing with more places, flip, golden versions, three designs; real palms once a partner is signed.', 'Watch: Premium from people who use the oasis.'),
]
phase_html = ''.join(f'<div style="background: #FFFFFF; border-radius: 20px; padding: 20px 22px; display: flex; flex-direction: column; gap: 8px;"><div style="display: flex; align-items: center; gap: 10px;"><span style="width: 32px; height: 32px; border-radius: 99px; background: #2F7A3A; color: #FFFFFF; font-weight: 700; display: flex; align-items: center; justify-content: center;">{n}</span><span style="font-size: 19px; font-weight: 700;">{t}</span></div><p style="margin: 0; font-size: 15px; line-height: 1.55; color: #45574B;">{d}</p><p style="margin: 0; font-size: 14px; color: #6B7A6F;">{m}</p></div>' for n, t, d, m in phases)

choices = [
    ('Neighbours off until the person turns it on?', 'Recommended: yes. Normal users never meet it.'),
    ('Premium gives 2x gold, not 2x XP?', 'Recommended: yes.'),
    ('The weekly show off until a room leader turns it on?', 'Recommended: yes (changed from “on”).'),
    ('Gifts free, once a day per friend, never asking for one back?', 'Recommended: yes.'),
    ('Golden versions at level 50 and up, 2,000 gold each?', 'Recommended: yes. Gold stays useful for years.'),
    ('Real palms with a planting partner?', 'Recommended: yes, after a price per palm.'),
]
choice_rows = ''.join(f'<div style="display: flex; flex-direction: column; gap: 4px; padding: 14px 0; border-bottom: 1px solid #EFE9DA;"><span style="font-weight: 700; font-size: 17px;">{i + 1}. {a}</span><span style="font-size: 15px; color: #45574B;">{b}</span></div>' for i, (a, b) in enumerate(choices))

boards = [('Deeper', 'A visit step by step, level 100, the five views'), ('Together', 'What Forest, Duolingo, Finch, Animal Crossing teach; paying'),
          ('Proud', 'The look: real art, bases, the plate'), ('Fits', 'XP grows it, gold builds in it'), ('Builder', 'Play: build your oasis')]
board_links = ''.join(f'<a href="{n}.dc.html" style="background: #FFFFFF; border-radius: 16px; padding: 14px 16px; text-decoration: none; color: #23352A; display: flex; flex-direction: column; gap: 4px;"><span style="font-weight: 700; font-size: 16px;">{n}</span><span style="font-size: 14px; color: #45574B;">{d}</span></a>' for n, d in boards)

plan_body = header(
    'The plan, in one page',
    'Quiet for everyone, deep for those who love it',
    'Your habits grow Doum’s island. Nobody is pushed into it: no notifications, no pop-ups, no badges. A normal user sees one card on Profile and one line when they level up. People who love it can build, visit friends and go as deep as they like.'
) + f"""
<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">Four depths</h2>
<p style="{LEAD}">Each depth is a choice the person makes. Nothing pulls them from one depth to the next.</p>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(300px, 100%), 1fr)); gap: 16px;">{depth_cards}</div>
</section>

<section style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 32px; align-items: start;">
<div style="display: flex; flex-direction: column; gap: 14px;">
<h2 style="{H2}">Never</h2>
<ul style="margin: 0; padding: 0; list-style: none; font-size: 17px; line-height: 1.45; background: #FFFFFF; border-radius: 24px; padding: 12px 24px;">{never_html}</ul>
</div>
<div style="display: flex; flex-direction: column; gap: 14px;">
<h2 style="{H2}">Where news waits</h2>
<div style="background: #FFFFFF; border-radius: 24px; padding: 20px 24px; display: flex; flex-direction: column; gap: 12px; font-size: 17px; line-height: 1.55; color: #45574B;">
<p style="margin: 0;">Only on the oasis page, as one quiet line, and only when the person opens it: «زارك 3 اليوم».</p>
<p style="margin: 0;">The level-up message they already get says what grew. That is the only place the oasis speaks outside its own page.</p>
<p style="margin: 0; font-size: 15px; color: #6B7A6F;">From Amber Case, Calm Technology (2015): technology should need the smallest possible amount of attention, and inform without demanding it.</p>
</div>
<div style="background: #23352A; color: #F5F0E1; border-radius: 24px; padding: 20px 24px; font-size: 17px; line-height: 1.55;">
<b>What a normal user notices:</b> one card on Profile, one line when they level up. Zero extra taps to log a habit.
</div>
</div>
</section>

<section style="display: flex; flex-direction: column; gap: 14px;">
<h2 style="{H2}">Every default</h2>
<div style="background: #FFFFFF; border-radius: 24px; padding: 4px 24px;">
<div style="display: grid; grid-template-columns: 1.3fr 1fr 1.5fr; gap: 16px; padding: 12px 0; border-bottom: 2px solid #E6DFCC; font-size: 14px; font-weight: 700; color: #6B7A6F; text-transform: uppercase; letter-spacing: 0.06em;"><span>Thing</span><span>Default</span><span>Who changes it</span></div>
{def_rows}
</div>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">Build order</h2>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(300px, 100%), 1fr)); gap: 16px;">{phase_html}</div>
</section>

<section style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 32px; align-items: start;">
<div style="display: flex; flex-direction: column; gap: 10px;">
<h2 style="{H2}">Your choices</h2>
<div style="background: #FFFFFF; border-radius: 24px; padding: 4px 24px;">{choice_rows}</div>
</div>
<div style="display: flex; flex-direction: column; gap: 10px;">
<h2 style="{H2}">Read more</h2>
<div style="display: grid; gap: 10px;">{board_links}</div>
</div>
</section>
"""
open(os.path.join(HERE, 'project', 'Plan.dc.html'), 'w').write(page('The plan', plan_body, 3400))
print('Plan')

# ================================================================ Deeper
steps = [
    ('dhow', 'Sail over', 'Tap a friend’s island on the map. Your Doum crosses on his boat and lands on their beach.'),
    ('palm_young', 'Walk', 'A close camera follows your Doum. Tap the ground to walk, tap a thing to go to it. Their Doum waves.'),
    ('fountain', 'Play with their things', 'Each thing does something: sit on the bench, light the lanterns, fill your can at the well.'),
    ('coral_house', 'Read its story', 'Every thing has a line: who built it, at what level, which day. Never a habit.'),
    ('dates_rutab', 'Take something home', 'One date from their palm and one cutting of a plant, once a day per friend. They go in your collection with their name.'),
    ('harvest_basket', 'Leave something', 'Water, a gift that sits on their sand for a week, a like. They see it next time they open the oasis, quietly.'),
    ('lanterns', 'Take a photo', 'A framed picture of their island with your Doum in it, to keep or share.'),
    ('frond_hut', 'Go inside', 'If they built a house, step into their room and see how they set it up.'),
]
step_cards = ''.join(
    f'<div style="background: #FFFFFF; border-radius: 22px; padding: 18px; display: flex; flex-direction: column; gap: 8px;">'
    f'<div style="display: flex; align-items: center; gap: 12px;"><span style="width: 52px; height: 52px; border-radius: 16px; background: #EEF6EC; display: flex; align-items: center; justify-content: center; flex-shrink: 0;"><img src="{A[a][0]}" alt="" style="width: 42px; height: 42px; object-fit: contain;"></span>'
    f'<span style="font-size: 13px; font-weight: 700; color: #6B7A6F;">{i + 1}</span><span style="font-size: 19px; font-weight: 700;">{t}</span></div>'
    f'<p style="margin: 0; font-size: 15px; line-height: 1.55; color: #45574B;">{d}</p></div>'
    for i, (a, t, d) in enumerate(steps))

take_home = [
    ('Dates from neighbours «تمر الجيران»', 'One date a day from each friend’s palm. Dates from 5 different neighbours complete the set and unlock a showpiece: a basket of neighbours’ dates.'),
    ('Cuttings «عقلة»', 'A cutting of a friend’s plant: «فل خالد», «رمان يوسف». It grows into your own plant with their name on its story line. Looks only; it never skips a level.'),
    ('No gold, no XP from visits', 'So nobody farms visits, and nobody feels they must.'),
]
take_rows = ''.join(f'<div style="display: flex; flex-direction: column; gap: 4px; padding: 12px 0; border-bottom: 1px solid #EFE9DA;"><span style="font-weight: 700; font-size: 17px;">{a}</span><span style="font-size: 15px; line-height: 1.55; color: #45574B;">{b}</span></div>' for a, b in take_home)

places = [('Sand, 1', '6'), ('Stone, 5', '7'), ('Coral, 10', '8'), ('Gold, 20', '10'), ('Rainbow, 35', '11'), ('Pearl ring, 50', '12'), ('Star crown, 75', '14')]
place_cells = ''.join(f'<div style="background: #FFFFFF; border-radius: 16px; padding: 14px; display: flex; flex-direction: column; align-items: center; gap: 2px;"><span style="font-size: 28px; font-weight: 700; color: #2F7A3A;">{n}</span><span style="font-size: 13px; color: #45574B; text-align: center;">{b}</span></div>' for b, n in places)

elder = [
    ('Move anything, anywhere', 'Every place takes anything you own. Swap, move, empty. Always open, at every level.'),
    ('Flip', 'Face a thing the other way. Small, but it is what makes a layout feel yours.'),
    ('Golden versions «ذهّبها»', 'From level 50: turn any made thing gold for 2,000 gold. The most visible sign of a long road, and it keeps gold useful for years.'),
    ('Three designs', 'From level 20: keep three layouts and switch between them, for example a Ramadan one. Clash of Clans players keep several bases for the same reason.'),
    ('Inside the house', 'Rooms to set up with your own things, seen by guests (Sheet 7 below).'),
    ('Paths and ponds, later', 'Paint stone paths and small ponds on the grass. Animal Crossing opens its Island Designer only after the island reaches 3 stars, about two weeks in, and it became the main thing late players do.'),
    ('Try a friend’s layout', 'On a visit, «جرّب ترتيبها» copies their arrangement into your empty design, using only things you own.'),
]
elder_cards = ''.join(f'<div style="background: #FFFFFF; border-radius: 20px; padding: 18px 20px; display: flex; flex-direction: column; gap: 6px;"><span style="font-size: 18px; font-weight: 700;">{a}</span><span style="font-size: 15px; line-height: 1.55; color: #45574B;">{b}</span></div>' for a, b in elder)

views = [('Overview', 'The whole island as a small diorama.', 'Profile card, oasis page, rooms, widget'),
         ('Walk', 'Close camera that follows Doum.', 'Visiting, or walking your own island'),
         ('Edit', 'The island with its places marked and your collection below.', 'Building and rearranging'),
         ('Inside', 'A room in Doum’s house.', 'Decorating, and guests stepping in'),
         ('Photo', 'A framed picture, no buttons.', 'Keeping or sharing a moment')]
view_rows = ''.join(f'<div style="display: grid; grid-template-columns: 140px 1.2fr 1fr; gap: 16px; padding: 12px 0; border-bottom: 1px solid #EFE9DA; font-size: 16px;"><span style="font-weight: 700;">{a}</span><span style="color: #45574B;">{b}</span><span style="color: #6B7A6F;">{c}</span></div>' for a, b, c in views)

research = [
    ('Animal Crossing', 'Each island has its own fruit; foreign fruit sells for 500 bells against 100, so people visit friends to trade. Island Designer (paths, water, cliffs) opens only after a 3-star island, and late players spend most of their time there.'),
    ('Hay Day', 'Visiting a friend’s farm: see how they designed it, help with the orders on their board, buy from their roadside shop.'),
    ('Clash of Clans', 'Several saved base layouts, and a link that opens a friend’s layout in your editor to adjust before saving.'),
    ('Finch', 'Tree Town: visit friends’ trees and see how their pet grows; furniture and wallpaper for the pet’s house, bought with stones earned from goals.'),
    ('Amy Jo Kim, Game Thinking', 'Four stages: discovery, onboarding, habit-building, mastery. Mastery needs an “elder game” for enthusiasts, the people who have done everything.'),
    ('Raph Koster', 'Max-level players need something to do that is not more levels; early online worlds lost them when the climb stopped.'),
]
research_cards = ''.join(f'<div style="background: #FFFFFF; border-radius: 20px; padding: 18px 20px; display: flex; flex-direction: column; gap: 6px;"><span style="font-size: 18px; font-weight: 700;">{a}</span><span style="font-size: 15px; line-height: 1.55; color: #45574B;">{b}</span></div>' for a, b in research)

SHEET7 = """A sticker sheet of 12 separate objects for a cute children’s-app world, in the same style as the green sprout mascot I attached. 4 columns × 3 rows, 1536 × 1024 px, each cell 384 × 341 px with 48 px of clear space inside every edge. Transparent background, no backdrop, no glow around the objects.
Style: thick dark green outline (#1E3A24, about 6 px), flat fills with one soft lighter shade, no gradients, no textures, no shadows on the ground.
Every object stands on the same invisible baseline 50 px above the bottom of its cell, centred left to right, seen from the front and slightly above. These go inside a Gulf house, so they are a little smaller than outdoor objects.
No text, no numbers, no letters. No faces on anything. No people, no animals, no birds, no insects, no mascot. No pictures of beings in frames.

1. A carved wooden chest with brass studs (mandoos)
2. A brass coffee pot with three small cups on a round tray
3. A brass incense burner with a thin curl of smoke
4. A set of floor cushions with a back cushion, red and cream stripes
5. A low round wooden table
6. A carved wooden door with brass rings
7. A wooden lattice window screen
8. A tall wooden shelf with clay pots and plain books
9. A hanging brass lantern on a short chain
10. A small palm in a clay pot
11. A framed geometric pattern in blue and gold
12. A round woven palm-frond floor mat"""

deeper_body = header(
    'Deeper',
    'A visit is a short trip, and level 100 is where building starts',
    'Your questions: what happens when you visit, and what someone does at level 100 when everything is open. A visit becomes a walk with things to do and things to take home. At 100 the island keeps changing because the person keeps designing it. All of it lives in depths 1 and 2 of the plan: nobody meets it unless they go looking.'
) + f"""
<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">Try it</h2>
<p style="{LEAD}">Press Play. On the walk, tap the palm, the jasmine, the bench, the lanterns and the house.</p>
<div style="display: flex; gap: 28px; flex-wrap: wrap;">{phones([('Walk', 'Walking Khalid’s island'), ('Edit', 'Editing at level 100'), ('Inside', 'Inside the coral house')])}</div>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">A visit, step by step</h2>
<p style="{LEAD}">About a minute. Walking and looking are unlimited; taking and leaving are once a day per friend. Nothing on the island ever shows a habit, a prayer or a quiet day.</p>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(300px, 100%), 1fr)); gap: 14px;">{step_cards}</div>
</section>

<section style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 32px; align-items: start;">
<div style="display: flex; flex-direction: column; gap: 10px;">
<h2 style="{H2}">A reason to visit: what you take home</h2>
<p style="margin: 0; font-size: 17px; line-height: 1.55; color: #45574B;">Animal Crossing’s trick: every island has something yours does not.</p>
<div style="background: #FFFFFF; border-radius: 24px; padding: 4px 24px;">{take_rows}</div>
</div>
<div style="display: flex; flex-direction: column; gap: 10px;">
<h2 style="{H2}">Five views</h2>
<div style="background: #FFFFFF; border-radius: 24px; padding: 4px 24px;">{view_rows}</div>
</div>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">Level 100: editing never ends</h2>
<p style="{LEAD}">Editing is open at every level. Higher bases add more places, so the island fills out as you go:</p>
<div style="display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 10px;">{place_cells}</div>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(300px, 100%), 1fr)); gap: 14px;">{elder_cards}</div>
<p style="margin: 0; font-size: 16px; line-height: 1.55; color: #45574B;">Gold keeps coming at 100: about 48 a day at 6 habits, 17,500 a year. Golden versions of 20 things cost 40,000, so there is always something to save for, without ever selling growth.</p>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">What the games do</h2>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(400px, 100%), 1fr)); gap: 14px;">{research_cards}</div>
</section>

<section style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 24px; align-items: start;">
<div style="background: #23352A; color: #F5F0E1; border-radius: 24px; padding: 26px 28px; display: flex; flex-direction: column; gap: 12px;">
<div style="font-size: 15px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: #9FD88F;">Sheet 7 for ChatGPT · inside the house</div>
<div style="font-size: 15px; line-height: 1.6; white-space: pre-wrap; font-family: 'IBM Plex Mono', ui-monospace, monospace; user-select: all;">{SHEET7}</div>
<div style="font-size: 14px; color: #C9D6C9;">Attach the same Doum sheet. Sheet 6 came back on a painted backdrop; this asks for a clear one, though the cutter handles both now.</div>
</div>
<div style="display: flex; flex-direction: column; gap: 10px;">
<h2 style="{H2}">Sources</h2>
<ul style="margin: 0; padding: 0 0 0 18px; font-size: 15px; line-height: 1.6;">
<li><a href="https://www.gamespot.com/articles/animal-crossing-terraforming-guide-how-to-unlock-a/1100-6475813" style="color: #2F6B3A;">Animal Crossing: unlocking Island Designer (GameSpot)</a></li>
<li><a href="https://www.inverse.com/gaming/animal-crossing-new-horizons-3-star-island-designer-terraforming" style="color: #2F6B3A;">Island Designer after 3 stars (Inverse)</a></li>
<li><a href="https://www.tomsguide.com/news/animal-crossing-new-horizons-multiplayer" style="color: #2F6B3A;">Animal Crossing native fruit and visits (Tom’s Guide)</a></li>
<li><a href="https://www.supercheats.com/hay-day/walkthrough/the-social-side-of-hay-day" style="color: #2F6B3A;">Hay Day, the social side (SuperCheats)</a></li>
<li><a href="https://apps.apple.com/app/id6740085081" style="color: #2F6B3A;">Clash of Clans layout links (ClashLy)</a></li>
<li><a href="https://www.internetmatters.org/advice/apps-and-platforms/wellbeing/finch/" style="color: #2F6B3A;">Finch, Tree Town and the house (Internet Matters)</a></li>
<li><a href="https://uwaterloo.ca/gamification/node/68" style="color: #2F6B3A;">Amy Jo Kim, the player journey</a></li>
<li><a href="https://massivelyop.com/2019/03/07/vague-patch-notes-its-not-the-mmo-endgame-its-the-sudden-stop-at-the-end/" style="color: #2F6B3A;">Raph Koster on the endgame (Massively OP)</a></li>
</ul>
</div>
</section>
"""
open(os.path.join(HERE, 'project', 'Deeper.dc.html'), 'w').write(page('Deeper', deeper_body, 5200))
print('Deeper')
