"""Generates project/Seen.dc.html: the oasis seen by others (icon, rooms, share card).

Icon art follows the app icon's own recipe: two colours per icon (a ground
and a light figure), no gradients, a figure that reads at 60 pt. The stages
are drawn here as inline SVG so every colour pair can be previewed.
"""
import math, os

HERE = os.path.dirname(__file__)

def frond(cx, cy, a_deg, L, w=0.24, droop=0.0):
    a = math.radians(a_deg)
    tx, ty = cx + L * math.cos(a), cy + L * math.sin(a) + droop
    mx, my = cx + L * .5 * math.cos(a), cy + L * .5 * math.sin(a) - L * .2
    nx, ny = -math.sin(a) * L * w, math.cos(a) * L * w
    return f'M{cx:.1f} {cy:.1f} Q{mx + nx:.1f} {my + ny:.1f} {tx:.1f} {ty:.1f} Q{mx - nx:.1f} {my - ny:.1f} {cx:.1f} {cy:.1f} Z'

def crown(cx, cy, L, n, G, C, spread=(195, 345)):
    out = ''
    for i in range(n):
        a = spread[0] + (spread[1] - spread[0]) * i / (n - 1)
        out += f'<path d="{frond(cx, cy, a, L, droop=L * .28 * abs(math.cos(math.radians(a))))}" fill="{C}" stroke="{G}" stroke-width="1.3" stroke-linejoin="round"></path>'
    return out

def trunk(x, base, h, w0, w1, G, C):
    rings = ''.join(f'<path d="M{x - w0 + (w0 - w1) * y / h:.1f} {base - y:.1f} H{x + w0 - (w0 - w1) * y / h:.1f}" stroke="{G}" stroke-width="1.1"></path>'
                    for y in [h * k / 5 for k in range(1, 5)])
    return (f'<path d="M{x - w0} {base} C{x - w0} {base - h * .5:.1f} {x - w1 + 1} {base - h * .8:.1f} {x - w1 + 1.5} {base - h} '
            f'L{x + w1 + 1.5} {base - h} C{x + w1 + 1} {base - h * .8:.1f} {x + w0} {base - h * .5:.1f} {x + w0} {base} Z" fill="{C}"></path>' + rings)

def icon(stage, G, C, size):
    base = 66
    s = (f'<svg viewBox="0 0 100 100" width="{size}" height="{size}" aria-hidden="true" style="display: block;">'
         f'<rect width="100" height="100" fill="{G}"></rect>'
         f'<circle cx="50" cy="108" r="44" fill="{C}"></circle>')
    if stage >= 5:
        s += f'<path d="M24 86 q4 -2.4 8 0 t8 0 M60 90 q4 -2.4 8 0 t8 0" fill="none" stroke="{G}" stroke-width="2" stroke-linecap="round"></path>'
        s += trunk(29, base + 4, 13, 2.2, 1.6, G, C) + crown(29.5, base + 4 - 13, 10, 6, G, C)
        s += trunk(71, base + 4, 11, 2.0, 1.5, G, C) + crown(71.5, base + 4 - 11, 9, 6, G, C)
    if stage == 1:
        s += crown(50, base - 1, 12, 6, G, C, (200, 340))
    elif stage == 2:
        s += trunk(49, base, 16, 2.6, 2.0, G, C) + crown(50.5, base - 16, 15, 7, G, C)
    else:
        s += trunk(48, base, 28, 3.4, 2.4, G, C) + crown(50, base - 28, 21, 9, G, C)
        if stage >= 4:
            for x, y in [(44, base - 25), (56, base - 25), (50, base - 23)]:
                s += ''.join(f'<circle cx="{x + dx}" cy="{y + dy}" r="1.9" fill="{C}" stroke="{G}" stroke-width="1"></circle>'
                             for dx, dy in [(0, 0), (-1.8, 2.6), (1.8, 2.6), (0, 4.8)])
    if stage >= 6:
        s += f'<circle cx="50" cy="56" r="40" fill="none" stroke="{C}" stroke-width="2.2" stroke-dasharray="0.5 6" stroke-linecap="round"></circle>'
    return s + '</svg>'

STAGES = [(1, 'فسيلة', 'Shoot', 'level 1'), (2, 'نخلة صغيرة', 'Young palm', 'level 10'), (3, 'نخلة', 'Palm', 'level 20'),
          (4, 'رطب', 'Dates', 'level 35'), (5, 'واحة', 'Oasis', 'level 50'), (6, 'واحة كاملة', 'Whole oasis', 'level 100')]
PALETTES = [('doum', '#74C878', '#F5F0E1', 'دوم'), ('emerald_gold', '#0F694A', '#E2A336', 'الأصلية'), ('baby_pink', '#692140', '#EE96AC', 'وردي'),
            ('nour_violet', '#351D6D', '#B6A0E9', 'بنفسجي'), ('black', '#000000', '#FFFFFF', 'أسود'), ('vanilla', '#FAE199', '#6B4F12', 'فانيلا')]

stage_tiles = ''.join(
    f'<figure style="margin: 0; display: flex; flex-direction: column; align-items: center; gap: 8px;">'
    f'<div style="width: 150px; height: 150px; border-radius: 34px; overflow: hidden; box-shadow: 0 6px 18px rgba(35,53,42,.18);">{icon(n, "#74C878", "#F5F0E1", 150)}</div>'
    f'<figcaption style="text-align: center; display: flex; flex-direction: column; gap: 2px;"><span dir="rtl" lang="ar" style="font-family: \'IBM Plex Sans Arabic\', sans-serif; font-size: 17px; font-weight: 700;">{ar}</span>'
    f'<span style="font-size: 13px; color: #6B7A6F;">{en} · {lv}</span></figcaption></figure>'
    for n, ar, en, lv in STAGES)

palette_tiles = ''.join(
    f'<figure style="margin: 0; display: flex; flex-direction: column; align-items: center; gap: 6px;">'
    f'<div style="width: 96px; height: 96px; border-radius: 22px; overflow: hidden;">{icon(4, G, C, 96)}</div>'
    f'<figcaption dir="rtl" lang="ar" style="font-family: \'IBM Plex Sans Arabic\', sans-serif; font-size: 14px; color: #45574B;">{ar}</figcaption></figure>'
    for _, G, C, ar in PALETTES)

def blank_icon(col):
    return f'<div style="width: 60px; height: 60px; border-radius: 14px; background: {col};"></div>'

home_row = ''.join([
    f'<div style="display: flex; flex-direction: column; align-items: center; gap: 5px;">{blank_icon("#5E7A8C")}<span style="font-size: 11px; color: #E4EAE6;">&nbsp;</span></div>',
    f'<div style="display: flex; flex-direction: column; align-items: center; gap: 5px;"><div style="width: 60px; height: 60px; border-radius: 14px; overflow: hidden;">{icon(5, "#74C878", "#F5F0E1", 60)}</div><span style="font-size: 11px; color: #F5F0E1;">GrowDaily</span></div>',
    f'<div style="display: flex; flex-direction: column; align-items: center; gap: 5px;">{blank_icon("#8C6A5E")}<span style="font-size: 11px; color: #E4EAE6;">&nbsp;</span></div>',
    f'<div style="display: flex; flex-direction: column; align-items: center; gap: 5px;">{blank_icon("#6E6A8C")}<span style="font-size: 11px; color: #E4EAE6;">&nbsp;</span></div>',
])

members = [('1', 'خالد', 52, 6, 17, '96%'), ('2', 'يوسف', 34, 4, 12, '91%'), ('3', 'أنت', 24, 3, 9, '88%'), ('4', 'سلمان', 9, 0, 2, '74%'), ('5', 'أحمد', 3, 0, 0, '60%')]
member_rows = ''.join(
    f'<div style="display: flex; align-items: center; gap: 10px; padding: 8px 12px; border-radius: 14px; background: {"#EEF6EC" if name == "أنت" else "#FFFFFF"};">'
    f'<span style="width: 18px; font-size: 15px; font-weight: 700; color: #6B7A6F; text-align: center;">{rank}</span>'
    f'<div style="width: 46px; height: 51px; flex-shrink: 0;"><dc-import name="Planet" mode="oasis" detail="glance" level="{lv}" medals="{md}" pearls="{pl}" pose="none" size="46" hint-size="46px,51px"></dc-import></div>'
    f'<div style="display: flex; flex-direction: column; gap: 1px; flex-grow: 1;"><span style="font-size: 16px; font-weight: 700;">{name}</span><span style="font-size: 12.5px; color: #6B7A6F;">المستوى {lv}</span></div>'
    f'<span style="font-size: 16px; font-weight: 700;">{score}</span></div>'
    for rank, name, lv, pl, md, score in members)

html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Seen by others</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600;700&amp;family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&amp;display=swap" rel="stylesheet">
<style>
body{{margin:0;background:#F5F0E1}}
a{{color:#2F6B3A}}a:hover{{color:#1E4A27}}
</style>
</helmet>
<div style="background: #F5F0E1; color: #23352A; font-family: 'IBM Plex Sans', 'IBM Plex Sans Arabic', sans-serif; min-height: 100vh;">
<div style="max-width: 1440px; margin: 0 auto; box-sizing: border-box; padding: 64px 48px 88px; display: flex; flex-direction: column; gap: 48px;">

<header style="display: flex; flex-direction: column; gap: 16px; max-width: 1060px;">
<div style="font-size: 15px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: #3F7A4A;">Seen by others</div>
<h1 style="margin: 0; font-size: 56px; line-height: 1.06; font-weight: 700;">A great palm says one thing: they kept going</h1>
<p style="margin: 0; font-size: 20px; line-height: 1.5; color: #45574B; text-wrap: pretty;">Nothing on the oasis can be bought, sped up or faked: no gold, no Premium, no shortcut. So when someone sees a tall palm with ripe dates, it can only mean one thing. Three places show it: the icon on your phone, your name in a room, and a card you choose to share. It shows how far you came, never what you prayed or which habits you keep.</p>
</header>

<section style="display: flex; flex-direction: column; gap: 20px;">
<div style="display: flex; flex-direction: column; gap: 8px;">
<h2 style="margin: 0; font-size: 32px; font-weight: 700;">1. The app icon grows with the oasis</h2>
<p style="margin: 0; font-size: 17px; line-height: 1.5; color: #45574B; max-width: 1040px;">Six new icon shapes, one per chapter, in the icon’s own two-colour style so the palm reads at 60 points. They join the shape picker on the icon page beside today’s seedling, sprout, grown and bloom. When a new one opens, the icon card you already have offers it; iOS then shows its own confirmation, as it does today. The app never changes the icon by itself.</p>
</div>
<div style="background: #FFFFFF; border-radius: 22px; padding: 26px; display: grid; grid-template-columns: repeat(auto-fit, minmax(min(160px, 100%), 1fr)); gap: 18px; justify-items: center;">
{stage_tiles}
</div>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(460px, 100%), 1fr)); gap: 16px;">
<div style="background: #FFFFFF; border-radius: 20px; padding: 22px 24px; display: flex; flex-direction: column; gap: 14px;">
<div style="font-size: 18px; font-weight: 700;">In every icon colour</div>
<div style="display: flex; flex-wrap: wrap; gap: 14px; justify-content: space-between;">{palette_tiles}</div>
<div style="font-size: 14px; line-height: 1.5; color: #6B7A6F;">The dates stage in six of the 24 colours. Every colour keeps its own free or Premium rule; the oasis shapes themselves are free, like the plant’s.</div>
</div>
<div style="background: #34444F; color: #F5F0E1; border-radius: 20px; padding: 22px 24px; display: flex; flex-direction: column; gap: 16px;">
<div style="font-size: 18px; font-weight: 700;">At real size, on a Home Screen</div>
<div style="display: flex; gap: 22px; justify-content: center;">{home_row}</div>
<div dir="rtl" lang="ar" style="align-self: center; background: #F5F0E1; color: #23352A; border-radius: 18px; padding: 14px 16px; font-family: 'IBM Plex Sans Arabic', sans-serif; display: flex; align-items: center; gap: 12px; width: min(100%, 360px); box-sizing: border-box;">
<div style="width: 44px; height: 44px; border-radius: 11px; overflow: hidden; flex-shrink: 0;">{icon(4, "#74C878", "#F5F0E1", 44)}</div>
<div style="display: flex; flex-direction: column; gap: 2px; flex-grow: 1;"><span style="font-size: 15px; font-weight: 700;">واحتك كبرت</span><span style="font-size: 13px; color: #45574B;">نخلتك صارت فيها رطب. تبي الأيقونة الجديدة؟</span></div>
<span style="font-size: 15px; font-weight: 700; color: #2F7A3A; padding: 10px 4px;">إيه</span>
</div>
<div style="font-size: 13px; line-height: 1.5; color: #C9D6C3;">iPhone only, as the icon page is today. Notification banners keep the original icon until a restart (Apple’s bug since iOS 18.1). The stages open at the world’s chapters; if you would rather keep icons on full days like the plant, the same art works with 30, 90, 180 and 365 full days.</div>
</div>
</div>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<div style="display: flex; flex-direction: column; gap: 8px;">
<h2 style="margin: 0; font-size: 32px; font-weight: 700;">2. In a room: your oasis beside your name</h2>
<p style="margin: 0; font-size: 17px; line-height: 1.5; color: #45574B; max-width: 1040px;">Rooms already show each person’s level and rank mark. The oasis takes the place of a number nobody reads: a small palm beside each name, at a glance. Tap it to visit: their oasis, their Doum waving, how long they have been growing. The room’s order stays the room’s own score; oases are never ranked against each other.</p>
</div>
<div style="display: flex; flex-wrap: wrap; gap: 24px; align-items: flex-start;">
<div dir="rtl" style="width: 390px; height: 700px; box-sizing: border-box; border-radius: 34px; overflow: hidden; background: #F5F0E1; font-family: 'IBM Plex Sans Arabic', sans-serif; padding: 40px 16px 0; display: flex; flex-direction: column; gap: 12px; position: relative; flex-shrink: 0; box-shadow: 0 0 0 1px #E1D9C4;">
<div style="font-size: 22px; font-weight: 700;">غرفة الفجر</div>
<div style="font-size: 14px; color: #6B7A6F;">هذا الأسبوع</div>
<div style="display: flex; flex-direction: column; gap: 8px;">{member_rows}</div>
<div style="position: absolute; left: 0; right: 0; bottom: 0; height: 330px; background: #FFFFFF; border-radius: 26px 26px 0 0; box-shadow: 0 -10px 30px rgba(35,53,42,.18); display: flex; flex-direction: column; align-items: center; padding: 10px 16px 0; gap: 4px;">
<div style="width: 40px; height: 5px; border-radius: 999px; background: #D9D1BC;"></div>
<div style="width: 200px; height: 222px; margin-top: 4px;"><dc-import name="Planet" mode="oasis" level="52" medals="17" pearls="6" size="200" hint-size="200px,222px"></dc-import></div>
<div style="font-size: 19px; font-weight: 700;">واحة خالد</div>
<div style="font-size: 14px; color: #6B7A6F;">المستوى 52 · تكبر من مايو 2026</div>
</div>
</div>
<div style="flex: 1 1 380px; min-width: 0; display: flex; flex-direction: column; gap: 12px;">
<div style="background: #FFFFFF; border-radius: 18px; padding: 20px 22px; display: flex; flex-direction: column; gap: 8px; font-size: 15px; line-height: 1.55; color: #45574B;">
<div style="font-size: 18px; font-weight: 700; color: #23352A;">What a visit shows, and what it never shows</div>
<div><b style="color: #23352A;">Shows:</b> the oasis as it is, their Doum, their level, the month they started, ripe dates and pearls.</div>
<div><b style="color: #23352A;">Never:</b> which habits, any prayer, any count of worship, missed days, or whether their oasis is quiet today (visitors always see it awake).</div>
</div>
<div style="background: #FFFFFF; border-radius: 18px; padding: 20px 22px; display: flex; flex-direction: column; gap: 8px; font-size: 15px; line-height: 1.55; color: #45574B;">
<div style="font-size: 18px; font-weight: 700; color: #23352A;">One switch</div>
<div>Settings › «أظهر واحتي في الغرف». On by default, since rooms already show your level; off shows the plain mark as today.</div>
</div>
<div style="background: #FFFFFF; border-radius: 18px; padding: 20px 22px; display: flex; flex-direction: column; gap: 8px; font-size: 15px; line-height: 1.55; color: #45574B;">
<div style="font-size: 18px; font-weight: 700; color: #23352A;">Why quiet days stay private</div>
<div>A visitor seeing someone’s oasis resting would be a public verdict on their week. So the thirst layer is for the owner only; everyone else sees what was earned.</div>
</div>
</div>
</div>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<div style="display: flex; flex-direction: column; gap: 8px;">
<h2 style="margin: 0; font-size: 32px; font-weight: 700;">3. A card you choose to share</h2>
<p style="margin: 0; font-size: 17px; line-height: 1.5; color: #45574B; max-width: 1040px;">From the oasis page, «شارك واحتي» makes a story-sized picture for WhatsApp status or Instagram. Only when the person asks; never automatic, never a prompt after a prayer.</p>
</div>
<div style="display: flex; flex-wrap: wrap; gap: 24px; align-items: flex-start;">
<div dir="rtl" style="width: 300px; height: 533px; border-radius: 28px; overflow: hidden; background: #DDF0F1; font-family: 'IBM Plex Sans Arabic', sans-serif; display: flex; flex-direction: column; align-items: center; position: relative; flex-shrink: 0; box-shadow: 0 10px 30px rgba(35,53,42,.18);">
<div style="margin-top: 40px; width: 300px; height: 333px;"><dc-import name="Planet" mode="oasis" level="34" medals="12" pearls="5" glowing="true" size="300" frame="rect" hint-size="300px,333px"></dc-import></div>
<div style="flex-grow: 1; width: 100%; background: #F5F0E1; border-radius: 24px 24px 0 0; margin-top: -18px; display: flex; flex-direction: column; align-items: center; gap: 4px; padding-top: 18px; color: #23352A;">
<div style="font-size: 22px; font-weight: 700;">واحة [اسمك]</div>
<div style="font-size: 15px; color: #45574B;">المستوى 34 · نخلة فيها رطب</div>
<div style="display: flex; align-items: center; gap: 6px; margin-top: 14px;"><div style="width: 24px; height: 24px; border-radius: 6px; overflow: hidden;">{icon(4, "#74C878", "#F5F0E1", 24)}</div><span style="font-size: 13px; color: #6B7A6F;">GrowDaily</span></div>
</div>
</div>
<div style="flex: 1 1 380px; min-width: 0; background: #FFFFFF; border-radius: 18px; padding: 22px 24px; display: flex; flex-direction: column; gap: 10px; font-size: 15px; line-height: 1.55; color: #45574B;">
<div style="font-size: 18px; font-weight: 700; color: #23352A;">The rules for being seen</div>
<div>Earned only: nothing on it can be bought, so it is an honest sign of care.</div>
<div>Pictures, not titles: no «بطل», no crown, no rank words on the card (the no-hero-titles rule).</div>
<div>Never ranked: no list of the biggest oases anywhere. Comparison is what cozy design leaves out.</div>
<div>Never about worship: no prayer, no Quran, no counts. Worship stays private; the oasis shows that someone kept going, nothing more.</div>
<div>Always the person’s choice: the room switch and the share button are theirs.</div>
</div>
</div>
</section>

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
with open(os.path.join(HERE, 'project', 'Seen.dc.html'), 'w') as fh:
    fh.write(html)
# a standalone sheet of the icons for a local check
with open(os.path.join(HERE, 'check', 'icons.svg'), 'w') as fh:
    tiles = ''.join(f'<g transform="translate({i * 110} 0)">' + icon(n, '#74C878', '#F5F0E1', 100).replace('<svg viewBox="0 0 100 100" width="100" height="100" aria-hidden="true" style="display: block;">', '<svg x="0" y="0" width="100" height="100" viewBox="0 0 100 100">') + '</g>' for i, (n, *_r) in enumerate(STAGES))
    tiles2 = ''.join(f'<g transform="translate({i * 110} 120)">' + icon(4, G, C, 100).replace('<svg viewBox="0 0 100 100" width="100" height="100" aria-hidden="true" style="display: block;">', '<svg x="0" y="0" width="100" height="100" viewBox="0 0 100 100">') + '</g>' for i, (_, G, C, _a) in enumerate(PALETTES))
    fh.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 660 230" width="1320" height="460"><rect width="660" height="230" fill="#ffffff"/>{tiles}{tiles2}</svg>')
print(len(html))
