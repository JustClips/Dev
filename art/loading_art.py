"""Loading screen sprites (2026-10-31, Dev asked for a better loading screen):
LoadingLeaf - a white maple-style leaf with a dark outline and veins, tinted autumn colours
in LoadingController as it drifts down. Run: python3 art/loading_art.py, then
python3 tools/upload_assets.py."""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "ui")
S = 4  # supersample


def leaf(size=256):
    """A pointed oval leaf, tilted, with a midrib, side veins and a short stem."""
    W = size * S
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    ink = (23, 25, 30, 255)
    L, Wd = W * 0.40, W * 0.21  # half length, half width

    def outline(scale):
        pts = []
        for i in range(181):
            t = i / 180 * math.pi
            x = -math.cos(t) * L * scale
            y = math.sin(t) ** 0.85 * Wd * scale
            pts.append((x, y))
        return pts + [(x, -y) for x, y in reversed(pts)]

    def place(pts):
        a = math.radians(-40)
        cx, cy = W * 0.5, W * 0.5
        return [(cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)) for x, y in pts]

    # Stem from the base end.
    d.line(place([(-L * 1.0, 0), (-L * 1.22, W * 0.03)]), fill=ink, width=int(W * 0.035))
    d.polygon(place(outline(1.0)), fill=ink)
    d.polygon(place(outline(0.9)), fill=(255, 255, 255, 255))
    # Lower half a touch darker (tint keeps it), then veins.
    half = [(x, y) for x, y in outline(0.9) if y <= 0]
    d.polygon(place(half), fill=(222, 222, 222, 255))
    veins = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    vd = ImageDraw.Draw(veins)
    vein = (150, 150, 150, 255)
    vd.line(place([(-L, 0), (L, 0)]), fill=vein, width=int(W * 0.02))
    for k in (-0.55, -0.2, 0.15, 0.5):
        for sgn in (1, -1):
            vd.line(place([(L * k, 0), (L * (k + 0.3), sgn * Wd)]), fill=vein, width=int(W * 0.014))
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).polygon(place(outline(0.9)), fill=255)
    img.paste(veins, (0, 0), Image.composite(veins.getchannel("A"), Image.new("L", (W, W), 0), mask))
    return img.resize((size, size), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    leaf().save(os.path.join(OUT, "LoadingLeaf.png"))
    print("wrote LoadingLeaf.png")
