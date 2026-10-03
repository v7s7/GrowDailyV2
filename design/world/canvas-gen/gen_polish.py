"""Generates project/Polish.dc.html: motion, size, places, clarity, and the animation sheet prompts."""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import island_core as ic
from gen_plan import page, header, phones, H2, LEAD
A = ic.ART
SCALE_IMG = '/_blob/e6d6559be6ff60590ff489b77d3271f2'
DOUM = '/_blob/4fe66825d4a1e1409975aaf4cae25efe'

# line-up at true relative height
K = 1.3
lineup_items = [('Doum', DOUM, 66, 633 / 767), ('flowers', None, 56, 0), ('bench', None, 40, 0), ('well', None, 76, 0),
                ('lemon', None, 96, 0), ('rose_arch', None, 92, 0), ('house', None, 104, 0), ('coral_house', None, 118, 0)]
names = dict((it[0], it[1]) for it in ic.ITEMS)
cells = ''
for n, src, h, ar in lineup_items:
    if src is None:
        src = A[n][0]
        ar = A[n][1] / A[n][2]
    label = 'دوم' if n == 'Doum' else names.get(n, n)
    cells += (f'<div style="display: flex; flex-direction: column; align-items: center; gap: 6px;">'
              f'<img src="{src}" alt="" style="height: {h * K:.0f}px; width: {h * K * ar:.0f}px;">'
              f'<div dir="rtl" style="font-family: \'IBM Plex Sans Arabic\', sans-serif; font-size: 14px; font-weight: 700;">{label}</div>'
              f'<div style="font-size: 13px; color: #6B7A6F;">{h} · {h / 66:.2f}×</div></div>')
palm_cell = (f'<div style="display: flex; flex-direction: column; align-items: center; gap: 6px;">'
             f'<img src="{A["palm_lanterns"][0]}" alt="" style="height: {150 * K:.0f}px; width: {150 * K * A["palm_lanterns"][1] / A["palm_lanterns"][2]:.0f}px;">'
             f'<div style="font-size: 14px; font-weight: 700;">The palm at 24</div><div style="font-size: 13px; color: #6B7A6F;">150 · 2.27×</div></div>')

motion = [
    ('Facing', 'He turns to the way he walks: front, three-quarter, side, three-quarter back, back, mirrored for the other side. All five views already exist in the app’s Doum set.'),
    ('Speed', 'A steady 70 points a second, so a short step takes half a second and crossing the island about two. The same speed everywhere feels like a real character, not a slide.'),
    ('Walk cycle', 'Four drawn frames per direction (Sheets 8 and 9), 0.44 s a cycle, with a tiny 1.2° sway. Five directions, mirrored for the other side.'),
    ('Shadow', 'A soft shadow under his feet moves with him, so he stands on the ground instead of floating over it.'),
    ('Start and stop', 'He eases out and in. On arrival he squashes for a third of a second, then turns to face you.'),
    ('Depth', 'He goes behind things further back and in front of nearer ones, as he walks.'),
    ('Camera', 'It follows with the same curve, 0.15 s behind him, so the view trails gently.'),
    ('Standing still', 'He breathes every 3.4 s, blinks every 5.3 s and glances left and right in a 12 s loop (Sheet 9 frames).'),
    ('Reactions', 'A tapped thing hops for 0.9 s and three sparkles or drops rise. Doum’s line appears when he arrives, not before, and stays 3.4 s.'),
    ('Reduce Motion', 'No waddle, hop or breathing; he moves straight there with a short fade.'),
]
motion_rows = ''.join(f'<div style="display: grid; grid-template-columns: 170px 1fr; gap: 16px; padding: 12px 0; border-bottom: 1px solid #EFE9DA;"><span style="font-weight: 700; font-size: 16px;">{a}</span><span style="font-size: 16px; line-height: 1.5; color: #45574B;">{b}</span></div>' for a, b in motion)

places = [
    ('Tall at the back', 'Trees and buildings look best in the two back places, low things (beds, benches, chests) in front. When someone puts a tall thing in front, the Builder offers to move it back.'),
    ('A stage for Doum', 'The front middle stays open for Doum. Nothing can be placed there.'),
    ('A path', 'Stones lead from the beach to his spot, so his walks follow something.'),
    ('The palm above all', 'Nothing may reach the palm’s crown; the tallest building is 118, the palm 150 and up.'),
    ('The plate stays clear', 'Nothing in front covers the level plate.'),
    ('Room to walk', 'Every place has a standing spot in front of it where Doum stops when you tap it.'),
]
place_cards = ''.join(f'<div style="background: #FFFFFF; border-radius: 20px; padding: 18px 20px; display: flex; flex-direction: column; gap: 6px;"><span style="font-size: 18px; font-weight: 700;">{a}</span><span style="font-size: 15px; line-height: 1.55; color: #45574B;">{b}</span></div>' for a, b in places)

clear = ['Every tap target is at least 44 points.', 'Tapping a thing names it, says when it came, and shows one button for what you can do there.',
         'The chosen thing glows on the ground; nothing else is highlighted.', 'One short line tells you what to do next; no tutorials, no hidden gestures.',
         'Arabic labels are one or two words.', 'Night, quiet days and Reduce Motion all keep the same layout.']
clear_html = ''.join(f'<li style="margin-bottom: 8px;">{x}</li>' for x in clear)

DOUM_BLOCK = """The same green sprout mascot as the attached pictures. 4 columns × 3 rows, 1536 × 1024 px, each cell 384 × 341 px, 48 px clear space inside every edge, transparent background.
Exactly the same character in every cell: boxy green body #74C878, cream belly and two cream leaves #F5F0E1 (always two leaves, always visible), pink cheeks, dark green outline #1E3A24, body 150 px tall without the leaves, feet on a line 50 px above the bottom of the cell.
This is an animation sheet: every cell is one frame. Keep the body the same size and in the same place in every frame; only the feet, arms and leaves move, and the body rises or sinks by at most 8 px. No motion lines, no dust, no shadows, no background, nothing else in the cells.
Happy or calm in every frame. No sad, worried or tired faces, no tears, no sweat drops. No text, numbers, music notes, crowns or medals. No praying, Quran, prayer beads or prayer mat. No food or drink in his mouth."""

SHEETS = [
    ('Sheet 8 · walking: side, front, back', 'Attach: mascot_front_wave, mascot_side_right, mascot_back', DOUM_BLOCK + """

Row 1: walking to the right, seen exactly from the side like the attached side picture. Four frames of one step: 1. right foot forward touching the ground, left foot back; 2. both feet under the body, body 6 px lower; 3. left foot forward touching the ground, right foot back; 4. both feet under the body, body 6 px higher. Arms swing opposite to the feet; leaves lean back a little.
Row 2: walking toward the viewer, seen from the front like the attached front picture, both arms down, the same four frames. Smiling.
Row 3: walking away from the viewer, seen from the back like the attached back picture, the same four frames."""),
    ('Sheet 9 · walking at an angle, and standing', 'Attach: mascot_three_quarter_wave, mascot_back, mascot_front_wave', DOUM_BLOCK + """

Row 1: walking toward the viewer and to the right, three-quarter front view like the attached three-quarter picture, arms down. Four frames of one step: right foot forward, down, left foot forward, up.
Row 2: walking away from the viewer and to the left, three-quarter back view, the same four frames.
Row 3: standing still, front view, arms down: 1. calm smile; 2. the same with eyes closed, a blink; 3. looking to his left, small smile; 4. looking to his right, small smile."""),
    ('Sheet 10 · things he does on the island', 'Attach: mascot_front_wave, mascot_side_right', DOUM_BLOCK.replace('only the feet, arms and leaves move, and the body rises or sinks by at most 8 px', 'he may bend, kneel or sit as each frame says') + """

Row 1: 1. on tiptoe, reaching up with both arms; 2. holding a small brown date bunch up, happy; 3. kneeling, snipping a small green cutting from a little plant with small garden scissors; 4. holding the little cutting up, proud.
Row 2: 1. tilting a green watering can; 2. pouring, a thin arc of water from the can; 3. sitting on a small wooden bench, seen from the side, relaxed (draw the bench); 4. sitting on red and cream floor cushions, seen from the front (draw the cushions).
Row 3: 1. walking to the right carrying a small woven basket with both arms; 2. bending to put the basket down; 3. holding a small camera up to his face; 4. pushing a wooden door open, seen from the back (draw the door)."""),
    ('Sheet 11 · Doum in parts (the smoothest option)', 'Attach: mascot_front_wave', """The same green sprout mascot as the attached picture, front view, taken apart into pieces so it can be animated in code. 4 columns × 3 rows, 1536 × 1024 px, each cell 384 × 341 px, 48 px clear space inside every edge, transparent background. Every piece at the same scale as a body 150 px tall. Same colours: green #74C878, cream #F5F0E1, outline #1E3A24, pink cheeks.
One piece per cell, centred, nothing else:
1. the body only, with no leaves, no face, no arms, no feet and no belly
2. the cream belly patch
3. the left leaf with its little stem
4. the right leaf with its little stem
5. the left arm
6. the right arm
7. the left foot
8. the right foot
9. both eyes open
10. both eyes closed in happy arcs
11. the smiling mouth with the two pink cheeks
12. an open happy mouth with the two pink cheeks
No text, no numbers, no shadows, no background."""),
]
sheet_html = ''.join(
    f'<div style="background: #23352A; color: #F5F0E1; border-radius: 24px; padding: 24px 26px; display: flex; flex-direction: column; gap: 10px;">'
    f'<div style="font-size: 15px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: #9FD88F;">{t}</div>'
    f'<div style="font-size: 14px; color: #FFF3C4; font-weight: 600;">{att}</div>'
    f'<div style="font-size: 14px; line-height: 1.6; white-space: pre-wrap; font-family: \'IBM Plex Mono\', ui-monospace, monospace; user-select: all;">{body}</div></div>'
    for t, att, body in SHEETS)

FMETA = ic.FRAME_META
def strip(names, classes, label, h=150, extra_cls=''):
    imgs = ''
    for n, c in zip(names, classes):
        m = FMETA[n]; sc = h / m['dh']
        imgs += (f'<img src="/_blob/{ic.FRAME_IDS[n]}" alt="" class="{c}" style="position: absolute; left: {-m["ax"] * sc:.0f}px; top: {-m["ay"] * sc:.0f}px; '
                 f'width: {m["w"] * sc:.0f}px; height: {m["h"] * sc:.0f}px; max-width: none;">')
    return (f'<div style="background: #FFFFFF; border-radius: 20px; padding: 12px; display: flex; flex-direction: column; align-items: center; gap: 8px;">'
            f'<div style="position: relative; width: 150px; height: 196px;"><div class="{extra_cls}" style="position: absolute; left: 75px; top: 188px; width: 0; height: 0;">{imgs}</div></div>'
            f'<div style="font-size: 14px; font-weight: 700; text-align: center;">{label}</div></div>')
cyc = lambda d: strip([f'walk_{d}_{k}' for k in range(1, 5)], [f'isl-fr isl-fr{i}' for i in range(4)], {'side': 'Walking, side', 'front': 'Walking toward you', 'back': 'Walking away', 'three': 'Walking at an angle', 'back34': 'Away at an angle'}[d], extra_cls='isl-sway-s')
strips = ''.join(cyc(d) for d in ['side', 'front', 'back', 'three', 'back34'])
strips += strip(['idle_calm', 'idle_blink', 'idle_look_l', 'idle_look_r'], ['', 'isl-blink', 'isl-lookl', 'isl-lookr'], 'Standing: blinks, glances', extra_cls='isl-breathe')
# the frames in use after the animation pass (2026-10-03): no prop that doubles up with the island
ACTS = [('reach', 'Reach'), ('hold_dates', 'Dates'), ('hold_cutting', 'Holds a cutting'), ('can_tilt', 'Tilt'), ('can_pour', 'Pour'),
        ('sit_front', 'Sits, any seat'), ('plant_dig', 'Digs'), ('plant_pat', 'Pats the sprout in'), ('carry_basket', 'Carries'), ('put_basket', 'Puts down'),
        ('camera', 'Photo'), ('door_push', 'Door')]
# every picture at the same Doum size (90 px standing), so their sizes compare
act_cells = ''.join(f'<div style="display: flex; flex-direction: column; align-items: center; justify-content: flex-end; gap: 4px;"><img src="/_blob/{ic.FRAME_IDS[n]}" alt="" '
                    f'style="height: {FMETA[n]["h"] * 90 / (302 * FMETA[n]["k"]):.0f}px; width: auto;"><span style="font-size: 13px; color: #45574B;">{t}</span></div>' for n, t in ACTS)

body = header(
    'Before we build',
    'Motion, size and places, checked',
    'Your ask: the best design and idea, smooth movement, nice animation, the right sizes, everything in a nice spot and clear. This page is the checklist, and all of it is now working on the canvas: open Walk and Play full-window. Sheets 8 to 11 are in: Doum really walks in five directions, blinks, glances, and does things.'
) + f"""
<section style="display: flex; flex-direction: column; gap: 20px;">
<h2 style="{H2}">Try the new walking</h2>
<p style="{LEAD}">Tap the ground far to the left, then far to the right, then behind the palm: he turns, steps with the drawn walk cycle, casts a shadow, passes behind things and lands. Then tap the palm (he picks dates), the jasmine (a cutting), the bench (he sits), the gift button (he carries a basket over) and the camera.</p>
<div style="display: flex; gap: 28px; flex-wrap: wrap;">{phones([('Walk', 'Visiting: your Doum walks'), ('Play', 'Your island: your Doum walks')])}</div>
</section>

<section style="display: flex; flex-direction: column; gap: 16px;">
<h2 style="{H2}">Doum's animation, in</h2>
<p style="{LEAD}">Sheets 8 to 11 are cut, lined up and wired. Every walk cycle below is live (four frames, about nine a second); the standing Doum blinks every five seconds and glances around; the actions play on visits and on your own island.</p>
<div style="display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 12px;">{strips}</div>
<div style="background: #FFFFFF; border-radius: 20px; padding: 18px; display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 12px; justify-items: center; align-items: end;">{act_cells}</div>
<p style="{LEAD}"><b>Animation pass, 3 October.</b> Some drawings brought their own props, which doubled up with the real thing next to Doum. The bench and cushion poses had their own seats: he now sits with one front-on picture on whatever seat is there, hopping up and down. The pour lost its little sapling, so the stream falls on the real plant. The door pose lost its door. Taking a cutting is reach, then hold. Planting is digging, then patting the sprout in, with no pot. He turns to face what he works on, and stands where nothing in front hides his hands.</p>
<h3 style="margin: 8px 0 0; font-size: 24px; font-weight: 700;">Doum from parts (Sheet 11)</h3>
<p style="margin: 0; font-size: 17px; line-height: 1.5; color: #45574B;">Press the buttons: the same Doum assembled from eight pieces and a face drawn in code. Leaves sway on their stems, eyes blink, arms swing from the shoulder.</p>
<div style="border-radius: 24px; overflow: hidden; width: 860px; height: 620px; box-shadow: 0 0 0 1px #E1D9C4;"><dc-import name="Rig" hint-size="860px,620px"></dc-import></div>
</section>

<section style="display: flex; flex-direction: column; gap: 14px;">
<h2 style="{H2}">How he moves</h2>
<div style="background: #FFFFFF; border-radius: 24px; padding: 4px 24px;">{motion_rows}</div>
<p style="margin: 0; font-size: 15px; line-height: 1.55; color: #6B7A6F;">In the app this is the same kind of code the sprout already uses for its hop and breath (keyframed squash and stretch at 60 frames a second), with the walk frames played on top.</p>
</section>

<section style="display: flex; flex-direction: column; gap: 14px;">
<h2 style="{H2}">Sizes: everything measured against Doum</h2>
<p style="{LEAD}">Before, trees were Doum’s height and the house barely taller, so the island read as a dollhouse. Now Doum is a little smaller and everything is sized by height against him: flower beds 0.85×, small things 0.6 to 1.1×, trees 1.45×, buildings 1.5 to 1.8×, the palm 2.3× and up.</p>
<div style="background: #FFFFFF; border-radius: 24px; padding: 24px; display: flex; align-items: flex-end; justify-content: space-between; gap: 14px; flex-wrap: wrap;">{cells}{palm_cell}</div>
<img src="{SCALE_IMG}" alt="Before and after at levels 24 and 80" style="width: 100%; max-width: 1340px; border-radius: 20px;">
<p style="margin: 0; font-size: 15px; color: #6B7A6F;">Left of each pair: before. Right: now. Levels 24 and 80.</p>
</section>

<section style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(560px, 100%), 1fr)); gap: 32px; align-items: start;">
<div style="display: flex; flex-direction: column; gap: 14px;">
<h2 style="{H2}">Places: rules the app follows</h2>
<div style="display: grid; gap: 12px;">{place_cards}</div>
</div>
<div style="display: flex; flex-direction: column; gap: 14px;">
<h2 style="{H2}">Clear</h2>
<ul style="margin: 0; background: #FFFFFF; border-radius: 24px; padding: 20px 24px 12px 42px; font-size: 17px; line-height: 1.5; color: #23352A;">{clear_html}</ul>
</div>
</section>

<section style="display: flex; flex-direction: column; gap: 16px;">
<h2 style="{H2}">The animation prompts (8 to 11 done; use them as templates)</h2>
<p style="{LEAD}">Do 8 and 9 first: with them Doum really steps in every direction. 10 adds the things he does on visits. 11 is the smoothest route: Doum in pieces, so code can sway his leaves, blink his eyes and swing his arms forever with tiny files. The reference pictures are in design/mascot/walk-refs. If a frame comes back off size, I fix the scale; if it comes back off model, redo only that sheet.</p>
<div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(min(600px, 100%), 1fr)); gap: 16px;">{sheet_html}</div>
</section>
"""
open(os.path.join(HERE, 'project', 'Polish.dc.html'), 'w').write(page('Before we build', body, 7600, ic.STYLE))
print('Polish')
