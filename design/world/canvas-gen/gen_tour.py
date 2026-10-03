"""Generates project/Tour.dc.html: how it will be, in the order a person meets it."""
import os, re
HERE = os.path.dirname(os.path.abspath(__file__))
AR = re.compile(r'«?[؀-ۿ][؀-ۿ\s:0-9،]*[؀-ۿ0-9]»?|«[؀-ۿ]»')
SC = 0.54
PW, PH = round(390 * SC), round(844 * SC)

ARROW = ('<svg width="34" height="24" viewBox="0 0 34 24" aria-hidden="true" style="flex-shrink: 0; align-self: center; margin-top: -60px;">'
         '<path d="M2 12 H28 M20 4 L29 12 L20 20" fill="none" stroke="#9AA79C" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"></path></svg>')


def phone(n, board, title, cap, attrs=''):
    return (f'<div style="display: flex; flex-direction: column; gap: 10px; width: {PW}px; flex-shrink: 0;">'
            f'<div style="width: {PW}px; height: {PH}px; border-radius: 22px; overflow: hidden; box-shadow: 0 0 0 1px #E1D9C4, 0 6px 18px rgba(35,53,42,0.08); position: relative; background: #F5F0E1;">'
            f'<div style="position: absolute; left: 0; top: 0; width: 390px; height: 844px; transform: scale({SC}); transform-origin: top left;">'
            f'<dc-import name="{board}" {attrs} hint-size="390px,844px"></dc-import></div></div>'
            f'<div style="display: flex; gap: 8px; align-items: baseline;"><span style="width: 26px; height: 26px; border-radius: 99px; background: #23352A; color: #F5F0E1; font-size: 13px; font-weight: 700; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0;">{n}</span>'
            f'<span style="font-size: 16px; font-weight: 700;">{title}</span></div>'
            f'<div style="font-size: 14px; line-height: 1.5; color: #45574B;">{cap}</div></div>')


def row(label, sub, tag, bg, items):
    cells = ARROW.join(items)
    return (f'<section style="display: flex; flex-direction: column; gap: 16px; background: {bg}; border-radius: 28px; padding: 26px 26px 28px;">'
            f'<div style="display: flex; align-items: baseline; gap: 14px; flex-wrap: wrap;"><h2 style="margin: 0; font-size: 30px; font-weight: 700;">{label}</h2>'
            f'<span style="font-size: 13px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: #6B5320; background: #FFF3C4; border-radius: 999px; padding: 4px 10px;">{tag}</span></div>'
            f'<p style="margin: 0; font-size: 17px; line-height: 1.5; color: #45574B; max-width: 1000px;">{sub}</p>'
            f'<div style="display: flex; gap: 10px; align-items: flex-start; overflow-x: auto; padding-bottom: 4px;">{cells}</div></section>')


body = (
    '<header style="display: flex; flex-direction: column; gap: 16px; max-width: 1060px;">'
    '<div style="font-size: 15px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: #3F7A4A;">How it will be</div>'
    '<h1 style="margin: 0; font-size: 56px; line-height: 1.06; font-weight: 700;">The whole thing, in the order a person meets it</h1>'
    '<p style="margin: 0; font-size: 20px; line-height: 1.5; color: #45574B; text-wrap: pretty;">Four rows, one per depth of the plan. Most people only ever see the first row. Every phone here is live: open it full-window to tap through.</p>'
    '</header>'
    + '<div dir="rtl" style="background: #23352A; color: #F5F0E1; border-radius: 24px; padding: 22px 26px; display: flex; flex-direction: column; gap: 8px;">'
      '<div dir="ltr" style="font-size: 15px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: #9FD88F;">Test drive: one path through everything</div>'
      '<div dir="ltr" style="font-size: 17px; line-height: 1.7;">'
      '1. Open the phone <b>A. Profile</b> full-window and tap the island card.<br>'
      '2. On the oasis page tap <b>امشِ فيها</b>: tap <b>جرّب: مستوى جديد</b> to see the level-up moment (Doum plants, the new thing grows in). Then tap the ground, the palm (he picks dates), the lemon (he waters it), the house, then <b>ادخل بيتك</b> to see the room; there tap <b>اجلس</b>.<br>'
      '3. Back on the oasis page tap <b>رتّب</b>: three tabs, the level slider, then <b>تعديل حر · 100</b> for level 100.<br>'
      '4. Tap <b>جيرانك</b>, tap Khalid’s island, try water, gift and the heart, then <b>انزل وتمشّى في واحته</b>: tap the palm, the jasmine, the bench, the gift button and the camera.<br>'
      '5. From the map, <b>معرض الأسبوع</b> opens the weekly show.'
      '</div></div>'
    + row('1. Everyone', 'Nothing to turn on, nothing that pings. One card on Profile, and the level-up message they already get says what grew.', 'Default', '#FFFFFF', [
        phone(1, 'Profile', 'A card on Profile', 'Their island, small, under the stats. Their level and what the next one brings.'),
        phone(2, 'LevelUp', 'Level up', 'The message that already appears now says what grew, with a small picture.'),
    ])
    + row('2. Tap the card', 'The oasis page. Play with it, build it, and keep editing at any level.', 'One tap', '#FFFFFF', [
        phone(3, 'PlanetPage', 'The oasis page', 'The island big, the level plate and the next base, the collection, the dates from medals.'),
        phone(4, 'Play', 'Play', 'Tap anything: it hops, Doum walks over and says when it grew.', 'demo="lemon"'),
        phone(5, 'Builder', 'Build', 'Six places. Grows with level, built with gold, rare pieces at each base. Colours and night.'),
        phone(6, 'Edit', 'Level 100', 'Fourteen places, move anything, flip it, make it gold, three saved designs.'),
    ])
    + row('3. Turn on Neighbours', 'Only for people who switch on «الجيران». They see friends from their rooms who switched it on too.', 'Their choice', '#EEF6EC', [
        phone(7, 'Neighbours', 'Neighbours', 'The islands of their room on the sea. Bigger islands, higher levels.'),
        phone(8, 'Neighbours', 'A visit', 'Water, a gift, a like, the visitors’ book. Then walk in.', 'view="visit"'),
        phone(9, 'Walk', 'Walk around', 'A close camera follows their Doum. A date from the palm and a cutting go home with them.', 'demo="palm"'),
        phone(10, 'Inside', 'Go inside', 'The room in the house, set up with real furniture. Guests look; owners change it.'),
        phone(11, 'Show', 'The weekly show', 'Only if the room leader turns it on. One vote, Saturday result, a flag for a week.'),
    ])
    + row('4. Premium', 'For people who want more of it. Speed and meaning, never the level.', 'Paid', '#FFF8E1', [
        phone(12, 'OasisPremium', 'Premium rows', '2x gold, real palms, seasons, own colours. Nothing that grows is for sale.'),
    ])
    + '<div style="background: #23352A; color: #F5F0E1; border-radius: 24px; padding: 22px 26px; font-size: 18px; line-height: 1.55;">'
      '<b>Never, at any depth:</b> notifications, screens that open by themselves, red dots, thirsty messages, streaks you can lose, chat, random boxes. '
      'Logging a habit takes exactly as many taps as today.</div>'
)

html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>How it will be</title>
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
<div style="max-width: 1440px; margin: 0 auto; box-sizing: border-box; padding: 64px 48px 88px; display: flex; flex-direction: column; gap: 28px;">
{body}
</div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1440,"height":3300}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {{}};
  }}
}}
</script>
</body>
</html>
"""
html = re.sub(r'>([^<]+)<', lambda m: '>' + AR.sub(lambda a: '<bdi dir="rtl">' + a.group(0) + '</bdi>', m.group(1)) + '<', html)
open(os.path.join(HERE, 'project', 'Tour.dc.html'), 'w').write(html)
print(len(html))
