"""Mutation skins for the voxel pets.

A voxel pet's colours all live in one small palette texture (art/blender/voxpets.py), so a
mutation can repaint the pet cube by cube: every swatch is mapped through the mutation's
colour ramp, keeping the pixel shading, the eyes and their shine. The game swaps the
pet's TextureID to the skin (AssetLibrary.applyMutation) instead of putting a coat over
it. Rainbow and Disco have 4 frames that the client cycles.

  python3 tools/pet_skins.py   # art/out/Alien_*.glb (voxel ones) -> art/out/ui/PetSkin_<Pet>_<Mutation>[_<frame>].png
                               # plus art/out/ui/Vfx_Pixel.png (square particle)
Then upload with tools/upload_assets.py.
"""
import colorsys
import glob
import io
import json
import os
import struct

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "art", "out")
UI = os.path.join(OUT, "ui")
KEEP = {(0x24, 0x1A, 0x16), (0xFF, 0xFF, 0xFF)}   # eye black and eye shine stay as they are
CELL, GRID = 4, 8


def hx(h):
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


NORM = [0.0, 1.0]   # this pet's darkest and lightest colour (set per pet in main)


def norm(c):
    """Luminance stretched over the pet's own range, so pale and dark pets both use the
    whole ramp."""
    lo, hi = NORM
    return min(1.0, max(0.0, (lum(c) - lo) / max(0.05, hi - lo)))


def ramp(lo, hi, gamma=1.0):
    lo, hi = hx(lo), hx(hi)
    return lambda c, i: mix(lo, hi, 0.08 + 0.92 * norm(c) ** gamma)


def ramp3(lo, mid, hi, floor=0.08):
    """Three-stop ramp: dark, a saturated middle, light (keeps gold looking like gold)."""
    lo, mid, hi = hx(lo), hx(mid), hx(hi)

    def f(c, i):
        t = floor + (1 - floor) * norm(c)
        return mix(lo, mid, t * 2) if t < 0.5 else mix(mid, hi, (t - 0.5) * 2)
    return f


def h01(i, salt=0):
    """A stable 0..1 hash of a swatch index."""
    x = (i * 2654435761 + salt * 40503) & 0xFFFFFFFF
    x ^= x >> 13
    x = (x * 0x5BD1E995) & 0xFFFFFFFF
    return (x ^ (x >> 15)) / 0xFFFFFFFF


def wet(c, i):
    """Wet fur: darker and more saturated, a little bluer."""
    h, s_, v = colorsys.rgb_to_hsv(*c)
    r = colorsys.hsv_to_rgb(h, min(1, s_ * 1.25), v * 0.72)
    return mix(r, hx("2F6DFF"), 0.18)


def rainbow(frame, sat, val, confetti):
    def f(c, i):
        h = (h01(i, 3) if confetti else norm(c) * 0.85) + frame / 4
        return colorsys.hsv_to_rgb(h % 1, sat, val[0] + val[1] * norm(c))
    return f


def tint(col, t, k=1.0):
    col = hx(col)
    return lambda c, i: tuple(min(1, x * k) for x in mix(c, col, t))


# Sparkles come from particles, not the texture: a glint per swatch would light up one of
# the four shades on every cube and draw stripes.
SKINS = {
    "Golden": ramp3("7A4300", "F0A818", "FFF3B8", 0.3),
    "MoonDusted": ramp("7C78AE", "F8F6FF"),
    "Wet": wet,
    "Frozen": lambda c, i: mix(c, mix(hx("5FA8DC"), hx("F2FBFF"), lum(c)), 0.75),
    "Shocked": ramp3("1A1640", "7A5CFF", "FFF36E"),
    "Windswept": tint("FF8F3A", 0.45, 1.05),
    "Bloodlit": ramp("26040A", "FF4A48"),
    "Starlit": ramp("0A1036", "4A6BE8"),
    "Starstruck": ramp3("8A4E10", "F6BE48", "FFF8DC", 0.3),
}
for f in range(4):
    SKINS[f"Rainbow_{f}"] = rainbow(f, 0.6, (0.55, 0.5), False)
    SKINS[f"Disco_{f}"] = rainbow(f, 0.9, (0.75, 0.3), True)


def glb_image(path):
    """The first embedded PNG in a GLB."""
    data = open(path, "rb").read()
    length = struct.unpack_from("<I", data, 8)[0]
    off = 12
    js, binc = None, None
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk)
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    bv = js["bufferViews"][js["images"][0]["bufferView"]]
    raw = binc[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
    return Image.open(io.BytesIO(raw)).convert("RGB")


def is_voxel(name, meta):
    return bool(meta.get(name, {}).get("voxel"))


def skin(img, fn):
    out = img.copy()
    px = out.load()
    w, h = out.size
    for idx in range(GRID * GRID):
        x0, y0 = (idx % GRID) * CELL, (idx // GRID) * CELL
        if y0 >= h:
            break
        c8 = px[x0 + CELL // 2, y0 + CELL // 2]
        if c8 in KEEP:
            continue
        c = tuple(v / 255 for v in c8)
        n = tuple(round(max(0, min(1, v)) * 255) for v in fn(c, idx))
        for y in range(y0, y0 + CELL):
            for x in range(x0, x0 + CELL):
                px[x, y] = n
    return out


def pixel_particle():
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    for y in range(3, 29):
        for x in range(3, 29):
            img.putpixel((x, y), (255, 255, 255, 255))
    img.save(os.path.join(UI, "Vfx_Pixel.png"))


def main():
    os.makedirs(UI, exist_ok=True)
    meta = json.load(open(os.path.join(OUT, "meta.json")))
    n = 0
    for path in sorted(glob.glob(os.path.join(OUT, "Alien_*.glb"))):
        name = os.path.basename(path)[:-4]
        if not is_voxel(name, meta):
            continue
        img = glb_image(path)
        pet = name[len("Alien_"):]
        cols = set(img.get_flattened_data() if hasattr(img, 'get_flattened_data') else img.getdata()) - KEEP - {(0, 0, 0)}
        ls = sorted(lum(tuple(v / 255 for v in c)) for c in cols)
        NORM[0], NORM[1] = ls[len(ls) // 20], ls[-1 - len(ls) // 20]
        for mut, fn in SKINS.items():
            skin(img, fn).save(os.path.join(UI, f"PetSkin_{pet}_{mut}.png"))
            n += 1
    pixel_particle()
    print(f"wrote {n} skins")


if __name__ == "__main__":
    main()
