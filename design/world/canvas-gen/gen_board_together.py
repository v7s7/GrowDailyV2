"""Generates project/Together.dc.html: visit, play, compete, and a reason to pay."""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ARB = "font-family: 'IBM Plex Sans Arabic', sans-serif;"
H2 = 'margin: 0; font-size: 34px; font-weight: 700;'
LEAD = 'margin: 0; font-size: 18px; line-height: 1.55; color: #45574B; max-width: 1000px;'

apps = [
    ('Forest', 'Grow a tree while you stay off your phone. Leave the app and the tree dies.',
     ['Coins you earn unlock new kinds of trees, so the forest is a collection.',
      'Spend 2,500 to 5,000 coins and Forest pays its partner, Trees for the Future, to plant a real tree.',
      'Plant Together: friends grow trees at the same time.',
      'Paid once: Pro unlocks real trees, stats and no ads.'],
     'Take: real trees bought with earned currency, a collection, doing it with friends.',
     'Leave: the dying tree and the focus timer. You removed focus mode on purpose, and our rule is that nothing earned is taken away.'),
    ('Duolingo', 'Weekly leagues: 30 people at a similar pace, ranked by XP, reset every week.',
     ['Leagues (borrowed from FarmVille 2) gave 17% more learning time and 3 times more highly engaged learners.',
      'Sells gems for XP boosts and streak repairs, plus the Super subscription.',
      'Users and researchers report XP farming and "cheating" once XP became the prize.'],
     'Take: small, fair groups and a weekly reset.',
     'Leave: selling XP. When XP can be bought or farmed, the rank stops meaning effort.'),
    ('Finch', 'A little pet that grows when you do self-care.',
     ['Friends connect with a code and send each other good vibes.',
      'Finch Plus (about $70 a year) adds clothes, more shop items and more goals.',
      'People pay for how it looks and for more options, not for the pet to grow.'],
     'Take: pay for looks and options, never for growth.',
     'Leave: nothing big; it is the closest cousin of the oasis.'),
    ('Animal Crossing', 'An island you build slowly, in your own style.',
     ['Visiting friends’ islands is the heart of it: every island is different.',
      'People decorate because someone will see it.',
      'Nothing to pay inside the game.'],
     'Take: visits, gifts, a reason to decorate.',
     'Leave: open chat with strangers.'),
]
app_cards = ''
for name, what, facts, take, leave in apps:
    fl = ''.join(f'<li style="margin: 0 0 6px;">{f}</li>' for f in facts)
    app_cards += (f'<div style="background: #FFFFFF; border-radius: 24px; padding: 24px; display: flex; flex-direction: column; gap: 10px;">'
                  f'<div style="font-size: 24px; font-weight: 700;">{name}</div>'
                  f'<div style="font-size: 16px; line-height: 1.5; color: #23352A; font-weight: 600;">{what}</div>'
                  f'<ul style="margin: 0; padding: 0 0 0 18px; font-size: 15px; line-height: 1.5; color: #45574B;">{fl}</ul>'
                  f'<div style="font-size: 15px; line-height: 1.5; color: #2F7A3A; font-weight: 600;">{take}</div>'
                  f'<div style="font-size: 15px; line-height: 1.5; color: #8A4B2B;">{leave}</div></div>')

books = [
    ('Yu-kai Chou, Actionable Gamification', 'Eight drives. "White hat" ones (meaning, progress, creativity) make people feel good and stay. "Black hat" ones (scarcity, chance, fear of loss) make them act now and feel bad later. Build the core on white hat; use black hat lightly.'),
    ('Nir Eyal, Hooked', 'The last step of a habit loop is investment: what people put in (things built, friends, history) brings them back and makes leaving costly. The island is that stored value.'),
    ('Norton, Mochon and Ariely, the IKEA effect', 'People value what they built with their own hands more than the same thing ready-made. Choosing and arranging the six places matters.'),
    ('Robert Cialdini, Influence', 'Reciprocity: a gift makes people want to give one back. Gifts on a friend’s sand bring visits back to yours.'),
    ('Deci and Ryan, self-determination theory', 'Rewards that feel bought or controlling weaken the inner reason for doing something. A level you can buy stops being proof that you cared.'),
    ('Nunes and Drèze, endowed progress', 'A head start makes people finish. People already at level 12 open the update to an island that is already grown.'),
]
book_cards = ''.join(
    f'<div style="background: #FFFFFF; border-radius: 20px; padding: 20px 22px; display: flex; flex-direction: column; gap: 8px;">'
    f'<div style="font-size: 17px; font-weight: 700;">{t}</div><p style="margin: 0; font-size: 15px; line-height: 1.55; color: #45574B;">{d}</p></div>'
    for t, d in books)

ladder = [
    ('1', 'Love it', 'Free', 'The island grows with your habits. Tap anything and it hops; Doum walks over and tells you when it grew.', '#EEF6EC'),
    ('2', 'Invest in it', 'Free', 'Build with gold, choose which six things stand out, pick colours, unlock rare pieces with each base, keep a collection.', '#EEF6EC'),
    ('3', 'Share it', 'Free, for those who turn it on', 'Neighbours map, visits, water, gifts, likes, the visitors’ book, the weekly show, team lanterns. Must be free: it only works if all your friends have it.', '#EEF6EC'),
    ('4', 'Pay for more of it', 'Premium', 'Build twice as fast (2x gold), plant real palms, seasonal looks, your own colours.', '#FFF3C4'),
]
ladder_html = ''.join(
    f'<div style="background: {bg}; border-radius: 22px; padding: 20px; display: flex; flex-direction: column; gap: 8px;">'
    f'<div style="display: flex; align-items: center; gap: 10px;"><span style="width: 34px; height: 34px; border-radius: 99px; background: #23352A; color: #F5F0E1; font-weight: 700; display: flex; align-items: center; justify-content: center;">{n}</span>'
    f'<span style="font-size: 21px; font-weight: 700;">{t}</span></div>'
    f'<span style="font-size: 13px; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; color: #6B5320;">{tag}</span>'
    f'<p style="margin: 0; font-size: 15px; line-height: 1.55; color: #45574B;">{d}</p></div>'
    for n, t, tag, d, bg in ladder)

phones = [('Neighbours', 'Neighbours: your room’s islands. Tap one to visit.'),
          ('Play', 'Your island: tap things, Doum walks to them.'),
          ('Show', 'The weekly show: one vote, Saturday result.'),
          ('OasisPremium', 'New rows on the Premium screen.')]
phone_row = ''.join(
    f'<div style="display: flex; flex-direction: column; gap: 10px; align-items: center;">'
    f'<div style="width: 273px; height: 591px; border-radius: 26px; overflow: hidden; box-shadow: 0 0 0 1px #E1D9C4; position: relative; background: #F5F0E1;">'
    f'<div style="position: absolute; left: 0; top: 0; width: 390px; height: 844px; transform: scale(0.7); transform-origin: top left;">'
    f'<dc-import name="{n}" hint-size="390px,844px"></dc-import></div></div>'
    f'<div style="font-size: 15px; color: #45574B; text-align: center; max-width: 260px;">{c}</div></div>'
    for n, c in phones)

visit_rules = [
    ('Who', 'Only people who turned on «الجيران», and only people in their rooms. No strangers, no search.'),
    ('Water', 'Once a day per friend. A cloud rains on their island and they see «خالد سقى واحتك». It changes nothing they earned; it is a hello.'),
    ('Gift', 'Once a day per friend: a فسيلة, a سلة فواكه or a محارة. It sits on their sand for a week, then goes to their collection with your name. Gifts only come from friends, which is a reason to bring friends.'),
    ('Like', 'A heart. Totals show under each island on the map.'),
    ('Visitors’ book', 'Who came today and what they left.'),
    ('Never shown', 'Habits, prayers, quiet days. A visitor always sees the island fresh. The switch «أظهر واحتي في الغرف» hides it.'),
    ('No chat', 'No free text anywhere, so nothing to moderate and safe for young users.'),
    ('No notifications', 'None, ever. Visits wait on the oasis page as one quiet line, seen only when the person opens it.'),
]
rule_rows = ''.join(f'<div style="display: grid; grid-template-columns: 170px 1fr; gap: 16px; padding: 12px 0; border-bottom: 1px solid #EFE9DA;"><span style="font-weight: 700; font-size: 16px;">{a}</span><span style="font-size: 16px; line-height: 1.5; color: #45574B;">{b}</span></div>' for a, b in visit_rules)

compete = [
    ('Room ranking stays the same', 'Habits and the room score decide places, exactly as today. The island never changes a rank.'),
    ('The weekly show «معرض الأسبوع»', 'Every room votes for the nicest island: one vote, not your own, result on Saturday with the weekly recap. The winner’s island flies a flag for a week. A tie shares the flag, like room places.'),
    ('Status you can see', 'On the neighbours map islands are bigger with level and show their base and rare pieces. A pearl ring next to a sand base says everything.'),
    ('Team rooms light lanterns', 'Each team day won lights a lantern on the ropes between the islands; seven lit is a full week. It uses the team days the app already counts.'),
]
compete_cards = ''.join(f'<div style="background: #FFFFFF; border-radius: 20px; padding: 20px 22px; display: flex; flex-direction: column; gap: 8px;"><div style="font-size: 18px; font-weight: 700;">{a}</div><p style="margin: 0; font-size: 15px; line-height: 1.55; color: #45574B;">{b}</p></div>' for a, b in compete)

never = [
    ('The level, the base, medals, dates, anything that grows', 'They are the proof of effort that friends read.'),
    ('Random boxes', 'Paying for a chance at a prize is gambling (maysir) to many scholars; Malaysia’s Federal Territories Mufti called loot boxes gambling. Every paid thing shows exactly what you get.'),
    ('A dying island you pay to save', 'Black hat at its worst, and it breaks our rule that nothing earned is taken away.'),
    ('Donations inside the app', 'Apple 3.2.2: only approved nonprofits may collect donations in an app. So GrowDaily pays for the real palms from its own revenue, the way Forest does.'),
]
never_rows = ''.join(f'<div style="display: flex; flex-direction: column; gap: 4px; padding: 12px 0; border-bottom: 1px solid rgba(245,240,225,0.18);"><span style="font-weight: 700; font-size: 16px;">{a}</span><span style="font-size: 15px; line-height: 1.5; color: #C9D6C9;">{b}</span></div>' for a, b in never)

choices = [
    ('Premium gives 2x gold, not 2x XP?', 'Recommended: yes. Faster building, an honest level.'),
    ('Real palms with a planting partner?', 'Recommended: yes, once a partner and a price per palm are signed. One per person per month at most.'),
    ('The weekly show in every room?', 'Recommended: off until a room leader turns it on.'),
    ('Gifts free, once a day per friend?', 'Recommended: yes. Free gifts are what make people invite friends.'),
    ('Does 2x gold also make streak freezes cheaper for Premium?', 'A freeze costs 100 gold, so with 2x it costs half the habits. Recommended: keep it; it is still earned by doing habits.'),
]
choice_rows = ''.join(f'<div style="display: flex; flex-direction: column; gap: 4px; padding: 14px 0; border-bottom: 1px solid #EFE9DA;"><span style="font-weight: 700; font-size: 17px;">{i + 1}. {a}</span><span style="font-size: 15px; color: #45574B;">{b}</span></div>' for i, (a, b) in enumerate(choices))

order = [('1', 'The island and the Builder', 'Already designed on this canvas.'),
         ('2', 'Neighbours map, visits, water, likes, visitors’ book', 'Reads islands of people in your rooms; one small record per visit.'),
         ('3', 'Gifts, the weekly show, team lanterns', 'Gift and vote records; the flag and lanterns are drawn from them.'),
         ('4', 'Premium rows', '2x gold, seasons, colours first; real palms when the partner is signed.')]
order_html = ''.join(f'<div style="display: flex; gap: 14px; align-items: flex-start;"><span style="width: 32px; height: 32px; flex-shrink: 0; border-radius: 99px; background: #2F7A3A; color: #FFFFFF; font-weight: 700; display: flex; align-items: center; justify-content: center;">{n}</span><div style="display: flex; flex-direction: column; gap: 2px;"><span style="font-size: 17px; font-weight: 700;">{t}</span><span style="font-size: 15px; color: #45574B;">{d}</span></div></div>' for n, t, d in order)

sources = [
    ('Forest: coins, real trees, Pro purchase (Xataka Android)', 'https://www.xatakandroid.com/aplicaciones-android/asi-forest-app-para-ayudarte-a-desconectar-trabajo-echar-cable-a-naturaleza'),
    ('Forest and Trees for the Future', 'https://sdg.hotelschool.nl/?p=81'),
    ('Forest user review analysis (Kimola)', 'https://kimola.com/reports/unlock-productivity-insights-forest-app-user-feedback-report-app-store-us-147179'),
    ('Duolingo leagues: 17% more learning time', 'https://marishalakhiani.substack.com/p/breaking-down-duolingos-growth-model'),
    ('Duolingo leagues, mechanics', 'https://duolingo.deconstructoroffun.com/mechanics/leagues'),
    ('When gamification spoils learning (arXiv 2203.16175)', 'https://arxiv.org/pdf/2203.16175'),
    ('Duolingo gems and XP boosts', 'https://duolingo.fandom.com/wiki/Gem'),
    ('Finch on the App Store', 'https://apps.apple.com/app/id1528595748'),
    ('Finch review and price (Bustle)', 'https://www.bustle.com/wellness/finch-app-review-features-price'),
    ('Animal Crossing: how visiting islands works', 'https://gamesbeat.com/animal-crossing-new-horizons-online-guide-how-visiting-islands-works/'),
    ('Octalysis, white hat and black hat (Yu-kai Chou)', 'https://yukaichou.com/the-ultimate-guide-to-gamification-past-present-and-future/'),
    ('Loot boxes called gambling by a Malaysian mufti (Massively OP)', 'https://massivelyop.com/?p=358591'),
    ('Maysir and loot boxes, a study', 'https://journal.uinsgd.ac.id/index.php/mashadiruna/article/view/38111'),
    ('Apple guideline 3.2.2 on donations (developer forums)', 'https://developer.apple.com/forums/thread/799549'),
]
src_html = ''.join(f'<li style="margin: 0 0 6px;"><a href="{u}" style="color: #2F6B3A;">{t}</a></li>' for t, u in sources)

html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Together</title>
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
<div style="max-width: 1440px; margin: 0 auto; box-sizing: border-box; padding: 64px 48px 88px; display: flex; flex-direction: column; gap: 60px;">

<header style="display: flex; flex-direction: column; gap: 16px; max-width: 1060px;">
<div style="font-size: 15px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: #3F7A4A;">Together, and worth paying for</div>
<h1 style="margin: 0; font-size: 56px; line-height: 1.06; font-weight: 700;">Visit, play, compete, and a reason to pay</h1>
<p style="margin: 0; font-size: 20px; line-height: 1.5; color: #45574B; text-wrap: pretty;">Your ask: not just a logo. A place people play with and build, visit with friends, compete around, and want to pay to invest in. Below: what Forest, Duolingo, Finch and Animal Crossing do, what the books say, and the plan. The short version: everything social is free and switched on only by people who want it, nothing sends a notification, competition stays fair, and Premium buys speed and meaning, never the level.</p>
</header>

<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">Try it</h2>
<p style="{LEAD}">Four new phones, all on the canvas below this board. Press Play on Neighbours and Play to tap around.</p>
<div style="display: flex; gap: 28px; flex-wrap: wrap; justify-content: space-between;">{phone_row}</div>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">What the loved apps do</h2>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(300px, 100%), 1fr)); gap: 16px;">{app_cards}</div>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">What the books say</h2>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(400px, 100%), 1fr)); gap: 16px;">{book_cards}</div>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">From loving it to paying for it</h2>
<p style="{LEAD}">People pay for what they already love and have put work into. So the first three steps are free and come first; the fourth sells more of the same joy.</p>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(300px, 100%), 1fr)); gap: 16px;">{ladder_html}</div>
</section>

<section style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 32px; align-items: start;">
<div style="display: flex; flex-direction: column; gap: 14px;">
<h2 style="{H2}">On a friend’s island</h2>
<div style="background: #FFFFFF; border-radius: 24px; padding: 8px 24px;">{rule_rows}</div>
</div>
<div style="display: flex; flex-direction: column; gap: 14px;">
<h2 style="{H2}">Compete, fairly</h2>
<div style="display: grid; gap: 14px;">{compete_cards}</div>
<p style="margin: 0; font-size: 15px; line-height: 1.55; color: #6B7A6F;">Why no global league like Duolingo: there XP is the whole product. Here habits include prayers, and ranking strangers on them is not something to build. Rooms are already small, fair groups.</p>
</div>
</section>

<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">Your 2x idea: double the gold, not the XP</h2>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 16px;">
<div style="background: #FFFFFF; border-radius: 24px; padding: 24px; display: flex; flex-direction: column; gap: 10px; box-shadow: 0 0 0 3px #2F7A3A;">
<div style="font-size: 22px; font-weight: 700; color: #2F7A3A;">Yes: 2x gold with Premium</div>
<p style="margin: 0; font-size: 16px; line-height: 1.55; color: #45574B;">Gold builds the made things: the house, the fountain, the pearl chest. With 2x you still do every habit; your things just come twice as fast. At 6 habits a day that is about 48 gold a day free and 96 with Premium. The coral house (1,200) takes 25 days free, 13 with Premium. All the buildable things together (about 10,500 gold) take about 7 months free, 3.5 with Premium. The rare pieces still wait for their base, which money cannot speed up.</p>
</div>
<div style="background: #FFFFFF; border-radius: 24px; padding: 24px; display: flex; flex-direction: column; gap: 10px;">
<div style="font-size: 22px; font-weight: 700; color: #8A4B2B;">No: 2x XP</div>
<p style="margin: 0; font-size: 16px; line-height: 1.55; color: #45574B;">XP makes the level and the base, the thing friends read as “this person cares”. If money doubles it, a gold base starts to mean “paid”, and nobody can be proud of it, including the people who paid. Duolingo sells XP boosts, and its users and researchers complain about XP farming and cheating. And bought rewards weaken the inner reason (self-determination theory).</p>
</div>
</div>
</section>

<section style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 32px; align-items: start;">
<div style="display: flex; flex-direction: column; gap: 14px;">
<h2 style="{H2}">Real palms</h2>
<p style="margin: 0; font-size: 17px; line-height: 1.6; color: #45574B;">Forest’s most loved part. There, people spend 2,500 to 5,000 earned coins and Forest pays Trees for the Future to plant a real tree. Ours: a Premium member spends 2,500 gold and GrowDaily pays a planting partner for one real palm, at most one per person per month so the cost has a ceiling. The island shows «نخيلك الحقيقية: 2», and the partner sends a photo and place for each batch. Wording stays factual, with no claims about reward.</p>
<p style="margin: 0; font-size: 15px; line-height: 1.55; color: #6B7A6F;">Needs before promising: a partner (a local palm planter, or Forest’s own partner), a price per palm, and a check that 12 palms a year fits inside a year of Premium.</p>
</div>
<div style="background: #23352A; color: #F5F0E1; border-radius: 24px; padding: 20px 24px; display: flex; flex-direction: column; gap: 4px;">
<div style="font-size: 15px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: #9FD88F; padding-bottom: 6px;">Never sold</div>
{never_rows}
</div>
</section>

<section style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 32px; align-items: start;">
<div style="display: flex; flex-direction: column; gap: 16px;">
<h2 style="{H2}">Build order</h2>
<div style="display: flex; flex-direction: column; gap: 16px;">{order_html}</div>
</div>
<div style="display: flex; flex-direction: column; gap: 10px;">
<h2 style="{H2}">Your choices</h2>
<div style="background: #FFFFFF; border-radius: 24px; padding: 4px 24px;">{choice_rows}</div>
</div>
</section>

<section style="display: flex; flex-direction: column; gap: 10px;">
<h2 style="margin: 0; font-size: 22px; font-weight: 700;">Sources</h2>
<ul style="margin: 0; padding: 0 0 0 18px; font-size: 15px; line-height: 1.5; columns: 2; column-gap: 40px;">{src_html}</ul>
</section>

</div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":1440,"height":5200}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    return {{}};
  }}
}}
</script>
</body>
</html>
"""
import re
AR = re.compile(r'«?[\u0600-\u06FF][\u0600-\u06FF\s:0-9،]*[\u0600-\u06FF0-9]»?|«[\u0600-\u06FF]»')
html = re.sub(r'>([^<]+)<', lambda m: '>' + AR.sub(lambda a: '<bdi dir="rtl">' + a.group(0) + '</bdi>', m.group(1)) + '<', html)
open(os.path.join(HERE, 'project', 'Together.dc.html'), 'w').write(html)
print(len(html))
