# Mascot art

Aziz generated the sheet with ChatGPT on 2026-09-27. The sheets here are
kept at full resolution and out of both bundles: pubspec.yaml bundles only
the asset folders it lists, and `design/` is not one of them.

- `mascot-sheet-original.png` (1536x1024, byte-identical to the download):
  18 poses of the sprout character in three rows. A six-angle turnaround,
  six expressions and six activities, on a transparent background.
- `mascot-sheet-final.png`: the chosen colours with the drawing fixes below.
  The 18 poses in `assets/images/mascot/` are cut from this sheet.
- `poses-native/`: the 18 poses cut at the sheet's own size (181 to 297 px
  wide, 1.3 MB), before upscaling. `poses-4x/`: the 4x masters.
- `color-options/`: the three comparison boards Aziz chose from (body
  greens, replacements for the gold, then this mix). The full-size option
  sheets were removed once the choice was made.

## Chosen colours (2026-09-27)

| Part | Colour | OKLCh |
| --- | --- | --- |
| Body, arms, legs, leaf undersides | #74C878 | 0.76 0.14 145 |
| Leaves, stem, belly | #F5F0E1 | 0.955 0.02 90 |
| Cheeks | soft pink | 0.74 0.12 25 |
| "?", "zZ", clipboard tick boxes | deeper green | L 0.55, chroma capped at 0.14 |

The pencil, the sparkles and the laugh and "!" lines are props and effects,
so they keep their yellow. The original body measured L 0.458 C 0.094
h 150.6 and the gold L 0.812 C 0.152 h 80.8. Shading keeps 80% of the body's
lightness range and 60% of the gold's, so the plush look survives.

## Drawing fixes (in `mascot-sheet-final.png`)

- Every cheek is soft pink. In the original three were olive (walking,
  book, sleeping) and two sit half hidden behind the laptop and the book.
- The belly rim and the leaf folds, where gold met green, are rebuilt as a
  proper blend of the new colours. Left alone they came out grey and olive.
- Outline pixels that carried an olive tint from the old gold now match
  the rest of the outline's dark green.
- Walking pose: the strap was a green and brown smear; it is solid brown,
  shaded like the backpack.
- Sleeping pose: a faint grey smudge beside the "zZ" is removed.
- Two 1 to 2 px dark specks on the body are removed (heart, book).

## The poses (`assets/images/mascot/`)

NOT in pubspec.yaml yet, so not bundled (4.7 MB for all 18, 160 to 340 KB
each). Add the folder, or just the files a screen uses, when a pose goes
into the app.

How they were made (2026-09-27), from `mascot-sheet-final.png`:

1. Cut: one pose per file with the effects that belong to it (sparkles,
   hearts, "?", lines, "zZ"). Nearby effects are grouped before being given
   to the nearest pose, or the big "Z" lands on the determined pose.
2. Upscaled 4x with Real-ESRGAN (`RealESRGAN_x4plus_anime_6B`, official
   GitHub release v0.2.2.4), colour and alpha each through the model. The
   model paints a light ring beside dark shapes (eyes, mouth); every output
   pixel is clamped to the min and max of the original 3x3 pixels around
   it, which removes the ring and keeps the sharp edge. Colour drift after
   upscaling is at most 0.004 in OKLab, well under what the eye can see.
3. Alpha cleanup: fully opaque body, no faint halo, edge pixels take the
   outline's colour (no light fringe on dark cards), transparent pixels
   carry the nearest colour (no dark bleed when scaled). What stays
   translucent on purpose: the gap between the two leaves, the soft ground
   shadows, and the effects' edges.
4. App size: the sheet drew its rows at different scales (by eye height,
   eye spacing and belly width, the turnaround row is 1.385x the activity
   row and the expression row 1.103x). Each file is scaled so the character
   is the SAME size in all 18, at 3x the activity row's original size, with
   a 12 px transparent margin.

The 4x masters, before step 4, are in `poses-4x/` (724 to 1188 px wide,
8.1 MB, not bundled) for anything bigger: store screenshots, a splash.

| File | Pose | Size |
| --- | --- | --- |
| `mascot_front_wave.png` | front, waving | 633x767 |
| `mascot_three_quarter_wave.png` | three-quarter front, waving | 597x750 |
| `mascot_side_right.png` | profile facing right, leaves bent back | 399x752 |
| `mascot_back.png` | from behind | 591x743 |
| `mascot_back_three_quarter.png` | from behind, turned, one arm out | 576x750 |
| `mascot_side_right_leaf_up.png` | profile facing right, one leaf straight up | 382x787 |
| `mascot_happy_sparkles.png` | arms up, two gold sparkles | 700x802 |
| `mascot_laugh.png` | laughing, eyes shut, gold laugh lines | 658x780 |
| `mascot_love_heart.png` | hugging a big heart, two small hearts | 649x784 |
| `mascot_wink.png` | winking, waving, one gold sparkle | 669x780 |
| `mascot_confused.png` | hand at the chin, green "?" | 668x777 |
| `mascot_determined.png` | frowning, fists up, motion lines | 695x780 |
| `mascot_walk_backpack.png` | walking with a backpack | 713x812 |
| `mascot_laptop.png` | sitting with a laptop | 737x763 |
| `mascot_reading.png` | sitting with an open book | 641x793 |
| `mascot_pencil.png` | winking, holding a pencil, gold "!" lines | 700x773 |
| `mascot_checklist.png` | holding a clipboard with three ticks | 679x778 |
| `mascot_sleeping.png` | lying asleep, "zZ" | 850x679 |

Two things to know when placing them:

- Because the character is one size in every file, show poses with one
  shared `scale` rather than one shared height:
  `Image.asset(path, scale: 4)` draws the front pose about 160 pt wide and
  every other pose with the same-size character. A shared height would
  shrink the character in tall poses and grow it in the sleeping one.
- Both profiles face right (the sheet repeated the side view rather than
  drawing the other side). The character is symmetric, so a left-facing one
  is a `Transform.flip` in code, which also suits RTL layouts.

## Rebuilding (`tool/mascot/`)

Three steps, each rerunnable on its own. Each script's docstring explains its
choices. They need Python 3 with numpy, scipy and Pillow, plus torch for step
3. Keep that environment outside the repo:

    python3 -m venv ~/.venvs/growdaily-mascot
    ~/.venvs/growdaily-mascot/bin/pip install numpy scipy pillow torch

    ~/.venvs/growdaily-mascot/bin/python tool/mascot/recolor_sheet.py   # -> mascot-sheet-final.png
    ~/.venvs/growdaily-mascot/bin/python tool/mascot/cut_poses.py       # -> poses-native/
    ~/.venvs/growdaily-mascot/bin/python tool/mascot/upscale_poses.py   # -> poses-4x/, assets/images/mascot/

Step 3 downloads the model weights (17.9 MB) into `~/.cache/growdaily/` on
first use and refuses a file whose SHA-256 differs from the one verified here.
Checked 2026-09-27: run from the original sheet, the three steps reproduce
every file in this folder and in `assets/images/mascot/` pixel for pixel.

- Another colour: edit the PALETTE block in `recolor_sheet.py`, run all three.
- One pose again: `upscale_poses.py --only mascot_laptop`.
- The other sheets: `cut_poses.py` and `upscale_poses.py` take `--sheet 2`,
  `--sheet sport`, `--sheet streak` or `--sheet ghutra` (the upscale's
  `--only` works with each). Every sheet has its own colour script and pose
  list (`poses-<name>.json`), and some a fix step, so the full order is at
  the end of each sheet's section below.
- A new sheet: `recolor_sheet.py`'s coordinates and `cut_poses.py`'s row
  splits belong to this sheet, and a new pose needs an entry in `poses.json`
  with the row whose scale it matches. Another sheet gets its own colour
  script, pose list and entry in the SHEETS table of both scripts.

The widget's two images (`SproutHappy`, `SproutSleeping` in
`ios/GrowDailyWidget/Assets.xcassets`) are written by step 3 too, from the
app copies at one shared scale; see upscale_poses.py's docstring.

## The second sheet (2026-09-29)

Aziz generated a second ChatGPT sheet on 2026-09-29, drawn from the first
package and already in its colours. Its files are in `sheet-2/`:

- `mascot-sheet-2-original.png` (1536x1024, byte-identical to the download):
  24 poses in four rows of six, on a transparent background.
- `mascot-sheet-2-final.png`: the same sheet with its paint matched to the
  palette (below). The poses are cut from this one.
- `poses-native/`: the 24 poses at the sheet's own size (193 to 332 px
  wide). `poses-4x/`: the 4x masters, not bundled.

What was done, in the same three steps as the first sheet:

1. Colour (`recolor_sheet_2.py`). The body came out lighter than the
   palette: L 0.800 against #74C878's 0.76, measured on the interior. Every
   pixel of green paint moves by that difference, keeping its offsets, so
   the drawing and its shading are untouched. The leaves, stem and belly
   differ by under 0.01 and are left alone, as are the cheeks and the
   outline. The green effects (the "?", music notes, "zZ", the calm pose's
   small leaves) take the first sheet's deeper green for the "?" and "zZ",
   so they stay legible on light cards. The one green confetti piece keeps
   its colour.
2. Cut (`cut_poses.py --sheet 2`), with the first sheet's rules. One
   piece needs placing by hand: the cheering pose's upper right-hand line
   sits nearer the magnifier pose's leaf. The headphones pose's two music
   notes are dropped here (Aziz, 2026-09-29), so the sheet still has them
   and the pose does not.
   Then `fix_poses_2.py`: ChatGPT drew the idea pose with one leaf. It gets
   the waving pose's pair (same row, same size, same head angle), set on its
   stem, and its bulb floats 70 px right and 18 px up to clear the new leaf
   (Aziz, 2026-09-29). The step cuts both poses again from the sheet, so it
   is safe to rerun.
3. Upscale (`upscale_poses.py --sheet 2`): the same model, clamp and alpha
   cleanup. The sheet drew two sizes, rows 1 and 2 about 11% bigger than
   rows 3 and 4, and each row is scaled so the character matches the first
   package's app copies (2.90, 2.93, 3.25 and 3.25 app px per sheet px; how
   they were measured is in upscale_poses.py's docstring). Show them with
   the same shared scale as the first 18.

### Repeats

Five poses repeat the first package. They keep a master in `poses-4x/` and
get no app copy; the first package's versions stay. Four more come close
with a new gesture and are in the app folder with the rest.

| Sheet 2 master | Sheet # | Repeats | Kept |
| --- | --- | --- | --- |
| `mascot_front_wave_2.png` | 6 | `mascot_front_wave` | the first package's |
| `mascot_confused_2.png` | 7 | `mascot_confused` | the first package's |
| `mascot_laptop_2.png` | 10 | `mascot_laptop` | the first package's |
| `mascot_love_heart_2.png` | 22 | `mascot_love_heart` | the first package's |
| `mascot_sleeping_2.png` | 23 | `mascot_sleeping` | the first package's |

### The new poses (`assets/images/mascot/`)

NOT in pubspec.yaml: add a file there, one line per pose, when a screen
draws it (sprout_assets_test checks the ones `Sprout` knows).

| File | Sheet # | Pose | Size |
| --- | --- | --- | --- |
| `mascot_cheer.webp` | 1 | cheering, one arm high, gold lines (close to `mascot_happy_sparkles`) | 699x789 |
| `mascot_magnifier.webp` | 2 | looking through a magnifying glass, one brow up | 716x783 |
| `mascot_idea.webp` | 3 | hand up, a light bulb above (leaves fixed) | 943x851 |
| `mascot_confetti.webp` | 4 | laughing, eyes shut, arms up, confetti | 748x789 |
| `mascot_thumbs_up.webp` | 5 | winking, thumbs up, one gold sparkle | 730x815 |
| `mascot_sunglasses.webp` | 8 | sunglasses, arms crossed, one gold sparkle | 640x792 |
| `mascot_mug.webp` | 9 | holding a steaming mug, eyes shut | 698x781 |
| `mascot_headphones.webp` | 11 | headphones on, eyes shut | 669x768 |
| `mascot_note.webp` | 12 | reading a sheet of paper, one arm up, gold lines (close to `mascot_checklist`) | 686x754 |
| `mascot_running.webp` | 13 | running, speed lines, a sweat drop | 790x725 |
| `mascot_megaphone.webp` | 14 | calling through a megaphone, gold lines | 887x752 |
| `mascot_shrug.webp` | 15 | arms out, frowning, blue question mark (close to `mascot_confused`) | 720x743 |
| `mascot_pointer.webp` | 16 | pointing with a stick, gold lines | 767x760 |
| `mascot_chart.webp` | 17 | presenting a rising bar chart on an easel | 1044x745 |
| `mascot_peek.webp` | 18 | peeking out from behind a post | 596x682 |
| `mascot_calm.webp` | 19 | sitting, eyes shut, hands folded, small leaves | 706x722 |
| `mascot_cookie.webp` | 20 | sitting, eating a cookie | 667x741 |
| `mascot_books.webp` | 21 | carrying a tall stack of books, straining | 724x732 |
| `mascot_wink_jump.webp` | 24 | winking, jumping, one arm high, gold sparkles (close to `mascot_wink`) | 856x798 |

Before placing one:

- `mascot_mug` and `mascot_cookie` eat and drink: never on a fasting habit
  or during Ramadan's day.
- `mascot_calm` sits cross-legged with its eyes shut, which reads as
  meditation: keep it for rest and calm, and away from worship moments like
  every other pose (never in tasbih or prayer times).
- `mascot_shrug` frowns. The app's rule is that Doum never looks sad at the
  reader, so it suits "nothing found", never a missed day.
- `mascot_peek`'s post is cut flat at the top and bottom: place it where
  the post meets an edge.
- `mascot_running` has a sweat drop: fine for "let's go", not for a streak
  at risk (reminders never press or blame).

Rebuilding: `recolor_sheet_2.py`, then `cut_poses.py --sheet 2`, then
`fix_poses_2.py`, then `upscale_poses.py --sheet 2`. Checked 2026-09-29, after the `--sheet`
option went in: the first sheet's cut still reproduces all 18 poses byte for
byte, and its upscale the two poses checked (front wave, laptop).

## The sport sheet (2026-09-30)

Aziz generated a sport sheet with ChatGPT on 2026-09-30. Its files are in
`sheet-sport/`:

- `sheet-sport-original.png` (1536x1024, byte-identical to the download
  "ChatGPT Image 30 سبتمبر 2026، 02_04_17 م.png"): 15 sport and exercise poses
  in three rows of five, on a transparent background.
- `sheet-sport-final.png`: the same sheet with its paint matched to the
  palette and its ground shadows lifted (below). The poses are cut from this
  one.
- `poses-native/`: the 15 poses at the sheet's own size (255 to 347 px wide,
  1.3 MB). `poses-4x/`: the 4x masters (1020 to 1388 px wide, 9.1 MB), not
  bundled.

What was done, in the same three steps as the other sheets, and one fix:

1. Colour and ground (`recolor_sheet_sport.py`). Measured on the interior,
   the body came out L 0.820 C 0.139 h 143.4, 0.06 lighter than #74C878
   (twice the second sheet's gap), the leaves, stem and belly 0.022 whiter
   than #F5F0E1, and the cheeks peach (hue 38) where the palette is pink
   (25). All three move onto the palette by the measured difference, keeping
   their offsets, so the drawing and its shading stay as drawn: the body now
   measures L 0.760 C 0.140 h 144.9, the cream 0.955, the cheeks 0.743 0.119
   h 25. The hue window is narrow and effects never move, so the tennis ball
   stays yellow and every red, blue, navy, black and orange prop, the burst,
   the sparkles and the sweat drops keep their colours. The headbands, towels
   and the football's white panels are the belly's warm white and take the
   same move; pure white highlights and the water bottle's pale blue keep
   theirs. ChatGPT also drew an opaque warm grey ellipse under every pose. No
   shipped pose has one, and on a dark card it shows as a grey slab, so it
   goes transparent, and the edges it blended with (feet, mats, tyres, the
   bag) are unmixed so they keep a clean outline.
2. Cut (`cut_poses.py --sheet sport`), with the first sheet's rules. Every
   prop touches its pose (punch bag, rope, mats, bike, treadmill, gym bag)
   and every effect lands on its own pose by grouping, so nothing is placed
   by hand.
3. Upscale (`upscale_poses.py --sheet sport`): the same model, clamp and
   alpha clean-up, app copies in their own folder. This sheet's size drifts
   inside its rows as much as between them (the jogger is drawn about a
   sixth bigger than the sit-ups beside it, the bike and the treadmill about
   a fifth smaller than the rest of their row), so each pose is measured on
   its own, by its face and its leaves, and falls into one of five size
   classes: 2.60, 2.85, 3.05, 3.25 and 3.65 app px per sheet px. In
   `poses-sport.json`, `row` is that class and `sheet_row` the row the pose
   sits in; how each was measured is in upscale_poses.py. Every app copy
   measures 0.95 to 1.03 of the shipped poses' median, so show them with the
   same shared scale as the rest.
4. See-through faces (`fix_poses_sport.py`). The racket's strings and the
   bike's spokes are drawn 1 to 2 px wide and see-through, and the model
   drew them as strokes of its own: the strings came out wavy and broken,
   some spokes went missing and one became a wide see-through fan. This step
   upscales the tennis and cycling poses again, with a plain Lanczos
   enlargement (smoothed, then sharpened) inside the racket's face and the
   two wheels, and keeps the model's pixels byte for byte elsewhere.
   Averaged back to the sheet's size, the strings and spokes now follow the
   sheet (correlation 0.993 and 0.986, where the model gave 0.952 and
   0.955).

None of the 15 repeats a shipped pose; two come close (noted below).

### The sport poses (`assets/images/mascot/sport/`)

NOT in pubspec.yaml: add a file there, one line per pose, when a screen
draws it. Lossless WebP, 4.1 MB for all 15 (182 to 392 KB each).

| File | Sheet # | Pose | Size |
| --- | --- | --- | --- |
| `sport_dumbbells.webp` | 1 | lifting two dumbbells, white headband, orange lines | 736x806 |
| `sport_jogging.webp` | 2 | jogging in a white headband, winking, two sweat drops, motion lines (close to `mascot_running`) | 707x837 |
| `sport_jump_rope.webp` | 3 | jumping rope, eyes shut, laughing, motion lines | 873x861 |
| `sport_sit_ups.webp` | 4 | doing sit-ups on a blue mat, hands behind the head, eyes squeezed shut, two sweat drops, motion lines | 795x787 |
| `sport_water_bottle.webp` | 5 | drinking from a water bottle, towel round the neck, eyes shut, three sweat drops | 676x850 |
| `sport_mat_rest.webp` | 6 | sitting on a blue mat, eyes shut, hands folded, smiling (close to `mascot_calm`) | 761x771 |
| `sport_plank.webp` | 7 | holding a low plank, eyes squeezed shut, small open mouth, two sweat drops | 783x691 |
| `sport_boxing.webp` | 8 | boxing gloves, punching a red bag on a chain, yellow burst, motion lines | 1096x899 |
| `sport_football.webp` | 9 | kicking a football in a navy kit, orange lines, motion lines | 752x780 |
| `sport_basketball.webp` | 10 | running with a basketball held at one side, red kit, motion lines | 727x759 |
| `sport_tennis.webp` | 11 | swinging a tennis racket at a ball, white headband, eyes shut, laughing, motion lines | 912x838 |
| `sport_cycling.webp` | 12 | riding a bike in a black helmet, motion lines | 895x1017 |
| `sport_barbell.webp` | 13 | lifting a red barbell overhead, eyes squeezed shut, smiling, orange lines | 1074x817 |
| `sport_treadmill.webp` | 14 | running on a treadmill, two sweat drops, motion lines | 957x1021 |
| `sport_gym_bag_shaker.webp` | 15 | sitting by a gym bag with a towel, winking, holding a protein shaker, two gold sparkles | 833x792 |

Before placing one:

- `sport_water_bottle` and `sport_gym_bag_shaker` drink: never on a fasting
  habit or during Ramadan's day.
- `sport_mat_rest` sits with its eyes shut and hands folded, which reads as
  meditation: keep it for rest and cool-down, away from worship moments
  (never in tasbih or prayer times).
- `sport_jogging`, `sport_water_bottle` and `sport_treadmill` sweat, and
  `sport_sit_ups` and `sport_plank` squeeze their eyes and sweat (the plank
  with a small worried mouth): fine for a workout under way or done, never
  for a missed day, a streak at risk or a reminder. Doum never looks sad at
  the reader, and reminders never press or blame.
- `sport_boxing`'s chain ends in the air above the bag: place it where the
  chain meets a card's top edge, or keep it small.
- The dumbbells, the bike and its helmet, the treadmill and the gym bag are
  near black with a dark outline, so on a dark card their edge fades, and
  the tennis racket's strings are drawn see-through, so its face reads dark
  there. Test these on the dark theme.

Rebuilding: `recolor_sheet_sport.py`, then `cut_poses.py --sheet sport`,
then `upscale_poses.py --sheet sport`, then `fix_poses_sport.py`. Run the
fix after every upscale of this sheet, or of the tennis or cycling pose
alone: the upscale by itself brings the wavy strings back. Checked
2026-09-30: the first two steps reproduce `sheet-sport-final.png` and all 15
native poses byte for byte, the upscale and the fix each reproduce their
masters and app copies byte for byte, and the first two sheets still cut
byte for byte (sheet 2's idea pose differs by design: fix_poses_2.py
rebuilds it after the cut).

## The streak sheet (2026-09-30)

Aziz generated this sheet with ChatGPT on 2026-09-29: Doum and a streak
whose flame is dying. Its files are in `sheet-streak/`:

- `sheet-streak-original.png` (1536x1024, byte-identical to the download
  "ChatGPT Image 29 سبتمبر 2026، 09_51_26 م.png"): 15 poses in three rows of
  five, on a transparent background.
- `sheet-streak-final.png`: the same sheet with its paint matched to the
  palette and two touching poses parted. The poses are cut from this one.
- `poses-native/`: the 15 poses at the sheet's own size (271 to 375 px wide,
  1.4 MB), without the cream ground the sheet drew under them. `poses-4x/`:
  the 4x masters (1084 to 1500 px wide, 9.6 MB), not bundled.

What was done, in the same three steps as the other sheets, plus one fix:

1. Colour (`recolor_sheet_streak.py`). The body came out lighter than the
   palette: L 0.806 C 0.133 h 143.1 on the interior. Every pixel of green
   paint moves by the difference, keeping its shading, and the body lands at
   L 0.762 C 0.140 h 145.2 (the shipped app copies measure 0.759, 0.140,
   145.0). The hue window is narrow (full within 12 degrees, none past 25),
   so no flame, ember or prop turns green. The big leaf the shelter pose
   holds is green paint of a prop: it moves with the body and keeps the step
   the generator drew below it. Left alone, its lit half would sit at the
   new body's lightness and read as part of him. The cheeks were drawn at
   the body's own lightness and move by its step. Leaves, belly, outline,
   fire, smoke, sweat drops and props are left alone. The poking pose's
   shadow touched the lying scribble pose's arm; 19 faint pixels go to the
   alpha floor so the two cut apart.
2. Cut (`cut_poses.py --sheet streak`), with nothing given by hand: every
   effect lands on its own pose. Then `fix_poses_streak.py`, which does two
   things. First, ChatGPT stood every pose, the coal piles and the calendar
   on a flat cream ellipse at nearly full opacity: a light patch on a dark
   card, which no shipped pose has. The step cuts all 15 again from the
   sheet without it. It rebuilds each outline's lower edge from the ink
   drawn against the cream, so feet, coal piles and the calendar's base end
   in a clean dark edge, and it keeps the watering can's spray. Second, it
   keeps the outline's ink where ChatGPT drew it below full alpha: beside
   the fires, at the stick's end and at the bubble's tail. The shared cut
   gives such pixels the colour of the nearest solid pixel, which there is
   the firelight, the wood, the bubble's inside or the body. That left light
   or green breaks in the outline of five poses (52 pixels), and those
   pixels get their own ink back. The step is safe to rerun.
3. Upscale (`upscale_poses.py --sheet streak`): the same model, clamp and
   alpha cleanup. This sheet draws a smaller face on the same body, so each
   pose is matched to the shipped app copies by its silhouette (leaf span,
   leaf area, green area), with the face as a check, and settled by eye. The
   drawing size drifts inside the rows as much as between them: the
   calendar pose is drawn about a fifth smaller than its row mates. So, as
   with the sport sheet, `row` in `poses-streak.json` is a size class and
   `sheet_row` the row the pose sits in. The classes are 2.45, 2.68 and 2.88
   app px per sheet px, and every pose is within 5% of its own measure. Show
   them with the same shared scale as the rest.

None of the 15 repeats a shipped pose.

### The streak poses (`assets/images/mascot/streak/`)

NOT in pubspec.yaml: add a file there, one line per pose, when a screen
draws it. Lossless WebP, 3.5 MB for all 15 (211 to 316 KB each).

| File | Sheet # | Pose | Size |
| --- | --- | --- | --- |
| `streak_fire_worried.webp` | 1 | worried, hands at the mouth, beside a small smoking campfire, blue sweat drops | 677x738 |
| `streak_fire_poke.webp` | 2 | worried, poking a small campfire with a stick, a loose flame, red alarm lines | 686x767 |
| `streak_fire_lying_scribble.webp` | 3 | lying on the front, chin on the arms, beside a smoking campfire, a scribble cloud above | 749x660 |
| `streak_phone_alert.webp` | 4 | worried, holding a phone, a speech bubble with a flame and a red alert dot, sweat drops | 845x770 |
| `streak_run_clock.webp` | 5 | running, mouth open, a wall clock beside, motion lines, sweat drops | 935x762 |
| `streak_broken_heart.webp` | 6 | hands at the mouth, a red broken heart above a smoking campfire | 667x722 |
| `streak_fire_blow.webp` | 7 | blowing on a small campfire, blue wind swirls | 690x707 |
| `streak_watering_can.webp` | 8 | worried, pouring a red watering can with a white heart toward a smoking campfire | 650x709 |
| `streak_leaf_shelter.webp` | 9 | sheltering a small campfire under a big green leaf held over the head | 712x759 |
| `streak_calendar_miss.webp` | 10 | startled, beside a desk calendar showing a flame and a red X, orange alarm lines | 1058x799 |
| `streak_fire_lying.webp` | 11 | lying flat on the front, chin on the arms, eyes low, beside a smoking campfire, no cloud | 799x641 |
| `streak_hourglass.webp` | 12 | worried, holding an hourglass, orange alarm lines | 781x762 |
| `streak_fire_scribble.webp` | 13 | hands at the mouth, a scribble cloud above, beside a smoking campfire | 755x751 |
| `streak_reach_flame.webp` | 14 | reaching toward a small floating flame, embers, motion lines | 841x768 |
| `streak_chase_flame.webp` | 15 | running after a small floating flame, embers, sweat drops, motion lines | 968x767 |

Before placing one:

- Every pose here is worried, startled or low, and four sweat. The app's
  rule is that Doum never looks sad at the reader and reminders never press
  or blame. None of them belongs in a reminder, in a notification, on a
  missed day or after a streak ends. Each pose's caution is in
  `poses-streak.json`.
- The caring ones (poke, blow, watering can, leaf shelter) suit keeping a
  streak going, not losing one. The watering can aims water at the fire,
  which can read as putting it out.
- `streak_calendar_miss`'s red X marks a missed day. Outside rooms an open
  day is never a miss, and neither is a rest or paused day.
- `streak_run_clock`, `streak_hourglass` and `streak_chase_flame` read as
  time running out: never use them to hurry the reader. `mascot_running` is
  the calm "let's go".
- `streak_phone_alert`'s bubble looks like a streak alert, and Doum never
  appears in notifications.
- The two lying poses are one drawing: `streak_fire_lying_scribble` carries
  the scribble cloud, `streak_fire_lying` has none.
- The scribble clouds (`streak_fire_lying_scribble`, `streak_fire_scribble`)
  and the motion lines are dark grey and fade on a dark card: test on the
  dark theme.

Rebuilding: `recolor_sheet_streak.py`, then `cut_poses.py --sheet streak`,
then `fix_poses_streak.py`, then `upscale_poses.py --sheet streak`. Checked
2026-09-30: run in that order from the original, the four steps wrote every
file in `sheet-streak/` and `assets/images/mascot/streak/`, and a rerun of
the fix reproduces the native poses byte for byte. The first sheet's cut
still reproduces all 18 poses byte for byte, and the second sheet's 23 of
24; `mascot_idea` differs because `fix_poses_2.py` rebuilds it after the cut.

## The ghutra sheet: Doum in a bisht (2026-09-30)

Aziz generated this ChatGPT sheet on 2026-09-29. Its poses join the winter
set, live beside the three winter pictures in `assets/images/mascot/winter/`
and are named `winter_bisht_` (see also `winter/README.md`). The files are
in `sheet-ghutra/`:

- `sheet-ghutra-original.png` (1536x1024, byte-identical to the download
  "ChatGPT Image 29 سبتمبر 2026، 09_47_26 م.png"): 12 poses in three rows of
  four. Doum wears a white ghutra, a black agal and a dark navy bisht with
  gold trim and a cream fur collar, by a small campfire. It is RGB on a
  near-white ground (254 254 254), NOT transparent.
- `sheet-ghutra-final.png`: the same sheet made transparent (RGBA), with the
  body green matched. The poses are cut from this one.
- `poses-native/`: the 12 poses at the sheet's own size (361 to 401 px wide,
  1.7 MB). `poses-4x/`: the 4x masters (1444 to 1604 px wide, 12.3 MB), not
  bundled.

The drawing is closer to the winter pictures than to the sheets:

- A costume hides the leaves and the belly.
- The cloth and fur are painted, and firelight falls on the face.
- The outline is thin: about 4 px at app size, against 6 on
  `winter_ghutra_cup` and 7 to 10 on the sheets.
- The cheeks are peach.

Only its outline is sheet-like, as black as the sheets' (L 0.11 to 0.13)
where the winter pictures' is grey. So, as with the winter pictures, the
drawing stays as drawn and only the colour and the size are matched.

What was done:

1. Transparency and colour (`recolor_sheet_ghutra.py`). The ghutra and the
   fur are white on a white ground, so the ground is not keyed by colour.
   The ground is what reaches the sheet's border without crossing the
   drawing's outlines, and everything enclosed stays opaque. Five short
   seals close spots where an outline is too faint to stop it: the ghutra's
   lower edge in the warming-hands and heart poses, and the blowing pose's
   cheek and mitten under the breath streak. Only that outside region is
   matted against the measured ground:
   - Edges are matted as the drawing's colour over the ground just beyond
     them (the firelight, a shadow or bare ground), so an outline keeps its
     colour with no white halo on dark cards.
   - The soft ground shadows stay translucent, as sheets 1 and 2 keep
     theirs. That includes the darker core right under each pose and under
     the logs (67 to 90% opaque), which is warmer and darker than the
     barrier's cut and would otherwise come out as opaque beige crumbs. The
     shadows seat the poses on the ground on a cream card and fade out on a
     dark one.
   - The firelight on the ground stays as a faint warm glow. One flame's
     pale inner tongue, in the hourglass pose, is the glow's own colour. A
     hand-placed box keeps it paint so no see-through slot opens inside that
     flame, and its tip fades into the glow over four rows.
   - Smoke, steam, breath and the wind swirls stay opaque in their own
     colour, with a soft edge.
   - The inside of the dizzy spiral is ground seen through the glyph and
     becomes transparent.

   Then the body green moves onto the palette as `upscale_winter.py` does.
   It measured L 0.811 C 0.131 h 139.8 against #74C878's 0.76 0.14 145, and
   moves by that difference keeping its shading, in a hue window that never
   reaches the fire, the embers, the gold trim or the firelight. The cheeks
   (peach), ghutra, fur, bisht, props and the cold pose's falling leaves are
   untouched.
2. Cut (`cut_poses.py --sheet ghutra`), with the other sheets' rules.
   Grouping places every effect on its own pose. The cold-wind pose's two
   upper leaves (top left and top right) win over the warming-hands pose
   above them by under 4 px, so they are also given by hand.
3. Firelight at the edges (`fix_poses_ghutra.py`). The cut gives every
   semi-transparent pixel within 3 px of an opaque one the nearest opaque
   colour. Beside a fire that turns the glow into a tan line along each
   outline on a cream card. This step cuts again the same way and gives
   those pixels their firelight colour back (4,910 px). The upscale's own
   edge rule still repaints the pixel right against an outline, so the tan
   line halves rather than goes.
4. Upscale (`upscale_poses.py --sheet ghutra`): the same model, clamp and
   alpha cleanup. Doum is matched by face against the app's poses (eye
   spacing and height against front wave and cheer, closed-eye spacing
   against mug, calm, headphones, laugh and confetti) and by the agal
   against `winter_ghutra_cup`'s. The three rows get 2.62, 2.61 and 2.75 app
   px per sheet px; row 3 is drawn about 5% smaller. In row 2 the laughing
   faces draw their eyes wider on the same head. By eye spacing alone the
   heart pose would take 2.45 and the blowing pose 2.75, but beside the
   other poses and the cup that makes their ghutra and bisht visibly
   different sizes. So the row keeps one scale: per pose, agal and face
   together stay within 4.5% of their row's scale in every row. Show them
   with the same shared scale as the rest (`Sprout.sizeOf`), never a shared
   height.

None of the 12 repeats a shipped pose. `winter_bisht_warm_hands` comes close
to `winter_cloak_campfire`, in another outfit.

### The bisht poses (`assets/images/mascot/winter/`)

NOT in pubspec.yaml: add a file there, one line per pose, when a screen
draws it. Lossless WebP, 4.7 MB for all 12 (343 to 449 KB each).

| File | Sheet # | Pose | Size |
| --- | --- | --- | --- |
| `winter_bisht_worried.webp` | 1 | worried, mittens clasped at the chin, beside a small campfire, grey smoke, two blue worry marks | 934x772 |
| `winter_bisht_burning_stick.webp` | 2 | holding a stick whose tip caught fire over the campfire, alarmed, red double exclamation, blue sweat drops | 968x780 |
| `winter_bisht_squeeze_eyes.webp` | 3 | eyes squeezed shut in a frown, both mittens held to the campfire, two grey swirls that read as question marks | 953x728 |
| `winter_bisht_grey_cloud.webp` | 4 | sad, a dark grey cloud overhead, mittens on the ground by a small campfire | 983x759 |
| `winter_bisht_blow_fire.webp` | 5 | eyes shut, blowing on the campfire, a grey breath swirl | 939x713 |
| `winter_bisht_warm_hands.webp` | 6 | warming both mittens at the campfire, startled, gold lines, blue sweat drops (close to `winter_cloak_campfire`) | 959x770 |
| `winter_bisht_happy_heart.webp` | 7 | laughing, eyes shut, a big campfire in front, a pink heart, gold lines | 927x734 |
| `winter_bisht_flame_up.webp` | 8 | laughing, one mitten holding up a big flame, the other arm out, one gold sparkle, gold lines | 990x839 |
| `winter_bisht_hourglass.webp` | 9 | worried, a mitten at the mouth, beside an hourglass and a small campfire, red double exclamation, grey smoke | 1074x794 |
| `winter_bisht_cold_wind.webp` | 10 | worried, wrapped in the fur collar, cold wind with blue swirls and green leaves blowing, a small campfire | 1051x804 |
| `winter_bisht_dizzy_lying.webp` | 11 | lying on the ground, tired and dizzy, a dark spiral overhead, a small campfire, grey smoke | 1069x725 |
| `winter_bisht_flame_hands.webp` | 12 | eyes shut, smiling, a small flame cupped in both mittens, four gold sparkles | 960x806 |

Before placing one:

- Test on the dark theme. The bisht is dark navy with a black outline, so on
  a dark card its edge fades into the background, as `winter_ghutra_cup`'s
  does. The soft shadows and the firelight glow are translucent: on a dark
  card the glow is a faint warm halo around each fire.
- Five poses look worried, sad or tired: `winter_bisht_worried`,
  `winter_bisht_grey_cloud`, `winter_bisht_hourglass`,
  `winter_bisht_cold_wind` and `winter_bisht_dizzy_lying`. The app's rule is
  that Doum never looks sad at the reader. Keep them for cold weather and
  playful moments, never for a missed day, and out of reminders (reminders
  never press or blame). The hourglass also reads as time running out:
  never on a streak at risk.
- `winter_bisht_burning_stick` (alarmed) and `winter_bisht_warm_hands`
  (startled) both have sweat drops: a playful oops or surprise, never a
  streak at risk and never a reminder.
- `winter_bisht_squeeze_eyes` strains with its eyes shut beside two grey
  swirls that read as question marks, so it reads as confused or
  overwhelmed as much as cold. Keep it for cold weather or warming up, never
  as a verdict and never in a reminder.
- `winter_bisht_flame_hands` holds a flame with its eyes shut, which reads
  as calm and devout. Keep it away from worship moments like every other
  pose (never in tasbih or prayer times).
- `winter_bisht_dizzy_lying`'s spiral is dark brown and all but disappears
  on a dark card.
- The three most firelit faces (`winter_bisht_happy_heart`,
  `winter_bisht_flame_up`, `winter_bisht_flame_hands`) come out lighter and
  yellower than the rest (L 0.78 to 0.80 against 0.75 to 0.76), as drawn.
- The leaves never show: the face and cheeks carry the character, as in the
  winter pictures.

Rebuilding: `recolor_sheet_ghutra.py`, then `cut_poses.py --sheet ghutra`,
then `fix_poses_ghutra.py`, then `upscale_poses.py --sheet ghutra`
(`upscale_winter.py` rebuilds only the three winter pictures). Checked
2026-09-30, running from the original:

- The first three steps reproduce the final sheet and all 12 native poses
  byte for byte, and the fix step is stable when run twice.
- The upscale reproduces a pose's master and app copy byte for byte
  (checked on two poses).
- The first sheet's cut still reproduces all 18 poses byte for byte, and the
  second sheet's 23 of 24. `mascot_idea` differs by design: `fix_poses_2.py`
  rebuilds it after the cut.

## Where the sprout lives in the app (built 2026-09-27)

From the design canvas Aziz approved (https://claude.ai/artifact/9pn6TiQQ448663K6WRCJVi).
Code: `lib/features/mascot/` (`Sprout`, `DayCardSprout`, `SproutTurnaround`,
the mood rules in `sprout_mood.dart`).

| Where | Pose | What it does |
| --- | --- | --- |
| Grid day card, beside the ring | wave, three-quarter, happy, laugh, sleeping | Greets once per launch; hops when the day's numbers rise, with praise that fits the habit just done (sprout_praise.dart: a list per category, male and female forms, a general list, no repeats); celebrates at the streak point (80%, «سلسلتك زادت!»: a streak pass, never «يوم كامل») and again at the perfect day, every habit the day asked for («يوم مثالي!» with praise under it); «عليج»، «فيج» forms when the character worn is a woman; laughs when tapped; asleep after 21:00 on a finished day. The ring's gold cup became a check. |
| Empty Grid | pencil | Replaces the icon in a circle. |
| Streak milestone | love heart | Pops in and celebrates with confetti; the flame is now a small mark by the label. |
| Saturday recap (Profile) | checklist | Peeks over the card's top edge, in from the end corner so it never covers the fold arrow or the folded number; taps on its feet reach the fold row. |
| Room finale dialog | love heart | Replaces the gold cup. |
| Welcome back card | walking with the backpack | Walks in, mirrored in Arabic. |
| Evening streak card (Profile) | wink | Replaces the looping flame. Its WORDS belong to the «على المحك» session (Aziz's pick there). |
| Rest-day explainer | sleeping | In the dialog's icon slot. |
| First run offer | side, three-quarter, front | Turns to face the reader, then waves. |
| Empty Rooms | wave | Replaces the grey people icon. |
| Premium, active | love heart | Replaces the verified tick; a plain pop, as the card shows on every visit. |
| Habits widget (small, medium) | happy, sleeping | REMOVED 2026-09-29 (Aziz: "make it without doum for now"); the seal and leaf are back. The two imagesets stay in the widget's catalog for his return. |

Rules the code keeps: it moves when something happens, breathes a few
times and goes still (no endless loop on the home screen); Reduce Motion
drops all movement; it never looks sad at the reader; it never appears in
tasbih, prayer times or notifications.
