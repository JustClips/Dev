"""Synthesised trailer sound effects (no licences needed). Writes art/trailer/audio/sfx_*.wav at 48 kHz.
Run: python3 art/trailer/sfx.py"""
import os
import numpy as np
import wave

SR = 48000
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "audio")
rng = np.random.default_rng(7)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a, r, curve=3.0):
    e = np.ones(n)
    na = max(1, int(SR * a))
    e[:na] = np.linspace(0, 1, na)
    x = np.linspace(0, 1, n - na)
    e[na:] = (1 - x) ** curve if r else 1
    return e


def lp(x, cut):
    """one-pole low-pass, cut may be an array (Hz)."""
    cut = np.broadcast_to(np.asarray(cut, float), x.shape)
    a = 1 - np.exp(-2 * np.pi * cut / SR)
    y = np.empty_like(x)
    s = 0.0
    for i in range(len(x)):
        s += a[i] * (x[i] - s)
        y[i] = s
    return y


def bp(x, cut):
    return lp(x, cut) - lp(lp(x, cut * 0.5), cut * 0.5)


def save(name, x, stereo_w=0.0):
    x = x / (np.abs(x).max() + 1e-9) * 0.9
    l, r = x, x
    if stereo_w:
        d = int(SR * 0.012)
        r = np.concatenate([np.zeros(d), x[:-d]])
        l = x * (1 - stereo_w) + r * stereo_w
    st = (np.stack([l, r], 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, f"sfx_{name}.wav"), "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(st.tobytes())


def whoosh(d=0.7, f0=300, f1=4000, peak=0.6):
    n = len(t(d))
    x = rng.standard_normal(n)
    k = np.linspace(0, 1, n)
    cut = f0 * (f1 / f0) ** np.sin(np.pi * np.clip(k / peak / 2, 0, 1)) 
    e = np.where(k < peak, (k / peak) ** 2, ((1 - k) / (1 - peak)) ** 1.5)
    return bp(x, cut) * e


def impact(d=1.6):
    tt = t(d)
    f = 55 * np.exp(-tt * 3) + 38
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 2.6)
    crack = lp(rng.standard_normal(len(tt)), 3000) * np.exp(-tt * 18)
    return boom * 1.0 + crack * 0.5


def coin(f=1568, d=0.5):
    tt = t(d)
    x = sum(a * np.sin(2 * np.pi * f * m * tt) * np.exp(-tt * (6 + 4 * m)) for m, a in [(1, 1), (2.76, 0.5), (5.4, 0.25)])
    x2 = np.roll(x, int(SR * 0.07)) * 0.0
    tt2 = tt
    x += np.where(tt > 0.06, np.sin(2 * np.pi * f * 1.335 * (tt2 - 0.06)) * np.exp(-(tt2 - 0.06).clip(0) * 7), 0) * 0.8
    return x * env(len(tt), 0.002, 1, 1)


def coins_burst(n=14, d=1.4):
    out = np.zeros(len(t(d)))
    for i in range(n):
        c = coin(rng.choice([1318, 1568, 1760, 2093]) * rng.uniform(0.98, 1.02), 0.4)
        s = int(SR * rng.uniform(0, d - 0.45) * (i / n) ** 0.7)
        out[s:s + len(c)] += c * rng.uniform(0.4, 1)
    return out


def pop(f=700, d=0.18):
    tt = t(d)
    fr = f * (1 + 2.5 * np.exp(-tt * 40))
    return np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-tt * 22)


def riser(d=5.0):
    tt = t(d)
    k = tt / d
    noise = bp(rng.standard_normal(len(tt)), 400 * 20 ** k) * k ** 2
    f = 120 * 8 ** k
    tone = sum(np.sin(2 * np.pi * np.cumsum(f * m) / SR) / m for m in (1, 2, 3)) * k ** 3 * 0.3
    return noise + tone


def sparkle(d=1.5):
    out = np.zeros(len(t(d)))
    for i in range(22):
        f = rng.uniform(2500, 6000)
        tt = t(0.25)
        g = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 25)
        s = int(SR * rng.uniform(0, d - 0.3))
        out[s:s + len(g)] += g * rng.uniform(0.2, 0.8)
    return out * np.linspace(1, 0.3, len(out))


def crack(d=0.35):
    tt = t(d)
    x = bp(rng.standard_normal(len(tt)), 2500) * np.exp(-tt * 30)
    return x + pop(260, d) * 0.6


def leaves(d=1.2):
    n = len(t(d))
    x = bp(rng.standard_normal(n), 1800) * (rng.random(n) < 0.08) * 3 + bp(rng.standard_normal(n), 900) * 0.4
    return x * env(n, 0.05, 1, 1.5)


def ding_big():
    tt = t(2.5)
    return sum(a * np.sin(2 * np.pi * f * tt) * np.exp(-tt * k) for f, a, k in
               [(523, 1, 1.5), (659, 0.8, 1.6), (784, 0.7, 1.7), (1046, 0.6, 2.2), (2093, 0.3, 3)])


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("whoosh", whoosh(), 0.5)
    save("whoosh_short", whoosh(0.35, 500, 6000, 0.7), 0.5)
    save("impact", impact(), 0.3)
    save("coin", coin())
    save("coins", coins_burst(), 0.6)
    save("pop", pop())
    save("riser", riser(), 0.4)
    save("sparkle", sparkle(), 0.7)
    save("crack", crack())
    save("leaves", leaves(), 0.6)
    save("chime", ding_big(), 0.4)
    print("ok")
