#!/usr/bin/env python3
"""Generate LocalLink Android brand assets (launcher icons + splash logos).

Brand: blue -> cyan diagonal gradient (LocalLinkBrand.heroGradient tokens:
#1E5BFF -> #23E0D8, topLeft -> bottomRight). Glyph: white chat bubble with a
link glyph (two interlocked rings). On the legacy tile and the splash logo the
rings are filled with the brand gradient; on the adaptive foreground the rings
are knocked out so the launcher-provided background shows through.

Also writes the Flutter-side splash asset (assets/brand/splash_logo.png).

Idempotent: re-running regenerates all PNGs deterministically.
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
ASSETS = os.path.join(ROOT, 'assets', 'brand')

BLUE = (30, 91, 255)     # #1E5BFF  LocalLinkBrand.gradientStart
CYAN = (35, 224, 216)    # #23E0D8  LocalLinkBrand.gradientEnd
WHITE = (255, 255, 255)

SS = 4  # supersampling factor for crisp edges


def diagonal_gradient(size: int) -> Image.Image:
    """TL blue -> BR cyan diagonal gradient via bilinear resize."""
    base = Image.new('RGB', (2, 2))
    base.putpixel((0, 0), BLUE)
    base.putpixel((1, 1), CYAN)
    mid = tuple((b + c) // 2 for b, c in zip(BLUE, CYAN))
    base.putpixel((1, 0), mid)
    base.putpixel((0, 1), mid)
    return base.resize((size, size), Image.BICUBIC)


def glyph_mask(size: int, scale: float) -> Image.Image:
    """Alpha mask (L) of the chat-bubble body + tail on a 100x100 unit grid."""
    grid = size * SS
    img = Image.new('L', (grid, grid), 0)
    d = ImageDraw.Draw(img)
    s = grid / 100.0
    cx = cy = grid / 2

    def U(x, y):
        return ((x - 50) * scale * s + cx, (y - 50) * scale * s + cy)

    x0, y0 = U(15, 22)
    x1, y1 = U(85, 70)
    d.rounded_rectangle([x0, y0, x1, y1], radius=14 * scale * s, fill=255)
    d.polygon([U(30, 68), U(47, 68), U(31, 88)], fill=255)
    return img


def rings_mask(size: int, scale: float) -> Image.Image:
    """Alpha mask (L) of the two interlocked rings (the 'link')."""
    grid = size * SS
    img = Image.new('L', (grid, grid), 0)
    d = ImageDraw.Draw(img)
    s = grid / 100.0
    cx = cy = grid / 2
    r_ring = 13 * scale * s
    stroke = 6.5 * scale * s
    for cx_u in (42, 58):
        gx = (cx_u - 50) * scale * s + cx
        gy = (46 - 50) * scale * s + cy
        d.ellipse([gx - r_ring, gy - r_ring, gx + r_ring, gy + r_ring],
                  outline=255, width=round(stroke))
    return img


def rounded_mask(size: int, radius_frac: float) -> Image.Image:
    grid = size * SS
    m = Image.new('L', (grid, grid), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [0, 0, grid - 1, grid - 1], radius=grid * radius_frac, fill=255)
    return m


def circle_mask(size: int) -> Image.Image:
    grid = size * SS
    m = Image.new('L', (grid, grid), 0)
    ImageDraw.Draw(m).ellipse([0, 0, grid - 1, grid - 1], fill=255)
    return m


def shrink(img: Image.Image, size: int) -> Image.Image:
    return img.resize((size, size), Image.LANCZOS)


def glyph_layer_raw(size: int, scale: float, knock_out_rings: bool) -> Image.Image:
    """Bubble + rings on the supersampled canvas (size * SS). RGBA."""
    big = size * SS
    grad = diagonal_gradient(big).convert('RGBA')
    bubble = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    bubble.paste(Image.new('RGBA', (big, big), WHITE + (255,)), (0, 0),
                 glyph_mask(size, scale))
    rings = rings_mask(size, scale)
    if knock_out_rings:
        clear = Image.new('RGBA', (big, big), (0, 0, 0, 0))
        bubble.paste(clear, (0, 0), rings)
    else:
        ring_layer = Image.new('RGBA', (big, big), (0, 0, 0, 0))
        ring_layer.paste(grad, (0, 0), rings)  # rings take the brand gradient
        bubble = Image.alpha_composite(bubble, ring_layer)
    return bubble


def glyph_layer(size: int, scale: float, knock_out_rings: bool) -> Image.Image:
    """Bubble + rings, RGBA. Baked gradient rings, or knocked-out rings."""
    return shrink(glyph_layer_raw(size, scale, knock_out_rings), size)


def legacy_icon(size: int, rounded: bool) -> Image.Image:
    """Full-bleed tile: gradient bg, white bubble, gradient rings."""
    big = size * SS
    grad = diagonal_gradient(big).convert('RGBA')
    mask = rounded_mask(size, 0.22) if rounded else circle_mask(size)
    tile = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    tile.paste(grad, (0, 0), mask)
    return shrink(Image.alpha_composite(tile, glyph_layer_raw(size, 0.86, False)), size)


def foreground(size: int) -> Image.Image:
    """Adaptive foreground: glyph in the 66/108dp safe zone, rings knocked out."""
    return glyph_layer(size, 0.62, True)


def splash_logo(size: int) -> Image.Image:
    """Standalone splash logo: large glyph, baked gradient rings, transparent bg."""
    return glyph_layer(size, 0.94, False)


LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
FORE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
SPLASH = {'mdpi': 150, 'hdpi': 225, 'xhdpi': 300, 'xxhdpi': 450, 'xxxhdpi': 600}


def save(img: Image.Image, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, 'PNG')
    print(f'  wrote {os.path.relpath(path, ROOT)} ({img.width}px)')


def main() -> None:
    print('Generating LocalLink brand assets...')
    for density, px in LEGACY.items():
        save(legacy_icon(px, rounded=True), os.path.join(RES, f'mipmap-{density}', 'ic_launcher.png'))
        save(legacy_icon(px, rounded=False), os.path.join(RES, f'mipmap-{density}', 'ic_launcher_round.png'))
    for density, px in FORE.items():
        save(foreground(px), os.path.join(RES, f'mipmap-{density}', 'ic_launcher_foreground.png'))
    for density, px in SPLASH.items():
        save(splash_logo(px), os.path.join(RES, f'drawable-{density}', 'splash_logo.png'))
    save(splash_logo(SPLASH['xxxhdpi']), os.path.join(ASSETS, 'splash_logo.png'))
    print('Done.')


if __name__ == '__main__':
    main()
