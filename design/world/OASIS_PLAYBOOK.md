# Doum's oasis: the playbook

How the oasis works, what each step of it needs (art, animation, timing), and
the exact steps and prompts for adding a new thing or a new Doum animation.

Canvas: https://claude.ai/artifact/8npqUYRC5bucfcFCaRJR21
(start with the top row, "Start here: the simple version", and its three
phones; everything below that row is the earlier, deeper thinking).

**2026-10-03, the simple version.** Aziz: "too deep with items, hard to use,
make it simple, direct, but nice, and everything has an idea; why would I go
to another user's oasis and click?" So: one idea (your days grow it; friends
can take a cutting of your plants), three screens (your oasis, arrange,
friends), and every tap has one reason. Section 2 is the simple flow; the
parked parts are listed under it.

Nothing here is built in the app yet. Everything below is the agreed design,
tested as a clickable prototype on the canvas.

---

## 0. Rules that never change

1. **Quiet.** The oasis never sends a notification of any kind. Nothing
   opens by itself, no red dots, no "your island is thirsty", no streaks you
   can lose, no daily login gifts, no chat. News waits on the oasis page as
   one line («أخذ خالد شتلة فل من واحتك»). A normal user sees one card on Profile and one
   line in the level-up message they already get, and logging a habit takes
   exactly as many taps as today.
2. **Depths are chosen.** 0 everyone (the card), 1 tap the card (your oasis
   and arrange), 2 Friends (the switch «أظهر واحتي لأصحابي», off until the
   person turns it on; off hides them both ways). Premium is one line: gold
   comes twice as fast.
3. **Halal art.** No people, animals, birds or insects. No faces on objects.
   Doum is the one character. No domes or minarets. No text or numbers in art.
4. **Growth is never sold.** Level, base, medals and dates come only from
   habits. Premium may give 2x gold (building speed), never XP. No random
   paid boxes (maysir).
5. **Visits show the island only.** Never habits, prayers or quiet days. A
   visitor always sees the island fresh.
6. **Reduce Motion** turns off every loop and bounce; Doum moves straight to
   where he goes with a short fade.

---

## 1. Where everything lives

| What | Where |
|---|---|
| Object sheets (originals and cut cells) | `design/world/sheet-<name>/` (plants, fx, later, palm, show, inside) |
| Island art at web size, plus anchors | `design/world/island/*.webp`, `design/world/island/meta.json` |
| Doum animation sheets and aligned frames | `design/mascot/sheet-walk/`, `sheet-walk2/`, `sheet-acts/`, `sheet-parts/` (each has `frames/` and `frames.json`) |
| Doum frames at web size, plus anchors | `design/mascot/frames-web/*.webp`, `design/mascot/frames-web/meta.json` |
| Reference pictures to attach to Doum prompts | `design/mascot/walk-refs/` (front, side, back, three-quarter) |
| Canvas generators (the source of every board) | `design/world/canvas-gen/` (see its README) |
| Object cutter | `tool/world/cut_world_sheet.py --sheet <name>` |
| Doum frame cutter | `tool/mascot/cut_frames.py --sheet <name>` |
| Palette fix for Doum paint | `tool/mascot/recolor_sheets_oct.py` (`recolor`, used by the frame cutter) |

---

## 2. The full flow, and the animation each step needs

Times are in seconds. "Units" are island units: the island is drawn in a
360 x 400 box and everything is placed in those units.

| # | Screen (canvas board) | What happens | Why it is there | Animation and assets |
|---|---|---|---|---|
| 1 | Profile card (Profile) | The island, small, under the stats. Tap opens your oasis. | The door. | Static. A new thing sparkles (1.6 loop) until the oasis is opened once. |
| 2 | Level-up message (LevelUp), then the planting moment (Oasis; test button «مستوى جديد») | The message that already exists says what grew. When the oasis opens, Doum walks to the empty place and plants it. | The one moment of reward. | Walk; `plant_seed` 1.1; the thing grows in 0.9 (scale 0.15 to 1.12 to 1) with a sparkle; one line «نبتت الخضار». |
| 3 | Your oasis (Oasis) | Doum lives there. Tap a thing: he walks to it and says its story («الفل نبت في المستوى 9», «البئر بنيناها بـ 250 ذهب»). The level card shows the bar and the next thing with its picture. A row says how many things your gold can build («7 أشياء تقدر تبنيها بذهبك») and opens «رتّب». One quiet news line when a friend took a cutting. Buttons «رتّب», «أصحابك». | Proof of your days, and what your habits grow next. | Life loop when nobody taps (sit on the bench 10, water a plant, the shore 6, dates at the palm, home 5; a tap pauses it 12 to 14). Walk cycles, `water`, `dates`, the sit (section 6). Reduce Motion: no life loop. |
| 4 | Arrange (Arrange) | Tap a place (empty places show a + ring). The tray, in three headed groups: «عندك» (cuttings say «من يوسف»), «ابنِ بالذهب» (price), «يفتح بعدين» (lock and level). Pick one: Doum walks over and plants it. On a place that has something: «نسخة ذهبية من هذا» for 2,000 gold, and «فضّه» returns it to yours. Short of gold: «ناقصك 650 ذهب». | Make it yours; gold has a use, and golden versions keep it useful after month five. | Walk; `plant_seed` 1.1 for plants, 0.3 for built things; grow-in 0.9 and sparkle. |
| 5 | Friends (Friends), off until turned on | First a card that says what it is and «شغّلها». Then friends from your rooms, highest level first, you in the list too. A chip: «عنده نبتتين ما عندك». | See where friends are (the list is the ranking), and a reason to visit. | Static; small glance islands. |
| 6 | A visit (Friends, visit) | Your Doum walks in from the boat; his Doum waves at home. Tap a plant you lack: «خذ شتلة» (a palm: «خذ فسيلة»); it grows in your oasis with his name. Tap one you have: «وعندك منه». Built things: price, or the level they open at. His bench: your Doum sits. | A cutting lasts: your oasis keeps your friends. Built things give you a goal. | Walk in (after 0.25); `cutting` (`snip` 0.5, then `hold_cutting`), line «صارت عندك»; the sit. |

**Seasons** come back every year and are Ramadan and the two Eids only (never
national days: Aziz holds them haram, and the app is for Muslims everywhere).
Ramadan nights: night sky, the crescent, two lanterns hanging from the palm's
fronds, everything that has a lantern glows (test button «ليالي رمضان»).

**Parked, art kept** (on the canvas under "Earlier thinking"): the room inside
the house (Sheet 7), gifts, likes, watering a friend and the visitors' book,
picking dates and photos on a visit, the weekly show, free editing at level 100
(14 places, flip, golden versions), a Premium page for the oasis. Each added a
screen or a button without a reason that lasts.

---

## 3. Adding a new thing to the island

### Step 1. Decide, on paper

| Field | Choices |
|---|---|
| id | lower_snake, English: `lemon`, `coral_house` |
| Arabic name | one or two words: «ليمون», «بيت مرجان» |
| kind | `grow` (opens by level, free; friends can take a cutting) · `build` (gold price) · `rare` (opens with a base, then gold) · `sea` · `sky` · parked: `inside`, `gift` |
| opens at | a level, or a base: 5 stone, 10 coral, 20 gold, 35 rainbow, 50 pearl ring, 75 star crown |
| gold price | built and rare things only (current list: bench 150 to coral house 1,200) |
| height | from the size table in section 7 (trees about 96, buildings 98 to 118, beds 52 to 60) |
| size | building (two back places), tall (back or middle), low (anywhere); or sea, sky |
| what Doum does there | `dates`, `water`, `sit` (a seat: give its seat height in units; the bench's is 15 at scale 1), or just a line (`look`); on a friend's plant, `cutting` |
| night lights | the points (as fractions of the picture) that glow at night, if any |
| story line | «نبت في المستوى 16، 9 أغسطس» / «بناه خالد في المستوى 20» |

### Step 2. Generate the art in ChatGPT

Paste the object block, then a numbered list of 12 things (4 x 3). If you need
fewer, add variants (a smaller one, a night version) to fill the sheet.

```
A sticker sheet of 12 separate objects for a cute children's-app world, in the same style as the green sprout mascot I attached. 4 columns × 3 rows, 1536 × 1024 px, each cell 384 × 341 px with 48 px of clear space inside every edge. Transparent background, no backdrop, no glow around the objects.
Style: thick dark green outline (#1E3A24, about 6 px), flat fills with one soft lighter shade, no gradients, no textures, no shadows on the ground.
Every object stands on the same invisible baseline 50 px above the bottom of its cell, centred left to right, seen from the front and slightly above.
Scale: a tree is about twice the height of the mascot's body; a bush about half. Keep that scale identical in every cell.
No text, no numbers, no letters. No faces on anything. No people, no animals, no birds, no insects, no mascot. No domes, no minarets. One object per cell, nothing touching the cell edges.

1. ...
2. ...
```

Attach `design/mascot/walk-refs/mascot_front_wave.png` so the style matches.

### Step 3. Cut it

1. Save the download as `design/world/sheet-<name>/sheet-<name>-original.png`.
2. Add an entry to `SHEETS` in `tool/world/cut_world_sheet.py`: the 12 ids in
   reading order (left to right, top to bottom), and how the ground was drawn:
   `blurbg=True` for a painted blurred backdrop (what ChatGPT has sent for
   sheets 6 to 11), `checker=True` for a painted checkerboard, neither for a
   real transparent ground.
3. Run `python tool/world/cut_world_sheet.py --sheet <name>`.

### Step 4. Check it

- Contact sheet on cream and on night blue (no holes, no leftover glow, no
  green halo). Holes in leaves mean the "closed-in ground" rule took too much.
- A line-up beside Doum at its target height (section 7).
- No creature, face, text or number anywhere.

### Step 5. Prepare web art

Trim to the painted pixels, at most 330 px on the long side, WebP quality 88,
and record `w`, `h` and `base` (the middle of the bottom 6% of painted
columns) in `design/world/island/meta.json`. The snippet used so far:

```python
from PIL import Image; import numpy as np, json
im = Image.open(cell).convert('RGBA'); a = np.array(im)[..., 3]
ys, xs = np.where(a > 20); im = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
k = min(1, 330 / max(im.size)); im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
a = np.array(im)[..., 3]; bx = np.where(a[int(im.height * .94):].max(0) > 20)[0]
meta[id] = dict(w=im.width, h=im.height, base=round((bx.min() + bx.max()) / 2 / im.width, 3))
im.save(f'design/world/island/{id}.webp', 'WEBP', quality=88, method=6)
```

### Step 6. Register it

On the canvas (generators in `design/world/canvas-gen/`):
- upload the WebP to the canvas (asset), add its id to `ART_IDS` in
  `island_core.py`, its height to `HEIGHTS`, and a row to `ITEMS`
  (id, Arabic, width, kind, gold, opens);
- if it lights up at night, add its points to `LIGHTS`;
- if Doum does something there, add it to the walk tables (`W_INFO`, `P_INFO`
  in `gen_walkers.py`): kind, story line, the stand point in front of it;
- re-run the generators and publish.

In the app (when building):
- `assets/images/world/<id>.webp` at 3x of its largest display size, listed
  in `pubspec.yaml`;
- one `OasisItem` entry: `id, nameAr, nameEn, kind, heightUnits, opensAtLevel
  or opensAtBase, goldPrice, place, interaction, lightPoints, baseAnchor`.

### Step 7. QA before it ships

- [ ] Size reads right next to Doum and next to the palm (nothing reaches the palm's crown).
- [ ] In each place it can go, it does not hide the level plate or the thing behind it.
- [ ] Night: dimmed like the rest; lights glow where they should.
- [ ] Tap target at least 44 points; its story line and button make sense.
- [ ] Reduce Motion: no hop or sparkle loop.
- [ ] Halal and no-text rules (section 0).

---

## 4. Adding a new Doum animation

### Step 1. Decide

- **Cycle** (loops: walking, a new way of moving): 4 frames per direction,
  played at about 9 frames a second (0.44 per cycle).
- **Action** (does something once): 1 frame, or 2 frames played as "start"
  0.5 then "hold" (reach then hold dates, tilt then pour).
- **Idle extra** (standing still): a single frame shown briefly over the calm
  frame (blink, glance).

### Step 2. Generate the sheet in ChatGPT

Attach the matching references from `design/mascot/walk-refs/` (front, side,
back, three-quarter). Paste the Doum animation block, then the rows.

```
The same green sprout mascot as the attached pictures. 4 columns × 3 rows, 1536 × 1024 px, each cell 384 × 341 px, 48 px clear space inside every edge, transparent background.
Exactly the same character in every cell: boxy green body #74C878, cream belly and two cream leaves #F5F0E1 (always two leaves, always visible), pink cheeks, dark green outline #1E3A24, body 150 px tall without the leaves, feet on a line 50 px above the bottom of the cell.
This is an animation sheet: every cell is one frame. Keep the body the same size and in the same place in every frame; only the feet, arms and leaves move, and the body rises or sinks by at most 8 px. No motion lines, no dust, no shadows, no background, nothing else in the cells.
Happy or calm in every frame. No sad, worried or tired faces, no tears, no sweat drops. No text, numbers, music notes, crowns or medals. No praying, Quran, prayer beads or prayer mat. No food or drink in his mouth.

Row 1: ...
Row 2: ...
Row 3: ...
```

For actions that bend, kneel or sit, replace the "Keep the body..." sentence
with: "Keep the body the same size in every frame; he may bend, kneel or sit
as each frame says."

**Never draw what the island already has** (lesson of 3 October). A pose that
brings its own seat, door, plant or pot doubles up with the real one next to
him: the bench pose showed two seats, the cushion pose two sets of cushions,
the pour a second sapling, the planting pose a pot. Draw only what he holds
(the can, the scissors, the cutting, the basket) and say in the line: "nothing
under him or in front of him; he sits on nothing / pours onto nothing / pushes
nothing". For sitting, ask for "sitting, seen from the front, legs forward,
nothing under him".

### Step 3. Cut and align

1. Save as `design/mascot/sheet-<name>/sheet-<name>-original.png`.
2. Add an entry to `SHEETS` in `tool/mascot/cut_frames.py`, one tuple per row:
   `("walk_side", "cycle")` names the four frames `walk_side_1..4`;
   `(["reach", "hold_dates", ...], "single")` names each cell.
3. Run `python tool/mascot/cut_frames.py --sheet <name>`. It removes the
   backdrop, moves the paint onto the palette, and for cycles puts every
   frame on one canvas with the same ground and centre. A line like
   `! walk_back_4: +9% against the row` means redraw that sheet; under 8% it
   is scaled to match.

### Step 4. Check

- Overlay the 4 frames of a cycle at one-third opacity (onion skin): the body
  must sit in one place; only feet, arms and leaves move.
- Compare the standing height with `idle_calm`.
- Look for props that the island already has (a seat, a door, a plant, a pot,
  soil). If one slipped in, take it off in `unprop()` in the frame cutter (by
  region and colour, as for `can_pour` and `door_push`), or redraw the pose if
  it overlaps his body (as `snip` does).
- Put the pose next to its real thing on a board and look at it at 2x
  (section 6, "Testing").

### Step 5. Web frames and wiring

- WebP, at most 300 px, into `design/mascot/frames-web/`, with `w, h, k`
  (the scale from the cut frame) and, for posed frames, `ax, ay` (ground point)
  and `dh` (painted height) in `meta.json`.
- Canvas: upload, add to `frame_ids.json`; cycles are picked up by direction
  name, actions go in the `ACT` table in `island_core.py`.
- App: play frames with one `AnimationController` per state (the sprout
  already does keyed hop and breath this way in `lib/features/mascot/sprout.dart`):
  place each frame by its ground point, scale so `dh` equals Doum's height
  (66 units on the island), sort by ground y for depth.

### What exists now

| Set | Frames | Use |
|---|---|---|
| Walk (Sheet 8) | `walk_side_1..4`, `walk_front_1..4`, `walk_back_1..4` | Walking right (mirrored for left), toward, away |
| Walk 2 (Sheet 9) | `walk_three_1..4` (toward and right), `walk_back34_1..4` (away and left), `idle_calm`, `idle_blink`, `idle_look_l`, `idle_look_r` | Diagonals (mirrored for the other side), standing |
| Acts (Sheet 10) | `reach`, `hold_dates`, `snip`, `hold_cutting`, `can_tilt`, `can_pour`, `sit_cushions`, `carry_basket`, `put_basket`, `camera`, `door_push` | Your oasis and visits (carry, put, camera, door are parked) |
| Sitting (from Sheet 10) | `sit_front`: `sit_cushions` with the cushions taken away by `cut_frames --sheet acts`; its anchor is the seat point | On any seat: the island bench and the room's cushions. `sit_bench` and `sit_cushions` are retired: they came with their own seats |
| Cleaned (Sheet 10) | `can_pour` without its sapling (the stream fades onto the real plant), `door_push` without its door | `snip` keeps its sapling and is not used; a cutting is `reach`, then `hold_cutting` |
| Planting (Sheet 1) | `plant_dig`, `plant_pat`, from `assets/images/mascot/work/` by `cut_frames --work` | Digging, then patting the sprout in. The old planting pose held a pot |
| Parts (Sheet 11) | `body`, `belly`, `leaf_l`, `leaf_r`, `arm_l`, `arm_r`, `foot_l`, `foot_r` (face drawn in code) | The code rig: breathing, leaves, blinking that never repeat stiffly |

Facing by heading (ground direction, y stretched x2.6 for the perspective):
front 67.5 to 112.5 degrees, three-quarter front 22.5 to 157.5, back -67.5 to
-112.5, three-quarter back -22.5 to -157.5, side otherwise. Mirror: side and
three-quarter front when going left; three-quarter back when going right.

---

## 5. All prompts used so far

| Sheet | What | Cut with |
|---|---|---|
| 1 | Doum at work (digging, planting, dates, wheelbarrow...) | `recolor_sheets_oct --sheet work`, `cut_poses`, `upscale_poses` |
| 2 | Palm stages and date bunches (drawn off the grid) | `cut_world_sheet --sheet palm` (free mode) |
| 3 | Things to plant (trees, flowers, house, well, spring) | `--sheet plants` (checker) |
| 4 | Later levels (stones, kite, lanterns, dhow, bench, falaj, rose arch...) | `--sheet later` |
| 5 | Effects (drops, splash, sparkle, pearl, basket...) | `--sheet fx` |
| 6 | Showpieces (coral house, fountain, golden palm, lantern arch, pearl chest, big dhow, majlis, palm-frond hut, lighthouse, lamp posts, lily pool, jasmine pergola) | `--sheet show` (blurbg) |
| 7 | Inside (mandoos, coffee set, incense burner, cushions, table, door, lattice window, shelf, lantern, potted palm, pattern frame, palm-frond mat) | `--sheet inside` (blurbg) |
| 8 | Walk side, front, back | `cut_frames --sheet walk` |
| 9 | Walk three-quarter front and back; standing calm, blink, look left, look right | `cut_frames --sheet walk2` |
| 10 | Actions | `cut_frames --sheet acts` |
| 11 | Parts | `cut_frames --sheet parts` |

The full text of sheets 6 to 11 is on the canvas boards "New look", "Deeper"
and "Before we build"; the blocks in sections 3 and 4 are the templates.

---

## 6. Motion spec

| Thing | Value |
|---|---|
| Walking speed | 70 units a second, eased in and out; never under 0.45 or over 2.6 |
| Walk cycle | 4 frames, 0.44 a cycle (0.11 a frame), tiny sway 1.2 degrees |
| Carrying | the carry frame with a 4 px bob and 2.5 degree sway |
| Landing | squash 0.32 (scale 1.07 x 0.90, then 0.98 x 1.03) |
| Standing | breathe 3.4 (2% taller); blink 0.15 every 5.3; glance left and right in a 12 loop |
| Actions | two-frame actions switch at 0.5; the line shows on arrival and stays 3.4 |
| Tapped thing | hops 0.9 (lift 9%, rock 3 degrees); three sparkles or drops rise 1.3 |
| Depth | sort by ground y every frame (Doum passes behind things further back) |
| Camera (walk view) | follows Doum on the same curve, 0.15 longer |
| Shadow | soft ellipse 36 units wide under the ground point, moves with him |
| Night | everything dims (brightness 0.78); lights glow (warm radial, 30 units) |
| Sitting | walks to the front of the seat (its ground + 7), a 0.18 beat facing front, hops up 0.42 (rises 9 units, the picture changes to `sit_front` at 45%, lands with a squash 1.07 x 0.92 at 78%), sits with a slow sway every 4.2 (1.2 degrees, 1 to 2.5% breathe), and hops down 0.38 before he walks anywhere. While seated he stands just in front of the seat in depth and has no shadow. Preview: `canvas-gen/doum-sits.gif` |
| His life loop | only while the oasis is open and nobody taps: the steps in section 2, row 3 |
| Facing an action | the action pictures face right; he is mirrored when the thing is on his left, so the can, the hand or the spade points at it |
| Where he stands | `STANDS` in `island_core.py`: beside back-row things (by the palm), on the outer sand for the middle row, in the open gap for the front row. Never behind a front-row thing, which would hide his hands. Planting uses `PLANT_STANDS`: the patted sprout, drawn 30 units to his side, lands on the place |
| Held actions | breathe like standing (3.4), so a 3-second pour is never a frozen picture |
| In the room | the same engine; speed 119 px a second (70 units at the room's scale, Doum 112 px tall); he walks to the cushions, sits on them with `sit_front`, and walks back |
| Testing | `node check/simulate.js` runs every board's taps; render each action next to its thing with `check/preview2.js` and look at it at 2x (`--force-device-scale-factor=2`) |
| Reduce Motion | no cycles, bobs, blinks, sparkles or life loop; Doum appears at the destination with a 0.2 fade |

---

## 7. Sizes, places and levels

**Doum is 66 units tall.** Everything is sized by height against him.

| Class | Height (units) | Ratio | Examples |
|---|---|---|---|
| Small things | 40 to 76 | 0.6 to 1.15 | bench 40, chest 54, telescope 62, well 76 |
| Beds and pools | 48 to 60 | 0.75 to 0.9 | spring 48, vegetables 52, flowers 56, rose 58 |
| Trees | 90 to 102 | 1.4 to 1.55 | sidr 90, lemon and pomegranate 96, second palm 102 |
| Arches and pergolas | 90 to 96 | about 1.45 | vine 90, rose arch 92, lantern arch and jasmine pergola 96 |
| Buildings | 90 to 118 | 1.4 to 1.8 | majlis 90, palm-frond hut 98, Doum's house 104, coral house 118 |
| The palm | 58 to 172 by level | up to 2.6 | shoot 58 (L1), young 96 (L5), medium 128 (L12), tall 150 (L20+) |

**Places** (ground point x, y in units; scale): back left (114, 226, 0.92),
back right (264, 226, 0.92), left (70, 256), right (294, 256), front left
(104, 286, 1.06), front right (254, 286, 1.06). The palm stands at (196, 228).
Doum's home spot is (168, 300); the front middle stays open for him. The
simple version keeps these six places at every level (more places with the
base is parked with level-100 editing).

**What may stand where** (Aziz, 2026-10-03: "big building only in the back").
Buildings (Doum's house, coral house, palm-frond hut, majlis) only in the two
back places; tall things (trees, the well, arches, the fountain, lamp posts)
in the back or middle row; low things (flowers, vegetables, bench, spring,
chest, telescope, falaj, lily pool) anywhere. In «رتّب» a place says what fits
(«مكان قدّام: الأشياء الواطية بس») and what does not sits greyed under
«للأماكن اللي ورا». `BIG`, `TALL`, `fits()` in `island_core.py`; the
automatic layout by level follows the same rule. A new thing: give it a size
in step 1 of section 3.

**Bases** (rank levels): 1 sand, 5 stone, 10 coral, 20 gold trim, 35
rainbow, 50 pearl ring, 75 star crown, 100 full gold glow. At about 7 habits
a day: stone in a week, coral in a month, gold in about 4 months, rainbow in
about 13 months, pearl ring in about 2 years, star crown in about 5 years.

---

## 8. Data the app needs

```
users/{uid}/oasis
  placements: [itemId x 6]                         // '' for an empty place
  owned: { itemId: { from? } }                     // earned by level, built with gold, cuttings with the friend's name
  golden: { place: true }                          // golden versions, 2,000 gold each; emptying the place drops it
  friendsOn: false                                 // the switch, off by default; off hides you both ways
users/{uid}/oasisNews                              // only when friendsOn
  [{ from, itemId, at }]                           // "took a cutting"; shown once as the quiet line, never pushed
```

A cutting: one of each plant you lack, from any friend; it gives no XP and no
gold, and the friend loses nothing. Visits give no XP and no gold.

---

## 9. Gold and XP, the real numbers (from the app's code, 2026-10-03)

| Source | XP | Gold |
|---|---|---|
| A habit | 15 to 40 by category (custom 20) | 5 to 15 (custom 8) |
| Surprise (15% of completions) | +50% | +50% |
| A task (at most 15 paid a day, once each) | 10 | 4 |
| Streak milestones (once) | 25 at 3 days up to 6,000 at 365 | |
| Level-up gold grants (levels 2 to 22) | | 350 over a lifetime |

The next level needs level x 100 XP, so reaching level L takes 50 x L x (L - 1)
XP. Daily ceiling: max(3,000, 150 x habits), an anti-abuse limit nobody honest
reaches. An active person (5 habits, 3 tasks) earns about 140 XP and 55 gold a
day: level 10 in about a month, 20 in 4.5 months, 35 in 14 months, 50 in 2.4
years, 75 in 5.4 years, 100 in about 10 years. Gold comes at about 1,650 a
month; everything buildable by level 20 costs about 5,200, so gold piles up
from month five. Golden versions (2,000 each) are the long-term use for it.

Already safe: clock changes (server rules check the real date), undo (exact
reversal; level-up gold never paid twice), tasks (paid once each). Open: the
phone writes level, XP and gold.

## 10. Open choices (for Aziz)

1. Friends off until the person turns it on (recommended yes).
2. Premium: seasons (Ramadan and the two Eids), own colours and real palms,
   instead of 2x gold, which doubles a currency already in surplus
   (recommended).
3. Fair rank: at most 10 habits a day count toward level, so Premium's
   unlimited habits can't buy a higher base; tracking stays unlimited
   (recommended).
4. The level friends see is checked on the server before Friends ships
   (recommended).
5. A cutting can be a plant you have not reached by level yet (recommended
   yes: it is how friends help; the level and the base stay yours alone).
6. Doum's life loop on your oasis while the page is open (recommended yes; off
   with Reduce Motion).
7. Bring the parked parts back one at a time, only if people ask.
8. For the app's Doum: drawn frames for walking, sitting and actions, the
   parts rig for all-day loops (recommended).
