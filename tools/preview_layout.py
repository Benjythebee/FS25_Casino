"""Rough preview of gui/CasinoFrame.xml: draws every element box of the content area with its profile colour.

    python tools/preview_layout.py   ->  tools/layout_preview.png

Only for checking positions and overlaps; text is drawn with a default font and states are not simulated.
"""

import re
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
MOD = HERE.parent / "FS25_Casino"

profiles = {}
for p in ET.parse(MOD / "gui" / "guiProfiles.xml").getroot().iter("Profile"):
    color = p.find("imageColor")
    profiles[p.get("name")] = (p.get("extends"), color.get("value") if color is not None else None)


def profile_color(name):
    while name in profiles:
        parent, value = profiles[name]
        if value is not None and not value.startswith("$"):
            r, g, b, a = (float(v) for v in value.split())
            return int(r * 255), int(g * 255), int(b * 255), int(a * 255)
        name = parent
    return None


def px(value):
    return [int(v) for v in re.findall(r"-?\d+", value)]


root = ET.parse(MOD / "gui" / "CasinoFrame.xml").getroot()
content = next(e for e in root.iter("GuiElement") if e.get("profile") == "casinoContent")

TEXTURES = {"casinoWheel": "wheel.dds", "casinoBall": "ball.dds", "icon": "leave.dds"}  # set from Lua in game

img = Image.new("RGBA", (1550, 830), (40, 44, 40, 255))
draw = ImageDraw.Draw(img, "RGBA")


def visit(element, ox, oy):
    for child in element:
        x, y = px(child.get("position", "0px 0px"))
        w, h = px(child.get("size", "0px 0px"))
        ax, ay = ox + x, oy - y
        profile = child.get("profile", "")
        color = profile_color(profile)
        hidden = profile in ("casinoCellWin",) or profile.startswith("casinoDot")
        texture = TEXTURES.get(child.get("id") or child.get("name") or "")
        if texture is not None:
            img.alpha_composite(Image.open(MOD / "images" / texture).convert("RGBA").resize((w, h)), (ax, ay))
        elif child.tag in ("Bitmap", "Button") and color is not None and not hidden and color[3] > 0:
            draw.rectangle([ax, ay, ax + w - 1, ay + h - 1], fill=color)
        if child.tag == "Button" and profile == "casinoButton":
            draw.rectangle([ax, ay, ax + w - 1, ay + h - 1], outline=(120, 160, 60, 255))
        label = child.get("text", "")
        if child.tag in ("Text", "Button") and label:
            label = label.replace("$l10n_casino_", "").replace("$l10n_", "")
            draw.text((ax + 4, ay + max(0, h // 2 - 6)), label, fill=(255, 255, 255, 255))
        if child.tag == "Text" and not label:
            draw.rectangle([ax, ay, ax + w - 1, ay + h - 1], outline=(90, 90, 140, 255))
        visit(child, ax, ay)


visit(content, 0, 0)
out = HERE / "layout_preview.png"
img.save(out)
print(f"wrote {out}")
