# GrowDaily — New Art Generation Guide

Full-code audit of every image, icon, and animation slot in the app. This covers what to generate, exactly what to type into ChatGPT / Nano Banana, and exactly where each file goes. Sections are ordered by value — do Part 1 first.

**How to get the best results:** all of these tools accept an image alongside your text prompt. Where a prompt says "reference:", attach that existing file from `assets/images/` before generating — it anchors the style far better than text alone, since these prompts can't literally show the model your art.

---

## Shared style guide (applies to every prompt below)

Flat vector illustration, cel-shaded (soft single-direction gradient shading for volume, not fully flat, not photorealistic, no textures/grain). Clean vector edges, no sketchy/hand-drawn linework. Soft subtle drop shadow is fine *within* the subject (e.g. under a fold of cloth) but the canvas background itself must be transparent — no baked-in background color, scene, or floor.

Core palette to pull from (hex, use as accents/reference — not every image needs all of them):
- Gold/amber: `#E4B45F` (primary accent), `#9C7436` (dim)
- Emerald green: `#2ECF8F` (primary), `#188A61` (dim)
- Warm cream (text/paper tones only, never as a background fill): `#FEFAF0`

Output format: PNG, RGBA (transparent background), no watermark, no text/lettering anywhere in the image.

---

## Part 1 — Accessory shop expansion (highest value, clearest gap)

The shop has 6 accessory categories. Two (Prayer Beads/misbah, Umbrella) have 3 color variants each — real choice. The other four (Frame, Badge, Lantern, Notebook) have exactly **one** item each, so there's nothing to actually shop for. Adding 2 more per category brings all 6 up to the same 3-item shape. I picked colors/rarities that fill the *cheap* end of each category, since the existing single item in each of these four is already the expensive top-tier one.

Each accessory renders in a specific spot on the character (I read the exact placement code, `character_avatar.dart`, to get this right):

### Frame — renders as a hollow ring/halo *behind* the character, centered
Composition must be a **hollow arch/ring frame with an open center** (the character shows through the middle) — not a solid rectangle. Roughly square canvas, symmetric, medium border thickness. Reference: `assets/images/accessories/frame_gold.png`.

**1. Silver Frame** — common rarity, ~150 gold
> A decorative circular frame made of brushed silver metal, ornate but restrained engraved geometric Islamic-star pattern along the ring, hollow open center, flat vector illustration with soft cel-shading, gentle highlight along the top edge, transparent background, no text, matching the style of a warm-toned golden version of the same frame shape.

Save as: `assets/images/accessories/frame_silver.png`

**2. Rose Frame** — uncommon rarity, ~300 gold
> A decorative circular frame in warm rose-gold/pink metal with a delicate floral vine engraving along the ring, hollow open center, flat vector illustration with soft cel-shading, gentle highlight, transparent background, no text, same silhouette and proportions as a matching gold-metal version of the same frame.

Save as: `assets/images/accessories/frame_rose.png`

### Badge — renders small (~11% scale) centered on the character's chest
Small circular chest-pin/medallion, front-facing, simple bold silhouette (it renders tiny, so avoid fine detail that won't read at small size). Reference: `assets/images/accessories/badge_knowledge.png`.

**3. Streak Badge** — common rarity, ~120 gold
> A small circular enamel-pin style badge, warm orange and amber colors, a simple bold flame icon at its center, thin gold rim border, flat vector illustration, soft cel-shading, transparent background, no text, bold simple shapes that stay readable at very small size.

Save as: `assets/images/accessories/badge_streak.png`

**4. Community Badge** — uncommon rarity, ~300 gold
> A small circular enamel-pin style badge, blue and gold colors, a simple bold icon of two linked figures/people at its center, thin gold rim border, flat vector illustration, soft cel-shading, transparent background, no text, bold simple shapes that stay readable at very small size.

Save as: `assets/images/accessories/badge_community.png`

### Lantern — held in the character's right hand, grip point at the very top ring
Traditional Middle-Eastern hanging lantern shape, tall and narrow (roughly 240×512 proportions), with a clearly defined ring/hook at the very top of the image (that's the exact pixel point the character's hand grips). Reference: `assets/images/accessories/lantern_gold.png`.

**5. Clay Lantern** — common rarity, ~80 gold
> A small traditional Middle-Eastern hanging lantern made of terracotta/clay with warm amber glass panels, simple geometric cut-outs, a metal ring at the very top for hanging, flat vector illustration, soft cel-shading, warm earthy orange-brown tones, transparent background, no text, tall narrow composition.

Save as: `assets/images/accessories/lantern_clay.png`

**6. Silver Lantern** — uncommon rarity, ~280 gold
> A small traditional Middle-Eastern hanging lantern made of brushed silver metal with pale blue-white glass panels, fine filigree cut-outs, a metal ring at the very top for hanging, flat vector illustration, soft cel-shading, cool silver tones, transparent background, no text, tall narrow composition.

Save as: `assets/images/accessories/lantern_silver.png`

### Notebook — held in the character's right hand
Small closed or slightly-angled notebook/journal with a clearly defined spine or page-edge on one side (roughly 350×512 proportions). Reference: `assets/images/accessories/notebook_teal.png`.

**7. Kraft Notebook** — common rarity, ~100 gold
> A small closed notebook/journal with a plain kraft-paper brown cover, simple twine tie closure, slightly worn/soft corners, flat vector illustration, soft cel-shading, warm neutral brown tone, transparent background, no text, held at a slight three-quarter angle showing the spine edge.

Save as: `assets/images/accessories/notebook_kraft.png`

**8. Rose Notebook** — uncommon rarity, ~350 gold
> A small closed notebook/journal with a dusty rose-pink fabric cover, delicate gold foil corner detailing, ribbon bookmark, flat vector illustration, soft cel-shading, transparent background, no text, held at a slight three-quarter angle showing the spine edge.

Save as: `assets/images/accessories/notebook_rose.png`

**After you drop these 8 files in:** tell me and I'll wire the new `Accessory` catalog entries into `accessory.dart` (name, rarity, price, category) — the code side is quick once the art exists.

---

## Part 2 — Missing empty-state illustrations

The Dashboard already has nice custom illustrations for "no habits yet" and "all done today." Two other screens fall back to a bare Material icon or plain text instead — worth matching the same treatment for visual consistency across the app.

**9. Insights empty state** — currently just plain text ("come back once you have more data"), no visual at all.
> A minimal flat vector illustration of a simple line-chart/graph icon drawn as a soft dashed outline, an hourglass or small clock accent nearby suggesting "still gathering data", warm amber/gold color on the line work, generous empty negative space around it, flat vector illustration, soft cel-shading, transparent background, no text, square canvas, calm and unhurried mood rather than alarming or empty-feeling.

Save as: `assets/images/empty_state_no_insights.png` — I'll wire it into `insights_screen.dart`'s empty state once it exists.

**10. Rooms empty state** — currently a plain gray Material icon (`Icons.groups_rounded`).
> A minimal flat vector illustration of two small speech-bubble or figure shapes side by side, warm and inviting, suggesting "invite a friend", gold and soft emerald accent colors, generous empty negative space around it, flat vector illustration, soft cel-shading, transparent background, no text, square canvas.

Save as: `assets/images/empty_state_no_rooms.png` — I'll wire it into `rooms_hub_screen.dart`'s `_EmptyRooms` widget once it exists.

---

## Part 3 — Optional / lower priority

**11. Premium screen hero** (optional). There used to be one here (`premium_upgrade_hero.png`) — it was deliberately removed earlier because it didn't accurately depict what Premium actually unlocks. The current icon+text benefits list works fine on its own, so only do this if you want the visual flourish back. If you do, it needs to depict the *real* benefits (unlimited habits, extended history, insights, extra color themes, voice notes) rather than a generic "growth" image:
> A flat vector illustration showing four small rounded-square cards fanned out, each with a different simple icon on it (a grid icon, a chart icon, a paint-palette icon, a microphone icon), warm gold and cream tones, a small sparkle accent above the tallest card, flat vector illustration, soft cel-shading, transparent background, no text, wide horizontal composition.

Save as: `assets/images/premium_upgrade_hero.png` — tell me once it exists and I'll re-add the `Image.asset` call to `premium_screen.dart`.

---

## Do NOT regenerate these — here's why

- **The 4 onboarding images** (`onboarding_1..4`, currently unused dead files). The onboarding screen was deliberately rebuilt to use small live Flutter mockups instead of static images — they inherit the real theme colors automatically and never go stale against a redesigned screen. Bringing back static PNGs here would reintroduce the exact "doesn't match the theme" bug I just fixed elsewhere. Recommend deleting these 4 files, not replacing them.
- **App icon and splash screen** — intentionally fixed brand marks. Both render before Flutter (and your saved theme) has even loaded, so they can't be theme-aware regardless. Only regenerate these if you want a genuine brand refresh, which is a separate decision.
- **Category icons** (`category_*.png`) — already exist, already dynamically recolor to match whichever theme/preset is active. No gap here.
- **Achievement medals** — rendered in code (gradient + shimmer animation per tier), not images. A static PNG medal would be a downgrade — it'd lose the per-tier color, the shimmer, and the progress ring.

---

## On animations

I checked: the `lottie` package is installed and `assets/lottie/` exists in the project, but it's empty and nothing in the code actually uses it — leftover scaffolding, never followed through on. Worth knowing before you spend time on this: **ChatGPT and Nano Banana only generate static PNGs, not Lottie files** (Lottie is vector animation data, a completely different format — not something an image generator can produce). If you want to actually use that installed package, the practical path is downloading free, ready-made animations from lottiefiles.com rather than generating them — search terms like "confetti burst," "trophy shine," or "checkmark success" would fit the celebration moments this app already has. Current celebrations (level-up, achievement unlock, perfect day) are hand-coded particle effects, not images, and already adapt to your theme colors correctly — so this isn't a gap that needs fixing, just an unused package if you ever want to add to it.
