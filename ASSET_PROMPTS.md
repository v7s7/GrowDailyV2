# GrowDaily — AI Image Generation Prompts

A shared style guide + a set of prompts for generating the app's visual assets (icon, splash, illustrations, badges). Written for a clean, flat, 2D "Apple-vibe" look — think App Store feature graphics, not skeuomorphic game art.

## Status: generated, cropped, and wired into the actual app

The 7 sheets generated from the prompts below were split into 17 files, and 12 of them are now actually referenced from Dart code (not just sitting in `assets/images/` unused):

| File | Source prompt | Wired into | Status |
|---|---|---|---|
| `icon_app.png` | #1 App icon | `flutter_launcher_icons` config in `pubspec.yaml` | ✅ configured — run `dart run flutter_launcher_icons` |
| `splash_background.png` | #2 Splash | `flutter_native_splash` config in `pubspec.yaml` | ✅ configured — run `dart run flutter_native_splash:create` |
| `category_quran.png` | #6 Category icons | `HabitCategory.iconAsset` + `CategoryIcon` widget, used in habit_card.dart, grid_screen.dart (x2), add_habit_sheet.dart | ✅ wired |
| `category_prayer.png` | #6 Category icons | same as above, mapped to `athkar` | ✅ wired |
| `category_focus.png` | #6 Category icons | same as above, mapped to `fasting` (repurposed — see note) | ✅ wired |
| `category_sleep.png` | #6 Category icons | same as above, mapped to `sleep` | ✅ wired |
| `category_fitness.png` | #6 Category icons | same as above, mapped to `fitness` | ✅ wired |
| `category_charity.png` | #6 Category icons | same as above, mapped to `sadaqah` | ✅ wired |
| `premium_upgrade_hero.png` | #8 Premium hero | `PremiumScreen` — illustration banner above the existing hero card | ✅ wired |
| `achievement_celebration_burst.png` | #7 Level-up burst | Profile screen — decorative banner above the achievements header | ✅ wired |
| `empty_state_no_habits.png` | #4 Empty states, panel 1 | `_EmptyHabitsState` on the dashboard | ✅ wired |
| `empty_state_all_done.png` | #4 Empty states, panel 2 | `_AllDoneBanner` on the dashboard | ✅ wired |
| `empty_state_no_achievements.png` | #4 Empty states, panel 3 | — | ⏳ not wired — no "zero achievements unlocked" empty state exists in the achievements grid today; would need new conditional UI, not just a drop-in image swap |
| `onboarding_1_start_habit.png` … `_4_celebrate_wins.png` | #3 Onboarding | — | ⏳ not wired — **there is no onboarding carousel/flow in the app at all** (routes go straight from auth to the grid). These need a new screen built, not just wiring, so they're deliberately left for a follow-up |

**Note on category mapping**: the app's real `HabitCategory` enum is `quran, athkar, fitness, fasting, sadaqah, sleep, custom` — not the `quran/prayer/focus/sleep/fitness/charity` names originally guessed when writing the prompts. Mapped `athkar→category_prayer` and `fasting→category_focus` (hourglass as a "counting down to iftar" metaphor) since those were the closest semantic fits among the 6 generated icons. `custom` has no custom art and still falls back to the original Material star icon — see `CategoryIcon` in `lib/shared/widgets/category_icon.dart`.

Also generated but not part of the original list: `AchievementUnlockSheet`'s celebration already used a superior hand-built physics confetti animation (`VictoryBurstOnMount` in `victory_burst.dart`) — the static burst image would have been a downgrade there, so it was placed on the Profile screen instead, where nothing better already existed.

All corner artifacts and stray black frame edges from generation were cleaned up (background color extended into the corners, not just cropped) so every file is a clean rectangle ready to drop into an `Image.asset(...)`. Still outstanding from the prompt list: the 5-tier achievement badge set (#5) hasn't been generated yet.

### Light/dark mode: what's transparent and what isn't

- **`category_*.png` (6 files)** — fully transparent except the icon glyph itself (the pastel tile background was removed too, not just the outer canvas), so `CategoryIcon` can tint them with `colorBlendMode: BlendMode.srcIn` exactly like a Material `Icon`. Verified clean on both dark and light test backdrops.
- **`icon_app.png`** — intentionally opaque (app icons must never have transparency; iOS/Android apply their own mask).
- **`splash_background.png`** — intentionally opaque. It's the screen backdrop itself, not an overlay, so "transparent background" isn't a meaningful thing to ask of it.
- **The other 9 illustrations** (`onboarding_*`, `empty_state_*`, `achievement_celebration_burst`, `premium_upgrade_hero`) — **tried and reverted.** They have soft radial glows/vignettes and long-shadow gradients baked into the art itself (not just a flat cream canvas), so a color-based cutout leaves a visible grainy halo once placed on a dark background — worse than keeping the cream backing. Every place these are wired in now deliberately wraps them in a fixed cream-colored card (`Color(0xFFFEFAF0)`) regardless of app theme, so they always sit on the backdrop they were designed for. Two real options if you want them fully theme-adaptive later:
  1. Keep the fixed-light-card treatment (what's shipped now) — a legitimate, common pattern.
  2. Regenerate this batch with an explicit prompt addition — *"flat solid background, no vignette, no radial glow, no gradient behind the subject"* — so a future pass cuts out cleanly.

Use these with any image generator that supports multi-panel / sheet output (Midjourney, Ideogram, DALL·E 3, Stable Diffusion + ControlNet grid). Each prompt below is written as one single generation that yields several related assets at once — the "PANEL" divisions are the trick that gets a grid/sheet result instead of one blended image. If your generator only returns one image per panel description, just run each panel line as its own separate prompt.

---

## Shared style block

Paste this at the start of every prompt (or keep as a saved style reference) so all assets feel like one family:

```
STYLE: flat 2D vector illustration, clean minimalist geometric shapes, generous
negative space, soft rounded corners, no outlines or only very thin 1px
outlines, subtle long-shadow or flat-shadow (not 3D bevels), a restrained
palette of 3-5 colors per image, no gradients except very soft subtle ones,
no text baked into the image, no photorealism, no skeuomorphism, no clutter —
Apple App Store / Apple Human Interface Guidelines marketing-art aesthetic,
similar in spirit to Apple's Fitness, Health, and Calm app iconography.
COLOR PALETTE: warm gold (#D4A24C), deep emerald green (#1E7A52), soft cream
background (#FAF6EE), charcoal ink (#2B2B2B), muted terracotta accent
(#C96F4A) — use 2-3 of these per asset, not all five at once.
```

---

## 1. App icon

```
STYLE: [paste shared style block]
Design a single app icon for a habit-tracking app called "GrowDaily" on a
rounded-square canvas, iOS App Store icon proportions (1024x1024, no
transparency, square corners — the OS will mask the rounding).
Subject: a single warm-gold square/tile mid-transformation into a small
sprouting plant, rendered as flat 2D geometric shapes — evokes "coloring your
life, one square at a time." Deep emerald background. No text, no words, no
app name lettering anywhere in the image.
Keep it extremely simple — an app icon is viewed at 40x40px on a phone home
screen, so use one clear silhouette, not a busy scene.
```

## 2. Splash / launch screen

```
STYLE: [paste shared style block]
Design a portrait-orientation (1170x2532, phone screen ratio) splash/launch
screen background. Soft cream background. Center: a small cluster of 3-4 flat
2D square tiles in a loose grid, each a different shade of emerald/gold,
one square mid-fill with a subtle upward-motion sprout icon inside it —
suggesting quiet progress, not a loading spinner. Plenty of empty space top
and bottom for a logotype to be added separately later. No text in the image.
```

## 3. Onboarding illustration set (4 panels, one generation)

```
STYLE: [paste shared style block]
Create ONE image sheet divided into 4 equal square panels arranged in a 2x2
grid, separated by a thin 2px charcoal divider line, cream background overall.
Each panel is a standalone flat 2D icon-illustration on its own subtle
background tint, no panel borders beyond the divider line, no text/labels:

PANEL 1 (top-left, gold tint): an open hand releasing a single small square
tile upward, representing "start your first habit."
PANEL 2 (top-right, emerald tint): a small grid of 7 squares in a row, most
colored green, one still gray/empty, representing "a week of streaks."
PANEL 3 (bottom-left, terracotta tint): a small flame/torch made of simple
geometric shapes sitting on top of a stacked set of squares, representing
"streaks build momentum."
PANEL 4 (bottom-right, gold tint): a small trophy or badge shape made of
soft rounded geometric forms with a subtle sparkle, representing
"celebrate your wins."
```

## 4. Empty-state illustrations (3 panels, one generation)

```
STYLE: [paste shared style block]
Create ONE image sheet divided into 3 equal panels side by side (horizontal
strip), separated by thin 2px charcoal divider lines, cream background.
No text/labels in the image itself:

PANEL 1: a single empty outlined square tile floating alone in soft
negative space, gentle dashed outline, representing "no habits added yet" —
calm and inviting, not sad.
PANEL 2: a fully colored-in grid of small green squares arranged in a neat
block, with 2-3 small confetti-like geometric shapes drifting above it,
representing "all done for today."
PANEL 3: a simple closed trophy-case or empty shelf shape made of flat
geometric forms, representing "no achievements unlocked yet" — inviting,
not empty/sad in tone.
```

## 5. Achievement badge set — by rarity tier (5 panels, one generation)

```
STYLE: [paste shared style block]
Create ONE image sheet with 5 badge icons arranged in a horizontal row,
evenly spaced with generous padding between them, cream background, no
panel dividers needed since each badge is a self-contained circular/hexagonal
medallion shape. No text/numbers on the badges themselves. Each badge shares
the same simple geometric medallion silhouette (a rounded hexagon or circle)
but with different material/finish and a subtle corresponding glow, from
left to right, increasing in richness:

1. COMMON — plain matte gray-cream medallion, flat, minimal detail.
2. UNCOMMON — soft sage-green medallion with a very subtle sheen.
3. RARE — cool blue-teal medallion with a faint soft glow.
4. EPIC — deep purple medallion with a slightly stronger soft glow and one
   small geometric star accent.
5. LEGENDARY — warm gold medallion with a gentle radiant glow and two small
   geometric star/sparkle accents.

Keep every badge flat 2D, no 3D bevels or embossing — the "richness" should
come only from color and a soft flat glow, matching Apple's flat-badge style
(like Apple Fitness+ award badges), not game-y metallic renders.
```

## 6. Habit-category icon set (6 panels, one generation)

```
STYLE: [paste shared style block]
Create ONE image sheet: 6 small flat 2D icons arranged in a single row with
even spacing, each icon inside its own softly rounded square tile of a
slightly different pastel tint, cream page background, no dividers needed
(the tile edges are the separation), no text/labels:

1. Quran / reading — an open book, minimal geometric form.
2. Prayer — simple praying-hands or prayer-mat silhouette, abstracted to
   basic geometric shapes, respectful and minimal (no facial features, no
   realistic figures).
3. Focus / deep work — a simple hourglass or clock made of soft geometric
   shapes.
4. Sleep — a crescent moon with 1-2 small star shapes.
5. Fitness/movement — a simple abstract running-figure silhouette made of
   rounded geometric blocks (no facial detail).
6. Charity/giving — a simple open-hand-with-heart or gift-box shape,
   abstracted, minimal.

Every icon should read clearly at 24x24px size — single bold silhouette,
no fine detail that would disappear when scaled down.
```

## 7. Level-up / celebration burst illustration

```
STYLE: [paste shared style block]
Design a single square illustration (1024x1024) of a joyful but restrained
celebration moment: a small cluster of flat 2D confetti shapes (simple
triangles, small squares, thin ribbon curls) in gold/emerald/terracotta,
bursting outward from a small central rounded-square badge shape. Cream
background. No text, no numbers, no characters/figures — the celebration
should read through shape and color alone, calm-app energy rather than
loud game-app energy.
```

## 8. Premium / upgrade screen hero illustration

```
STYLE: [paste shared style block]
Design a single wide illustration (1600x900) for a "Premium" upsell screen.
Subject: a small stack of flat 2D square tiles growing progressively larger
left to right, the tallest/rightmost tile rendered in gold with a subtle
soft glow and one small geometric star accent above it, suggesting "unlock
more growth." Soft cream background, plenty of breathing room, no text,
no lock icons, no coins/currency imagery (keep it aspirational, not
transactional-looking).
```

---

### Notes on using these

- Generate each prompt at 2-4x the final display size and downscale — flat
  vector styles alias badly if generated at exact target resolution.
- If a generator ignores the "no text" instruction, add `, textless` and
  `--no text, no words, no letters` (Midjourney) or an explicit negative
  prompt field (Stable Diffusion/Ideogram).
- Once you've picked a winning app-icon image, it still needs to be resized
  into the full iOS/Android icon set (20+ sizes) — tools like
  `flutter_launcher_icons` (add as a dev dependency) can generate the full
  set from one 1024x1024 source PNG automatically.
