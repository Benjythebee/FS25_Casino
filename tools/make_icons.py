"""Draw the mod's textures and save them as uncompressed DDS.

    python tools/make_icons.py

- icon_casino.dds       512x512 mod icon (colour)
- images/menuIcon.dds   256x256 menu tab icon: white glyph on transparent, the game tints it
- images/wheel.dds      512x512 roulette wheel with numbers; pocket i of the wheel order is centred i-1 steps
                        clockwise from the top (CasinoFrame rotates it so the result ends under the pointer)
- images/ball.dds       512x512 transparent layer with the ball at the top, same size as the wheel
- images/leave.dds      128x128 white "leave seat" glyph

Needs Pillow. The DDS writer is inline (32-bit BGRA, no mipmaps), which the GIANTS engine loads as is.
"""

import math
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
MOD = HERE.parent / "FS25_Casino"

WHEEL = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18,
         29, 7, 28, 12, 35, 3, 26]
RED = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}
GOLD = (245, 200, 60, 255)
WHITE = (255, 255, 255, 255)
SCALE = 4  # draw large, then downsample for smooth edges


def save_dds(image, path):
    image = image.convert("RGBA")
    w, h = image.size
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x8  # caps, height, width, pixelformat, pitch
    pixel_format = struct.pack("<II4sIIIII", 32, 0x41, b"\0\0\0\0", 32, 0x00FF0000, 0x0000FF00, 0x000000FF, 0xFF000000)
    header = struct.pack("<4sIIIIII", b"DDS ", 124, flags, h, w, w * 4, 0) + struct.pack("<I", 0) + b"\0" * 44
    header += pixel_format + struct.pack("<IIIII", 0x1000, 0, 0, 0, 0)
    r, g, b, a = image.split()
    data = Image.merge("RGBA", (b, g, r, a)).tobytes()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + data)
    print(f"wrote {path}")


def font(size):
    try:
        return ImageFont.truetype("arialbd.ttf", int(size))
    except OSError:
        return ImageFont.load_default()


def circle(d, c, r, **kwargs):
    d.ellipse([c - r, c - r, c + r, c + r], **kwargs)


def pocket_color(n):
    return (20, 140, 60, 255) if n == 0 else (190, 25, 25, 255) if n in RED else (22, 22, 22, 255)


def draw_pockets(d, c, r_out, r_in):
    step = 360 / len(WHEEL)
    for i, n in enumerate(WHEEL):
        start = -90 - step / 2 + i * step
        d.pieslice([c - r_out, c - r_out, c + r_out, c + r_out], start, start + step, fill=pocket_color(n))
    return step


def wheel_texture(size):
    s = size * SCALE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2

    circle(d, c, s * 0.5, fill=GOLD)
    circle(d, c, s * 0.49, fill=(70, 38, 14, 255))  # wooden rim
    r_out, r_in = s * 0.44, s * 0.29
    circle(d, c, r_out + s * 0.008, fill=GOLD)
    step = draw_pockets(d, c, r_out, r_in)

    # gold frets between pockets
    for i in range(len(WHEEL)):
        a = math.radians(-90 - step / 2 + i * step)
        d.line([c + math.cos(a) * r_in, c + math.sin(a) * r_in, c + math.cos(a) * r_out, c + math.sin(a) * r_out],
               fill=GOLD, width=int(s * 0.004))

    # numbers, upright when their pocket is at the top
    f = font(s * 0.048)
    for i, n in enumerate(WHEEL):
        label = Image.new("RGBA", (int(s * 0.09), int(s * 0.07)), (0, 0, 0, 0))
        ld = ImageDraw.Draw(label)
        box = ld.textbbox((0, 0), str(n), font=f)
        ld.text(((label.width - (box[2] - box[0])) / 2 - box[0], (label.height - (box[3] - box[1])) / 2 - box[1]), str(n),
                font=f, fill=WHITE)
        angle = i * step  # clockwise from the top
        label = label.rotate(-angle, expand=True, resample=Image.BICUBIC)
        r = s * 0.395
        x = c + math.sin(math.radians(angle)) * r - label.width / 2
        y = c - math.cos(math.radians(angle)) * r - label.height / 2
        img.alpha_composite(label, (int(x), int(y)))

    # inner cone, turret and hub (the result number is drawn on the hub by the GUI)
    circle(d, c, r_in, fill=GOLD)
    circle(d, c, r_in - s * 0.008, fill=(120, 72, 28, 255))
    circle(d, c, s * 0.2, fill=(95, 55, 20, 255))
    for k in range(4):
        a = math.radians(45 + k * 90)
        d.line([c + math.cos(a) * s * 0.13, c + math.sin(a) * s * 0.13, c + math.cos(a) * r_in * 0.96,
                c + math.sin(a) * r_in * 0.96], fill=GOLD, width=int(s * 0.018))
    circle(d, c, s * 0.135, fill=GOLD)
    circle(d, c, s * 0.122, fill=(25, 25, 25, 255))

    return img.resize((size, size), Image.LANCZOS)


def ball_texture(size):
    s = size * SCALE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    by = c - s * 0.335
    r = s * 0.026
    d.ellipse([c - r * 1.25, by - r * 1.15, c + r * 1.25, by + r * 1.35], fill=(0, 0, 0, 110))  # shadow
    d.ellipse([c - r, by - r, c + r, by + r], fill=(235, 235, 235, 255))
    d.ellipse([c - r * 0.45, by - r * 0.6, c + r * 0.05, by - r * 0.1], fill=(255, 255, 255, 255))  # highlight
    return img.resize((size, size), Image.LANCZOS)


def tab_glyph(size):
    s = size * SCALE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    circle(d, c, s * 0.46, fill=WHITE)
    circle(d, c, s * 0.38, fill=(0, 0, 0, 0))
    # alternate pockets as notches in the ring
    for i in range(0, 18):
        a = math.radians(i * 20)
        d.line([c + math.cos(a) * s * 0.38, c + math.sin(a) * s * 0.38, c + math.cos(a) * s * 0.46,
                c + math.sin(a) * s * 0.46], fill=(0, 0, 0, 0), width=int(s * 0.035))
    circle(d, c, s * 0.33, fill=WHITE)
    circle(d, c, s * 0.25, fill=(0, 0, 0, 0))
    for k in range(4):
        a = math.radians(45 + k * 90)
        d.line([c, c, c + math.cos(a) * s * 0.26, c + math.sin(a) * s * 0.26], fill=WHITE, width=int(s * 0.06))
    circle(d, c, s * 0.08, fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


def leave_glyph(size):
    s = size * SCALE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = int(s * 0.08)
    # open door frame on the left, arrow pointing out to the right
    d.line([s * 0.55, s * 0.18, s * 0.18, s * 0.18, s * 0.18, s * 0.82, s * 0.55, s * 0.82], fill=WHITE, width=w, joint="curve")
    d.line([s * 0.55, s * 0.14, s * 0.55, s * 0.30], fill=WHITE, width=w)
    d.line([s * 0.55, s * 0.70, s * 0.55, s * 0.86], fill=WHITE, width=w)
    d.line([s * 0.38, s * 0.5, s * 0.82, s * 0.5], fill=WHITE, width=w)
    d.polygon([(s * 0.92, s * 0.5), (s * 0.70, s * 0.33), (s * 0.70, s * 0.67)], fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)


def mod_icon(size):
    s = size * SCALE
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=s * 0.08, fill=(10, 60, 30, 255))
    wheel = wheel_texture(int(size * 0.92)).resize((int(s * 0.92), int(s * 0.92)), Image.LANCZOS)
    img.alpha_composite(wheel, (int(s * 0.04), int(s * 0.02)))
    ball = ball_texture(int(size * 0.92)).resize((int(s * 0.92), int(s * 0.92)), Image.LANCZOS)
    img.alpha_composite(ball, (int(s * 0.04), int(s * 0.02)))
    f = font(s * 0.13)
    text = "CASINO"
    box = d.textbbox((0, 0), text, font=f)
    tw, th = box[2] - box[0], box[3] - box[1]
    x, y = s / 2 - tw / 2, s * 0.92 - th
    d.rounded_rectangle([x - s * 0.04, y - s * 0.03, x + tw + s * 0.04, y + th + s * 0.05], radius=s * 0.03, fill=(0, 0, 0, 210))
    d.text((x - box[0], y - box[1]), text, font=f, fill=GOLD)
    return img.resize((size, size), Image.LANCZOS)


def main():
    icon = mod_icon(512)
    save_dds(icon, MOD / "icon_casino.dds")
    save_dds(tab_glyph(256), MOD / "images" / "menuIcon.dds")
    wheel = wheel_texture(512)
    save_dds(wheel, MOD / "images" / "wheel.dds")
    ball = ball_texture(512)
    save_dds(ball, MOD / "images" / "ball.dds")
    save_dds(leave_glyph(128), MOD / "images" / "leave.dds")

    # previews (gitignored)
    icon.save(HERE / "icon_preview.png")
    preview = Image.new("RGBA", (512 * 2 + 256 + 128, 512), (40, 40, 40, 255))
    preview.alpha_composite(wheel, (0, 0))
    combined = wheel.copy()
    combined.alpha_composite(ball)
    preview.alpha_composite(combined, (512, 0))
    preview.alpha_composite(tab_glyph(256), (1024, 0))
    preview.alpha_composite(leave_glyph(128), (1280, 0))
    preview.save(HERE / "textures_preview.png")


if __name__ == "__main__":
    main()
