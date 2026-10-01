# Doum's poses: what to use where

Every drawing of Doum the app has, what he is doing in it, where it is
drawn today, where it fits, and what to watch for. Read this before
placing Doum anywhere. How the pictures were made is in `README.md`
beside this file; the placement plan with phone mockups is the canvas
"Where Doum lives" (https://claude.ai/artifact/JeSUWfh7ZbH8hWwt7GHV32).

Last updated 2026-10-01: 130 poses, 45 wired into the app.

## Using a pose

- **Files.** `assets/images/mascot/<folder>/<name>.webp`, lossless WebP
  with a transparent ground. Every file draws the character at ONE shared
  scale, so draw them with one scale, never one shared height:
  `Sprout(pose: SproutPose.x, height: h)` sizes every pose from the front
  pose's height (`Sprout.sizeOf`, `sproutScaleFor`).
- **Wiring a pose that is not in the app yet.** Add a value to the
  `SproutPose` enum in `lib/features/mascot/sprout.dart` with its file
  path under `assets/images/mascot/` (without `.webp`) and the file's
  pixel width and height, and add the file to `pubspec.yaml`, one line per
  file. `test/features/mascot/sprout_assets_test.dart` fails unless the
  enum and pubspec list the same files. Only wire what a screen draws.
- **Motion.** `SproutEntrance` (none, pop, popAndCelebrate, walkIn), a
  `SproutController` for `hop()` and `celebrate()`, `idleBreaths` (a few,
  then still), `mirror` for Arabic when he walks somewhere, a speech
  bubble (`SproutBubble`). Reduce Motion drops every movement.

## Rules for every placement

1. He reacts to something the person just did, then rests. Nothing loops
   for ever, and he never blocks the button someone came for.
2. Never sad, worried or hurried at the reader: not on a missed day, a
   lost streak, an error or in any reminder. The streak sheet and the
   worried bisht poses are for stories the person starts, never for a
   miss. The one exception Aziz picked is `streak_leaf_shelter` on the
   evening streak banner.
3. Never in the tasbih counter, prayer times, the prayer widget or any
   notification. Worship praise is a du'a only; no pose holds a Quran,
   prayer beads or a prayer mat, and poses that read as meditation or
   devotion (`calm`, `sport_mat_rest`, `winter_bisht_flame_hands`) stay
   away from worship.
4. Eating or drinking (`mug`, `cookie`, `sport_water_bottle`,
   `sport_gym_bag_shaker`, `winter_ghutra_cup`, `habits_cooking`,
   `ramadan_dates`, `ramadan_maamoul`, `ramadan_dallah`) never on a
   fasting habit, a planned fast day or Ramadan's daytime. The Ramadan
   food is for iftar, suhoor or Eid.
5. No crowns, medals or hero titles beside him (see the no-hero-titles
   rule); a celebration states what happened and what is next.
6. Dark props (phones, treadmill, bike, dumbbells, the doorway's inside)
   fade on a dark card: check the dark theme.
7. The home-screen widgets do not show Doum (Aziz, 2026-09-29). Ask first.

## Folders

| Folder | Sheet | Poses | Wired |
| --- | --- | --- | --- |
| `mascot/` | sheet 1 (09-27) and sheet 2 (09-29) | 37 | 27 |
| `mascot/sport/` | sport (09-30) | 15 | 1 |
| `mascot/streak/` | streak flame (09-30) | 15 | 1 |
| `mascot/winter/` | bisht by the fire (09-30) and 3 winter pictures | 15 | 2 |
| `mascot/moments/` | app moments (10-01) | 12 | 2 |
| `mascot/habits/` | daily habits (10-01) | 12 | 0 |
| `mascot/ramadan/` | Ramadan and Eid (10-01) | 12 | 0 |
| `mascot/language/` | the two language looks, suit and thobe (10-01) | 12 | 12 |

## Sheets 1 and 2 (`mascot/`)

| Pose | Doum is | Drawn today | Fits |
| --- | --- | --- | --- |
| `mascot_front_wave` | facing you, waving | Grid day card (nothing done yet), bottom-bar stand-in, hide dialog, empty Rooms, first run, splash ready moments, the first open's flight to the sign-in screen | greetings, a new week |
| `mascot_three_quarter_wave` | turned a little, waving | Grid day card (day in progress), splash | |
| `mascot_happy_sparkles` | arms up, gold sparkles | Grid day card on a perfect day, splash full day and first open | big wins |
| `mascot_laugh` | laughing, eyes shut | Grid day card when tapped | |
| `mascot_sleeping` | asleep, "zZ" | rest days, night on the Grid, rest-day dialog, splash night | |
| `mascot_love_heart` | hugging a big heart | streak milestone, room finale, Premium active | Premium bought, thanks |
| `mascot_walk_backpack` | walking in with a backpack | comeback card, splash welcome back | |
| `mascot_pencil` | winking, holding a pencil | empty Grid, onboarding slide 1 (on the week row) | Grid medals, journal empty |
| `mascot_checklist` | holding a ticked clipboard | Saturday recap, splash evening | |
| `mascot_idea` | hand up, light bulb | app update dialog, splash update | |
| `mascot_side_right`, `mascot_back`, `mascot_back_three_quarter`, `mascot_side_right_leaf_up` | the turnaround angles | splash turnaround, first run | |
| `mascot_determined` | fists up, frowning with resolve | splash Saturday | Steadiness medals |
| `mascot_cheer` | one arm high, cheering | splash steps goal | Streak medals, first habit |
| `mascot_magnifier` | looking through a magnifier | splash slow load | errors, offline, search |
| `mascot_confetti` | arms up in confetti | splash Eid | Platinum medals, team day won |
| `mascot_thumbs_up` | winking, thumbs up | splash evening | Tasks cleared, comeback claimed |
| `mascot_sunglasses` | sunglasses, arms crossed | splash summer noon | |
| `mascot_mug` | steaming mug, eyes shut | splash morning | rule 4 |
| `mascot_running` | running, sweat drop | splash steps goal | not for a streak at risk |
| `mascot_pointer` | pointing with a stick | splash first open, the first-run question (after his wave) | the app guide, coach marks |
| `mascot_chart` | presenting a rising chart | splash Saturday | Insights empty, recap going up |
| `mascot_wink_jump` | winking, jumping | splash walk ending | Level medals, level up |
| `mascot_wink` | winking and waving | WIRED, drawn nowhere | Get Started finished |
| `mascot_confused` | hand at chin, "?" | WIRED, drawn nowhere | a join code not found (gentle) |
| `mascot_laptop` | sitting with a laptop | no | study and work habits |
| `mascot_reading` | reading a book | no | empty records page, reading habits |
| `mascot_books` | carrying a tall stack of books | no | learning habits |
| `mascot_headphones` | headphones on, eyes shut | no | listening habits |
| `mascot_note` | reading a sheet of paper | no | an empty Tasks day, Night Review history |
| `mascot_megaphone` | calling through a megaphone | no | admin messages, room created |
| `mascot_peek` | peeking from behind a post (the post is drawn) | no | prefer `moments_peek_edge` |
| `mascot_shrug` | arms out, frowning, "?" | no | never after a missed day |
| `mascot_calm` | sitting, eyes shut, hands folded | no | rule 3: mind habits only |
| `mascot_cookie` | eating a cookie | no | rule 4 |

## Sport (`mascot/sport/`)

Habit-matched praise: when a sport habit's square fills, the pose of that
sport. All show effort (some sweat): fine for a workout, never for a miss.

| Pose | Doum is | Fits |
| --- | --- | --- |
| `sport_treadmill` | running on a treadmill | WIRED: splash walk scene (runs, sweats, jumps off) |
| `sport_jogging` | jogging in a headband | walk and run habits, the long-streak medals |
| `sport_football` | kicking a football | football |
| `sport_basketball` | running with a basketball | basketball |
| `sport_tennis` | swinging a racket | tennis, padel |
| `sport_cycling` | on a bike, helmet | cycling (dark bike: rule 6) |
| `sport_dumbbells`, `sport_barbell` | lifting | gym (dark weights: rule 6) |
| `sport_jump_rope` | jumping rope | cardio |
| `sport_plank`, `sport_sit_ups` | core work, straining | core workouts |
| `sport_boxing` | punching a bag on a chain | boxing, martial arts (the chain ends in the air: put it under a card edge or keep it small) |
| `sport_water_bottle` | drinking, towel | water habit, rule 4 |
| `sport_gym_bag_shaker` | gym bag, protein shaker | gym, rule 4 |
| `sport_mat_rest` | sitting on a mat, eyes shut | stretching only, rule 3 |

## Streak flame (`mascot/streak/`)

Every one has a worried face (rule 2).

| Pose | Doum is | Use |
| --- | --- | --- |
| `streak_leaf_shelter` | sheltering a small fire under a big leaf | WIRED: Profile evening streak banner (Aziz's pick) |
| `streak_fire_blow` | blowing on a small fire | maybe: a streak freeze kept the flame alive |
| `streak_reach_flame` | reaching for a floating flame | maybe: day one of a new streak |
| `streak_fire_worried`, `streak_fire_poke`, `streak_fire_scribble`, `streak_fire_lying`, `streak_fire_lying_scribble`, `streak_phone_alert`, `streak_chase_flame` | worried by a smoking fire | none in the app (rule 2) |
| `streak_run_clock`, `streak_hourglass` | hurried by time | no: they hurry the reader |
| `streak_watering_can` | watering a fire | no: water on a fire reads wrong |
| `streak_calendar_miss`, `streak_broken_heart` | a missed day, a broken heart | no |

## Winter (`mascot/winter/`)

Bahrain's winter is December to February. The splash's "missing winter"
scene plays in the other months.

| Pose | Doum is | Use |
| --- | --- | --- |
| `winter_bisht_hourglass` | ghutra and bisht, worried by an hourglass and a small fire | WIRED: splash missing winter (start) |
| `winter_bisht_happy_heart` | laughing by a big fire, a heart | WIRED: splash missing winter (ending) |
| `winter_bisht_flame_up` | laughing, holding up a big flame | winter on the Grid: a perfect day |
| `winter_cloak_campfire` | fur cloak, warming hands at a fire | winter on the Grid: day in progress |
| `winter_blanket_heater` | wrapped in a blanket by a heater | winter on the Grid: night |
| `winter_ghutra_cup` | ghutra, sunglasses, a cup | winter mornings, rule 4 |
| `winter_bisht_blow_fire` | blowing on the fire | the splash's slow-load variant |
| `winter_bisht_flame_hands` | a small flame in his hands, eyes shut | rule 3: never near worship |
| `winter_bisht_worried`, `winter_bisht_warm_hands`, `winter_bisht_squeeze_eyes`, `winter_bisht_burning_stick`, `winter_bisht_cold_wind` | worried, startled or cold | splash stories only (rule 2) |
| `winter_bisht_grey_cloud`, `winter_bisht_dizzy_lying` | sad, dizzy | no |

## App moments (`mascot/moments/`, new 2026-10-01)

| Pose | Doum is | Fits |
| --- | --- | --- |
| `moments_peek_edge` | peeking over a flat edge: head and hands only, cut flat at the bottom | the surprise bonus over the day card, any reveal over a card edge. Always put its flat bottom ON an edge |
| `moments_gift` | holding out a wrapped gift | the surprise bonus, a reward claimed |
| `moments_phone_up` | holding a phone up, curious | offline, looking for signal (with the Wi-Fi mark) |
| `moments_stamp_check` | stamping a green check | WIRED: onboarding slide 2, on «الآن». Also Tasks: the day cleared |
| `moments_clap` | clapping, eyes shut happy | WIRED: onboarding slide 3, on the board. Also a teammate finished, praise |
| `moments_doorway_wave` | waving from an open doorway | room joined, welcome (dark doorway: rule 6) |
| `moments_stairs` | stepping up three blocks | level up |
| `moments_flag_hill` | planting a flag on a hill | Get Started finished, a goal reached |
| `moments_photo_album` | looking through a photo album | Doum's album, the records page |
| `moments_phone_show` | showing his phone's screen | the share card, "share the code" |
| `moments_notebook_lamp` | writing at a table by a lamp | Night Review |
| `moments_wrench` | holding a wrench, toolbox | something went wrong, maintenance |

## Daily habits (`mascot/habits/`, new 2026-10-01)

| Pose | Doum is | Fits |
| --- | --- | --- |
| `habits_swimming` | swimming, goggles, splash | swimming |
| `habits_stretch` | arms up, stretching | stretching, warm-up, waking up |
| `habits_watering_plant` | watering a seedling | gardening; Grow Daily itself (a growing habit) |
| `habits_planting_seed` | planting a seed in a pot | the first habit, a new habit added |
| `habits_phone_basket` | putting his phone in a basket | screen-free time, quit and cut-down habits (dark phone: rule 6) |
| `habits_piggy_bank` | a coin into a piggy bank | saving money |
| `habits_brushing_teeth` | brushing his teeth | hygiene |
| `habits_sweeping` | sweeping, dust puffs | home chores, tidying |
| `habits_cooking` | stirring a pot, apron | cooking (rule 4) |
| `habits_phone_call` | talking on the phone | calling family, keeping in touch |
| `habits_painting` | painting at an easel | art, hobbies, creative habits |
| `habits_bedtime` | sleep cap, hugging a pillow | sleeping early (the cap hides one leaf) |

## Ramadan and Eid (`mascot/ramadan/`, new 2026-10-01)

Ramadan 1448 starts about 8 February 2027. Food and drink: rule 4.

| Pose | Doum is | Fits |
| --- | --- | --- |
| `ramadan_lantern` | holding up a glowing fanous | Ramadan days on the Grid, the splash |
| `ramadan_crescent` | sitting on a golden crescent | the eve of Ramadan, Ramadan nights |
| `ramadan_telescope` | looking through a telescope | moon sighting: the last nights of Sha'ban and Ramadan |
| `ramadan_lights` | hanging festive lights | the days before Eid |
| `ramadan_night_lantern` | sitting by a lantern under the stars | Ramadan nights, after taraweeh time |
| `ramadan_sunset` | waving at the setting sun | iftar time |
| `ramadan_dates` | holding a bowl of dates | iftar only |
| `ramadan_dallah` | carrying Arabic coffee and cups | iftar, Eid visits |
| `ramadan_maamoul` | holding a plate of maamoul | Eid |
| `ramadan_eid_thobe` | in a white thobe, waving | Eid morning |
| `ramadan_envelope` | holding an Eidiya envelope | Eid |
| `ramadan_confetti` | throwing confetti | Eid's celebration |

## The language looks (`mascot/language/`, new 2026-10-01)

WIRED (DoumLanguageLook in lib/features/mascot/doum_language_look.dart):
the sign-in screen's head, where the app icon was, and Settings › Language,
over the two cards. For the language switch only (canvas "Doum picks the
language"). The everyday Doum's front, three-quarter, side and back are the
first half of the turn when the splash's Doum lands on the sign-in screen
and dresses. Each look is drawn at ONE scale across its six poses, and the two
looks match each other, so the spin can swap them mid-turn without a jump.
The turnaround order is front, three-quarter, side, back, as the plain
`SproutTurnaround` uses.

| Pose | Doum is | Fits |
| --- | --- | --- |
| `lang_suit_front_wave` | slate-blue suit and burgundy tie, waving | the English look at rest |
| `lang_suit_three_quarter`, `lang_suit_side`, `lang_suit_back` | the suit's turnaround angles | the spin |
| `lang_suit_bow` | a small bow, hands together, eyes shut smiling | English just picked |
| `lang_suit_jump` | jumping, arms up, gold lines | the landing after the spin |
| `lang_thobe_front_wave` | long thobe, ghutra and agal, leaves hidden, waving | the Arabic look at rest |
| `lang_thobe_three_quarter`, `lang_thobe_side`, `lang_thobe_back` | the thobe's turnaround angles | the spin |
| `lang_thobe_hand_chest` | hand on his chest, eyes shut smiling | Arabic just picked |
| `lang_thobe_jump` | jumping, arms up, gold lines | the landing after the spin |

The thobe poses show no leaves (the ghutra covers them): keep them beside
the suit, in the language moments, where it is clear who he is.

## A habit to a pose (quick lookup)

| Habit | Pose |
| --- | --- |
| football, basketball, tennis or padel, cycling | `sport_football`, `sport_basketball`, `sport_tennis`, `sport_cycling` |
| gym, weights | `sport_dumbbells`, `sport_barbell` |
| walking, running, steps | `sport_jogging`, `sport_treadmill` |
| swimming | `habits_swimming` |
| stretching, waking up | `habits_stretch` |
| reading, learning, study | `mascot_reading`, `mascot_books`, `mascot_laptop` |
| listening (podcasts, lessons) | `mascot_headphones` |
| water | `sport_water_bottle` (rule 4) |
| saving money | `habits_piggy_bank` |
| screen time, quit habits | `habits_phone_basket` |
| family, calls | `habits_phone_call` |
| cleaning | `habits_sweeping` |
| cooking | `habits_cooking` (rule 4) |
| hygiene | `habits_brushing_teeth` |
| art, hobbies | `habits_painting` |
| sleeping early | `habits_bedtime` |
| gardening | `habits_watering_plant` |
| prayer, Quran, dhikr, fasting, sadaqah | his own poses only (wave, happy sparkles, love heart), du'a lines (rule 3) |
