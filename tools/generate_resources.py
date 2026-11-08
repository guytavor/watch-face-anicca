"""Generate Anicca's resources from the fonts in fonts/ and the shapes of the browser design.

- Bitmap fonts (AngelCode BMFont) for the date, readings and the word below the time.
  Each font is cropped so that a reference glyph ("H", or "x" for lowercase) fills the
  line: VCENTER then centers capitals (or the x-height) on the given y.
- The time's points of light: every digit and the colon of Jost at 148 px, sampled on a
  3 px grid, as resources/jsonData/glyph_*.json ([advance, packed point pairs...]).
- source/Generated.mc: the bodhi leaf, heart icon and glyph metrics as constants.
- resources/drawables/launcher_icon.png.

Usage: python3 tools/generate_resources.py   (needs Pillow)
"""

import json
import math
import pathlib

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
JOST = ROOT / "fonts" / "Jost.ttf"
SPECTRAL_ITALIC = ROOT / "fonts" / "Spectral-LightItalic.ttf"
FONT_DIRECTORY = ROOT / "resources" / "fonts"
JSON_DIRECTORY = ROOT / "resources" / "jsonData"
GENERATED_SOURCE = ROOT / "source" / "Generated.mc"
ICON = ROOT / "resources" / "drawables" / "launcher_icon.png"
ATLAS_WIDTH = 512
PADDING = 2

UPPERCASE = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
LOWERCASE = "abcdefghijklmnopqrstuvwxyz"
DIGITS = "0123456789"

# The design draws small text at 13-16 px on a 454 px canvas shown about 2.5 times larger
# than the watch's screen; these sizes keep it legible on the wrist.
# name, font file, weight (variable fonts), pixel size, characters, letter spacing, reference glyph (centered
# vertically by TEXT_JUSTIFY_VCENTER)
FONTS = [
    ("date", JOST, 500, 17, UPPERCASE + DIGITS + " ", 4, "H"),
    ("data", JOST, 400, 21, DIGITS + ":,-", 0, "H"),
    ("word", SPECTRAL_ITALIC, None, 36, "anic", 0, "x"),
    ("breath", SPECTRAL_ITALIC, None, 28, "observthba ", 0, "x"),
]

TIME_SIZE = 148
TIME_WEIGHT = 400
TIME_GRID = 3
TIME_CHARACTERS = DIGITS + ":"
# Points are stored relative to the glyph's pen position and the top of the capitals, shifted so they are never negative
TIME_Y_PAD = 6
TIME_X_PAD = 6

LEAF_SIZE = 17
HEART_SIZE = 9
LEAF_DOT_SPACING = 4.5


def load_font(path, weight, size):
    font = ImageFont.truetype(str(path), size)
    if weight is not None:
        font.set_variation_by_axes([weight])
    return font


def render_font(name, path, weight, size, characters, letter_spacing, reference):
    font = load_font(path, weight, size)
    # The compiler crops glyphs to the line box, so it is grown evenly above and below the reference glyph until every
    # glyph fits; growing it evenly keeps the reference centered for TEXT_JUSTIFY_VCENTER.
    reference_top, reference_bottom = font.getbbox(reference)[1], font.getbbox(reference)[3]
    boxes = [font.getbbox(character) for character in characters if character != " "]
    overshoot = max([0] + [reference_top - box[1] for box in boxes] + [box[3] - reference_bottom for box in boxes])
    reference_top -= overshoot
    reference_height = reference_bottom + overshoot - reference_top

    glyphs = []
    for character in characters:
        left, top, right, bottom = font.getbbox(character)
        advance = round(font.getlength(character)) + letter_spacing
        if right <= left or bottom <= top:
            glyphs.append((character, None, 0, 0, advance))
            continue
        image = Image.new("L", (right - left, bottom - top), 0)
        ImageDraw.Draw(image).text((-left, -top), character, font=font, fill=255)
        glyphs.append((character, image, left, top - reference_top, advance))

    cursor_x, cursor_y, row_height = PADDING, PADDING, 0
    placements = []
    for character, image, x_offset, y_offset, advance in glyphs:
        width, height = image.size if image else (0, 0)
        if cursor_x + width + PADDING > ATLAS_WIDTH:
            cursor_x, cursor_y = PADDING, cursor_y + row_height + PADDING
            row_height = 0
        placements.append((character, image, cursor_x, cursor_y, x_offset, y_offset, advance))
        cursor_x += width + PADDING
        row_height = max(row_height, height)
    atlas_height = cursor_y + row_height + PADDING

    alpha = Image.new("L", (ATLAS_WIDTH, atlas_height), 0)
    for _, image, x, y, _, _, _ in placements:
        if image:
            alpha.paste(image, (x, y))
    Image.merge("RGB", (alpha, alpha, alpha)).save(FONT_DIRECTORY / f"{name}.png")

    lines = [
        f'info face="{name}" size={size} bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=0,0',
        f"common lineHeight={reference_height} base={reference_height} scaleW={ATLAS_WIDTH} scaleH={atlas_height} pages=1 packed=0",
        f'page id=0 file="{name}.png"',
        f"chars count={len(placements)}",
    ]
    for character, image, x, y, x_offset, y_offset, advance in placements:
        width, height = image.size if image else (0, 0)
        lines.append(
            f"char id={ord(character)} x={x} y={y} width={width} height={height} "
            f"xoffset={x_offset} yoffset={y_offset} xadvance={advance} page=0 chnl=15"
        )
    (FONT_DIRECTORY / f"{name}.fnt").write_text("\n".join(lines) + "\n")
    print(f"font {name}: size {size}, reference height {reference_height}")


def render_time_glyphs():
    """Sample each time glyph on a grid; returns the cap height of the time font."""
    font = load_font(JOST, TIME_WEIGHT, TIME_SIZE)
    cap_top = font.getbbox("H")[1]
    cap_height = font.getbbox("H")[3] - cap_top
    for character in TIME_CHARACTERS:
        left, top, right, bottom = font.getbbox(character)
        image = Image.new("L", (right - left, bottom - top), 0)
        ImageDraw.Draw(image).text((-left, -top), character, font=font, fill=255)
        pixels = image.load()
        points = []
        for row in range(0, image.size[1], TIME_GRID):
            for column in range(0, image.size[0], TIME_GRID):
                if pixels[column, row] > 140:
                    x = left + column + TIME_X_PAD
                    y = top - cap_top + row + TIME_Y_PAD
                    assert 0 <= x < 128 and 0 <= y < 128, (character, x, y)
                    points.append((x << 7) | y)
        if len(points) % 2:
            points.append(points[-1])
        packed = [(points[i] << 14) | points[i + 1] for i in range(0, len(points), 2)]
        advance = round(font.getlength(character))
        name = "colon" if character == ":" else character
        (JSON_DIRECTORY / f"glyph_{name}.json").write_text(json.dumps([advance] + packed))
        print(f"glyph {character}: advance {advance}, {len(points)} points")
    return cap_height


# Paths of the browser design, in units of the symbol's size around its center:
# ("M", point), ("C", control, control, end), ("Q", control, end)
LEAF_OUTLINE = [
    ("M", (0, -0.62)),
    ("C", (0.25, -0.98), (0.86, -0.92), (0.82, -0.3)),
    ("C", (0.8, 0.25), (0.26, 0.6), (0.08, 1.0)),
    ("Q", (0.02, 1.25), (-0.05, 1.47)),
    ("Q", (-0.02, 1.2), (-0.08, 1.0)),
    ("C", (-0.26, 0.6), (-0.8, 0.25), (-0.82, -0.3)),
    ("C", (-0.86, -0.92), (-0.25, -0.98), (0, -0.62)),
]
LEAF_MIDRIB = [
    ("M", (0.12, -1.08)),
    ("Q", (0.02, -0.9), (0, -0.62)),
    ("Q", (0.03, 0.5), (-0.05, 1.47)),
]
HEART = [
    ("M", (0, 0.35)),
    ("C", (-0.9, -0.25), (-0.45, -0.85), (0, -0.35)),
    ("C", (0.45, -0.85), (0.9, -0.25), (0, 0.35)),
]


def flatten(path, size, steps=10):
    points = []
    current = None
    for command, *arguments in path:
        if command == "M":
            current = arguments[0]
            points.append(current)
            continue
        for step in range(1, steps + 1):
            t = step / steps
            if command == "C":
                (x1, y1), (x2, y2), (x3, y3) = arguments
                x0, y0 = current
                u = 1 - t
                x = u ** 3 * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t ** 3 * x3
                y = u ** 3 * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t ** 3 * y3
            else:
                (x1, y1), (x2, y2) = arguments
                x0, y0 = current
                u = 1 - t
                x = u * u * x0 + 2 * u * t * x1 + t * t * x2
                y = u * u * y0 + 2 * u * t * y1 + t * t * y2
            points.append((x, y))
        current = arguments[-1]
    return [(x * size, y * size) for x, y in points]


def leaf_half_width(offset):
    profile = [(-0.62, 0.0), (-0.85, 0.45), (-0.3, 0.82), (0.25, 0.7), (0.6, 0.42), (1.0, 0.09), (1.45, 0.0)]
    for i in range(1, len(profile)):
        low_offset, low_width = profile[i - 1]
        high_offset, high_width = profile[i]
        if min(low_offset, high_offset) <= offset <= high_offset:
            fraction = (offset - low_offset) / (high_offset - low_offset)
            return low_width + (high_width - low_width) * fraction
    return 0


def leaf_veins(size):
    veins = []
    for vein in range(6):
        start = -0.48 + vein * 0.22
        end = start - 0.26
        reach = leaf_half_width(end) * 0.82
        if reach < 0.1:
            continue
        for side in (-1, 1):
            veins.append(flatten([("M", (0.01, start)), ("Q", (side * reach * 0.45, start - 0.04), (side * reach, end))], size, 4))
    return veins


def resample(points, spacing):
    """Points every `spacing` pixels along a polyline, like a dotted stroke."""
    dots = [points[0]]
    carry = 0.0
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        length = math.hypot(x1 - x0, y1 - y0)
        distance = spacing - carry
        while distance <= length:
            t = distance / length
            dots.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t))
            distance += spacing
        carry = (carry + length) % spacing
    return dots


def monkey_floats(points):
    return "[" + ", ".join(f"{value:.1f}" for point in points for value in point) + "]"


def write_generated_source(time_cap_height):
    outline = flatten(LEAF_OUTLINE, LEAF_SIZE)
    midrib = flatten(LEAF_MIDRIB, LEAF_SIZE, 6)
    veins = leaf_veins(LEAF_SIZE)
    dots = resample(outline, LEAF_DOT_SPACING) + resample(midrib, LEAF_DOT_SPACING)
    heart = flatten(HEART, HEART_SIZE)
    lines = [
        "// Generated by tools/generate_resources.py; do not edit.",
        "import Toybox.Lang;",
        "",
        f"//! Cap height of the time's 148 px digits; glyph points are stored {TIME_X_PAD} px right and {TIME_Y_PAD} px down",
        f"const TIME_CAP_HEIGHT = {time_cap_height};",
        f"const TIME_X_PAD = {TIME_X_PAD};",
        f"const TIME_Y_PAD = {TIME_Y_PAD};",
        f"const TIME_GRID = {TIME_GRID};",
        "",
        "//! Bodhi leaf polylines as flat [x0, y0, x1, y1, ...] offsets from the leaf's center",
        f"const LEAF_OUTLINE = {monkey_floats(outline)} as Array<Float>;",
        f"const LEAF_MIDRIB = {monkey_floats(midrib)} as Array<Float>;",
        "const LEAF_VEINS = [",
    ]
    lines += [f"    {monkey_floats(vein)}," for vein in veins]
    lines += [
        "] as Array<Array<Float>>;",
        "//! Dots of the leaf's faint dotted outline",
        f"const LEAF_DOTS = {monkey_floats(dots)} as Array<Float>;",
        f"const HEART_OUTLINE = {monkey_floats(heart)} as Array<Float>;",
        "",
    ]
    GENERATED_SOURCE.write_text("\n".join(lines))
    print(f"source: leaf {len(outline)} outline points, {len(dots)} dots, {len(veins)} veins")


def write_icon():
    size = 65
    scale = 4
    image = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((0, 0, size * scale - 1, size * scale - 1), fill=(0, 0, 0, 255))
    leaf_size = 21 * scale
    center = (size * scale / 2, size * scale / 2 - 4 * scale)
    outline = [(center[0] + x, center[1] + y) for x, y in flatten(LEAF_OUTLINE, leaf_size)]
    draw.polygon(outline, fill=(110, 80, 37, 255))
    draw.line(outline + [outline[0]], fill=(217, 160, 74, 255), width=2 * scale, joint="curve")
    midrib = [(center[0] + x, center[1] + y) for x, y in flatten(LEAF_MIDRIB, leaf_size, 6)]
    draw.line(midrib, fill=(217, 160, 74, 255), width=int(1.5 * scale), joint="curve")
    image.resize((size, size), Image.LANCZOS).save(ICON)


def main():
    FONT_DIRECTORY.mkdir(parents=True, exist_ok=True)
    JSON_DIRECTORY.mkdir(parents=True, exist_ok=True)
    for font_definition in FONTS:
        render_font(*font_definition)
    cap_height = render_time_glyphs()
    write_generated_source(cap_height)
    write_icon()


if __name__ == "__main__":
    main()
