# Widget art

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
- `backdrop-night-original.png` → the dark appearance of the same imageset
  (`PrayerBackdropNight.jpg`), same treatment.
- `mosque-original.png` (1254x1254, mostly transparent padding) →
  `ios/GrowDailyWidget/Assets.xcassets/MosqueMark.imageset`, cropped to
  the silhouette and scaled to 297x360, 19KB. The "transparent" padding is
  not quite: it carries faint noise (alpha 1 to 22), so a plain bounding-box
  trim keeps most of it. The first copy (385x360) did, and a fifth of its
  height was empty. Re-cut 2026-09-24 by zeroing alpha under 16 before
  cropping, so a face's `MosqueMark(height:)` is the mosque's own height.
  Marked `template-rendering-intent: template` so the widget tints it
  rather than painting the raw black, which lets one file serve every face.

## The prayer widget's skies (wired 2026-09-24)

Made from the brief "the same prompt each time, only the light changes",
one per stretch of the day. Each → `PrayerSky<Name>.imageset`, resized to
1200x628 and saved as JPEG q90 (`sips -s format jpeg -s formatOptions 90
-z 628 1200`), 70-93KB. Which sky shows when, and the colours solved for
each, are in `ios/GrowDailyWidget/PrayerSky.swift`.

- `sky-sunrise-original.png` → `PrayerSkySunrise`, الشروق to الظهر
- `sky-midday-original.png` → `PrayerSkyMidday`, الظهر to العصر
- `sky-afternoon-original.png` → `PrayerSkyAfternoon`, العصر to المغرب
- `sky-night-original.png` → `PrayerSkyNight`, المغرب to الشروق, الفجر
  included (the brief's الفجر sky, indigo to dusty rose, was never made;
  Aziz chose to share the night one)

## Corner marks for the other widgets

Same set as the mosque, one per widget: `corner-habits-original.png` (a
plant in a pot), `corner-tasks-original.png` (a clipboard with a tick),
`corner-rooms-original.png` (two crescents, one slightly ahead).

Regenerate by repeating those steps. If a sky is regenerated, its text
colours must be re-measured and re-solved (see PrayerSky.swift).
