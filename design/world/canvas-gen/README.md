# Canvas generators for "Doum's Planet" (the oasis design canvas)

Every board on https://claude.ai/artifact/8npqUYRC5bucfcFCaRJR21 is built by
these scripts into `project/` (the canvas's own files, `canvas.json` included).
Moved here from the session scratchpad on 2026-10-03 so they survive restarts.

Python: any venv with Pillow, numpy and scipy (torch only for the old upscaler).

## Build

```
python gen_simple.py      # Oasis, Arrange, Friends: the simple version (2026-10-03, start here)
python gen_start.py       # Simple.dc.html: its start board
python gen_island.py      # Island.dc.html: the island component (all others import it or inline it)
python gen_builder2.py    # Builder.dc.html
python gen_together.py    # Neighbours, Show, OasisPremium
python gen_deeper.py      # Edit
python gen_inside.py      # Inside
python gen_walkers.py     # Walk, Play (the walking engine)
python gen_page.py        # PlanetPage (the hub)
python gen_proud.py       # Proud
python gen_tour.py        # Tour (start here)
python gen_rig.py         # Rig (Doum from parts)
python gen_polish.py      # Polish (also rewrites Plan and Deeper via gen_plan)
python gen_board_together.py   # Together
```

`island_core.py` holds the shared island: art ids (`ART_IDS`), item list and
heights (`ITEMS`, `HEIGHTS`), places (`SPOTS`), the JS island renderer with
Doum's sprite engine, and the CSS animations (`STYLE`). Doum's frames come from
`frame_ids.json` and `design/mascot/frames-web/meta.json`. `ENGINE_JS` is the
walking engine every board with a moving Doum shares: `go` (turn, walk, land),
`sitOn` (to the front of a seat, a beat, hop up, sit; any later `go` hops down
first), `doAct`, `doumState`.

## The proposal canvas (for friends)

`python gen_proposal.py` builds "Doum's Oasis: should we build it?"
(https://claude.ai/artifact/CNgeqhi9vJ2Y2GZwc7Ybbw) into `proposal/project/`:
Main (the case and five questions), the click-through phones, Changes (before and
after), Wiring (the diagram), Build (waves, decisions, risks). It reuses the phones
gen_simple.py writes, so run that first. Images live per canvas: `proposal/blob_ids.json`
maps each local file to its copy there; a new image is listed in
`proposal/to_upload.json` until it is uploaded (`asset: true`) and added to the map.
Publish with `root` = `proposal`. `PROJ=proposal/project node check/simulate.js` runs the taps there.

## Check

```
node check/simulate.js                       # runs every interactive board's logic through a tap script
node check/preview2.js project/Walk.dc.html check/out.html '{}' '{"walk":[224,262],"action":"dates"}'
check/shot.sh out.png 400 860 390 844 out.html     # headless Chrome screenshot (run inside check/)
python check/sit_gif.py                      # doum-sits.gif, the sit frame by frame (steps in its docstring)
```

Pass `still="true"` to Oasis in a preview: it stops Doum's life loop.

`check/blobmap.json` maps canvas asset ids to local files so previews show the art.

## Publish

Publish with the Artifact tool: `root` = this folder, `file_path` =
`project/canvas.json`, `files` = the changed `project/*.dc.html`. Re-read the
canvas's `project/canvas.json` first if it may have been edited on the canvas.

The playbook for adding items and animations: `../OASIS_PLAYBOOK.md`.
