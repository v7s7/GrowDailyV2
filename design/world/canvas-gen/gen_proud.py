"""Generates project/Proud.dc.html: why the oasis now looks like something to be proud of."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic

ARB = "font-family: 'IBM Plex Sans Arabic', sans-serif;"

before = ['A green ball; things sit on its edge, about 30 px each',
          'Thin drawings, all about the same size',
          'Your level shows nowhere on it',
          'Something new looks the same as something old']
after = ['A flat island; things stand on it, about 80 px each',
         'The real art from your five sheets',
         'A plate with your level, on a base that changes as you go up',
         'A new thing sparkles and glows until you have seen it']


def bullets(items, colour):
    return ''.join(f'<li style="display: flex; gap: 10px; align-items: baseline;"><span style="width: 8px; height: 8px; border-radius: 99px; background: {colour}; flex-shrink: 0; transform: translateY(-2px);"></span><span>{t}</span></li>' for t in items)


tiers = [
    (1, 'قاعدة رمل', 'Sand', 'Day 1', 1, 0),
    (5, 'قاعدة حجر', 'Stone', 'About 1 week', 2, 1),
    (10, 'قاعدة مرجان', 'Coral', 'About 1 month', 3, 1),
    (20, 'إطار ذهب', 'Gold trim', 'About 4 months', 8, 2),
    (35, 'قوس قزح', 'Rainbow', 'About 13 months', 13, 3),
    (50, 'عقد لؤلؤ', 'Pearl ring', 'About 2 years', 17, 4),
    (75, 'تاج نجوم', 'Star crown', 'About 5 years', 20, 4),
]
tier_cards = ''.join(
    f'<div style="display: flex; flex-direction: column; align-items: center; gap: 8px; min-width: 0;">'
    f'<div style="border-radius: 20px; overflow: hidden; width: 172px; height: 191px;">'
    f'<dc-import name="Island" level="{lv}" medals="{md}" pearls="{pr}" size="172" frame="rect" pose="{"wave" if lv < 10 else "none"}" hint-size="172px,191px"></dc-import></div>'
    f'<div style="display: flex; flex-direction: column; align-items: center; gap: 2px; text-align: center;">'
    f'<div style="font-size: 15px; font-weight: 700;">Level {lv} · {en}</div>'
    f'<div dir="rtl" style="{ARB} font-size: 16px; font-weight: 600; color: #3F7A4A;">{ar}</div>'
    f'<div style="font-size: 13px; color: #6B7A6F;">{when}</div></div></div>'
    for lv, ar, en, when, md, pr in tiers)

rules = [
    ('Big', 'Each thing is about a fifth of the island’s width: 80 px on a phone, where it was 30. You can tell a lemon tree from a well without zooming.'),
    ('Few places', 'Six places on the land, plus the palm, the sea and the sky. Everything earned stays in your collection; you choose which six stand out, in the Builder.'),
    ('One hero', 'The palm in the middle grows with you: shoot, young palm, tall palm. Medals hang dates under its crown, and lanterns bought with gold hang from it.'),
    ('The base is the level', 'A plate with the number, and a base that turns stone, coral, gold, with a rainbow, a pearl ring, a star crown. Readable even tiny in Rooms.'),
    ('New things shine', 'A sparkle and a glow on what just grew, and Doum holds up sparkles, until you open the oasis once. Then it calms down.'),
]
rule_cards = ''.join(
    f'<div style="background: #FFFFFF; border-radius: 20px; padding: 22px 22px 24px; display: flex; flex-direction: column; gap: 10px;">'
    f'<div style="display: flex; align-items: center; gap: 12px;"><span style="width: 34px; height: 34px; border-radius: 99px; background: #2F7A3A; color: #FFFFFF; font-weight: 700; font-size: 16px; display: flex; align-items: center; justify-content: center;">{i + 1}</span>'
    f'<span style="font-size: 21px; font-weight: 700;">{t}</span></div>'
    f'<p style="margin: 0; font-size: 16px; line-height: 1.55; color: #45574B;">{d}</p></div>'
    for i, (t, d) in enumerate(rules))

people = [('أحمد', 3, 0, 0), ('عبدالله', 12, 4, 1), ('خالد', 24, 9, 3), ('يوسف', 52, 17, 5)]
room_rows = ''.join(
    f'<div style="display: flex; align-items: center; gap: 12px; padding: 8px 4px; border-bottom: 1px solid #EFE9DA;">'
    f'<div style="width: 64px; height: 71px; flex-shrink: 0;"><dc-import name="Island" detail="glance" level="{lv}" medals="{md}" pearls="{pr}" pose="none" size="64" frame="bubble" hint-size="64px,71px"></dc-import></div>'
    f'<div style="display: flex; flex-direction: column; gap: 0; flex-grow: 1;"><span style="font-size: 16px; font-weight: 700;">{n}</span><span style="font-size: 13px; color: #6B7A6F;">المستوى {lv}</span></div>'
    f'<span style="font-size: 14px; font-weight: 600; color: #2F7A3A;">زيارة</span></div>'
    for n, lv, md, pr in people)

PROMPT = """A sticker sheet of 12 separate objects for a cute children’s-app world, in the same style as the green sprout mascot I attached. 4 columns × 3 rows, 1536 × 1024 px, each cell 384 × 341 px with 48 px of clear space inside every edge. Transparent background.
Style: thick dark green outline (#1E3A24, about 6 px), flat fills with one soft lighter shade, no gradients, no textures, no shadows on the ground.
Every object stands on the same invisible baseline 50 px above the bottom of its cell, centred left to right, seen from the front and slightly above.
These are the special, rare things of the world, so make them a little grander and shinier than ordinary objects: brass and gold details, warm glowing lights, white coral stone.
No text, no numbers, no letters. No faces on anything. No people, no animals, no birds, no insects, no mascot. No domes, no minarets. One object per cell, nothing touching the cell edges.

1. A white coral-stone house with a tall square wind tower, a blue wooden door and small arched windows
2. A round three-tier stone fountain, water falling from each tier
3. A golden date palm: gold-edged fronds, amber date bunches that glow softly
4. A carved white stone archway with four lit brass lanterns hanging inside it
5. An open wooden chest with gold corners, full of white pearls
6. A big pearl-diving dhow with a tall cream sail and small lanterns on its rail, on a little patch of water
7. An outdoor majlis: low cushions on a patterned carpet under a palm-frond shade, a brass coffee pot on a tray, nobody sitting
8. A traditional palm-frond hut with a wooden door
9. A white lighthouse with one red band and a warm glowing lamp, on rocks
10. A pair of tall carved stone garden lamp posts with warm lights
11. A round stone pool with pink water lilies and floating lit lanterns
12. A wooden pergola wrapped in white jasmine with a string of small warm lights"""

show = [('Gold trim, level 20', '4. Lantern archway, 1. Coral house'),
        ('Rainbow, level 35', '2. Fountain, 11. Lily pool, 12. Jasmine pergola'),
        ('Pearl ring, level 50', '5. Pearl chest, 6. Big dhow, 9. Lighthouse'),
        ('Star crown, level 75', '3. Golden palm, 7. Majlis, 10. Lamp posts')]
show_rows = ''.join(f'<div style="display: flex; justify-content: space-between; gap: 16px; padding: 10px 0; border-bottom: 1px solid #EFE9DA; font-size: 15px;"><span style="font-weight: 700;">{a}</span><span style="color: #45574B; text-align: right;">{b}</span></div>' for a, b in show)

html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Proud of it</title>
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
<div style="background: #F5F0E1; color: #23352A; font-family: 'IBM Plex Sans', sans-serif; min-height: 100vh;">
<div style="max-width: 1440px; margin: 0 auto; box-sizing: border-box; padding: 64px 48px 88px; display: flex; flex-direction: column; gap: 56px;">

<header style="display: flex; flex-direction: column; gap: 16px; max-width: 1040px;">
<div style="font-size: 15px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: #3F7A4A;">New look</div>
<h1 style="margin: 0; font-size: 56px; line-height: 1.06; font-weight: 700;">An oasis worth showing</h1>
<p style="margin: 0; font-size: 20px; line-height: 1.5; color: #45574B; text-wrap: pretty;">Your note: make it nicer, so people are proud of what they did, with fancy things that are easy to notice. Five changes: a flat island instead of a ball, the real art from your sheets, fewer and bigger things, a base that shows the level from far away, and a shine on anything new. The Builder, the oasis page, the profile card, the level-up toast and Rooms all use it now.</p>
</header>

<section style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 24px;">
<div style="background: #FFFFFF; border-radius: 28px; padding: 28px; display: flex; flex-direction: column; gap: 18px; align-items: center;">
<div style="align-self: stretch; display: flex; justify-content: space-between; align-items: baseline;"><span style="font-size: 24px; font-weight: 700;">Before</span><span style="font-size: 15px; color: #6B7A6F;">Level 24, the old planet</span></div>
<div style="border-radius: 24px; overflow: hidden; width: 400px; height: 444px;"><dc-import name="Planet" mode="oasis" level="24" medals="9" pearls="3" size="400" frame="rect" hint-size="400px,444px"></dc-import></div>
<ul style="align-self: stretch; margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 8px; font-size: 17px; line-height: 1.45; color: #45574B;">{bullets(before, '#C9B9A0')}</ul>
</div>
<div style="background: #FFFFFF; border-radius: 28px; padding: 28px; display: flex; flex-direction: column; gap: 18px; align-items: center; box-shadow: 0 0 0 3px #2F7A3A;">
<div style="align-self: stretch; display: flex; justify-content: space-between; align-items: baseline;"><span style="font-size: 24px; font-weight: 700; color: #2F7A3A;">Now</span><span style="font-size: 15px; color: #6B7A6F;">Level 24, the island</span></div>
<div style="border-radius: 24px; overflow: hidden; width: 400px; height: 444px;"><dc-import name="Island" level="24" medals="9" pearls="3" size="400" frame="rect" fresh="1" hint-size="400px,444px"></dc-import></div>
<ul style="align-self: stretch; margin: 0; padding: 0; list-style: none; display: flex; flex-direction: column; gap: 8px; font-size: 17px; line-height: 1.45; color: #23352A;">{bullets(after, '#2F7A3A')}</ul>
</div>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<div style="display: flex; flex-direction: column; gap: 8px; max-width: 1000px;">
<h2 style="margin: 0; font-size: 34px; font-weight: 700;">The base says how far you came</h2>
<p style="margin: 0; font-size: 18px; line-height: 1.5; color: #45574B;">The base changes on the same levels as the ranks the app already has. Times are for about 7 habits a day (150 XP). The first three come fast so a new person sees the base change in their first month. The last ones take years on purpose: if a friend’s island has a pearl ring, everyone knows it took two years.</p>
</div>
<div style="background: #FFFFFF; border-radius: 28px; padding: 28px 20px; display: grid; grid-template-columns: repeat(7, minmax(0, 1fr)); gap: 8px;">{tier_cards}</div>
<p style="margin: 0; font-size: 16px; color: #6B7A6F;">Level 100 adds a full gold glow around the island. Growth is never sold: no gold or money can change the base.</p>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="margin: 0; font-size: 34px; font-weight: 700;">Easy to notice: five rules</h2>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(250px, 100%), 1fr)); gap: 16px;">{rule_cards}</div>
</section>

<section style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 24px;">
<div style="display: flex; flex-direction: column; gap: 16px;">
<h2 style="margin: 0; font-size: 34px; font-weight: 700;">What friends see</h2>
<p style="margin: 0; font-size: 18px; line-height: 1.5; color: #45574B;">In a room, everyone’s island sits beside their name, small. At 64 px you still see the palm’s height, the base colour, the rainbow and the pearl ring, so a high level and real care show without a word. Tap Visit to see it big. It never shows habits, prayers or quiet days, and it only shows for people who turned on Neighbours.</p>
<div dir="rtl" style="{ARB} background: #FFFFFF; border-radius: 24px; padding: 12px 16px; display: flex; flex-direction: column; max-width: 420px;">
<div style="font-size: 15px; font-weight: 700; padding: 6px 4px 8px;">غرفة الصباح</div>
{room_rows}
</div>
</div>
<div style="display: flex; flex-direction: column; gap: 16px;">
<h2 style="margin: 0; font-size: 34px; font-weight: 700;">Going up a level</h2>
<p style="margin: 0; font-size: 18px; line-height: 1.5; color: #45574B;">Level 19 to 20: Doum plants, the base turns gold, the plate shines, and the toast says what changed and what is next. No title for the person, just the fact.</p>
<div style="display: flex; gap: 16px; align-items: flex-start; flex-wrap: wrap;">
<div style="display: flex; flex-direction: column; gap: 8px; align-items: center;"><div style="border-radius: 20px; overflow: hidden; width: 240px; height: 267px;"><dc-import name="Island" level="19" medals="7" pearls="2" size="240" frame="rect" hint-size="240px,267px"></dc-import></div><span style="font-size: 14px; color: #6B7A6F;">Level 19</span></div>
<div style="display: flex; flex-direction: column; gap: 8px; align-items: center;"><div style="border-radius: 20px; overflow: hidden; width: 240px; height: 267px; box-shadow: 0 0 0 3px #E9B949;"><dc-import name="Island" level="20" medals="7" pearls="2" size="240" frame="rect" glowing="true" hint-size="240px,267px"></dc-import></div><span style="font-size: 14px; color: #6B7A6F;">Level 20</span></div>
</div>
<div dir="rtl" style="{ARB} background: #23352A; color: #F5F0E1; border-radius: 20px; padding: 14px 16px; display: flex; align-items: center; gap: 14px; max-width: 496px; box-sizing: border-box;">
<div style="width: 50px; height: 28px; border-radius: 8px; background: #F2C14E; border: 2px solid #A87D12; color: #4A3200; font-weight: 700; font-size: 16px; display: flex; align-items: center; justify-content: center; flex-shrink: 0;">20</div>
<div style="display: flex; flex-direction: column; flex-grow: 1;"><span style="font-size: 16px; font-weight: 700;">المستوى 20 · الواحة صار لها إطار ذهب</span><span style="font-size: 13px; color: #C9D6C9;">الجاي: قوس قزح في المستوى 35</span></div>
<span style="font-size: 15px; font-weight: 700; color: #9FD88F;">شوف</span>
</div>
</div>
</section>

<section style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 24px; align-items: start;">
<div style="background: #23352A; color: #F5F0E1; border-radius: 24px; padding: 26px 28px; display: flex; flex-direction: column; gap: 12px;">
<div style="font-size: 15px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: #9FD88F;">Sheet 6 for ChatGPT · showpieces</div>
<div style="font-size: 15px; font-weight: 700; color: #FFF3C4;">Done 3 October: all 12 are cut and on the island, in the Builder’s rare tab.</div>
<div style="font-size: 15px; line-height: 1.6; white-space: pre-wrap; font-family: 'IBM Plex Mono', ui-monospace, monospace; user-select: all;">{PROMPT}</div>
<div style="font-size: 14px; color: #C9D6C9;">Attach the same Doum sheet as before. Everything else on the island already exists from your five sheets.</div>
</div>
<div style="display: flex; flex-direction: column; gap: 12px;">
<h2 style="margin: 0; font-size: 34px; font-weight: 700;">Fancier things for the higher bases</h2>
<p style="margin: 0; font-size: 18px; line-height: 1.5; color: #45574B;">So the top of the ladder has things nobody gets early. Each opens with its base and is built with gold, like the other made things. The golden palm is the one exception: it grows, so it comes with level 75 itself.</p>
<div style="background: #FFFFFF; border-radius: 20px; padding: 8px 20px;">{show_rows}</div>
</div>
</section>

</div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1440,"height":4200}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {{}};
  }}
}}
</script>
</body>
</html>
"""
open(os.path.join(HERE, 'project', 'Proud.dc.html'), 'w').write(html)
print(len(html))
