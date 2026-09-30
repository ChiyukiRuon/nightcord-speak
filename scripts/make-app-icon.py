#!/usr/bin/env python3
"""Builds the Windows application icon from the Nightcord mark.

The mark is three circles, so it is drawn here rather than rasterised from the
SVG: there is no SVG renderer in this toolchain, and adding one to draw three
circles would be a heavier dependency than the drawing itself.

**The numbers are the SVG's** (`apps/client/assets/nightcord-logo.svg`), in its
own `viewBox` coordinates:

    outer disc   centre (18.45, 18.45)  r 18.45
    cut-out      centre (22.86, 18.45)  r 13.82   — offset right; that offset is
                                                    what makes it a crescent
    eyes         (17.84, 18.42) and (27.88, 18.42), r 2.2

They are duplicated in `apps/client/lib/design/components/app_logo.dart`, which
draws the same mark on screen. If the logo changes, all three move together.

Why this is a script and not a one-off: the `.ico` is a committed binary, and a
committed binary nobody can regenerate is a binary nobody dares touch. Run it
again after editing the mark.

Usage:
    python scripts/make-app-icon.py
"""

from __future__ import annotations

import io
import os

from PIL import Image, ImageDraw

# The SVG's coordinate system.
BOX = 36.9
OUTER = ((18.45, 18.45), 18.45)
CUTOUT = ((22.86, 18.45), 13.82)
EYES = [((17.84, 18.42), 2.2), ((27.88, 18.42), 2.2)]

# Nightcord's primary (docs/UI设计与配色规范.md §42).
#
# Not the white of the SVG: a white mark on a transparent icon disappears on a
# light taskbar, and the app has a light theme now. A mid-tone purple is
# readable on both — it is about 0.27 relative luminance, so it stands off
# white and off a dark taskbar alike, and it is the colour the brand already is.
COLOUR = (0x8C, 0x82, 0xC2, 255)

# Windows picks the closest of these for the taskbar, the alt-tab list, the
# Explorer thumbnail and the small list views.
SIZES = [16, 24, 32, 48, 64, 128, 256]

# Drawn at this multiple and reduced with LANCZOS. Pillow's `ellipse` has no
# anti-aliasing of its own, and at 16px the two eyes are barely a pixel each —
# they need all the help they can get.
SUPERSAMPLE = 8

OUT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "..",
    "apps",
    "client",
    "windows",
    "runner",
    "resources",
    "app_icon.ico",
)


def draw(size: int) -> Image.Image:
    """Renders the mark at `size` pixels square, on transparency."""
    scale = size * SUPERSAMPLE / BOX
    canvas = Image.new("RGBA", (size * SUPERSAMPLE, size * SUPERSAMPLE), (0, 0, 0, 0))
    pen = ImageDraw.Draw(canvas)

    def disc(centre: tuple[float, float], radius: float, fill) -> None:
        cx, cy = centre[0] * scale, centre[1] * scale
        r = radius * scale
        pen.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill)

    # The crescent, in two passes rather than even-odd: fill the outer disc,
    # then punch the cut-out back out by writing fully transparent pixels into
    # it. Same result, and `ImageDraw` has no fill rule to reach for. The eyes
    # go on after, so they land *inside* the hole.
    disc(*OUTER, fill=COLOUR)
    disc(*CUTOUT, fill=(0, 0, 0, 0))
    for eye in EYES:
        disc(*eye, fill=COLOUR)

    return canvas.resize((size, size), Image.LANCZOS)


def main() -> None:
    frames = [draw(size) for size in SIZES]

    # `append_images` keeps each size as rendered. Pillow's `sizes=` argument
    # would instead resample the single largest image down to 16px, which is
    # exactly the size that needs to be drawn rather than shrunk.
    buffer = io.BytesIO()
    frames[-1].save(buffer, format="ICO", append_images=frames[:-1], sizes=[(s, s) for s in SIZES])

    out = os.path.normpath(OUT)
    with open(out, "wb") as handle:
        handle.write(buffer.getvalue())

    print(f"wrote {out}")
    for size, frame in zip(SIZES, frames, strict=True):
        print(f"  {size}x{size}")


if __name__ == "__main__":
    main()
