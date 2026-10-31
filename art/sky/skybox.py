"""Sky gradient skyboxes for the clear-weather sky, one per zone look (Config/SkyLooks).

  python3 art/sky/skybox.py            # writes art/out/ui/Sky_<Look>_<Face>.png + previews

Seam-proof by design: the sky colour depends only on elevation, and every cloud sits
inside one side face, so the six faces line up whatever way Roblox folds or mirrors
them. Up and Dn are pure radial gradients. No sun is painted: the real sun moves with
the day/night cycle.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art", "out", "ui")
N = 1024


def c(*rgb):
    return np.array(rgb, dtype=np.float32) / 255.0


# Sky stops are (elevation in degrees, colour). Clouds: lit, shade, and the far haze rim.
LOOKS = {
    "Clear": {
        "stops": [(-90, c(150, 186, 222)), (0, c(178, 212, 240)), (8, c(150, 196, 238)), (25, c(98, 160, 228)), (60, c(60, 128, 214)), (90, c(48, 114, 206))],
    },
    "CozyAutumn": {
        "stops": [(-90, c(196, 182, 176)), (0, c(226, 206, 188)), (8, c(176, 196, 226)), (25, c(108, 160, 222)), (60, c(68, 128, 208)), (90, c(56, 114, 200))],
    },
    "Tropical": {
        "stops": [(-90, c(140, 200, 220)), (0, c(160, 222, 240)), (8, c(118, 196, 240)), (25, c(64, 160, 236)), (60, c(28, 122, 222)), (90, c(20, 106, 214))],
    },
    "GoldenHour": {
        "stops": [(-90, c(210, 160, 128)), (0, c(240, 188, 140)), (8, c(214, 186, 170)), (25, c(132, 156, 206)), (60, c(84, 120, 196)), (90, c(70, 104, 188))],
    },
    "Frosty": {
        "stops": [(-90, c(180, 196, 220)), (0, c(204, 218, 238)), (8, c(170, 198, 236)), (25, c(118, 162, 224)), (60, c(84, 132, 212)), (90, c(72, 120, 206))],
    },
}

# Painted clouds are off: Roblox's own volumetric Terrain.Clouds draw the clouds (Dev
# wanted real clouds, 2026-10-31). The shapes stay in case a look wants them back.
PAINT_CLOUDS = False

# Puffs per cloud: (dx, dy, r) in units of the cloud's scale, flat bottom at dy=0.
SHAPES = [
    [(-1.6, 0.35, 0.55), (-0.8, 0.6, 0.85), (0.1, 0.85, 1.05), (1.0, 0.6, 0.8), (1.75, 0.35, 0.5)],
    [(-1.2, 0.4, 0.6), (-0.3, 0.75, 0.95), (0.7, 0.55, 0.75), (1.4, 0.3, 0.45)],
    [(-0.9, 0.35, 0.5), (0.0, 0.6, 0.75), (0.8, 0.4, 0.55)],
    [(-2.1, 0.3, 0.45), (-1.3, 0.55, 0.75), (-0.3, 0.9, 1.1), (0.7, 0.7, 0.9), (1.6, 0.45, 0.6), (2.3, 0.25, 0.4)],
]

# Clouds per side face: (shape, centre u, bottom v, scale). v=0 is the horizon.
FACES = {
    "Ft": [(0, -0.3, 0.14, 0.2), (2, 0.55, 0.36, 0.1)],
    "Rt": [(3, 0.0, 0.1, 0.16), (2, -0.62, 0.46, 0.08)],
    "Bk": [(1, 0.25, 0.18, 0.19), (2, -0.55, 0.12, 0.1)],
    "Lf": [(0, 0.08, 0.26, 0.15), (1, -0.58, 0.1, 0.1), (2, 0.62, 0.44, 0.07)],
}


def gradient(elev, stops):
    xs = np.array([s[0] for s in stops], dtype=np.float32)
    out = np.empty(elev.shape + (3,), dtype=np.float32)
    for ch in range(3):
        out[..., ch] = np.interp(elev, xs, [s[1][ch] for s in stops])
    return out


def smooth(edge, x):
    t = np.clip(0.5 - x / edge, 0, 1)
    return t * t * (3 - 2 * t)


def grid():
    t = (np.arange(N, dtype=np.float32) + 0.5) / N * 2 - 1
    u, vdown = np.meshgrid(t, t)
    return u, -vdown


def cloud_sdf(u, v, shape, cu, cv, s, shrink=0.0, shift=(0.0, 0.0)):
    d = np.full(u.shape, 9.0, dtype=np.float32)
    for dx, dy, r in shape:
        px, py = cu + (dx + shift[0]) * s, cv + (dy + shift[1]) * s
        d = np.minimum(d, np.hypot(u - px, v - py) - r * s * (1 - shrink))
    return np.maximum(d, cv - v)  # flat bottom


def side_face(look, clouds):
    u, v = grid()
    elev = np.degrees(np.arctan2(v, np.sqrt(u * u + 1)))
    img = gradient(elev, look["stops"])
    aa = 2.5 / N
    for shape_i, cu, cv, s in clouds:
        shape = SHAPES[shape_i]
        body = cloud_sdf(u, v, shape, cu, cv, s)
        mask = smooth(aa * 2, body)
        # Light from the upper right: the lit part is the cloud pushed that way and shrunk.
        lit_sdf = cloud_sdf(u, v, shape, cu, cv + 0.32 * s, s, shrink=0.06, shift=(0.1, 0.0))
        lit = smooth(aa * 3, lit_sdf)
        col = look["shade"][None, None, :] * (1 - lit[..., None]) + look["lit"][None, None, :] * lit[..., None]
        # Soft warm rim right at the outline.
        rim = np.clip(1 - np.abs(body) / (0.02 * s / 0.12), 0, 1) * 0.35
        col = col * (1 - rim[..., None]) + look["edge"][None, None, :] * rim[..., None]
        a = mask[..., None] * 0.97
        img = img * (1 - a) + col * a
    return img


def cap_face(look, up):
    u, v = grid()
    elev = np.degrees(np.arctan2(1, np.sqrt(u * u + v * v))) * (1 if up else -1)
    return gradient(elev, look["stops"])


def save(arr, path):
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path, optimize=True)


def preview(faces, path):
    # Four side faces in a row, cropped to the band the player sees, with a ground strip.
    strip = np.concatenate([faces[f] for f in ("Ft", "Rt", "Bk", "Lf")], axis=1)
    band = strip[int(N * 0.12): int(N * 0.53)]
    ground = np.zeros((int(band.shape[0] * 0.18), band.shape[1], 3), dtype=np.float32)
    ground[:] = c(86, 150, 60)
    ground[: ground.shape[0] // 3] = c(214, 110, 40)
    img = np.concatenate([band, ground], axis=0)
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).resize((img.shape[1] // 2, img.shape[0] // 2), Image.LANCZOS).save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    prev_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "art", "out", "sky_preview")
    os.makedirs(prev_dir, exist_ok=True)
    for name, look in LOOKS.items():
        faces = {f: side_face(look, cl if PAINT_CLOUDS else []) for f, cl in FACES.items()}
        faces["Up"] = cap_face(look, True)
        faces["Dn"] = cap_face(look, False)
        for f, arr in faces.items():
            save(arr, os.path.join(OUT, f"Sky_{name}_{f}.png"))
        preview(faces, os.path.join(prev_dir, f"{name}.png"))
        print("wrote", name)


if __name__ == "__main__":
    main()
