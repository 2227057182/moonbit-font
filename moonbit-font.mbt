///|
/// moonbit-font — TrueType font parsing and glyph rasterization for MoonBit.
///
/// The usual path is:
///
/// 1. `Font::load(bytes)` — parse the sfnt container and table directory.
/// 2. `Font::glyph_index(codepoint)` — map a character to a glyph id.
/// 3. `Font::outline(gid)` — resolve contours (handles composite glyphs).
/// 4. `render_glyph` / `render_text` — rasterize to an antialiased `Bitmap`.
///
/// Output helpers live in `image.mbt` (`to_pgm`, `to_ascii_art`, `ink`,
/// `covered_ratio`) and `font.mbt` (`to_svg_path`). Every error is surfaced as
/// `FontError`, so callers can decide whether a malformed font is fatal.
