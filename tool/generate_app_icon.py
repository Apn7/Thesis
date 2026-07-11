#!/usr/bin/env python3
"""Generate the SmartCane launcher icon.

Design: white cane (international symbol of blindness — white shaft, red
band near the tip, dark grip) on a deep-teal gradient, with amber sonar
arcs radiating from the sensor end. Colors follow lib/core/theme/
app_colors.dart (primary #00BCD4 family, accent #FFB300).

Outputs:
  assets/icon/app_icon.png                      1024x1024 master
  android/app/src/main/res/mipmap-*/ic_launcher.png
  windows/runner/resources/app_icon.ico

Run from the app root:  python3 tool/generate_app_icon.py
"""

import math
import os

from PIL import Image, ImageDraw

S = 4  # supersample factor
SIZE = 1024
C = SIZE * S  # canvas size

# Palette (from app_colors.dart)
TEAL_TOP = (0, 188, 212)  # primary #00BCD4
TEAL_BOTTOM = (0, 54, 61)  # deep shade of primaryDark
AMBER = (255, 179, 0)  # accent #FFB300
WHITE = (255, 255, 255)
RED = (244, 67, 54)  # error/red band #F44336
GRIP = (38, 50, 56)  # blueGrey 900


def sc(v):
    return int(round(v * S))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def make_background():
    """Diagonal teal gradient (corners rounded at the end, post-draw)."""
    # Small gradient, then upscale — smooth and cheap.
    g = Image.new("RGB", (64, 64))
    px = g.load()
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126.0
            px[x, y] = lerp(TEAL_TOP, TEAL_BOTTOM, t)
    return g.resize((C, C), Image.LANCZOS).convert("RGBA")


def round_corners(img):
    """Apply the rounded-rect alpha mask to the finished composition, so
    no stroke can paint outside the corner radius."""
    mask = Image.new("L", (C, C), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, C - 1, C - 1], radius=sc(180), fill=255
    )
    out = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def thick_segment(draw, p1, p2, width, color):
    """Line with round caps."""
    draw.line([p1, p2], fill=color, width=width)
    r = width // 2
    for p in (p1, p2):
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=color)


def along(p1, p2, t):
    return (p1[0] + (p2[0] - p1[0]) * t, p1[1] + (p2[1] - p1[1]) * t)


def main():
    img = make_background()
    draw = ImageDraw.Draw(img)

    # Cane: handle top-left-of-center, tip bottom-right. Sensor at the top.
    top = (sc(392), sc(268))
    tip = (sc(600), sc(884))
    w = sc(92)

    # Sonar arcs radiate from the sensor end toward the upper right.
    cx, cy = sc(430), sc(300)
    for radius in (sc(180), sc(300), sc(420)):
        bbox = [cx - radius, cy - radius, cx + radius, cy + radius]
        draw.arc(bbox, start=-72, end=18, fill=AMBER, width=sc(38))

    # White shaft.
    thick_segment(draw, top, tip, w, WHITE)
    # Dark grip: top 22% of the shaft.
    thick_segment(draw, top, along(top, tip, 0.22), w, GRIP)
    # Red band near the tip (72%..84% along), square ends so it reads as
    # a band across the shaft, not a blob.
    draw.line([along(top, tip, 0.72), along(top, tip, 0.84)], fill=RED, width=w)

    # Amber sensor dot on the grip end — ties cane to the arcs.
    r = sc(26)
    draw.ellipse([top[0] - r, top[1] - r, top[0] + r, top[1] + r], fill=AMBER)

    master = round_corners(img).resize((SIZE, SIZE), Image.LANCZOS)

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    icon_dir = os.path.join(root, "assets", "icon")
    os.makedirs(icon_dir, exist_ok=True)
    master.save(os.path.join(icon_dir, "app_icon.png"))

    # Android mipmaps (legacy full-bleed launcher icons).
    densities = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }
    res = os.path.join(root, "android", "app", "src", "main", "res")
    for name, px in densities.items():
        out = master.resize((px, px), Image.LANCZOS)
        out.save(os.path.join(res, f"mipmap-{name}", "ic_launcher.png"))

    # Windows .ico (multi-size).
    ico_sizes = [(s, s) for s in (256, 128, 64, 48, 32, 16)]
    master.save(
        os.path.join(root, "windows", "runner", "resources", "app_icon.ico"),
        sizes=ico_sizes,
    )

    print("wrote master, %d mipmaps, app_icon.ico" % len(densities))


if __name__ == "__main__":
    main()
