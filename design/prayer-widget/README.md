# Prayer countdown widget art

Aziz generated these on 2026-09-23. They are the ORIGINALS, kept at full
resolution and out of the way of both bundles.

They are not shipped from here. `assets/` is Flutter's bundle and a widget
extension cannot read it — a widget is a separate native target with its own
bundle — so the shipped copies live in the widget's own asset catalog:

- `backdrop-original.png` (1733x907) → `ios/GrowDailyWidget/Assets.xcassets/PrayerBackdrop.imageset`
  resized to 1200x628 and saved as JPEG q90: 1.0MB down to 47KB, max
  per-channel error 10/255 on a gradient this soft, which is invisible. JPEG
  rather than PNG because PNG stores a smooth gradient badly (the same image
  as an optimised PNG is 512KB, and palette-quantised 388KB).
- `mosque-original.png` (1254x1254, mostly transparent padding) →
  `ios/GrowDailyWidget/Assets.xcassets/MosqueMark.imageset`
  trimmed to its bounding box and scaled to 385x360, 31KB. Marked
  `template-rendering-intent: template` so the widget tints it rather than
  painting the raw black, which lets one file serve every face.

Regenerate by repeating those two steps; nothing else reads these.
