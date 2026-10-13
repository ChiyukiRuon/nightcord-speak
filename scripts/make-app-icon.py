#!/usr/bin/env python3
"""Builds the application icons from the Nightcord mark.

Three consumers, one drawing:

    Windows   `apps/client/windows/runner/resources/app_icon.ico`
    macOS     `apps/client/macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png`
    Web       `apps/client/web/favicon.png`, `apps/client/web/icons/*.png`

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

Why this is a script and not a one-off: the icons are committed binaries, and a
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
WINDOWS_SIZES = [16, 24, 32, 48, 64, 128, 256]

# macOS names ten slots in `Contents.json` over seven distinct rasters: each size
# is listed twice, once at 1x and again as the 2x of the size below it. So these
# are the files to write, and the manifest says which slot reads which.
MACOS_SIZES = [16, 32, 64, 128, 256, 512, 1024]

# The browser tab, and the home screen the page can be added to. `favicon.png`
# is what `index.html`'s `<link rel="icon">` points at; the larger one is what
# iOS reads as `apple-touch-icon` (Android would want a manifest to go with it,
# which the page does not declare — see the web client docs).
#
# 32 rather than the 16 the Flutter template ships: a tab icon is drawn at the
# device pixel ratio, so the template's size is soft on any HiDPI screen.
WEB_FAVICON = 32
WEB_TOUCH_ICON = 192

# Drawn at this multiple and reduced with LANCZOS. Pillow's `ellipse` has no
# anti-aliasing of its own, and at 16px the two eyes are barely a pixel each —
# they need all the help they can get.
SUPERSAMPLE = 8

# ...but the working canvas is capped, because 8x of 1024 is an 8192-square RGBA
# image — 256 MB to draw five circles into. Past 256px the eyes are tens of
# pixels across and the supersampling has nothing left to smooth, so the cap
# costs nothing: every size Windows packs is still drawn at the full 8x, and the
# macOS rasters above 256 drop to the multiple that fits.
SUPERSAMPLE_CAP = 2048

_ROOT = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
)

ICO_OUT = os.path.join(
    _ROOT, "apps", "client", "windows", "runner", "resources", "app_icon.ico"
)

APPICONSET_OUT = os.path.join(
    _ROOT,
    "apps",
    "client",
    "macos",
    "Runner",
    "Assets.xcassets",
    "AppIcon.appiconset",
)

WEB_OUT = os.path.join(_ROOT, "apps", "client", "web")
WEB_ICONS_OUT = os.path.join(WEB_OUT, "icons")


def factors(size: int) -> int:
    """The supersample factor to draw `size` at."""
    return max(1, min(SUPERSAMPLE, SUPERSAMPLE_CAP // size))


def draw(size: int) -> Image.Image:
    """Renders the mark at `size` pixels square, on transparency."""
    factor = factors(size)
    scale = size * factor / BOX
    canvas = Image.new("RGBA", (size * factor, size * factor), (0, 0, 0, 0))
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


def render_all() -> dict[int, Image.Image]:
    """Draws every size any consumer asks for, once each.

    16 and 32 are wanted by more than one, and they are the two slowest to get
    right, so they are drawn once and shared rather than twice and compared.
    """
    wanted = sorted(set(WINDOWS_SIZES) | set(MACOS_SIZES) | {WEB_FAVICON, WEB_TOUCH_ICON})
    return {size: draw(size) for size in wanted}


def write_ico(rendered: dict[int, Image.Image]) -> None:
    frames = [rendered[size] for size in WINDOWS_SIZES]

    # `append_images` keeps each size as rendered. Pillow's `sizes=` argument
    # would instead resample the single largest image down to 16px, which is
    # exactly the size that needs to be drawn rather than shrunk.
    buffer = io.BytesIO()
    frames[-1].save(
        buffer, format="ICO", append_images=frames[:-1], sizes=[(s, s) for s in WINDOWS_SIZES]
    )

    with open(ICO_OUT, "wb") as handle:
        handle.write(buffer.getvalue())

    print(f"wrote {ICO_OUT}")
    for size in WINDOWS_SIZES:
        print(f"  {size}x{size}")


def write_appiconset(rendered: dict[int, Image.Image]) -> None:
    """Writes the PNGs `Contents.json` names. The manifest is not touched.

    It is the template's, and it already lists exactly these seven files in the
    ten slots macOS wants — regenerating it here would be a second opinion about
    a file that has one job.
    """
    print(f"wrote {APPICONSET_OUT}")
    for size in MACOS_SIZES:
        path = os.path.join(APPICONSET_OUT, f"app_icon_{size}.png")
        rendered[size].save(path, format="PNG")
        print(f"  app_icon_{size}.png")


def write_web(rendered: dict[int, Image.Image]) -> None:
    """Writes what `index.html` links to.

    Transparent, like the other two: iOS composites a transparent home-screen
    icon onto black, which is a shade off the app's own #242034 background and
    the same shape the mark already keeps on a dark taskbar.
    """
    os.makedirs(WEB_ICONS_OUT, exist_ok=True)

    favicon = os.path.join(WEB_OUT, "favicon.png")
    rendered[WEB_FAVICON].save(favicon, format="PNG")
    print(f"wrote {favicon}")
    print(f"  favicon.png ({WEB_FAVICON}x{WEB_FAVICON})")

    touch = os.path.join(WEB_ICONS_OUT, f"Icon-{WEB_TOUCH_ICON}.png")
    rendered[WEB_TOUCH_ICON].save(touch, format="PNG")
    print(f"  Icon-{WEB_TOUCH_ICON}.png")


def main() -> None:
    rendered = render_all()
    write_ico(rendered)
    write_appiconset(rendered)
    write_web(rendered)


if __name__ == "__main__":
    main()
