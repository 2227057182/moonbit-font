///|
fn fixture() -> Bytes raise {
  @fs.read_file_to_bytes("fixtures/MoonTest-Regular.ttf")
}

///|
test "sfnt header, table directory and font wide metrics" {
  let font = @moonbit-font.Font::load(fixture())
  let m = font.metrics()
  assert_eq(m.units_per_em, 1000)
  assert_eq(font.num_glyphs(), 4)
  assert_eq(m.ascent, 800)
  assert_eq(m.descent, -200)
  assert_eq(m.line_gap, 0)
  assert_eq(m.bbox_xmin, 100)
  assert_eq(m.bbox_ymin, 0)
  assert_eq(m.bbox_xmax, 800)
  assert_eq(m.bbox_ymax, 800)
  assert_eq(font.table_records().length(), 10)
  assert_true(font.has_table(0x68656164))
  assert_true(font.has_table(0x676C7966))
  assert_true(font.has_table(0x636D6170))
  assert_true(font.has_table(0x6C6F6361))
  assert_false(font.has_table(0x6B65726E))
}

///|
test "cmap format 4 maps code points to glyph ids" {
  let font = @moonbit-font.Font::load(fixture())
  assert_eq(font.glyph_index(65), 1)
  assert_eq(font.glyph_index(66), 2)
  assert_eq(font.glyph_index(67), 3)
  // Characters outside the mapping fall back to .notdef.
  assert_eq(font.glyph_index(68), 0)
  assert_eq(font.glyph_index(97), 0)
  assert_eq(font.glyph_index(0x4E00), 0)
}

///|
test "horizontal metrics cover the monospaced tail" {
  let font = @moonbit-font.Font::load(fixture())
  assert_eq(font.advance_width(0), 500)
  assert_eq(font.advance_width(1), 800)
  assert_eq(font.advance_width(2), 800)
  assert_eq(font.advance_width(3), 900)
  let gm = font.glyph_metrics(1)
  assert_eq(gm.advance, 800)
  assert_eq(gm.lsb, 0)
}

///|
test "simple glyph outlines and bounding boxes" {
  let font = @moonbit-font.Font::load(fixture())
  let glyph_a = font.outline(1)
  assert_eq(glyph_a.contours.length(), 1)
  assert_eq(glyph_a.point_count(), 4)
  let bbox_a = glyph_a.bbox()
  assert_eq(bbox_a.x_min, 100.0)
  assert_eq(bbox_a.y_min, 0.0)
  assert_eq(bbox_a.x_max, 700.0)
  assert_eq(bbox_a.y_max, 700.0)
  let glyph_b = font.outline(2)
  assert_eq(glyph_b.point_count(), 3)
  // The apex of the arch is an off-curve control point.
  assert_false(glyph_b.contours[0].points[1].on_curve)
}

///|
test "composite glyph resolves component transforms" {
  let font = @moonbit-font.Font::load(fixture())
  let glyph_c = font.outline(3)
  assert_eq(glyph_c.contours.length(), 1)
  assert_eq(glyph_c.point_count(), 4)
  let bbox_c = glyph_c.bbox()
  // Same square as "A", shifted right by 100 font units.
  assert_eq(bbox_c.x_min, 200.0)
  assert_eq(bbox_c.x_max, 800.0)
  assert_eq(bbox_c.y_min, 0.0)
  assert_eq(bbox_c.y_max, 700.0)
}

///|
test "empty glyph has no outline" {
  let font = @moonbit-font.Font::load(fixture())
  let glyph = font.outline(0)
  assert_eq(glyph.contours.length(), 0)
  assert_eq(glyph.point_count(), 0)
}

///|
test "glyph rasterization yields antialiased coverage" {
  let font = @moonbit-font.Font::load(fixture())
  let bmp = @moonbit-font.render_glyph(font, 1, 48)
  // The square is 600/1000 x 700/1000 em, i.e. 28.8 x 33.6 px at 48 px em,
  // plus one pixel of padding on each side.
  assert_true(bmp.width >= 29 && bmp.width <= 33)
  assert_true(bmp.height >= 34 && bmp.height <= 38)
  assert_true(bmp.ink() > 0)
  // A solid square inside the padded box covers most, but not all, pixels.
  assert_true(bmp.covered_ratio() > 0.6)
  assert_true(bmp.covered_ratio() < 1.0)
  // Antialiasing must produce some intermediate grey values, not just 0/255.
  let mut intermediate = 0
  for i = 0; i < bmp.pixels.length(); i = i + 1 {
    let v = bmp.pixels[i]
    if v > 0 && v < 255 {
      intermediate = intermediate + 1
    }
  }
  assert_true(intermediate > 0)
}

///|
test "curved outline rasterizes to fewer ink pixels than its bbox" {
  let font = @moonbit-font.Font::load(fixture())
  let bmp = @moonbit-font.render_glyph(font, 2, 64)
  assert_true(bmp.ink() > 0)
  // The arch is a thin curve: it must not fill the whole box.
  assert_true(bmp.covered_ratio() < 0.6)
}

///|
test "text measurement follows advance widths" {
  let font = @moonbit-font.Font::load(fixture())
  let tm = @moonbit-font.measure_text(font, "ABC", 32)
  assert_eq(tm.lines, 1)
  // (800 + 800 + 900) / 1000 * 32 = 80 px
  assert_true(tm.advance_width > 79.0 && tm.advance_width < 81.0)
  assert_true(tm.width >= 82 && tm.width <= 86)
  let multi = @moonbit-font.measure_text(font, "A\nB", 32)
  assert_eq(multi.lines, 2)
  assert_true(multi.height > tm.height)
}

///|
test "text rendering draws every glyph" {
  let font = @moonbit-font.Font::load(fixture())
  let opts = @moonbit-font.RenderOptions::new(32)
  let one = @moonbit-font.render_text(font, "A", opts)
  let three = @moonbit-font.render_text(font, "ABC", opts)
  assert_true(one.ink() > 0)
  assert_true(three.ink() > one.ink())
  assert_true(three.width > one.width)
}

///|
test "unknown characters render nothing but keep their advance" {
  let font = @moonbit-font.Font::load(fixture())
  let tm = @moonbit-font.measure_text(font, "AZA", 32)
  assert_true(tm.advance_width > 0.0)
  let bmp = @moonbit-font.render_text(font, "AZA", @moonbit-font.RenderOptions::new(16))
  assert_true(bmp.ink() > 0)
}

///|
test "pgm and ascii encoders emit one row per bitmap row" {
  let font = @moonbit-font.Font::load(fixture())
  let bmp = @moonbit-font.render_glyph(font, 1, 16)
  let pgm = bmp.to_pgm()
  let ascii = bmp.to_ascii_art()
  assert_true(pgm.has_prefix("P2\n"))
  assert_true(pgm.contains("255"))
  // Header plus one line per row plus a trailing newline.
  let mut lines = 0
  for c in pgm.iter() {
    if c.to_int() == 10 {
      lines = lines + 1
    }
  }
  assert_true(lines >= bmp.height + 3)
  let mut ascii_lines = 0
  for c in ascii.iter() {
    if c.to_int() == 10 {
      ascii_lines = ascii_lines + 1
    }
  }
  // One newline per bitmap row; no header for the ASCII ramp.
  assert_true(ascii_lines >= bmp.height)
}
