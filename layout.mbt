///|
/// Options controlling text rendering.
pub(all) struct RenderOptions {
  font_size : Int
  padding : Int
  line_spacing : Double
}

///|
pub fn RenderOptions::new(font_size : Int) -> RenderOptions {
  { font_size, padding: 2, line_spacing: 1.25 }
}

///|
/// Size of a rendered text block, in pixels.
pub(all) struct TextMetrics {
  width : Int
  height : Int
  lines : Int
  /// Advance width of the widest line, in pixels.
  advance_width : Double
}

///|
/// Font units to pixels for a given pixel size.
pub fn Font::scale_for(self : Font, font_size : Int) -> Double {
  font_size.to_double() / self.metrics().units_per_em.to_double()
}

///|
/// Splits text on newlines.
fn split_lines(text : String) -> Array[String] {
  let lines : Array[String] = []
  for part in text.split("\n") {
    lines.push(part.data())
  }
  if lines.length() == 0 {
    lines.push("")
  }
  lines
}

///|
/// Measures a text block without rendering it.
pub fn measure_text(
  font : Font,
  text : String,
  font_size : Int,
) -> TextMetrics raise FontError {
  let scale = font.scale_for(font_size)
  let lines = split_lines(text)
  let mut max_advance = 0.0
  for l = 0; l < lines.length(); l = l + 1 {
    let line = lines[l]
    let mut pen = 0.0
    let mut prev_gid = -1
    for c in line.to_array() {
      let gid = font.glyph_index(c.to_int())
      if gid >= 0 && gid < font.num_glyphs() {
        if prev_gid >= 0 {
          pen = pen + font.kern(prev_gid, gid).to_double() * scale
        }
        pen = pen + font.advance_width(gid).to_double() * scale
        prev_gid = gid
      }
    }
    if pen > max_advance {
      max_advance = pen
    }
  }
  let m = font.metrics()
  let line_h = (m.ascent - m.descent).to_double() * scale * 1.25
  let num_lines = if lines.length() == 0 { 1 } else { lines.length() }
  let width = floor_of(max_advance + 4.0 + 0.999)
  let height = floor_of(line_h * num_lines.to_double() + 4.0 + 0.999)
  { width, height, lines: num_lines, advance_width: max_advance }
}

///|
/// Renders a text block into a coverage bitmap. Every glyph outline is
/// flattened and rasterized in one pass, so antialiasing is computed consistently
/// across characters.
pub fn render_text(
  font : Font,
  text : String,
  options : RenderOptions,
) -> Bitmap raise FontError {
  let scale = font.scale_for(options.font_size)
  let m = font.metrics()
  let lines = split_lines(text)
  let mut max_advance = 0.0
  for l = 0; l < lines.length(); l = l + 1 {
    let line = lines[l]
    let mut pen = 0.0
    let mut prev_gid = -1
    for c in line.to_array() {
      let gid = font.glyph_index(c.to_int())
      if gid >= 0 && gid < font.num_glyphs() {
        if prev_gid >= 0 {
          pen = pen + font.kern(prev_gid, gid).to_double() * scale
        }
        pen = pen + font.advance_width(gid).to_double() * scale
        prev_gid = gid
      }
    }
    if pen > max_advance {
      max_advance = pen
    }
  }
  let num_lines = if lines.length() == 0 { 1 } else { lines.length() }
  let line_h = (m.ascent - m.descent).to_double() * scale * options.line_spacing
  let pad = options.padding.to_double()
  let width = floor_of(max_advance + pad * 2.0 + 0.999)
  let height = floor_of(line_h * num_lines.to_double() + pad * 2.0 + 0.999)
  let polylines : Array[Polyline] = []
  for l = 0; l < lines.length(); l = l + 1 {
    let line = lines[l]
    let baseline = pad + m.ascent.to_double() * scale + l.to_double() * line_h
    let mut pen = pad
    let mut prev_gid = -1
    for c in line.to_array() {
      let gid = font.glyph_index(c.to_int())
      if gid >= 0 && gid < font.num_glyphs() {
        if prev_gid >= 0 {
          pen = pen + font.kern(prev_gid, gid).to_double() * scale
        }
        let outline = font.outline(gid)
        for k = 0; k < outline.contours.length(); k = k + 1 {
          let poly = flatten_contour(outline.contours[k], scale, pen, baseline)
          if poly.xs.length() > 0 {
            polylines.push(poly)
          }
        }
        pen = pen + font.advance_width(gid).to_double() * scale
        prev_gid = gid
      }
    }
  }
  rasterize(polylines, width, height)
}

///|
/// Renders a single glyph into its own bitmap, tightly cropped to the outline
/// bounding box. `font_size` gives the em size in pixels.
pub fn render_glyph(
  font : Font,
  glyph_id : Int,
  font_size : Int,
) -> Bitmap raise FontError {
  let outline = font.outline(glyph_id)
  let box = outline.bbox()
  let scale = font.scale_for(font_size)
  let pad = 1.0
  let width = floor_of((box.x_max - box.x_min) * scale + pad * 2.0 + 0.999)
  let height = floor_of((box.y_max - box.y_min) * scale + pad * 2.0 + 0.999)
  let polylines : Array[Polyline] = []
  for k = 0; k < outline.contours.length(); k = k + 1 {
    let poly = flatten_contour(
      outline.contours[k],
      scale,
      pad - box.x_min * scale,
      pad + box.y_max * scale,
    )
    if poly.xs.length() > 0 {
      polylines.push(poly)
    }
  }
  rasterize(polylines, width, height)
}
