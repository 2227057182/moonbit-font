///|
/// Errors raised while parsing or rendering a font.
pub(all) suberror FontError {
  OutOfBounds(Int, Int)
  MissingTable(Int)
  InvalidFormat(String)
  Unsupported(String)
  NoGlyph(Int)
}

///|
/// A read-only window over one table inside a font file. All offsets are
/// relative to the start of the table, and every read is bounds checked so a
/// truncated or hostile file raises instead of trapping.
pub struct Slice {
  data : Bytes
  base : Int
  size : Int
}

///|
pub fn Slice::new(data : Bytes, base : Int, size : Int) -> Slice {
  { data, base, size }
}

///|
pub fn Slice::size(self : Slice) -> Int {
  self.size
}

///|
/// Reads one unsigned byte at `off`.
pub fn Slice::u8(self : Slice, off : Int) -> Int raise FontError {
  if off < 0 || off + 1 > self.size {
    raise FontError::OutOfBounds(off, self.size)
  }
  self.data[self.base + off].to_int()
}

///|
/// Reads one signed byte at `off`.
pub fn Slice::i8(self : Slice, off : Int) -> Int raise FontError {
  let v = self.u8(off)
  if v >= 128 {
    v - 256
  } else {
    v
  }
}

///|
/// Reads one big-endian unsigned 16-bit value at `off`.
pub fn Slice::u16(self : Slice, off : Int) -> Int raise FontError {
  self.u8(off) * 256 + self.u8(off + 1)
}

///|
/// Reads one big-endian signed 16-bit value at `off`.
pub fn Slice::i16(self : Slice, off : Int) -> Int raise FontError {
  let v = self.u16(off)
  if v >= 32768 {
    v - 65536
  } else {
    v
  }
}

///|
/// Reads one big-endian unsigned 32-bit value at `off`. Values whose most
/// significant byte is set (i.e. anything above 2 GiB) are rejected: a font
/// that large is outside what this library intends to handle, and MoonBit
/// `Int` is 32 bits wide.
pub fn Slice::u32(self : Slice, off : Int) -> Int raise FontError {
  let b0 = self.u8(off)
  if b0 >= 128 {
    raise FontError::Unsupported("32-bit field exceeds the supported range")
  }
  b0 * 16777216 + self.u8(off + 1) * 65536 + self.u8(off + 2) * 256 + self.u8(off + 3)
}

///|
/// The tag of a table (`head`, `glyf`, ...) packed into one 32-bit integer,
/// so comparisons stay allocation free.
pub fn Slice::tag_u32(self : Slice, off : Int) -> Int raise FontError {
  self.u32(off)
}
