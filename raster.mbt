///|
/// A closed polyline in pixel space, produced by flattening one contour.
pub(all) struct Polyline {
  xs : Array[Double]
  ys : Array[Double]
}

///|
/// A grayscale coverage bitmap, row-major, one byte per pixel.
pub(all) struct Bitmap {
  width : Int
  height : Int
  pixels : Array[Int]
}

///|
pub fn Bitmap::new(width : Int, height : Int) -> Bitmap {
  let pixels : Array[Int] = []
  for i = 0; i < width * height; i = i + 1 {
    pixels.push(0)
  }
  { width, height, pixels }
}

///|
/// Coverage value at (x, y), 0 outside the bitmap.
pub fn Bitmap::get(self : Bitmap, x : Int, y : Int) -> Int {
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    0
  } else {
    self.pixels[y * self.width + x]
  }
}

///|
fn min_of(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn max_of(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// Largest integer not greater than `v`.
fn floor_of(v : Double) -> Int {
  let truncated = v.to_int()
  if v < 0.0 && v != truncated.to_double() {
    truncated - 1
  } else {
    truncated
  }
}

///|
/// Flattens a quadratic Bezier into the polyline. The recursion stops when the
/// control point is within half a pixel of the chord.
fn flatten_quad(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  x2 : Double,
  y2 : Double,
  xs : Array[Double],
  ys : Array[Double],
) -> Unit {
  let dx = x0 - 2.0 * x1 + x2
  let dy = y0 - 2.0 * y1 + y2
  if dx * dx + dy * dy <= 0.25 {
    xs.push(x2)
    ys.push(y2)
  } else {
    let ax = (x0 + x1) / 2.0
    let ay = (y0 + y1) / 2.0
    let bx = (x1 + x2) / 2.0
    let by = (y1 + y2) / 2.0
    let mx = (ax + bx) / 2.0
    let my = (ay + by) / 2.0
    flatten_quad(x0, y0, ax, ay, mx, my, xs, ys)
    flatten_quad(mx, my, bx, by, x2, y2, xs, ys)
  }
}

///|
/// Flattens one contour into a closed polyline in pixel space. `scale` maps
/// font units to pixels, `origin_x` is the pen position and `baseline` the y
/// coordinate of the baseline. The y axis is flipped because font units point
/// up while bitmap rows grow downwards.
fn flatten_contour(
  contour : Contour,
  scale : Double,
  origin_x : Double,
  baseline : Double,
) -> Polyline {
  let xs : Array[Double] = []
  let ys : Array[Double] = []
  let n = contour.points.length()
  if n == 0 {
    return { xs, ys }
  }
  let px : Array[Double] = []
  let py : Array[Double] = []
  let on : Array[Bool] = []
  for i = 0; i < n; i = i + 1 {
    let p = contour.points[i]
    px.push(p.x * scale + origin_x)
    py.push(baseline - p.y * scale)
    on.push(p.on_curve)
  }
  let mut start = -1
  for i = 0; i < n; i = i + 1 {
    if on[i] {
      start = i
      break
    }
  }
  if start >= 0 {
    xs.push(px[start])
    ys.push(py[start])
    let mut cur_x = px[start]
    let mut cur_y = py[start]
    let mut i = 1
    while i < n {
      let idx = (start + i) % n
      if on[idx] {
        xs.push(px[idx])
        ys.push(py[idx])
        cur_x = px[idx]
        cur_y = py[idx]
        i = i + 1
      } else {
        let next_idx = (idx + 1) % n
        if on[next_idx] {
          flatten_quad(cur_x, cur_y, px[idx], py[idx], px[next_idx], py[next_idx], xs, ys)
          cur_x = px[next_idx]
          cur_y = py[next_idx]
          i = i + 2
        } else {
          let mx = (px[idx] + px[next_idx]) / 2.0
          let my = (py[idx] + py[next_idx]) / 2.0
          flatten_quad(cur_x, cur_y, px[idx], py[idx], mx, my, xs, ys)
          cur_x = mx
          cur_y = my
          i = i + 1
        }
      }
    }
    if cur_x != px[start] || cur_y != py[start] {
      xs.push(px[start])
      ys.push(py[start])
    }
  } else {
    // No on-curve point at all: walk the midpoint chain as on-curve points.
    let last_x = (px[n - 1] + px[0]) / 2.0
    let last_y = (py[n - 1] + py[0]) / 2.0
    xs.push(last_x)
    ys.push(last_y)
    let mut cur_x = last_x
    let mut cur_y = last_y
    for i = 0; i < n; i = i + 1 {
      let next_idx = (i + 1) % n
      let mx = (px[i] + px[next_idx]) / 2.0
      let my = (py[i] + py[next_idx]) / 2.0
      flatten_quad(cur_x, cur_y, px[i], py[i], mx, my, xs, ys)
      cur_x = mx
      cur_y = my
    }
  }
  { xs, ys }
}

///|
/// Rasterizes closed polylines into an antialiased coverage bitmap.
///
/// Each pixel is sampled by a 4x4 grid: for every sub scanline the crossings of
/// all polygon edges are collected, sorted and accumulated under the nonzero
/// winding rule, which yields 17 grey levels per pixel.
pub fn rasterize(
  polylines : Array[Polyline],
  width : Int,
  height : Int,
) -> Bitmap {
  let bmp = Bitmap::new(width, height)
  if width <= 0 || height <= 0 {
    return bmp
  }
  let cov : Array[Double] = []
  for i = 0; i < width * height; i = i + 1 {
    cov.push(0.0)
  }
  let sub_grid = 4
  // Each scanline row is sampled by `sub_grid` sub scanlines; a pixel's
  // coverage is the sum of those horizontal overlaps divided by sub_grid.
  let total_samples = 4.0
  for row = 0; row < height; row = row + 1 {
    for sub = 0; sub < sub_grid; sub = sub + 1 {
      let sy = row.to_double() + (sub.to_double() + 0.5) / 4.0
      let crossings : Array[Double] = []
      let dirs : Array[Int] = []
      for p = 0; p < polylines.length(); p = p + 1 {
        let poly = polylines[p]
        let n = poly.xs.length()
        for k = 0; k < n; k = k + 1 {
          let k2 = (k + 1) % n
          let x0 = poly.xs[k]
          let y0 = poly.ys[k]
          let x1 = poly.xs[k2]
          let y1 = poly.ys[k2]
          if y0 == y1 {
            continue
          }
          let spans = (y0 <= sy && sy < y1) || (y1 <= sy && sy < y0)
          if spans {
            let x = x0 + (sy - y0) * (x1 - x0) / (y1 - y0)
            crossings.push(x)
            dirs.push(if y1 > y0 { 1 } else { -1 })
          }
        }
      }
      // Insertion sort: outlines have few crossings per scanline.
      for a = 1; a < crossings.length(); a = a + 1 {
        let key_x = crossings[a]
        let key_dir = dirs[a]
        let mut b = a - 1
        while b >= 0 && crossings[b] > key_x {
          crossings[b + 1] = crossings[b]
          dirs[b + 1] = dirs[b]
          b = b - 1
        }
        crossings[b + 1] = key_x
        dirs[b + 1] = key_dir
      }
      let mut winding = 0
      let mut prev_x = 0.0
      for a = 0; a < crossings.length(); a = a + 1 {
        let x = crossings[a]
        if winding != 0 {
          let mut px = floor_of(prev_x)
          while px.to_double() < x {
            if px >= 0 && px < width {
              let overlap = min_of(x, (px + 1).to_double()) -
                max_of(prev_x, px.to_double())
              if overlap > 0.0 {
                let idx = row * width + px
                cov[idx] = cov[idx] + overlap / total_samples
              }
            }
            px = px + 1
          }
        }
        winding = winding + dirs[a]
        prev_x = x
      }
    }
  }
  for i = 0; i < cov.length(); i = i + 1 {
    let v = cov[i] * 255.0
    let iv = floor_of(v)
    bmp.pixels[i] = if iv < 0 {
      0
    } else if iv > 255 {
      255
    } else {
      iv
    }
  }
  bmp
}
