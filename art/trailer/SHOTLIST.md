# Sweep the World — cinematic trailer (v1)

Not for upload. Dev asked to see it first (2026-11-02).

## What the research says (and how this trailer follows it)
- Hook in the first 3-5 s, gameplay right away, no logo intro. Many viewers watch the start muted, so
  the first shot must read without sound.
- 30-60 s total. Shots 1-4 s. Fast open, short breather, ramp to a big finish.
- Cut on the music beat; biggest moments (hatch reveal, Cosmic burst) land on the drops.
- Show the core loop (sweep -> cash -> upgrade -> hatch -> pets earn) and escalate it.
- Short punchy text supers (2-3 words), logo + PLAY NOW only at the end.

Music: 120 BPM, so 1 beat = 0.5 s = 15 frames at 30 fps, 1 bar = 2 s.

## Render spec (Blender, Dev's PC)
- 1920x1080, 30 fps, EEVEE (bloom/glare on, soft shadows, AO), AgX or Standard view, bright cartoon look
  matching the ads in /ads/2026-11-02 (Roblox Studio "Future lighting" feel, saturated, sunny).
- Characters: classic Roblox R6 bacon-hair avatar (blocky R6 body, brown bacon hair, simple smile face,
  blue shirt, green pants). Dev dislikes custom faces.
- Use the game's real models from art/out (build with art/blender/*.py), scene kit art/ads/kit.py + scenes.py.
- Every shot: real camera motion (dolly, orbit, push-in, handheld-ish shake on impacts), motion blur on,
  shallow DOF on close-ups. Render each shot with 0.5 s extra at each end (handles), NO text in renders.
- Output per shot: `art/trailer/renders/Sxx_name.mp4` (H.264, CRF 16, yuv420p, 30 fps).

## Shots (length without handles)
| # | Len | Shot | Notes |
|---|---|---|---|
| S01 | 3.0 s | HOOK: ground-level close-up, avatar with leaf blower blasts a giant autumn leaf pile, leaves fly at the lens, cash coins burst out | most exciting image first |
| S02 | 4.0 s | BEFORE/AFTER: high drone dolly over a base buried in leaves; a clean line sweeps across left->right, behind it is clean green grass | leaves vanish by x position (animate) |
| S03 | 3.0 s | Top-down drone follows avatar with broom carving a clean path through thick leaves | |
| S04 | 2.0 s | Close-up: coins pop out of a cleared pile and fly/magnet into the player | |
| S05 | 4.0 s | TOOL LADDER: 4 x 1 s hero shots, avatar holding broom, rake, blower, vacuum, slight orbit each | handtools.py tiers |
| S06 | 3.0 s | Low tracking shot, sweeper car drives through a leaf field, brushes spinning, leaves spray | cars.py |
| S07 | 2.0 s | Egg on the pet park pad grows from small to full, sparkles | eggs.py |
| S08 | 5.0 s | HATCH: egg floats up, wobbles, cracks, bursts (hatch_vfx meshes: ring, swirl, star, brick shards), Legendary pet (Dragon) revealed; camera slow push | burst at exactly 3.0 s into the shot |
| S09 | 2.0 s | Pet hero turntable: Phoenix with flame aura, low angle | |
| S10 | 3.0 s | PET ARMY: avatar walks toward camera with 8-10 voxel pets following, low angle | |
| S11 | 3.0 s | Base earning: pets sitting on the base, coins rising from each pet | |
| S12 | 6.0 s | ZONES: 4 x 1.5 s wide drone shots: Park (fountain), Beach, City, Snowy Peaks | park/beach/city/snowpeaks.py |
| S13 | 4.0 s | CLIMAX: Cosmic hatch (AutumnStag), world dims, bigger burst, cosmic pet glow | burst at 2.0 s |
| S14 | 5.0 s | END: sunset hero wide, avatar + pets on a clean hill, slow pull back; leave the upper middle empty for the logo | |

Total ~49 s. Edit, text supers, cash/combo numbers, music and SFX are done afterwards in the edit.
