"""Cut the trailer: rendered shots + text supers + flashes + music + SFX -> one mp4.
Run: python3 art/trailer/edit.py RENDERS_DIR OUT.mp4 [--preview]
Shots are art/trailer/renders/Sxx_*.mp4 (each has 0.5 s handles). The timeline below is in seconds and
snapped to the beats of Pamgaea (Kevin MacLeod, incompetech.com, CC BY 4.0)."""
import glob
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "blender", "fonts", "Montserrat-Black.ttf")
AUD = os.path.join(HERE, "audio")
FPS = 30
W, H = 1920, 1080
HANDLE = 0.5

# --- music: part A (0.07 -> 25.61) then part B from 76.67 (breakdown) with the drop at B+5.09
MUSIC = [(0.07, 25.61), (76.67, 96.0)]
DROP = 25.54 + (81.76 - 76.67)  # trailer time of the drop
BEAT = 0.6385


def beat(k):
    return k * BEAT


# timeline: (shot prefix, trailer start, length, source offset into the shot after its handle, speed)
CUTS = [
    ("S01", beat(0), beat(4), 0.0, 1.0),
    ("S02", beat(4), beat(4), 0.4, 1.0),
    ("S03", beat(8), beat(4), 0.2, 1.0),
    ("S04", beat(12), beat(2), 0.0, 1.0),
    ("S05", beat(14), beat(4), 0.0, 1.0),     # 4 tools, ~1 s each in render; sped to fit
    ("S06", beat(18), beat(4), 0.2, 1.0),
    ("S07", beat(22), beat(2), 0.0, 1.0),
    ("S09", beat(24), beat(2), 0.0, 1.0),
    ("S10", beat(26), beat(4), 0.0, 1.0),
    ("S11", beat(30), beat(4), 0.0, 1.0),
    ("S12", beat(34), beat(6), 0.0, 1.0),     # 4 zones; sped to fit
    ("S08", beat(40), None, None, 1.0),       # hatch: burst (5.2 s into shot) lands on the drop
    ("S13", None, beat(8), None, 1.0),        # cosmic: burst (2.0 s in) on a beat
    ("S14", None, None, 0.0, 1.0),
]


def plan():
    out = []
    for i, (p, start, length, off, speed) in enumerate(CUTS):
        out.append([p, start, length, off, speed])
    # S08 runs from beat 40 to DROP + 1.6 s, burst at shot 5.2 s == DROP
    s08 = out[11]
    s08[2] = DROP + 1.6 - s08[1]
    s08[3] = 5.2 - (DROP - s08[1])
    # S13 next; its burst (2.0 s in) 4 beats after it starts
    s13 = out[12]
    s13[1] = s08[1] + s08[2]
    s13[3] = 2.0 - beat(3)
    s14 = out[13]
    s14[1] = s13[1] + s13[2]
    s14[2] = 5.5
    return out


TIMELINE = plan()
TOTAL = TIMELINE[-1][1] + TIMELINE[-1][2]

# --- text supers: (start, dur, text, style, y, size)
GOLD = ("FFF27A", "FFB31A")
GREEN = ("C8FF7A", "3FCB3A")
WHITE = ("FFFFFF", "D8ECFF")
PURPLE = ("F3B8FF", "B04DFF")
CASH = ("D9FF9A", "4BD82E")
SUPERS = [
    (0.25, beat(4) - 0.3, "CLEAN THE WORLD!", GOLD, 0.2, 120),
    (beat(4) + 0.1, beat(2) - 0.15, "BEFORE", WHITE, 0.2, 110),
    (beat(6) + 0.05, beat(2) - 0.1, "AFTER!", GREEN, 0.2, 130),
    (beat(14) + 0.05, beat(4) - 0.1, "UPGRADE!", GOLD, 0.18, 130),
    (beat(18) + 0.05, beat(4) - 0.1, "DRIVE & CLEAN", WHITE, 0.18, 110),
    (beat(22) + 0.05, beat(4) - 0.1, "HATCH EGGS", GOLD, 0.18, 120),
    (beat(26) + 0.05, beat(4) - 0.1, "COLLECT PETS", GREEN, 0.18, 120),
    (beat(30) + 0.05, beat(4) - 0.1, "GET RICH!", CASH, 0.18, 130),
    (beat(34) + 0.05, beat(1.5) - 0.05, "PARK", WHITE, 0.2, 110),
    (beat(35.5) + 0.05, beat(1.5) - 0.05, "BEACH", WHITE, 0.2, 110),
    (beat(37) + 0.05, beat(1.5) - 0.05, "CITY", WHITE, 0.2, 110),
    (beat(38.5) + 0.05, beat(1.5) - 0.05, "SNOWY PEAKS", WHITE, 0.2, 110),
    (DROP + 0.15, 1.4, "LEGENDARY!", GOLD, 0.2, 150),
]


def climb():
    """the game's rarity-name climb while the egg wobbles before the drop"""
    names = [("COMMON", WHITE), ("UNCOMMON", GREEN), ("RARE", ("A8E1FF", "2E9BFF")), ("EPIC", PURPLE)]
    s = TIMELINE[11][1] + 0.3
    step = (DROP - 0.4 - s) / len(names)
    return [(s + i * step, step - 0.04, n + "...", c, 0.22, 90 + i * 10) for i, (n, c) in enumerate(names)]


SUPERS += climb()
S13 = TIMELINE[12][1]
S13_BURST = S13 + beat(3)
SUPERS += [(S13_BURST + 0.1, TIMELINE[12][2] - beat(3) - 0.15, "COSMIC!!", PURPLE, 0.2, 170)]
END = TIMELINE[13][1]

# floating cash / combo numbers: (start, dur, text, x, y, size)
FLOATS = [
    (0.9, 1.2, "+$1,250", 0.70, 0.55, 90),
    (1.5, 1.1, "+$980", 0.30, 0.62, 70),
    (beat(12) + 0.1, 1.1, "+$12,400", 0.62, 0.5, 90),
    (beat(30) + 0.3, 2.0, "$1.2M/s", 0.5, 0.62, 110),
]
COMBO = (beat(8), beat(12) + beat(2), 12, 553)  # start, end, from, to: the x553 COMBO counter
FLASHES = [beat(4), DROP, S13_BURST, END]
SHAKES = [(0.0, 0.5, 10), (DROP, 0.6, 22), (S13_BURST, 0.7, 26)]

# sfx cues: (time, file, gain)
SFX = [(0.0, "impact", 0.7), (0.05, "leaves", 0.6), (0.85, "coins", 0.55), (beat(4) - 0.35, "whoosh", 0.5),
       (beat(6), "sparkle", 0.4), (beat(12), "coins", 0.6), (beat(14) - 0.3, "whoosh_short", 0.45),
       (beat(15), "pop", 0.3), (beat(16), "pop", 0.3), (beat(17), "pop", 0.3), (beat(18) - 0.3, "whoosh", 0.5),
       (beat(22), "sparkle", 0.4), (beat(24), "chime", 0.35), (beat(30) + 0.3, "coins", 0.55),
       (beat(34) - 0.3, "whoosh", 0.5), (DROP - 5.0, "riser", 0.5), (DROP - 2.0, "crack", 0.5),
       (DROP - 1.0, "crack", 0.6), (DROP, "impact", 0.95), (DROP, "chime", 0.5), (DROP + 0.1, "sparkle", 0.5),
       (S13_BURST - 2.0, "riser", 0.35), (S13_BURST, "impact", 1.0), (S13_BURST, "chime", 0.55),
       (END, "impact", 0.8), (END + 0.2, "sparkle", 0.5)]
SFX += [(COMBO[0] + i * 0.32, "pop", 0.12) for i in range(int((COMBO[1] - COMBO[0]) / 0.32))]

_font_cache = {}


def font(size):
    if size not in _font_cache:
        _font_cache[size] = ImageFont.truetype(FONT, size)
    return _font_cache[size]


_sprite_cache = {}


def sprite(text, cols, size):
    """game-style text: vertical gradient fill, thick dark outline, hard drop shadow"""
    key = (text, cols, size)
    if key in _sprite_cache:
        return _sprite_cache[key]
    f = font(size)
    ow = max(7, size // 7)
    l, t, r, b = f.getbbox(text)
    w, h = r - l + ow * 2 + 20, b - t + ow * 2 + 24
    mask = Image.new("L", (w, h))
    ImageDraw.Draw(mask).text((ow + 10 - l, ow + 10 - t), text, font=f, fill=255)
    outline = Image.new("L", (w, h))
    ImageDraw.Draw(outline).text((ow + 10 - l, ow + 10 - t), text, font=f, fill=255, stroke_width=ow)
    c0 = np.array([int(cols[0][i:i + 2], 16) for i in (0, 2, 4)], float)
    c1 = np.array([int(cols[1][i:i + 2], 16) for i in (0, 2, 4)], float)
    g = np.linspace(0, 1, h)[:, None, None]
    fill = (c0 * (1 - g) + c1 * g).repeat(w, 1)
    img = np.zeros((h, w, 4), float)
    sh = np.roll(np.array(outline, float), (int(ow * 0.9), int(ow * 0.5)), (0, 1)) / 255
    img[..., :3] = 0
    img[..., 3] = sh * 0.55
    o = np.array(outline, float)[..., None] / 255
    img[..., :3] = img[..., :3] * (1 - o) + np.array([27, 27, 36]) * o
    img[..., 3:] = np.maximum(img[..., 3:], o)
    m = np.array(mask, float)[..., None] / 255
    img[..., :3] = img[..., :3] * (1 - m) + fill * m
    img[..., 3] *= 255
    im = Image.fromarray(img.clip(0, 255).astype(np.uint8), "RGBA")
    _sprite_cache[key] = im
    return im


def pop_scale(k):
    """0..1 time since appear (in seconds*?) -> overshoot scale"""
    if k < 0:
        return 0
    if k < 0.12:
        return 0.3 + 0.95 * (k / 0.12)
    if k < 0.22:
        return 1.25 - 0.25 * ((k - 0.12) / 0.1)
    return 1.0


def paste(frame, im, cx, cy, scale=1.0, alpha=1.0, rot=0.0):
    if scale <= 0.02 or alpha <= 0.01:
        return
    w, h = im.size
    s = im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.BILINEAR)
    if rot:
        s = s.rotate(rot, Image.BILINEAR, expand=True)
    if alpha < 1:
        a = s.getchannel("A").point(lambda v: int(v * alpha))
        s.putalpha(a)
    frame.alpha_composite(s, (int(cx - s.size[0] / 2), int(cy - s.size[1] / 2)))


def overlays(frame, tt):
    for s, d, text, cols, y, size in SUPERS:
        if s <= tt < s + d:
            k = tt - s
            out = max(0.0, (tt - (s + d - 0.12)) / 0.12)
            sc = pop_scale(k) * (1 - out * 0.4)
            paste(frame, sprite(text, cols, int(size * 1.35)), W / 2, H * y, sc, 1 - out, rot=math.sin(k * 5) * 1.5)
    for s, d, text, x, y, size in FLOATS:
        if s <= tt < s + d:
            k = (tt - s) / d
            paste(frame, sprite(text, CASH, size), W * x, H * y - k * 140, pop_scale(tt - s), 1 - max(0, k - 0.7) / 0.3)
    c0, c1, a, b = COMBO
    if c0 <= tt < c1:
        k = (tt - c0) / (c1 - c0)
        n = int(a + (b - a) * k ** 1.6)
        bump = 1 + 0.12 * max(0, 1 - ((tt - c0) % 0.32) / 0.12)
        paste(frame, sprite(f"x{n} COMBO", GOLD, 96), W * 0.5, H * 0.8, pop_scale(tt - c0) * bump)
        if n >= 500:
            paste(frame, sprite("GREAT! x500 COMBO", ("FFFFFF", "FFD84A"), 80), W * 0.5, H * 0.66, pop_scale(tt - c0 - k * 0 - (c1 - c0) * (500 - a) / (b - a)))
    if tt >= END + 0.25:
        logo = end_logo()
        k = tt - END - 0.25
        paste(frame, logo, W / 2, H * 0.36, pop_scale(k) * 0.95)
        if tt >= END + 1.1:
            k2 = tt - END - 1.1
            pulse = 1 + 0.05 * math.sin(k2 * 6)
            paste(frame, play_now(), W / 2, H * 0.74, pop_scale(k2) * pulse)


_logo = None


def end_logo():
    global _logo
    if _logo is None:
        lg = Image.open(os.path.join(HERE, "logo.png")).convert("RGBA")
        a = np.array(lg)
        # logo.png has a flat blue backing: key it out
        bg = a[5, 5, :3].astype(int)
        d = np.abs(a[..., :3].astype(int) - bg).sum(-1)
        a[..., 3] = np.where(d < 40, 0, a[..., 3])
        lg = Image.fromarray(a)
        _logo = lg.resize((int(lg.width * 1.05), int(lg.height * 1.05)), Image.LANCZOS)
    return _logo


_play = None


def play_now():
    global _play
    if _play is None:
        txt = sprite("PLAY NOW", ("FFFFFF", "FFFFFF"), 84)
        pad = 34
        bw, bh = txt.width + pad * 2, txt.height + pad
        btn = Image.new("RGBA", (bw + 16, bh + 16))
        dr = ImageDraw.Draw(btn)
        dr.rectangle((8, 14, bw + 8, bh + 14), fill=(27, 27, 36, 255))  # shadow / outline, no rounded corners
        dr.rectangle((0, 0, bw, bh), fill=(27, 27, 36, 255))
        dr.rectangle((7, 7, bw - 7, bh - 7), fill=(64, 200, 60, 255))
        btn.alpha_composite(txt, ((bw - txt.width) // 2, (bh - txt.height) // 2 - 2))
        _play = btn
    return _play


def find(renders, prefix):
    m = sorted(glob.glob(os.path.join(renders, prefix + "*.mp4")))
    if not m:
        raise SystemExit(f"missing render {prefix}")
    return m[0]


def probe_len(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                       capture_output=True, text=True)
    return float(r.stdout.strip())


def shot_frames(path, off, length, speed):
    """yield RGB frames for this cut; time-stretches by speed (frame picking) and holds the last frame"""
    src_len = probe_len(path)
    p = subprocess.Popen(["ffmpeg", "-v", "error", "-i", path, "-vf", f"scale={W}:{H},fps={FPS}", "-f", "rawvideo",
                          "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
    frames = []
    while True:
        b = p.stdout.read(W * H * 3)
        if len(b) < W * H * 3:
            break
        frames.append(b)
    p.wait()
    n = int(round(length * FPS))
    start = HANDLE + off
    # fit: if the shot is shorter than asked, speed it up only as much as needed
    avail = src_len - start - 0.05
    if avail < length * speed:
        speed = max(speed, avail / length) if avail > 0 else speed
    for i in range(n):
        idx = int((start + i / FPS * speed) * FPS)
        idx = max(0, min(len(frames) - 1, idx))
        yield np.frombuffer(frames[idx], np.uint8).reshape(H, W, 3)


def shake(tt):
    for s, d, amp in SHAKES:
        if s <= tt < s + d:
            k = (tt - s) / d
            a = amp * (1 - k) ** 2
            return int(math.sin(tt * 90) * a), int(math.cos(tt * 77) * a)
    return 0, 0


def flash(tt):
    v = 0.0
    for s in FLASHES:
        if s - 1 / FPS <= tt < s + 0.25:
            v = max(v, 1 - max(0, tt - s) / 0.25)
    return v


def build_audio(path):
    import wave
    sr = 48000
    tmp = path + ".music.wav"
    parts = "".join(f"[0:a]atrim={a}:{b},asetpts=PTS-STARTPTS[a{i}];" for i, (a, b) in enumerate(MUSIC))
    cat = "".join(f"[a{i}]" for i in range(len(MUSIC)))
    music_end = TOTAL
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", os.path.join(AUD, "Pamgaea.mp3"), "-filter_complex",
                    parts + f"{cat}concat=n={len(MUSIC)}:v=0:a=1,aresample={sr},atrim=0:{music_end},"
                    f"afade=t=out:st={music_end - 2.2}:d=2.2[m]", "-map", "[m]", "-ac", "2", tmp], check=True)
    with wave.open(tmp) as w:
        m = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, 2).astype(float) / 32768
    mix = np.zeros((int(TOTAL * sr) + sr, 2))
    mix[:len(m)] += m * 0.8
    # duck the music a bit under the big hits
    for t0, f, g in SFX:
        with wave.open(os.path.join(AUD, f"sfx_{f}.wav")) as w:
            s = np.frombuffer(w.readframes(w.getnframes()), np.int16).reshape(-1, 2).astype(float) / 32768
        i = int(t0 * sr)
        if i < 0:
            s, i = s[-i:], 0
        s = s[:len(mix) - i]
        mix[i:i + len(s)] += s * g
    mix = mix[:int(TOTAL * sr)]
    peak = np.abs(mix).max()
    mix = np.tanh(mix / max(peak, 1e-6) * 1.4) / np.tanh(1.4) * 0.95
    out = path + ".mix.wav"
    with wave.open(out, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes((mix * 32767).astype(np.int16).tobytes())
    os.remove(tmp)
    return out


def main():
    renders, out = sys.argv[1], sys.argv[2]
    preview = "--preview" in sys.argv
    audio = build_audio(out)
    vw, vh = (960, 540) if preview else (W, H)
    enc = subprocess.Popen(["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
                            "-r", str(FPS), "-i", "-", "-i", audio, "-vf", f"scale={vw}:{vh}", "-c:v", "libx264",
                            "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
                            "-shortest", "-movflags", "+faststart", out], stdin=subprocess.PIPE)
    fi = 0
    for p, start, length, off, speed in TIMELINE:
        for fr in shot_frames(find(renders, p), off, length, speed):
            tt = fi / FPS
            img = Image.fromarray(fr).convert("RGBA")
            dx, dy = shake(tt)
            if dx or dy:
                img = img.transform(img.size, Image.AFFINE, (0.97, 0, dx + W * 0.015, 0, 0.97, dy + H * 0.015), Image.BILINEAR)
            overlays(img, tt)
            a = np.asarray(img.convert("RGB")).astype(np.float32)
            fl = flash(tt)
            if fl:
                a = a + (255 - a) * fl * 0.85
            if tt > TOTAL - 0.6:
                a *= max(0, (TOTAL - tt) / 0.6) * 0.0 + 1  # music fades; picture holds on the logo
            enc.stdin.write(a.clip(0, 255).astype(np.uint8).tobytes())
            fi += 1
    enc.stdin.close()
    enc.wait()
    os.remove(audio)
    print(out, f"{fi / FPS:.1f}s")


if __name__ == "__main__":
    main()
