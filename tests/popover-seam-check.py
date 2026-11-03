#!/usr/bin/env python3
"""Fails when the popover's arrow and body are not one connected shape of one colour.

Make the pictures without showing anything but the popover for a moment (never flips the Mac's look):
  ./post-test.sh popshot:light    -> /tmp/nox-pop-light.png
  ./post-test.sh popshot:dark     -> /tmp/nox-pop-dark.png
Then:  python3 tests/popover-seam-check.py /tmp/nox-pop-light.png /tmp/nox-pop-dark.png

Walks straight down the middle of the arrow into the body and also along the join on both sides of the
arrow. Any colour step bigger than STEP between neighbouring pixels (a seam or hairline) fails.
"""
import sys
from PIL import Image

STEP = 6  # largest allowed difference per channel between neighbouring pixels (0 to 255)

def worst(px, pts):
    w = 0
    for a, b in zip(pts, pts[1:]):
        w = max(w, max(abs(px[a][i] - px[b][i]) for i in range(3)))
    return w

def check(path):
    im = Image.open(path).convert("RGBA")
    W, H = im.size
    px = im.load()
    cx = W // 2
    top = next((y for y in range(H) if px[cx, y][3] > 200), None)   # first solid pixel: the arrow tip
    if top is None:
        return f"{path}: no popover found"
    body = next((y for y in range(top, H) if px[cx - 80, y][3] > 200), top)   # first solid row away from the arrow
    ys = list(range(top + 2, min(H, body + 40)))
    column = [(cx, y) for y in ys]
    join_l = [(x, body + 2) for x in range(cx - 70, cx - 14)]
    join_r = [(x, body + 2) for x in range(cx + 14, cx + 70)]
    seen = max(worst(px, column), worst(px, join_l), worst(px, join_r))
    return None if seen <= STEP else f"{path}: seam, colour step {seen} (limit {STEP})"

fails = [m for m in (check(p) for p in sys.argv[1:]) if m]
print("\n".join(fails) if fails else "popover arrow and body are one shape: OK")
sys.exit(1 if fails else 0)
