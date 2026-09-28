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
- A new sheet: `recolor_sheet.py`'s coordinates and `cut_poses.py`'s row
  splits belong to this sheet, and a new pose needs an entry in `poses.json`
  with the row whose scale it matches.

The widget's two images (`SproutHappy`, `SproutSleeping` in
`ios/GrowDailyWidget/Assets.xcassets`) are written by step 3 too, from the
app copies at one shared scale; see upscale_poses.py's docstring.

## Where the sprout lives in the app (built 2026-09-27)

From the design canvas Aziz approved (https://claude.ai/artifact/9pn6TiQQ448663K6WRCJVi).
Code: `lib/features/mascot/` (`Sprout`, `DayCardSprout`, `SproutTurnaround`,
the mood rules in `sprout_mood.dart`).

| Where | Pose | What it does |
| --- | --- | --- |
| Grid day card, beside the ring | wave, three-quarter, happy, laugh, sleeping | Greets once per launch; hops when the day's numbers rise; celebrates at the streak point (80%, «يوم كامل!») and again at every square green («يوم مثالي!»); laughs when tapped; asleep after 21:00 on a finished day. The ring's gold cup became a check. |
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
| Habits widget (small, medium) | happy, sleeping | Only in the "nothing left" slot, never beside open habits. |

Rules the code keeps: it moves when something happens, breathes a few
times and goes still (no endless loop on the home screen); Reduce Motion
drops all movement; it never looks sad at the reader; it never appears in
tasbih, prayer times or notifications.
