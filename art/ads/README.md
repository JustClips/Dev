# Ad thumbnails

Sponsored-ad / experience thumbnails rendered from the game's own models.

| Step | Command | Output |
|---|---|---|
| Build models | `python art/blender/build.py`, `python art/blender/voxpets.py`, `python art/blender/clouds.py` (needs `bpy`) | `art/out/*.glb` |
| Render scenes | `python art/ads/scenes.py OUT [--preview] [scene ...]` | `OUT/<scene>.png`, 1920x1080 (640x360 with `--preview`) |
| Add text and effects | `python3 art/ads/compose.py OUT ADS` | `ADS/<ad>.png/.jpg`, `ADS/notext_*.jpg`, `ADS/contact_sheet.jpg` |

- `kit.py` is the scene kit: imports GLBs as instances, a blocky avatar (`avatar()`, `hold()` for tools),
  leaf carpet, sky, sun, camera. Cycles CPU, about 2 minutes per 1080p scene on 4 cores.
- The props' cartoon outlines are inverted hulls. Cycles has no backface culling, so `split_ink()` moves
  the dark outline faces to a material that is see-through from behind and invisible to shadow rays.
- Leaf_* meshes are untextured in the GLB (the game tints them), so `scenes.tint_leaf()` recolours them.
- Text: Montserrat Black, gradient fill, thick dark outline, hard shadow. Keep it in the top two
  thirds; Roblox draws the title and player count over the bottom of the image.
