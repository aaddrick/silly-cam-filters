#!/usr/bin/env python3
"""Generate the Face Stickers PNGs (original art, drawn procedurally; no downloaded art).

usage: python3 gen_stickers.py [outdir]     (default: this script's folder)
Writes sticker_nose.png (512x512), sticker_mustache.png (1024x400), sticker_glasses.png (1024x420).
Deterministic (no randomness). Requires numpy + Pillow.

Method: every shape is a signed distance field (SDF) evaluated per pixel at 2x the output size;
coverage = clamp(0.5 - sdf/px), so edges are analytically antialiased. Layers are composited
premultiplied, downsampled 2x premultiplied (box filter), then un-premultiplied. Finally the RGB of
fully transparent pixels is "bled" from the nearest opaque neighbours, so a bilinear
lookup of the straight-alpha PNG never pulls in black (no dark fringe at any scale).

Anchors the effect relies on (main.hlsl STICKER_* constants):
  nose:     ball centre = image centre; ball diameter = 0.90 of the image width.
  glasses:  lens centres at x = 0.5 +- 0.2246 of the width, y = 0.5 of the height
            (lens centre distance = 0.4492 of the width).
  mustache: body centre (between the lobes) = image centre.
Licence: same as the plugin (GPL-2.0-or-later), made for Silly Cam Filters.
"""
import os
import sys

import numpy as np
from PIL import Image

SS = 2  # supersampling factor (on top of the analytic AA)


def grid(w, h):
    ys, xs = np.mgrid[0:h * SS, 0:w * SS].astype(np.float64)
    return (xs + 0.5) / SS, (ys + 0.5) / SS  # output-pixel units


def cov(sdf):
    """Coverage 0..1 from an SDF in output pixels (AA width 1 output px)."""
    return np.clip(0.5 - sdf, 0.0, 1.0)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.x, self.y = grid(w, h)
        self.rgb = np.zeros(self.x.shape + (3,))  # premultiplied
        self.a = np.zeros(self.x.shape)

    def over(self, color, alpha):
        """Composite a layer: color (..,3) or (3,) straight, alpha (..) 0..1."""
        color = np.broadcast_to(np.asarray(color, dtype=np.float64), self.rgb.shape)
        alpha = np.clip(alpha, 0.0, 1.0)
        self.rgb = color * alpha[..., None] + self.rgb * (1.0 - alpha[..., None])
        self.a = alpha + self.a * (1.0 - alpha)

    def save(self, path):
        h, w = self.h, self.w
        rgb = self.rgb.reshape(h, SS, w, SS, 3).mean(axis=(1, 3))
        a = self.a.reshape(h, SS, w, SS).mean(axis=(1, 3))
        straight = np.where(a[..., None] > 1e-4, rgb / np.maximum(a[..., None], 1e-4), 0.0)
        straight = bleed(np.clip(straight, 0, 1), a)
        out = np.dstack([straight, a])
        Image.fromarray(np.round(out * 255).astype(np.uint8), "RGBA").save(path, optimize=True)


def bleed(rgb, a, thresh=0.004, rounds=64):
    """Fill RGB of (almost) fully transparent pixels (alpha < thresh) from neighbours (iterative dilation)."""
    known = a >= thresh
    rgb = rgb.copy()
    rgb[~known] = 0.0
    for _ in range(rounds):
        if known.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros(a.shape)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                k = np.roll(np.roll(known, dy, 0), dx, 1)
                c = np.roll(np.roll(rgb, dy, 0), dx, 1)
                acc += c * k[..., None]
                cnt += k
        new = (~known) & (cnt > 0)
        rgb[new] = acc[new] / cnt[new][:, None]
        known = known | new
    # anything still unknown (far from art): flat mean colour of the art
    if not known.all():
        rgb[~known] = rgb[known].mean(axis=0) if known.any() else 0.5
    # keep the original colour where the art is partly covered (alpha >= thresh already kept)
    return rgb


def blur(img, r):
    """Cheap separable box blur x3 (approx. gaussian), r in supersampled px."""
    r = max(1, int(r))
    out = img
    for _ in range(3):
        for axis in (0, 1):
            c = np.cumsum(np.pad(out, [(r + 1, r) if i == axis else (0, 0) for i in range(out.ndim)], mode="edge"), axis=axis)
            hi = np.take(c, np.arange(2 * r + 1, c.shape[axis]), axis=axis)
            lo = np.take(c, np.arange(0, c.shape[axis] - 2 * r - 1), axis=axis)
            out = (hi - lo) / (2 * r + 1)
    return out


def norm(v):
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v)


# ---------------------------------------------------------------- clown nose
def make_nose(path):
    W = H = 512
    c = Canvas(W, H)
    cx, cy, R = 256.0, 252.0, 228.0
    dx, dy = c.x - cx, c.y - cy
    d = np.sqrt(dx * dx + dy * dy)
    # soft contact shadow, down-right, for depth on the skin
    sh = cov(np.sqrt((c.x - cx - 10) ** 2 + (c.y - cy - 16) ** 2) - (R - 4))
    sh = blur(sh, 10 * SS) * 0.30
    c.over((0.12, 0.02, 0.02), sh)
    # sphere shading
    nx, ny = dx / R, dy / R
    nz = np.sqrt(np.clip(1.0 - nx * nx - ny * ny, 0.0, 1.0))
    L = norm((-0.45, -0.55, 0.70))
    ndl = np.clip(nx * L[0] + ny * L[1] + nz * L[2], 0.0, 1.0)
    base = np.array((0.93, 0.07, 0.09))
    shade = 0.42 + 0.68 * ndl
    col = base[None, None, :] * shade[..., None]
    # bounce light from below (warm) so the dark side is not muddy
    bounce = np.clip(ny, 0, 1) ** 2 * np.clip(nz, 0, 1) * 0.18
    col += np.array((0.9, 0.25, 0.2)) * bounce[..., None]
    # specular (Blinn-Phong) + a soft second highlight
    Hv = norm(L + np.array((0.0, 0.0, 1.0)))
    ndh = np.clip(nx * Hv[0] + ny * Hv[1] + nz * Hv[2], 0.0, 1.0)
    spec = ndh ** 60 * 0.95
    col = col * (1 - spec[..., None]) + spec[..., None]
    hl = cov((np.sqrt(((c.x - (cx - 0.38 * R)) / 1.6) ** 2 + (c.y - (cy - 0.45 * R)) ** 2) - 0.13 * R))
    hl = blur(hl, 5 * SS) * 0.85
    col = col * (1 - hl[..., None]) + hl[..., None]
    c.over(np.clip(col, 0, 1), cov(d - R))
    c.save(path)


# ---------------------------------------------------------------- glasses
def make_glasses(path):
    W, H = 1024, 420
    c = Canvas(W, H)
    cy = 210.0
    sep = 0.4492 * W / 2.0  # 230 px
    lx, rx = W / 2 - sep, W / 2 + sep
    Rl = 168.0  # lens radius (inner edge of the frame)
    T = 30.0    # frame thickness
    frame_col = np.array((0.10, 0.10, 0.12))
    for lxc in (lx, rx):
        dx, dy = c.x - lxc, c.y - cy
        d = np.sqrt(dx * dx + dy * dy)
        # lens: light blue tint + two glare streaks (white), eyes stay visible
        lens = cov(d - Rl)
        c.over((0.75, 0.88, 1.0), lens * 0.16)
        u = (dx + dy) / np.sqrt(2.0)  # diagonal coordinate
        g1 = cov(np.abs(u + 0.30 * Rl) - 0.10 * Rl) * lens
        g2 = cov(np.abs(u + 0.02 * Rl) - 0.035 * Rl) * lens
        fade = np.clip(1.0 - (dx - dy) / (2.2 * Rl) - 0.1, 0, 1)  # streaks fade to the lower right
        c.over((1.0, 1.0, 1.0), (g1 * 0.55 + g2 * 0.45) * fade)
    # bridge: an arc above the line between the lenses
    bdx, bdy = c.x - W / 2, c.y - (cy + 40)
    bd = np.abs(np.sqrt(bdx * bdx + bdy * bdy) - 70.0) - 11.0
    bd = np.where((c.y < cy + 10) & (np.abs(bdx) < sep - Rl + 10), bd, 1e3)
    # temples: short bars from the outer rims to the image edge
    tdy = np.abs(c.y - (cy - 0.55 * Rl)) - 10.0
    tl = np.maximum(tdy, np.maximum(c.x - (lx - Rl), 6.0 - c.x))
    tr = np.maximum(tdy, np.maximum((rx + Rl) - c.x, c.x - (W - 6.0)))
    rims = []
    for lxc in (lx, rx):
        d = np.sqrt((c.x - lxc) ** 2 + (c.y - cy) ** 2)
        rims.append(np.abs(d - (Rl + T / 2)) - T / 2)
    frame_sdf = np.minimum.reduce([rims[0], rims[1], bd, tl, tr])
    fa = cov(frame_sdf)
    # glossy frame: lighter top edge highlight
    col = np.broadcast_to(frame_col, c.rgb.shape).copy()
    for lxc in (lx, rx):
        dx, dy = c.x - lxc, c.y - cy
        d = np.sqrt(dx * dx + dy * dy)
        ang_up = np.clip(-dy / np.maximum(d, 1e-6), 0, 1)
        ring = np.clip(1.0 - np.abs(d - (Rl + T * 0.7)) / (T * 0.22), 0, 1)
        col += (ring * ang_up ** 2 * 0.55)[..., None]
    c.over(np.clip(col, 0, 1), fa)
    c.save(path)


# ---------------------------------------------------------------- mustache
def catmull(pts, n):
    pts = np.asarray(pts, dtype=np.float64)
    P = np.vstack([pts[0], pts, pts[-1]])
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for t in np.linspace(0, 1, n, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(P[-2])
    return np.array(out)


def make_mustache(path):
    W, H = 1024, 400
    c = Canvas(W, H)
    ox, oy = W / 2.0, 168.0  # path origin (top centre of the body)
    # right half path (x outwards, y down), curling up at the tip
    ctrl = [(0, 18), (55, 40), (140, 64), (230, 66), (310, 42), (368, 0), (392, -48),
            (378, -88), (344, -96), (322, -72), (332, -48), (352, -50)]
    curve = catmull(ctrl, 24)
    n = len(curve)
    s = np.linspace(0, 1, n)
    rad = 64.0 * (1.0 - s) ** 0.85 + 7.0
    best = np.full(c.x.shape, 1e9)     # sdf of the union of discs
    core = np.full(c.x.shape, 1e9)     # normalized distance to the centre line
    above = np.zeros(c.x.shape)
    for side in (1.0, -1.0):
        for (px, py), r in zip(curve, rad):
            X, Y = ox + side * px, oy + py
            d = np.sqrt((c.x - X) ** 2 + (c.y - Y) ** 2)
            sdf = d - r
            m = sdf < best
            best = np.where(m, sdf, best)
            core = np.where(m, d / r, core)
            above = np.where(m, (Y - c.y) / r, above)
    # philtrum notch at the top centre
    notch = 30.0 - np.sqrt(((c.x - ox) / 0.8) ** 2 + (c.y - (oy - 46)) ** 2)
    sdf = np.maximum(best, notch)
    a = cov(sdf)
    base = np.array((0.26, 0.15, 0.08))
    k = np.clip(1.15 - 0.45 * np.clip(core, 0, 1), 0, 2)
    col = base[None, None, :] * k[..., None]
    # sheen on the upper side of each lobe
    sheen = np.clip(above, 0, 1) * np.clip(1.0 - core, 0, 1) * 0.35
    col += np.array((0.55, 0.38, 0.25)) * sheen[..., None]
    # fine combed strands: thin darker lines along the stroke (radial stripes from the lobe centre)
    ang = np.arctan2(c.y - (oy + 20), np.abs(c.x - ox) - 150)
    strand = 0.5 + 0.5 * np.cos(ang * 46.0)
    col *= (1.0 - 0.10 * strand)[..., None]
    c.over(np.clip(col, 0, 1), a)
    c.save(path)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(out, exist_ok=True)
    make_nose(os.path.join(out, "sticker_nose.png"))
    make_glasses(os.path.join(out, "sticker_glasses.png"))
    make_mustache(os.path.join(out, "sticker_mustache.png"))
    print("wrote", out)


if __name__ == "__main__":
    main()
