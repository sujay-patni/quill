"""Generates Quill's tileable paper texture (mobile/assets/paper.png).

A grey + alpha PNG: transparent paper fibres, grain and soft mottling, laid over the reader
theme's background colour, so one texture serves every theme. No external dependencies.

Usage: python3 -I tools/make_paper_texture.py
"""
import math, os, random, struct, zlib

N = 192  # tile size in pixels; must tile seamlessly
rng = random.Random(1307)

def periodic_noise(octaves):
    """Smooth tileable value noise from a few periodic sine layers."""
    layers = []
    for f in octaves:
        for _ in range(3):
            ax, ay = rng.randint(-f, f), rng.randint(-f, f)
            layers.append((ax, ay, rng.random() * 2 * math.pi, rng.random()))
    def at(x, y):
        v = 0.0
        for ax, ay, ph, w in layers:
            v += w * math.sin(2 * math.pi * (ax * x + ay * y) / N + ph)
        return v / max(1e-9, sum(w for *_, w in layers))
    return at

mottle = periodic_noise([1, 2, 3])
alpha = [[0.0] * N for _ in range(N)]
for y in range(N):
    for x in range(N):
        a = 13 + 12 * mottle(x, y)         # soft uneven tone
        a += rng.gauss(0, 3.8)              # fine grain
        alpha[y][x] = a

# Fibres: short, thin, slightly curved strokes, wrapped around the tile edges.
for _ in range(140):
    x, y = rng.random() * N, rng.random() * N
    ang = rng.random() * math.pi
    length = rng.randint(6, 26)
    strength = rng.uniform(4, 11)
    for t in range(length):
        ang += rng.gauss(0, 0.12)
        x += math.cos(ang); y += math.sin(ang)
        ix, iy = int(x) % N, int(y) % N
        alpha[iy][ix] += strength
        alpha[iy][(ix + 1) % N] += strength * 0.35

def png(width, height, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 4, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))

GREY = 70  # warm-neutral ink of the fibres; the theme colour shows through
rows = []
for y in range(N):
    row = []
    for x in range(N):
        row += [GREY, max(0, min(50, int(round(alpha[y][x]))))]
    rows.append(row)

out = os.path.join(os.path.dirname(__file__), '..', 'mobile', 'assets', 'paper.png')
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'wb') as f:
    f.write(png(N, N, rows))
print('wrote', os.path.normpath(out), os.path.getsize(out), 'bytes')
