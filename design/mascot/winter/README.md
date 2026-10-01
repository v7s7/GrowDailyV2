# Doum in winter

Aziz, 2026-09-29: "I loved this, save it in a winter folder, we will use it
later, cropped and upscaled." Then, after seeing how they differ from the
sheets: "use it, but change the sizes, and upscale to make it high quality
matching the other poses". The drawing stays as drawn (thinner, greyer
outline, softer shading, peach cheeks, leaves hidden under the ghutra and
the hood); only the body colour and the size are matched.

| File | Picture | App copy |
| --- | --- | --- |
| `winter_ghutra_cup` | in a white ghutra and black agal, sunglasses, holding a cup | 805x662 |
| `winter_cloak_campfire` | in a brown fur-lined cloak, warming his hands at a campfire | 949x671 |
| `winter_blanket_heater` | wrapped in a navy blanket beside an electric heater, eyes closed | 958x766 |

- `originals/`: the three 512x512 Canva exports as received (from
  `~/Downloads/new 3 imgs/`, also in `Untitled design.zip`).
- `cropped/`: each cut to the picture plus a 12 px margin, two stray specks
  removed (a dot off the cloak, a dot beside the blanket). The campfire's
  two embers are kept. Colours as received.
- `4x/`: the cropped pictures with the body green matched to #74C878, at
  four times the size, through the same Real-ESRGAN model and clean-up as
  the app's poses. Not bundled.
- App copies: `assets/images/mascot/winter/`, lossless WebP like the other
  poses, with Doum at the same size as every other pose. Show them with the
  same shared scale as the rest (`Sprout.sizeOf`), never a shared height.
  NOT in pubspec.yaml: add a file there when a screen draws it.

Rebuild everything with `python tool/mascot/upscale_winter.py [source]
[weights]`, in the environment `tool/mascot/upscale_poses.py` uses. How the
colour and the sizes were measured is in that script's docstring.

- Colour: the body was L 0.80 to 0.81 and hue 140 to 142; it is moved onto
  the palette keeping its shading (now L 0.76, hue 145, like the sheets).
  The fire, embers and heater bars are left alone.
- Size, in app px per original px: ghutra 2.05, cloak 2.40, blanket 2.55.
  The pictures drew Doum at different sizes; each is scaled by its face.
  The blanket picture's leaves come out about a quarter wider than the
  sheets' leaves, as drawn.

Before placing one:

- The cup keeps the mug's rule: never on a fasting day, in Ramadan or on its
  eve. Ramadan 1448 falls in winter (about February 2027).
- The navy blanket and the dark bisht have no outline of their own, so on a
  dark card their edge fades into the background. Test on the dark theme.
- The leaves only show in `winter_blanket_heater`. In the other two, the face
  and cheeks carry the character.

## Doum in a bisht (2026-09-30)

Twelve more winter poses sit in `assets/images/mascot/winter/` beside these
three, named `winter_bisht_`: Doum in a white ghutra, a black agal and a
dark navy bisht with gold trim and a cream fur collar, by a small campfire.
They come from a ChatGPT sheet Aziz generated on 2026-09-29, not from Canva
pictures, so the sheet pipeline builds them and their source files are in
`../sheet-ghutra/`. `upscale_winter.py` writes only the three pictures
above and leaves them alone.

    python tool/mascot/recolor_sheet_ghutra.py         # -> sheet-ghutra-final.png (transparent)
    python tool/mascot/cut_poses.py --sheet ghutra     # -> sheet-ghutra/poses-native/
    python tool/mascot/fix_poses_ghutra.py             # firelight at the edges
    python tool/mascot/upscale_poses.py --sheet ghutra # -> sheet-ghutra/poses-4x/, the app copies here

Like these three, the drawing stays as drawn (thin outline, painted cloth,
peach cheeks, leaves under the ghutra) and only the body green and the size
are matched, so Doum is the same size as in every other pose. Show them with
the same shared scale (`Sprout.sizeOf`). NOT in pubspec.yaml: add a file
there when a screen draws it.

The pose table, how the colour and sizes were matched, and every caution are
in `../README.md`, section "The ghutra sheet: Doum in a bisht". In short:
test them on the dark theme (the bisht's edge fades there, as the ghutra
cup's does); the worried, sad and tired ones (worried, grey cloud,
hourglass, cold wind, dizzy lying) and the two with sweat drops (burning
stick, warm hands) never go on a missed day or in a reminder; and
`winter_bisht_flame_hands` reads as devout, so it stays away from worship
moments like every other pose.
