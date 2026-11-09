# moonbit-font

**A pure-MoonBit TrueType font parser and glyph rasterizer.**

`moonbit-font` reads a `.ttf` file, resolves glyph outlines (including composite
glyphs and quadratic curves), rasterizes them into antialiased coverage bitmaps,
lays out text with real advance widths and kerning, and exports the result as
PGM, ASCII preview or SVG paths — with **zero runtime dependencies** and no
system font stack.

```mbt no-check
let data = @fs.read_file_to_bytes("fonts/arial.ttf")
let font = @font.Font::load(data)
let bitmap = @font.render_text(font, "MoonBit", @font.RenderOptions::new(32))
let pgm = bitmap.to_pgm()
```

## Why this exists

MoonBit targets wasm, wasm-gc, js and native. None of them ships a font stack:
there is no way to turn `"Hello"` into pixels without a browser or an operating
system API. Every MoonBit project that needs rendered text — a wasm game UI, a
chart exporter that turns SVG into a bitmap, a PDF writer, an image annotator,
a terminal renderer, a captcha generator — has to write a font parser from
scratch.

`moonbit-font` is that layer. It is the MoonBit counterpart of
`stb_truetype` / FreeType's outline+raster core, written from the binary format
up, and it runs on every MoonBit target.

## Status

| Check | Result |
| --- | --- |
| `moon test` | 16 / 16 passing |
| `moon check --deny-warn` | clean, no warnings |
| `moon build --target wasm` | builds (`_build/wasm/debug/build/cmd/main/main.wasm`) |
| Real font, Latin | Arial: 24 tables, 4651 glyphs, cmap format 12, correct "Moon" render |
| Real font, CJK | SimHei: `U+4E2D` (中) resolves to gid 1123 and renders correctly |

## Features

**Parsing** — every table a rasterizer needs:

| Table | What is read |
| --- | --- |
| sfnt header | version, table directory (tag / offset / length) |
| `head` | `unitsPerEm`, `indexToLocFormat`, font bounding box |
| `maxp` | `numGlyphs` |
| `hhea` / `hmtx` | ascent, descent, line gap, advance widths, left side bearings |
| `loca` / `glyf` | glyph offsets, simple outlines, composite glyphs |
| `cmap` | format 4 (BMP) and format 12 (full Unicode) |
| `kern` | Microsoft format 0 pair kerning |

**Outlines**

- Simple glyphs: end points, run-length compressed flags, delta-encoded x/y.
- Composite glyphs: recursive components with word/byte offsets, `F2Dot14`
  scale, x/y scale and full 2×2 transforms.
- Quadratic Bézier segments preserved (on/off-curve point model).

**Rasterization**

- Adaptive quadratic flattening, half-pixel flatness tolerance.
- Scanline fill with the **nonzero winding rule**.
- **4×4 supersampling** per pixel, 17 grey levels, no staircase edges.
- All glyphs of a text block are flattened and filled in a single pass, so
  antialiasing is consistent across characters.

**Layout and output**

- Multi-line text, per-glyph advance widths, kerning applied between pairs.
- `Bitmap::to_pgm()` — ASCII PGM (P2), diffable and readable.
- `Bitmap::to_ascii_art()` — terminal preview.
- `Outline::to_svg_path()` — `M`/`L`/`Q`/`Z` path with flipped y axis.
- Coverage statistics: `ink()`, `covered_ratio()`.

## Install

```bash no-check
moon add 2227057182/moonbit-font
```

```toml
# moon.mod
import {
  "2227057182/moonbit-font",
}
```

```mbt no-check
// moon.pkg
import {
  "2227057182/moonbit-font" @font,
}
```

## Library API

| Call | Purpose |
| --- | --- |
| `Font::load(data : Bytes)` | parse an sfnt file from memory |
| `font.metrics()` | units per em, ascent, descent, line gap, bbox |
| `font.num_glyphs()` / `font.table_records()` | font inventory |
| `font.glyph_index(codepoint)` | Unicode → glyph id (cmap 4 / 12) |
| `font.advance_width(gid)` / `font.glyph_metrics(gid)` | horizontal metrics |
| `font.glyph_range(gid)` | glyph offset and length inside `glyf` |
| `font.outline(gid)` | resolved contours in font units |
| `font.kern(left, right)` | pair kerning in font units |
| `outline.bbox()` / `outline.point_count()` | outline geometry |
| `outline.to_svg_path()` | SVG path data |
| `render_glyph(font, gid, size)` | tightly cropped glyph bitmap |
| `measure_text(font, text, size)` | width, height, line count |
| `render_text(font, text, options)` | multi-line text bitmap |
| `bitmap.to_pgm()` / `to_ascii_art()` / `ink()` / `covered_ratio()` | outputs and statistics |

Errors are explicit: `FontError::{OutOfBounds, MissingTable, InvalidFormat,
Unsupported, NoGlyph}`. A truncated or hostile file raises instead of trapping.

## CLI

```bash no-check
# Font inventory: tables, unitsPerEm, glyph count, metrics, cmap format
moon run cmd/main -- info fonts/arial.ttf

# Render text to a PGM image and print an ASCII preview
moon run cmd/main -- render fonts/arial.ttf "MoonBit" 32 out.pgm

# Render one glyph
moon run cmd/main -- glyph fonts/simhei.ttf "中" 48 zhong.pgm

# Dump outline points, optionally emit an SVG document
moon run cmd/main -- outline fonts/arial.ttf A --svg

# Query a kerning pair
moon run cmd/main -- kern fonts/arial.ttf A V
```

Real output from a local Arial run:

```
font: fonts/arial.ttf
tables (24): GDEF GPOS GSUB JSTF LTSH OS/2 PCLT VDMX cmap cvt  fpgm gasp glyf hdmx head hhea hmtx kern loca maxp meta name post prep
unitsPerEm: 2048
numGlyphs: 4651
ascent / descent / lineGap: 1854 / -434 / 67
cmap format: 12
kern(A,V): gid 36,57 = -152 font units
```

## Implementation notes

- **Bounds-checked reads.** Every table access goes through a `Slice` that
  validates `offset + size` against the table length, so a malformed font
  produces a `FontError` rather than a runtime trap.
- **Signed 16-bit deltas.** `glyf` coordinates use `i16` deltas when the short
  flag is clear and 1-byte deltas with an explicit sign bit when it is set; the
  parser follows that encoding exactly.
- **Repeat flags.** Point flags are run-length compressed; the repeat bit
  (0x08) is expanded before coordinates are read.
- **Composite recursion is bounded** (depth 8) so self-referencing fonts
  cannot loop forever.
- **Start point selection.** A contour is walked from its first on-curve point;
  when every point is off-curve, the midpoint chain is used as synthetic
  on-curve anchors.
- **Winding, not even-odd.** TrueType fills with the nonzero rule, which is
  what the scanline accumulator implements.

## Limits (intentionally explicit)

- `OTTO` (CFF/PostScript outlines) is rejected with `Unsupported`; only
  TrueType `glyf` outlines are rasterized.
- TrueType Collections (`.ttc`) are not supported — pass a single `.ttf`.
- No hinting: grids are not snapped, so small sizes rely on antialiasing.
- Coverage is 4×4 supersampled (17 levels), not analytic area coverage.

## Test fixture

`fixtures/MoonTest-Regular.ttf` is generated by `tools/make_fixture.py`
(fontTools) and contains exactly four glyphs: an empty `.notdef`, a square,
a quadratic arch and a composite glyph translated by (100, 0) with
`unitsPerEm = 1000`. It is small (968 bytes), license-clean and fully
self-contained, so the test suite needs no system fonts:

```bash no-check
moon test        # 16 tests, no external files besides the fixture
```

## License

Apache-2.0.
