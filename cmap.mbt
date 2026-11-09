///|
/// Maps a Unicode code point to a glyph index. Returns 0 (the .notdef glyph)
/// when the character is not covered by the font.
pub fn Font::glyph_index(self : Font, codepoint : Int) -> Int raise FontError {
  let view = self.table(tag_cmap())
  let sub = self.cmap_subtable
  if self.cmap_format == 4 {
    cmap_format4_lookup(view, sub, codepoint)
  } else if self.cmap_format == 12 {
    cmap_format12_lookup(view, sub, codepoint)
  } else {
    0
  }
}

///|
/// Format 4: segmented mapping for the Basic Multilingual Plane.
///
/// Layout, relative to `sub`:
///   0 format, 2 length, 4 language, 6 segCountX2, 8 searchRange,
///   10 entrySelector, 12 rangeShift, 14 endCode[], then reservedPad,
///   startCode[], idDelta[], idRangeOffset[].
fn cmap_format4_lookup(view : Slice, sub : Int, code : Int) -> Int raise FontError {
  if code < 0 || code > 0xFFFF {
    return 0
  }
  let seg_count = view.u16(sub + 6) / 2
  if seg_count == 0 {
    return 0
  }
  let end_base = sub + 14
  let start_base = end_base + seg_count * 2 + 2
  let delta_base = start_base + seg_count * 2
  let range_base = delta_base + seg_count * 2
  for seg = 0; seg < seg_count; seg = seg + 1 {
    let end_code = view.u16(end_base + seg * 2)
    if code <= end_code {
      let start_code = view.u16(start_base + seg * 2)
      if code < start_code {
        return 0
      }
      let delta = view.i16(delta_base + seg * 2)
      let range_off = view.u16(range_base + seg * 2)
      if range_off == 0 {
        return wrap16(code + delta)
      }
      let addr = range_base + seg * 2 + range_off + (code - start_code) * 2
      let gid_raw = view.u16(addr)
      if gid_raw == 0 {
        return 0
      }
      return wrap16(gid_raw + delta)
    }
  }
  0
}

///|
/// Format 12: groups of (startCharCode, endCharCode, startGlyphID), used for
/// the full Unicode range.
fn cmap_format12_lookup(view : Slice, sub : Int, code : Int) -> Int raise FontError {
  let num_groups = view.u32(sub + 12)
  let base = sub + 16
  for group = 0; group < num_groups; group = group + 1 {
    let rec = base + group * 12
    let start_code = view.u32(rec)
    let end_code = view.u32(rec + 4)
    if code >= start_code && code <= end_code {
      return view.u32(rec + 8) + (code - start_code)
    }
  }
  0
}

///|
/// Wraps an idDelta computation back into the 16-bit range as the cmap spec
/// requires.
fn wrap16(value : Int) -> Int {
  if value < 0 {
    value + 65536
  } else if value >= 65536 {
    value - 65536
  } else {
    value
  }
}
