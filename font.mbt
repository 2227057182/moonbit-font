///|
/// Formats one font-unit coordinate. SVG uses the same integer grid as the
/// font, but its y axis points down, so callers pass already-negated y values.
fn svg_int(v : Double) -> String {
  "\{v.to_int()}"
}

///|
/// Serializes an outline as an SVG path `d` attribute.
///
/// Straight segments become `L`, quadratic segments become `Q` (TrueType
/// contours are quadratic), and every contour is closed with `Z`. The y axis is
/// flipped so the path renders upright in SVG coordinates.
pub fn Outline::to_svg_path(self : Outline) -> String {
  let mut d = ""
  for ci = 0; ci < self.contours.length(); ci = ci + 1 {
    let contour = self.contours[ci]
    let n = contour.points.length()
    if n == 0 {
      continue
    }
    let mut start = -1
    for i = 0; i < n; i = i + 1 {
      if contour.points[i].on_curve {
        start = i
        break
      }
    }
    if start >= 0 {
      let first = contour.points[start]
      d = d + "M " + svg_int(first.x) + " " + svg_int(-first.y) + " "
      let mut i = 1
      while i < n {
        let idx = (start + i) % n
        let point = contour.points[idx]
        if point.on_curve {
          d = d + "L " + svg_int(point.x) + " " + svg_int(-point.y) + " "
          i = i + 1
        } else {
          let next_idx = (idx + 1) % n
          let next = contour.points[next_idx]
          if next.on_curve {
            d = d + "Q " + svg_int(point.x) + " " + svg_int(-point.y) + " " +
              svg_int(next.x) + " " + svg_int(-next.y) + " "
            i = i + 2
          } else {
            let mid_x = (point.x + next.x) / 2.0
            let mid_y = (point.y + next.y) / 2.0
            d = d + "Q " + svg_int(point.x) + " " + svg_int(-point.y) + " " +
              svg_int(mid_x) + " " + svg_int(-mid_y) + " "
            i = i + 1
          }
        }
      }
      d = d + "Z "
    } else {
      // Every point is off-curve: use the midpoint chain as on-curve anchors.
      let last_x = (contour.points[n - 1].x + contour.points[0].x) / 2.0
      let last_y = (contour.points[n - 1].y + contour.points[0].y) / 2.0
      d = d + "M " + svg_int(last_x) + " " + svg_int(-last_y) + " "
      for i = 0; i < n; i = i + 1 {
        let next_idx = (i + 1) % n
        let point = contour.points[i]
        let next = contour.points[next_idx]
        let mid_x = (point.x + next.x) / 2.0
        let mid_y = (point.y + next.y) / 2.0
        d = d + "Q " + svg_int(point.x) + " " + svg_int(-point.y) + " " +
          svg_int(mid_x) + " " + svg_int(-mid_y) + " "
      }
      d = d + "Z "
    }
  }
  d
}

///|
/// Kerning adjustment between two glyphs in font units. Returns 0 when the
/// font carries no `kern` table or no pair entry; a negative value means the
/// glyphs should be moved closer together.
pub fn Font::kern(self : Font, left : Int, right : Int) -> Int raise FontError {
  if !self.has_table(tag_kern()) {
    return 0
  }
  let kern = self.table(tag_kern())
  // Support the Microsoft layout: version 0 with format 0 subtables.
  let version = kern.u16(0)
  if version != 0 {
    return 0
  }
  let num_tables = kern.u16(2)
  let mut pos = 4
  for t = 0; t < num_tables; t = t + 1 {
    if pos + 6 > kern.size() {
      return 0
    }
    let sub_version = kern.u16(pos)
    let length = kern.u16(pos + 2)
    let coverage = kern.u16(pos + 4)
    let format = (coverage >> 8) & 0xFF
    if sub_version == 0 && format == 0 && pos + 14 <= kern.size() {
      let num_pairs = kern.u16(pos + 6)
      let pairs_base = pos + 14
      // Linear scan: the pair list is sorted, but fonts rarely exceed a few
      // thousand pairs and lookups happen once per character pair.
      for p = 0; p < num_pairs; p = p + 1 {
        let rec = pairs_base + p * 6
        if rec + 6 > kern.size() {
          return 0
        }
        let left_glyph = kern.u16(rec)
        if left_glyph == left {
          let right_glyph = kern.u16(rec + 2)
          if right_glyph == right {
            return kern.i16(rec + 4)
          }
        } else if left_glyph > left {
          // Pairs are sorted by the left glyph id; stop scanning early.
          break
        }
      }
    }
    pos = pos + length
    if length == 0 {
      return 0
    }
  }
  0
}
