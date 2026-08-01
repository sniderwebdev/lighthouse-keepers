#!/usr/bin/env python3
"""The two M10 art acceptance checks, scripted.

    tools/check_art.py            # prints a report, exits non-zero on failure

1. PALETTE — every non-transparent pixel in every generated sprite must be a hex
   from the locked ramps in DESIGN.md §6. The ramps are the art direction; a
   colour that is nearly right is the one that makes a scene look muddy and
   nobody can say why.

2. SILHOUETTE — the two keepers must stay tellable apart as grayscale thumbnails
   at 50% scale, i.e. with colour and half the resolution thrown away. That is
   the state they are actually in at 640x360 during a dark tide phase, which is
   exactly when it matters that you can find your partner.
"""
import os
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
KEEPERS = os.path.join(ROOT, "godot", "assets", "art", "keepers")

# DESIGN.md §6, verbatim and in order. Nothing may be outside this set.
RAMPS = {
    "dusk sky": ["#191536", "#241d47", "#33265a", "#47336d", "#61437e",
                 "#82558a", "#ab6a85", "#d98d78", "#f2ae80"],
    "sea": ["#244b58", "#2c5d6b", "#35707c", "#3f818b", "#f2b285", "#d8ecdf"],
    "warm story accents": ["#f6c752", "#f2c14e", "#ffd97a", "#fff3c4"],
    "keeper reds": ["#c0473b", "#c14a3d"],
    "structure neutrals": ["#ece2d0", "#3a3340", "#453c4a"],
    "rock/ground": ["#1f1b29", "#322c3d", "#3a3347", "#4d4560", "#565070"],
    "life greens": ["#2f4a38", "#3d5f4c"],
    "creature corals": ["#d2603f", "#cf6f57", "#e88a6a"],
}
ALLOWED = {h.lower() for ramp in RAMPS.values() for h in ramp}

FRAME_W, FRAME_H = 16, 24
COLS, ROWS = 8, 3

failures = []
passes = []


def check(ok, label, detail):
    (passes if ok else failures).append((label, detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}\n        {detail}")


def palette_check(path):
    img = Image.open(path).convert("RGBA")
    off = {}
    for x in range(img.width):
        for y in range(img.height):
            r, g, b, a = img.getpixel((x, y))
            if a == 0:
                continue
            hexv = f"#{r:02x}{g:02x}{b:02x}"
            if hexv not in ALLOWED:
                off[hexv] = off.get(hexv, 0) + 1
    name = os.path.basename(path)
    if off:
        worst = sorted(off.items(), key=lambda kv: -kv[1])[:4]
        check(False, f"{name}: every pixel is on a locked ramp",
              f"{len(off)} off-ramp hex(es): " + ", ".join(f"{h} x{n}" for h, n in worst))
    else:
        check(True, f"{name}: every pixel is on a locked ramp",
              f"{img.width}x{img.height}, all colours from DESIGN §6")


def frame(img, col, row):
    return img.crop((col * FRAME_W, row * FRAME_H,
                     (col + 1) * FRAME_W, (row + 1) * FRAME_H))


def thumb_gray(im):
    """What the eye gets: colour gone, half the size."""
    flat = Image.new("RGBA", im.size, (0, 0, 0, 0))
    flat.paste(im, (0, 0))
    g = flat.convert("LA").resize((FRAME_W // 2, FRAME_H // 2), Image.NEAREST)
    return g


def silhouette_check(a_path, b_path):
    a = Image.open(a_path).convert("RGBA")
    b = Image.open(b_path).convert("RGBA")
    worst_iou = 0.0
    worst_row = None
    diffs = []
    for row, label in enumerate(["down", "side", "up"]):
        ga, gb = thumb_gray(frame(a, 0, row)), thumb_gray(frame(b, 0, row))
        pa, pb = ga.load(), gb.load()
        inter = union = 0
        gray_delta = 0
        n = 0
        for x in range(ga.width):
            for y in range(ga.height):
                la, aa = pa[x, y]
                lb, ab = pb[x, y]
                sa, sb = aa > 0, ab > 0
                inter += 1 if (sa and sb) else 0
                union += 1 if (sa or sb) else 0
                if sa or sb:
                    gray_delta += abs((la if sa else 0) - (lb if sb else 0))
                    n += 1
        iou = inter / union if union else 1.0
        diffs.append(gray_delta / n if n else 0)
        if iou > worst_iou:
            worst_iou, worst_row = iou, label

    # Two figures of the same species will always overlap somewhat; what must not
    # happen is near-identity. 0.85 is the line: above it the outlines are the
    # same drawing in two colours, which is precisely what colour-blind dusk
    # rendering would erase.
    check(worst_iou < 0.85,
          "the two keepers differ in silhouette alone at 50% grayscale",
          f"worst overlap {worst_iou:.2f} (on the {worst_row} frame); "
          f"limit 0.85, lower is more distinct")
    mean_delta = sum(diffs) / len(diffs)
    check(mean_delta > 12.0,
          "and they differ in value, not just in hue",
          f"mean grayscale difference {mean_delta:.1f} of 255; floor 12.0")


def grid_check(path):
    img = Image.open(path)
    ok = img.size == (FRAME_W * COLS, FRAME_H * ROWS)
    check(ok, f"{os.path.basename(path)}: matches the documented frame grid",
          f"{img.width}x{img.height}, expected {FRAME_W * COLS}x{FRAME_H * ROWS} "
          f"({COLS} cols x {ROWS} rows of {FRAME_W}x{FRAME_H})")


def main():
    a = os.path.join(KEEPERS, "keeper_a.png")
    b = os.path.join(KEEPERS, "keeper_b.png")
    for p in (a, b):
        if not os.path.exists(p):
            print(f"  FAIL  missing sheet\n        {p}")
            return 1

    print("=" * 62)
    print("M10 art AC — palette and silhouette")
    print("=" * 62)
    for p in (a, b):
        grid_check(p)
    for p in (a, b):
        palette_check(p)
    silhouette_check(a, b)

    print()
    print(f"art result: {len(passes)} passed, {len(failures)} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
