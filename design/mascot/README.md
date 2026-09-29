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
