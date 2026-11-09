///|
/// One point of an outline. `on_curve` points are the endpoints of segments;
/// off-curve points are quadratic Bezier control points.
pub(all) struct Point {
  x : Double
  y : Double
  on_curve : Bool
}

///|
/// A closed contour of an outline, in font units.
pub(all) struct Contour {
  points : Array[Point]
}

///|
/// The outline of one glyph: closed contours in font units, y pointing up.
pub(all) struct Outline {
  contours : Array[Contour]
}

///|
/// Axis aligned bounding box in font units.
pub(all) struct BBox {
  x_min : Double
  y_min : Double
  x_max : Double
  y_max : Double
}

///|
/// Returns the outline of a glyph. Composite glyphs are resolved recursively
/// with their component transforms applied.
pub fn Font::outline(self : Font, glyph_id : Int) -> Outline raise FontError {
  self.resolve_outline(glyph_id, 0)
}

///|
fn Font::resolve_outline(
  self : Font,
  glyph_id : Int,
  depth : Int,
) -> Outline raise FontError {
  if depth > 8 {
    raise FontError::InvalidFormat("composite glyph nesting is too deep")
  }
  let (offset, length) = self.glyph_range(glyph_id)
  if length == 0 {
    return { contours: [] }
  }
  let view = Slice::new(self.data, offset, length)
  let num_contours = view.i16(0)
  if num_contours >= 0 {
    parse_simple_glyph(view, num_contours)
  } else {
    self.parse_composite_glyph(view, depth)
  }
}

///|
/// Decodes a simple (non composite) glyph: contour end points, run-length
/// compressed flags, then delta encoded x and y coordinates.
fn parse_simple_glyph(view : Slice, num_contours : Int) -> Outline raise FontError {
  if num_contours == 0 {
    return { contours: [] }
  }
  let end_points : Array[Int] = []
  for i = 0; i < num_contours; i = i + 1 {
    end_points.push(view.u16(10 + i * 2))
  }
  let num_points = end_points[num_contours - 1] + 1
  let instr_len = view.u16(10 + num_contours * 2)
  let mut pos = 10 + num_contours * 2 + 2 + instr_len
  let flags : Array[Int] = []
  while flags.length() < num_points {
    let flag = view.u8(pos)
    pos = pos + 1
    flags.push(flag)
    // Bit 3 (0x08) repeats the previous flag; the next byte is the number of
    // additional repetitions.
    if (flag & 0x08) != 0 {
      let repeat = view.u8(pos)
      pos = pos + 1
      for i = 0; i < repeat; i = i + 1 {
        flags.push(flag)
      }
    }
  }
  let xs : Array[Int] = []
  let mut cur_x = 0
  for i = 0; i < num_points; i = i + 1 {
    let f = flags[i]
    if (f & 0x02) != 0 {
      // 1-byte delta, positive when bit 4 is set, negative otherwise.
      let v = view.u8(pos)
      pos = pos + 1
      if (f & 0x10) != 0 {
        cur_x = cur_x + v
      } else {
        cur_x = cur_x - v
      }
    } else if (f & 0x10) == 0 {
      cur_x = cur_x + view.i16(pos)
      pos = pos + 2
    }
    xs.push(cur_x)
  }
  let ys : Array[Int] = []
  let mut cur_y = 0
  for i = 0; i < num_points; i = i + 1 {
    let f = flags[i]
    if (f & 0x04) != 0 {
      let v = view.u8(pos)
      pos = pos + 1
      if (f & 0x20) != 0 {
        cur_y = cur_y + v
      } else {
        cur_y = cur_y - v
      }
    } else if (f & 0x20) == 0 {
      cur_y = cur_y + view.i16(pos)
      pos = pos + 2
    }
    ys.push(cur_y)
  }
  let contours : Array[Contour] = []
  let mut start = 0
  for c = 0; c < num_contours; c = c + 1 {
    let end = end_points[c]
    let pts : Array[Point] = []
    for i = start; i <= end; i = i + 1 {
      let on_curve = (flags[i] & 0x01) != 0
      pts.push(
        { x: xs[i].to_double(), y: ys[i].to_double(), on_curve: on_curve },
      )
    }
    contours.push({ points: pts })
    start = end + 1
  }
  { contours: contours }
}

///|
/// Decodes a composite glyph: a list of components, each one another glyph
/// with an offset and an optional 2x2 transform.
fn Font::parse_composite_glyph(
  self : Font,
  view : Slice,
  depth : Int,
) -> Outline raise FontError {
  let mut pos = 10
  let contours : Array[Contour] = []
  let mut more = true
  while more {
    let flags = view.u16(pos)
    let comp_gid = view.u16(pos + 2)
    pos = pos + 4
    let mut dx = 0.0
    let mut dy = 0.0
    if (flags & 0x0001) != 0 {
      dx = view.i16(pos).to_double()
      dy = view.i16(pos + 2).to_double()
      pos = pos + 4
    } else {
      dx = view.i8(pos).to_double()
      dy = view.i8(pos + 1).to_double()
      pos = pos + 2
    }
    let mut a = 1.0
    let mut b = 0.0
    let mut c = 0.0
    let mut d = 1.0
    if (flags & 0x0008) != 0 {
      a = f2dot14(view.i16(pos))
      d = a
      pos = pos + 2
    } else if (flags & 0x0040) != 0 {
      a = f2dot14(view.i16(pos))
      d = f2dot14(view.i16(pos + 2))
      pos = pos + 4
    } else if (flags & 0x0080) != 0 {
      a = f2dot14(view.i16(pos))
      b = f2dot14(view.i16(pos + 2))
      c = f2dot14(view.i16(pos + 4))
      d = f2dot14(view.i16(pos + 6))
      pos = pos + 8
    }
    let component = self.resolve_outline(comp_gid, depth + 1)
    for i = 0; i < component.contours.length(); i = i + 1 {
      let src = component.contours[i]
      let pts : Array[Point] = []
      for j = 0; j < src.points.length(); j = j + 1 {
        let p = src.points[j]
        pts.push(
          { x: a * p.x + b * p.y + dx, y: c * p.x + d * p.y + dy, on_curve: p.on_curve },
        )
      }
      contours.push({ points: pts })
    }
    more = (flags & 0x0020) != 0
  }
  { contours: contours }
}

///|
/// Decodes a F2Dot14 fixed point number (two's complement, 14 fractional bits).
fn f2dot14(raw : Int) -> Double {
  raw.to_double() / 16384.0
}

///|
/// Bounding box of an outline. An empty outline yields a zero box.
pub fn Outline::bbox(self : Outline) -> BBox {
  let mut x_min = 0.0
  let mut y_min = 0.0
  let mut x_max = 0.0
  let mut y_max = 0.0
  let mut first = true
  for i = 0; i < self.contours.length(); i = i + 1 {
    let contour = self.contours[i]
    for j = 0; j < contour.points.length(); j = j + 1 {
      let p = contour.points[j]
      if first {
        x_min = p.x
        y_min = p.y
        x_max = p.x
        y_max = p.y
        first = false
      } else {
        if p.x < x_min {
          x_min = p.x
        }
        if p.x > x_max {
          x_max = p.x
        }
        if p.y < y_min {
          y_min = p.y
        }
        if p.y > y_max {
          y_max = p.y
        }
      }
    }
  }
  { x_min, y_min, x_max, y_max }
}

///|
/// Total number of points in an outline, useful in tests and diagnostics.
pub fn Outline::point_count(self : Outline) -> Int {
  let mut count = 0
  for i = 0; i < self.contours.length(); i = i + 1 {
    count = count + self.contours[i].points.length()
  }
  count
}
