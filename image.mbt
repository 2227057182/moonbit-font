///|
/// Encodes the bitmap as an ASCII PGM (P2) image. Values are in 0..255 and
/// every row is written on its own line, which keeps the output diffable in
/// tests and readable in a text editor.
pub fn Bitmap::to_pgm(self : Bitmap) -> String {
  let mut out = "P2\n\{self.width} \{self.height}\n255\n"
  for y = 0; y < self.height; y = y + 1 {
    for x = 0; x < self.width; x = x + 1 {
      out = out + "\{self.pixels[y * self.width + x]}"
      if x + 1 < self.width {
        out = out + " "
      }
    }
    out = out + "\n"
  }
  out
}

///|
/// One character of the ASCII ramp for a coverage value.
fn ramp_char(value : Int) -> String {
  if value >= 224 {
    "@"
  } else if value >= 192 {
    "%"
  } else if value >= 160 {
    "#"
  } else if value >= 128 {
    "*"
  } else if value >= 96 {
    "+"
  } else if value >= 64 {
    "="
  } else if value >= 32 {
    "-"
  } else {
    " "
  }
}

///|
/// Renders the bitmap with an ASCII ramp, for quick visual inspection in a
/// terminal or in a test assertion.
pub fn Bitmap::to_ascii_art(self : Bitmap) -> String {
  let mut out = ""
  for y = 0; y < self.height; y = y + 1 {
    for x = 0; x < self.width; x = x + 1 {
      out = out + ramp_char(self.pixels[y * self.width + x])
    }
    out = out + "\n"
  }
  out
}

///|
/// Fraction of pixels that carry any coverage. A cheap way to assert that
/// something was actually drawn.
pub fn Bitmap::covered_ratio(self : Bitmap) -> Double {
  let mut covered = 0
  for i = 0; i < self.pixels.length(); i = i + 1 {
    if self.pixels[i] > 0 {
      covered = covered + 1
    }
  }
  if self.pixels.length() == 0 {
    0.0
  } else {
    covered.to_double() / self.pixels.length().to_double()
  }
}

///|
/// Sum of all coverage values, useful as a "ink amount" measure.
pub fn Bitmap::ink(self : Bitmap) -> Int {
  let mut total = 0
  for i = 0; i < self.pixels.length(); i = i + 1 {
    total = total + self.pixels[i]
  }
  total
}
