#!/usr/bin/env python3
"""Render every SomaFM channel logo at 16x16, as it would look on the LEDs.

Fetches the logos live and draws each one as round LEDs, with the channel's
signature colour from scripts/somafm_lib.be as a bar on the left of its tile.
The image stays local: the logos belong to SomaFM.

Usage:  python3 tools/logo_sheet.py [docs/logos_16x16.png]
"""
import io
import json
import pathlib
import re
import sys
import urllib.request

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
UA = {"User-Agent": "somafm-awtrix-generator"}
COLUMNS = 9
LED = 8          # pixels per LED
GAP = 22         # space between tiles
LABEL = 18       # height of the name under a tile
BAR = 2 * LED    # signature colour bar, 2 LEDs wide


def fetch(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=20) as r:
        return r.read()


def main():
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs" / "logos_16x16.png"
    table = (ROOT / "scripts" / "somafm_lib.be").read_text(encoding="utf-8")
    colours = {m[0]: int(m[1], 16) for m in re.findall(r'\["([a-z0-9]+)", "[^"]*", "[^"]*", 0x([0-9A-F]{6})\]', table)}
    channels = sorted(json.loads(fetch("https://somafm.com/channels.json"))["channels"], key=lambda c: c["title"].lower())

    tile_w = BAR + LED + 16 * LED
    rows = (len(channels) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGB", (COLUMNS * (tile_w + GAP) + GAP, rows * (16 * LED + LABEL + GAP) + GAP), (18, 18, 18))
    draw = ImageDraw.Draw(sheet)

    failed = []
    for i, c in enumerate(channels):
        x0 = GAP + (i % COLUMNS) * (tile_w + GAP)
        y0 = GAP + (i // COLUMNS) * (16 * LED + LABEL + GAP)
        v = colours.get(c["id"], 0xB4B4B4)
        for ly in range(16):
            for lx in range(2):
                draw.ellipse([x0 + lx * LED + 1, y0 + ly * LED + 1, x0 + lx * LED + LED - 2, y0 + ly * LED + LED - 2],
                             fill=((v >> 16) & 255, (v >> 8) & 255, v & 255))
        try:
            logo = Image.open(io.BytesIO(fetch(c["image"]))).convert("RGB").resize((16, 16), Image.LANCZOS)
        except Exception as e:
            failed.append(f"{c['id']}: {e}")
            logo = None
        lx0 = x0 + BAR + LED
        for ly in range(16):
            for lx in range(16):
                colour = logo.getpixel((lx, ly)) if logo else (40, 40, 40)
                draw.ellipse([lx0 + lx * LED + 1, y0 + ly * LED + 1, lx0 + lx * LED + LED - 2, y0 + ly * LED + LED - 2], fill=colour)
        draw.text((x0, y0 + 16 * LED + 4), c["title"][:27], fill=(215, 215, 215))

    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"{len(channels)} channels -> {out}")
    for f in failed:
        print("failed", f)


if __name__ == "__main__":
    main()
