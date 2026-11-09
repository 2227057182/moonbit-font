"""Generate a minimal, self-contained TrueType font used as the test fixture.

The font is intentionally tiny and contains only the tables a rasterizer needs:
head, maxp, hhea, hmtx, cmap (format 4), loca, glyf, name, OS/2, post.

Glyph layout (unitsPerEm = 1000):
    0  .notdef   empty glyph
    1  A         square outline (100,0) (100,700) (700,700) (700,0)   advance 800
    2  B         single quadratic curve triangle (off-curve apex)      advance 800
    3  C         composite glyph: component "A" translated by (100,0) advance 900

Run:  python tools/make_fixture.py fixtures/MoonTest-Regular.ttf
"""

import sys
import os

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib.tables._g_l_y_f import Glyph, GlyphComponent

UNITS_PER_EM = 1000
ASCENT = 800
DESCENT = -200

GLYPH_ORDER = [".notdef", "A", "B", "C"]
ADVANCES = {".notdef": 500, "A": 800, "B": 800, "C": 900}
CMAP = {ord("A"): "A", ord("B"): "B", ord("C"): "C"}


def build_glyphs():
    glyphs = {}

    pen = TTGlyphPen(None)
    glyphs[".notdef"] = pen.glyph()

    # A: axis-aligned square, four on-curve points.
    pen = TTGlyphPen(None)
    pen.moveTo((100, 0))
    pen.lineTo((100, 700))
    pen.lineTo((700, 700))
    pen.lineTo((700, 0))
    pen.closePath()
    glyphs["A"] = pen.glyph()

    # B: an arch made of two quadratic segments with an off-curve apex.
    pen = TTGlyphPen(None)
    pen.moveTo((100, 0))
    pen.qCurveTo((400, 800), (700, 0))
    pen.closePath()
    glyphs["B"] = pen.glyph()

    # C: composite glyph referencing A translated by (100, 0).
    comp_glyph = Glyph()
    comp_glyph.numberOfContours = -1
    comp_glyph.components = []
    comp = GlyphComponent()
    comp.glyphName = "A"
    comp.x = 100
    comp.y = 0
    # ARG_1_AND_2_ARE_WORDS (0x0001) | ARGS_ARE_XY_VALUES (0x0002)
    comp.flags = 0x0001 | 0x0002
    comp_glyph.components.append(comp)
    glyphs["C"] = comp_glyph

    return glyphs


def main(path):
    fb = FontBuilder(UNITS_PER_EM, isTTF=True)
    fb.setupGlyphOrder(GLYPH_ORDER)
    fb.setupCharacterMap(CMAP)
    fb.setupGlyf(build_glyphs())
    fb.setupHorizontalMetrics({name: (ADVANCES[name], 0) for name in GLYPH_ORDER})
    fb.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    fb.setupNameTable(
        {
            "familyName": "MoonTest",
            "styleName": "Regular",
            "uniqueFontIdentifier": "MoonTest Regular 1.0",
            "fullName": "MoonTest Regular",
            "psName": "MoonTest-Regular",
            "version": "Version 1.0",
        }
    )
    fb.setupOS2(
        sTypoAscender=ASCENT,
        sTypoDescender=DESCENT,
        usWinAscent=ASCENT,
        usWinDescent=-DESCENT,
    )
    fb.setupPost()

    out_dir = os.path.dirname(os.path.abspath(path))
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)
    fb.save(path)

    # Report the facts our MoonBit tests will assert on, so the two
    # implementations can be cross-checked field by field.
    font = fb.font
    print("saved:", path, os.path.getsize(path), "bytes")
    print("unitsPerEm:", font["head"].unitsPerEm)
    print("numGlyphs:", font["maxp"].numGlyphs)
    print("bbox:", font["head"].xMin, font["head"].yMin, font["head"].xMax, font["head"].yMax)
    print("ascent:", font["hhea"].ascent, "descent:", font["hhea"].descent)
    print("numHMetrics:", font["hhea"].numberOfHMetrics)
    print("indexToLocFormat:", font["head"].indexToLocFormat)
    for name in GLYPH_ORDER:
        adv, lsb = font["hmtx"][name]
        g = font["glyf"][name]
        contours = getattr(g, "numberOfContours", 0)
        print(f"glyph {name}: advance={adv} lsb={lsb} contours={contours}")
    cmap = font.getBestCmap()
    print("cmap:", {chr(k): v for k, v in sorted(cmap.items())})
    # Re-open from disk: this both proves the binary is a valid sfnt and lists
    # exactly the tables a reader will find.
    from fontTools.ttLib import TTFont

    reloaded = TTFont(path)
    print("tables:", sorted(reloaded.reader.keys()))
    for name in GLYPH_ORDER:
        coords = reloaded["glyf"][name].getCoordinates(reloaded["glyf"])
        print(f"glyph {name}: points={len(coords[0])} endPts={list(coords[1] or [])}")


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "fixtures/MoonTest-Regular.ttf"
    main(target)
