# Art pipeline

Everything visual is made by scripts, so it can be rebuilt and tweaked.

| Step | Command | Output |
|---|---|---|
| Models (19 aliens, 7 eggs, 6 tools, 3 vehicles, map props) | `python art/blender/build.py` (needs `bpy`) | `art/out/*.glb` + `art/out/meta.json` |
| Preview renders | `python art/blender/render.py`, `art/blender/sheet.py` | `art/out/renders/` |
| HUD icons (512 px, navy outline) | `python art/blender/icons.py` | `art/out/icons/*.png` |
| Stud texture | `python art/blender/stud.py` | `art/out/ui/Stud.png` |
| Animations (Pet_Idle, Pet_Walk, Pet_Happy, Player_Hold, Player_Sweep) | `python art/anim/build_anims.py` | `art/out/anims/*.rbxmx` |
| Upload to Roblox | `ROBLOXAPIKEY=... python tools/upload_assets.py` | `art/assets.lock.json`, `src/shared/Config/Assets.luau` |

`art/out/` is not committed (only `meta.json`); run the steps above to rebuild it.
The upload step only re-uploads files whose hash changed.

Conventions:

- 1 Blender metre = 1 stud.
- Blender -Y is the model's front: it becomes -Z (LookVector) in Roblox.
- Colours come from a small palette texture per model, so they survive the GLB import.
- The player broom pose and the tool grip are designed together with R15 forward kinematics (`art/anim/r15.py`). After changing the pose in `build_anims.py`, run `python3 art/anim/check_grip.py`: it checks the head stays on the ground and the left hand on the handle, and prints the `GRIP_ROTATION` to paste into `ToolService`.
- Aliens use the part names Body, Head, LegFL/FR/BL/BR, LegL/R, ArmL/R, EarL/R, Tail, WingL/R and Tent1-4. Joints are stored in the meta and rigged at runtime with Motor6Ds (`AssetLibrary.prepare`), so the shared pet animations fit every alien.
- Parts named `*_Glow` turn Neon. `*_Glass` parts turn Glass.
- Logo and shop banners were made with ForgeUI (`art/out/ui/Logo.png`, `Banner*.png`).
