# GrowDaily — AI Image Generation Prompts

A shared style guide + a set of prompts for generating the app's visual assets (icon, splash, illustrations, badges). Written for a clean, flat, 2D "Apple-vibe" look — think App Store feature graphics, not skeuomorphic game art.

## Status: first batch generated, cropped, and in `assets/images/`

The 7 sheets generated from the prompts below have been split into 17 individual, ready-to-wire files:

| File | Source prompt | Wire into |
|---|---|---|
| `icon_app.png` | #1 App icon | `flutter_launcher_icons` config → generates the full iOS/Android icon set |
| `splash_background.png` | #2 Splash | Native splash screen background (e.g. `flutter_native_splash`) |
| `onboarding_1_start_habit.png` | #3 Onboarding, panel 1 | Onboarding carousel, slide 1 |
| `onboarding_2_track_progress.png` | #3 Onboarding, panel 2 | Onboarding carousel, slide 2 |
| `onboarding_3_streak_momentum.png` | #3 Onboarding, panel 3 | Onboarding carousel, slide 3 |
| `onboarding_4_celebrate_wins.png` | #3 Onboarding, panel 4 | Onboarding carousel, slide 4 |
| `empty_state_no_habits.png` | #4 Empty states, panel 1 | Dashboard empty state ("no habits yet") |
| `empty_state_all_done.png` | #4 Empty states, panel 2 | `_AllDoneBanner` on the dashboard |
| `empty_state_no_achievements.png` | #4 Empty states, panel 3 | Profile achievements section, empty case |
| `category_quran.png` | #6 Category icons | Quran/reading habit category |
| `category_prayer.png` | #6 Category icons | Prayer habit category |
| `category_focus.png` | #6 Category icons | Focus/deep-work habit category |
| `category_sleep.png` | #6 Category icons | Sleep habit category |
| `category_fitness.png` | #6 Category icons | Fitness/movement habit category |
| `category_charity.png` | #6 Category icons | Charity/giving habit category |
| `achievement_celebration_burst.png` | #7 Level-up burst | `AchievementUnlockSheet` / level-up overlay |
| `premium_upgrade_hero.png` | #8 Premium hero | `PremiumScreen` hero banner |

All corner artifacts and stray black frame edges from generation were cleaned up (background color extended into the corners, not just cropped) so every file is a clean rectangle ready to drop into an `Image.asset(...)`. Still outstanding from the prompt list: the 5-tier achievement badge set (#5) hasn't been generated yet.

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
