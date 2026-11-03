"""Minimal block-compressed DDS writer: BC1 (DXT1, opaque) and BC3 (DXT5, with alpha), no mipmaps.

The game logs a "raw format" warning for uncompressed textures and ModHub requires BC1/BC3/BC7, so all textures of
the mod go through here. Endpoints come from a weighted principal-axis fit per 4x4 block, refined once by least
squares; good enough for flat UI graphics.

    from dds import save_bc1, save_bc3
"""

import struct

import numpy as np

DDSD_CAPS, DDSD_HEIGHT, DDSD_WIDTH, DDSD_PIXELFORMAT, DDSD_LINEARSIZE = 0x1, 0x2, 0x4, 0x1000, 0x80000
DDPF_FOURCC = 0x4
DDSCAPS_TEXTURE = 0x1000


def _blocks(image):
    """RGBA image -> float array (blocks, 16, 4), blocks in row-major order"""
    a = np.asarray(image.convert("RGBA"), dtype=np.float64)
    h, w = a.shape[:2]
    assert h % 4 == 0 and w % 4 == 0, "texture size must be a multiple of 4"
    a = a.reshape(h // 4, 4, w // 4, 4, 4).transpose(0, 2, 1, 3, 4)
    return a.reshape(-1, 16, 4), w, h


def _to565(c):
    c = np.clip(np.rint(c), 0, 255)
    return ((c[..., 0].astype(np.uint32) * 31 + 127) // 255) << 11 | \
           ((c[..., 1].astype(np.uint32) * 63 + 127) // 255) << 5 | \
           ((c[..., 2].astype(np.uint32) * 31 + 127) // 255)


def _from565(v):
    r = (v >> 11) & 31
    g = (v >> 5) & 63
    b = v & 31
    return np.stack([(r * 255 + 15) // 31, (g * 255 + 31) // 63, (b * 255 + 15) // 31], axis=-1).astype(np.float64)


def _palette(e0, e1):
    c0, c1 = _from565(e0), _from565(e1)
    return np.stack([c0, c1, (2 * c0 + c1) / 3, (c0 + 2 * c1) / 3], axis=1)  # (n, 4, 3)


def _nearest(rgb, palette):
    d = ((rgb[:, :, None, :] - palette[:, None, :, :]) ** 2).sum(-1)  # (n, 16, 4)
    return d.argmin(-1), d.min(-1)


def _color_blocks(rgb, weight):
    """rgb (n, 16, 3), weight (n, 16) -> uint16 c0, uint16 c1, uint32 indices, all 4-colour mode (c0 > c1)"""
    w = weight[:, :, None] + 1e-6
    mean = (rgb * w).sum(1) / w.sum(1)
    centred = (rgb - mean[:, None, :]) * np.sqrt(w)
    cov = np.einsum("nki,nkj->nij", centred, centred)
    axis = np.ones((len(rgb), 3))
    for _ in range(8):  # power iteration for the principal axis
        axis = np.einsum("nij,nj->ni", cov, axis)
        axis /= np.linalg.norm(axis, axis=1, keepdims=True) + 1e-12
    proj = np.einsum("nki,ni->nk", rgb - mean[:, None, :], axis)
    visible = weight > 0  # fully transparent pixels don't pull the endpoints
    lo = np.where(visible, proj, np.inf).min(1)
    hi = np.where(visible, proj, -np.inf).max(1)
    lo, hi = np.where(np.isfinite(lo), lo, 0.0), np.where(np.isfinite(hi), hi, 0.0)
    start = mean + axis * hi[:, None]
    end = mean + axis * lo[:, None]

    e0, e1 = _to565(start), _to565(end)
    index, _ = _nearest(rgb, _palette(e0, e1))

    # one least-squares refit of the endpoints for the chosen indices
    t = np.array([0.0, 1.0, 1 / 3, 2 / 3])[index]  # weight of c1
    a, b = (1 - t), t
    ww = weight + 1e-6
    aa, bb, ab = (ww * a * a).sum(1), (ww * b * b).sum(1), (ww * a * b).sum(1)
    ax = (ww[:, :, None] * a[:, :, None] * rgb).sum(1)
    bx = (ww[:, :, None] * b[:, :, None] * rgb).sum(1)
    det = aa * bb - ab * ab
    ok = np.abs(det) > 1e-9
    r0 = np.where(ok[:, None], (ax * bb[:, None] - bx * ab[:, None]) / np.where(ok, det, 1)[:, None], start)
    r1 = np.where(ok[:, None], (bx * aa[:, None] - ax * ab[:, None]) / np.where(ok, det, 1)[:, None], end)
    f0, f1 = _to565(r0), _to565(r1)
    index2, err2 = _nearest(rgb, _palette(f0, f1))
    _, err1 = _nearest(rgb, _palette(e0, e1))
    better = ((err2 * ww).sum(1) < (err1 * ww).sum(1))
    e0, e1 = np.where(better, f0, e0), np.where(better, f1, e1)
    index = np.where(better[:, None], index2, index)

    # BC1 needs c0 > c1 for the 4-colour mode: swap endpoints (and indices 0<->1, 2<->3) where needed
    swap = e0 < e1
    e0, e1 = np.where(swap, e1, e0), np.where(swap, e0, e1)
    index = np.where(swap[:, None], index ^ 1, index)
    same = e0 == e1
    index = np.where(same[:, None], 0, index)

    bits = (index.astype(np.uint64) << (2 * np.arange(16, dtype=np.uint64))).sum(1).astype(np.uint32)
    return e0.astype(np.uint16), e1.astype(np.uint16), bits


def _alpha_blocks(alpha):
    """alpha (n, 16) -> a0, a1 (uint8, 8-value mode a0 > a1) and 48-bit indices"""
    a0 = alpha.max(1)
    a1 = alpha.min(1)
    values = np.empty((len(alpha), 8))
    values[:, 0], values[:, 1] = a0, a1
    for i in range(1, 7):
        values[:, i + 1] = ((7 - i) * a0 + i * a1) / 7
    index = np.abs(alpha[:, :, None] - values[:, None, :]).argmin(-1)
    index = np.where((a0 == a1)[:, None], 0, index)
    bits = (index.astype(np.uint64) << (3 * np.arange(16, dtype=np.uint64))).sum(1)
    return a0.astype(np.uint8), a1.astype(np.uint8), bits


def _header(w, h, fourcc, linear_size):
    flags = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT | DDSD_LINEARSIZE
    header = struct.pack("<4sIIIIII", b"DDS ", 124, flags, h, w, linear_size, 0) + struct.pack("<I", 0) + b"\0" * 44
    header += struct.pack("<II4sIIIII", 32, DDPF_FOURCC, fourcc, 0, 0, 0, 0, 0)
    header += struct.pack("<IIIII", DDSCAPS_TEXTURE, 0, 0, 0, 0)
    return header


def save_bc1(image, path):
    blocks, w, h = _blocks(image)
    c0, c1, bits = _color_blocks(blocks[:, :, :3], np.ones(blocks.shape[:2]))
    data = np.zeros(len(blocks), dtype=[("c0", "<u2"), ("c1", "<u2"), ("i", "<u4")])
    data["c0"], data["c1"], data["i"] = c0, c1, bits
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(_header(w, h, b"DXT1", data.nbytes) + data.tobytes())
    print(f"wrote {path} (BC1)")


def save_bc3(image, path):
    blocks, w, h = _blocks(image)
    alpha = blocks[:, :, 3]
    a0, a1, abits = _alpha_blocks(alpha)
    c0, c1, cbits = _color_blocks(blocks[:, :, :3], alpha / 255.0)
    data = np.zeros(len(blocks), dtype=[("a0", "u1"), ("a1", "u1"), ("ai", "u1", 6), ("c0", "<u2"), ("c1", "<u2"), ("i", "<u4")])
    data["a0"], data["a1"] = a0, a1
    data["ai"] = np.stack([(abits >> np.uint64(8 * k)) & np.uint64(0xFF) for k in range(6)], axis=1).astype(np.uint8)
    data["c0"], data["c1"], data["i"] = c0, c1, cbits
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(_header(w, h, b"DXT5", data.nbytes) + data.tobytes())
    print(f"wrote {path} (BC3)")
