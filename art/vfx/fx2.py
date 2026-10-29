"""Second pass of weather VFX textures (numpy). Run after textures.py:

  python3 art/vfx/fx2.py   # writes art/out/ui/Vfx_*.png (overwrites the moons and the rain)

Rules every texture here follows, so they look right however Roblox blends them:
  * the colour is premultiplied (black wherever it's see-through), and
  * alpha is exactly 0 on the image border (no visible square around soft glows).
"""
import colorsys
import math
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "out", "ui")
os.makedirs(OUT, exist_ok=True)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def write(rgb, alpha, name):
    """rgb: HxWx3 floats 0..1 (straight colour), alpha HxW 0..1."""
    alpha = np.clip(alpha, 0, 1)
    rgb = np.clip(rgb, 0, 1) * alpha[..., None]  # premultiply: black where transparent
    rgba = np.dstack([rgb, alpha])
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, f"Vfx_{name}.png"))
    print("wrote", name)


def value_noise(size, cells, seed):
    rng = np.random.default_rng(seed)
    grid = rng.random((cells + 1, cells + 1))
    y, x = np.mgrid[0:size, 0:size] / size * cells
    x0, y0 = x.astype(int), y.astype(int)
    fx, fy = x - x0, y - y0
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = grid[y0, x0] * (1 - fx) + grid[y0, x0 + 1] * fx
    b = grid[y0 + 1, x0] * (1 - fx) + grid[y0 + 1, x0 + 1] * fx
    return a * (1 - fy) + b * fy


def fbm(size, seed, octaves=5):
    total, amp, norm = np.zeros((size, size)), 1.0, 0.0
    for i in range(octaves):
        total += value_noise(size, 4 * 2**i, seed + i) * amp
        norm += amp
        amp *= 0.5
    return total / norm


# Moons --------------------------------------------------------------------------------------
# A lit sphere with dark "seas", craters with bright rims, and a soft glow around it that
# fades to nothing well inside the image.
def moon(name, light, dark, glow, size=512, radius=0.3, glow_strength=0.9, hue_shift=False, seed=3):
    s = size
    y, x = (np.mgrid[0:s, 0:s] + 0.5) / s - 0.5
    d = np.hypot(x, y)
    r = radius
    inside = smoothstep(r + 0.004, r - 0.004, d)

    # Sphere normal z for limb darkening.
    nz = np.sqrt(np.clip(1 - (d / r) ** 2, 0, 1))
    shade = 0.55 + 0.45 * nz**0.6

    seas = smoothstep(0.52, 0.66, fbm(s, seed)) * 0.75
    grain = fbm(s, seed + 20, 6)
    surface = np.clip(1 - seas * 0.6 + (grain - 0.5) * 0.25, 0, 1)

    rng = np.random.default_rng(seed + 50)
    crater = np.zeros((s, s))
    rim = np.zeros((s, s))
    for _ in range(26):
        a, k = rng.random() * math.tau, rng.random() ** 0.7 * r * 0.85
        cx, cy = math.cos(a) * k, math.sin(a) * k
        cr = r * (0.04 + rng.random() ** 2 * 0.16)
        dc = np.hypot(x - cx, y - cy) / cr
        crater = np.maximum(crater, smoothstep(1.0, 0.7, dc) * 0.55)
        rim = np.maximum(rim, smoothstep(0.75, 1.0, dc) * smoothstep(1.25, 1.0, dc) * 0.5)
    surface = np.clip(surface - crater * 0.5 + rim * 0.35, 0, 1)

    light = np.array(light) / 255
    dark = np.array(dark) / 255
    if hue_shift:
        ang = (np.arctan2(y, x) / math.tau + 0.5 + d * 1.5) % 1
        hsv = np.vectorize(lambda h: colorsys.hsv_to_rgb(h, 0.5, 1), otypes=[float, float, float])
        cr_, cg_, cb_ = hsv(ang)
        tint = np.dstack([cr_, cg_, cb_])
        disk_rgb = tint * (0.55 + 0.45 * surface[..., None])
    else:
        disk_rgb = dark + (light - dark) * surface[..., None]
    disk_rgb = disk_rgb * shade[..., None]

    # Glow: bright close to the moon, gone by 0.48 of the image.
    g = np.exp(-np.clip(d - r, 0, None) / 0.05) * 0.85 + np.exp(-np.clip(d - r, 0, None) / 0.12) * 0.35
    g *= smoothstep(0.48, 0.38, d) * glow_strength
    glow = np.array(glow) / 255
    if hue_shift:
        glow_rgb = tint
    else:
        glow_rgb = np.broadcast_to(glow, (s, s, 3))

    alpha = np.maximum(inside, g)
    rgb = np.where(inside[..., None] > 0, disk_rgb * inside[..., None] + glow_rgb * (1 - inside[..., None]), glow_rgb)
    write(rgb, alpha, name)


# Rain ---------------------------------------------------------------------------------------
# Square image with one streak through the full height. Particles are drawn square, so the
# streak's width share decides how thick a drop is (6% of the particle size).
def rain():
    s = 128
    y, x = (np.mgrid[0:s, 0:s] + 0.5) / s
    across = smoothstep(0.035, 0.0, np.abs(x - 0.5))
    along = smoothstep(0.0, 0.7, y) * smoothstep(1.0, 0.9, y)  # thin tail at the top, bright head
    alpha = across * along * 0.95
    write(np.ones((s, s, 3)) * np.array([0.88, 0.93, 1.0]), alpha, "Rain")


# Splash flipbook (4x4 frames, 128 px each): a crown of droplets jumps up and falls back while
# a flat ripple spreads out and fades. Used with FlipbookLayout Grid4x4, OneShot.
def splash():
    cell, n = 128, 4
    sheet_a = np.zeros((cell * n, cell * n))
    y, x = (np.mgrid[0:cell, 0:cell] + 0.5) / cell
    rng = np.random.default_rng(9)
    drops = [((i / 8) * 2 - 1 + rng.uniform(-0.08, 0.08), rng.uniform(0.6, 1.0), rng.uniform(0.022, 0.034)) for i in range(9)]
    for f in range(n * n):
        t = f / (n * n - 1)
        a = np.zeros((cell, cell))
        base_y = 0.82
        # Ripple: flat ellipse ring that grows and fades.
        rx, ry = 0.08 + t * 0.36, 0.02 + t * 0.07
        e = np.hypot((x - 0.5) / rx, (y - base_y) / ry)
        a = np.maximum(a, smoothstep(0.75, 1.0, e) * smoothstep(1.25, 1.0, e) * (1 - t) ** 1.2)
        # Crown: a short upward sheet early on.
        if t < 0.45:
            k = t / 0.45
            h = max(0.22 * math.sin(k * math.pi), 0.01)
            w = 0.07 + k * 0.12
            hb = np.clip(base_y - y, 0, None)  # height above the water
            half = w + hb * 0.9  # walls lean outward like a crown
            crown = smoothstep(half + 0.025, half, np.abs(x - 0.5)) * smoothstep(half - 0.04, half, np.abs(x - 0.5))
            crown *= (y < base_y) * (hb < h) * smoothstep(h, h * 0.6, hb)
            a = np.maximum(a, crown * 0.8 * (1 - k * 0.5))
        # Droplets on arcs.
        for dx, up, rad in drops:
            px = 0.5 + dx * 0.42 * min(1, t * 1.6)
            py = base_y - up * 0.32 * (4 * t * (1 - t))
            dd = np.hypot(x - px, (y - py) * 0.8)
            a = np.maximum(a, smoothstep(rad, rad * 0.4, dd) * (1 - t**3))
        a *= smoothstep(0.0, 0.08, x) * smoothstep(1.0, 0.92, x) * smoothstep(0.0, 0.08, y) * smoothstep(1.0, 0.92, y)
        cy, cx = divmod(f, n)
        sheet_a[cy * cell:(cy + 1) * cell, cx * cell:(cx + 1) * cell] = a
    write(np.ones(sheet_a.shape + (3,)) * np.array([0.9, 0.95, 1.0]), sheet_a, "Splash")


# Rain curtain for distant Beams. A Beam runs the image's X along its length, so the
# streaks are drawn along X (they fall down the beam) and the image tiles in X.
def rain_sheet():
    w, h = 256, 256
    a = np.zeros((h, w))
    rng = np.random.default_rng(12)
    xs = np.arange(w)
    for _ in range(220):
        y0 = rng.uniform(0, h)
        x0 = rng.uniform(0, w)
        length = rng.uniform(25, 70)
        thick = rng.uniform(0.5, 1.1)
        strength = rng.uniform(0.25, 0.8)
        dx = (xs - x0) % w  # wraps so it tiles along the length
        along = smoothstep(0, length * 0.3, dx) * smoothstep(length, length * 0.6, dx)
        rows = np.arange(h)[:, None]
        across = np.exp(-(((rows - y0 + h / 2) % h - h / 2) / thick) ** 2)
        a = np.maximum(a, across * along[None, :] * strength)
    edge = smoothstep(0, 40, np.arange(h)) * smoothstep(h, h - 40, np.arange(h))
    a *= edge[:, None]
    write(np.ones((h, w, 3)) * np.array([0.85, 0.9, 1.0]), a, "RainSheet")


# Big soft out-of-focus snowflake for flakes close to the camera.
def bokeh():
    s = 64
    y, x = (np.mgrid[0:s, 0:s] + 0.5) / s - 0.5
    d = np.hypot(x, y)
    a = smoothstep(0.42, 0.3, d) * (0.55 + 0.45 * smoothstep(0.25, 0.4, d))
    write(np.ones((s, s, 3)), a, "Bokeh")


# Four-point glint for sparkles (crisper than the cartoon star).
def sparkle():
    s = 128
    y, x = (np.mgrid[0:s, 0:s] + 0.5) / s - 0.5
    d = np.hypot(x, y)
    rays = np.exp(-np.abs(x) * 60) * np.exp(-np.abs(y) * 6) + np.exp(-np.abs(y) * 60) * np.exp(-np.abs(x) * 6)
    diag = (np.exp(-np.abs(x - y) * 70) + np.exp(-np.abs(x + y) * 70)) * np.exp(-d * 14) * 0.5
    core = np.exp(-(d / 0.06) ** 2) + np.exp(-d / 0.08) * 0.4
    a = np.clip(rays + diag + core, 0, 1) * smoothstep(0.5, 0.4, d)
    write(np.ones((s, s, 3)), a, "Sparkle")


# Wind wisp: a thin curling stroke along X with faded ends (FacingCamera particles).
def wind():
    w, h = 256, 64
    y, x = np.mgrid[0:h, 0:w] + 0.5
    u = x / w
    centre = h * 0.5 + np.sin(u * math.pi * 2.2) * h * 0.18 + np.sin(u * math.pi * 5) * h * 0.05
    across = np.exp(-((y - centre) / 1.6) ** 2)
    along = smoothstep(0, 0.35, u) * smoothstep(1, 0.7, u)
    write(np.ones((h, w, 3)), across * along * 0.9, "Wind")


# Coloured autumn leaves (drawn in colour, emitters use white): maple, oval and birch.
def leaves():
    from PIL import ImageDraw
    s, k = 128, 4
    specs = {
        "LeafMaple": ((235, 90, 35), (255, 160, 40)),
        "LeafOval": ((240, 170, 40), (255, 220, 90)),
        "LeafGreen": ((110, 165, 55), (180, 210, 80)),
    }
    for name, (dark, light) in specs.items():
        mask = Image.new("L", (s * k, s * k), 0)
        d = ImageDraw.Draw(mask)
        c = s * k / 2
        pts = []
        for i in range(240):
            t = i / 240 * math.tau
            if name == "LeafMaple":
                r = 0.3 + 0.12 * abs(math.cos(t * 2.5)) ** 3 + 0.06 * math.cos(t * 10)
                r *= 1 - 0.25 * max(0, math.cos(t)) ** 8  # notch at the stem
            elif name == "LeafOval":
                r = 0.42 / math.sqrt((math.cos(t) / 1.0) ** 2 + (math.sin(t) / 0.55) ** 2) * 0.5 + 0.02 * math.cos(t * 18)
            else:
                r = 0.4 / math.sqrt((math.cos(t) / 1.0) ** 2 + (math.sin(t) / 0.5) ** 2) * 0.5
            pts.append((c + math.sin(t) * r * s * k, c - math.cos(t) * r * s * k))
        d.polygon(pts, fill=255)
        alpha = np.asarray(mask.resize((s, s), Image.LANCZOS)) / 255
        y, x = (np.mgrid[0:s, 0:s] + 0.5) / s - 0.5
        g = np.clip(0.5 - y * 1.2 + x * 0.4, 0, 1)[..., None]
        rgb = (np.array(dark) / 255) * (1 - g) + (np.array(light) / 255) * g
        vein = np.exp(-(x / 0.012) ** 2) * (np.abs(y) < 0.4)
        side = (np.exp(-((y + np.abs(x) * 0.8) % 0.12 / 0.012) ** 2) * (np.abs(x) < 0.2) * 0.6)
        rgb = rgb * (1 - 0.35 * np.clip(vein + side, 0, 1))[..., None]
        write(rgb, alpha, name)


# Light shaft for Golden Hour: soft vertical-in-beam glow (bright along the middle of the
# width, fading toward the bottom end of the length).
def godray():
    w, h = 128, 64
    y, x = (np.mgrid[0:h, 0:w] + 0.5)
    u, v = x / w, y / h
    a = np.exp(-((v - 0.5) / 0.22) ** 2) * smoothstep(0, 0.15, u) * smoothstep(1, 0.4, u)
    write(np.ones((h, w, 3)), a * 0.9, "GodRay")


if __name__ == "__main__":
    rain()
    splash()
    rain_sheet()
    bokeh()
    sparkle()
    wind()
    leaves()
    godray()
    moon("GoldMoon", (255, 222, 120), (205, 140, 30), (255, 190, 60), seed=3)
    moon("BloodMoon", (255, 95, 80), (150, 15, 20), (255, 40, 40), seed=5)
    moon("MegaMoon", (245, 248, 255), (165, 180, 215), (170, 205, 255), seed=8, glow_strength=1.0)
    moon("RainbowMoon", (255, 255, 255), (200, 200, 200), (255, 255, 255), seed=11, hue_shift=True)
