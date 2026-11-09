///|
fn tag_head() -> Int {
  0x68656164
}

///|
fn tag_maxp() -> Int {
  0x6D617870
}

///|
fn tag_hhea() -> Int {
  0x68686561
}

///|
fn tag_hmtx() -> Int {
  0x686D7478
}

///|
fn tag_loca() -> Int {
  0x6C6F6361
}

///|
fn tag_glyf() -> Int {
  0x676C7966
}

///|
fn tag_cmap() -> Int {
  0x636D6170
}

///|
fn tag_kern() -> Int {
  0x6B65726E
}

///|
fn tag_name_table() -> Int {
  0x6E616D65
}

///|
fn tag_os2() -> Int {
  0x4F532F32
}

///|
fn tag_post() -> Int {
  0x706F7374
}

///|
fn tag_cff() -> Int {
  0x43464620
}

///|
/// Human readable name for a table tag. Unknown tags are rendered as their
/// numeric value so a report never hides a table.
pub fn tag_name(tag : Int) -> String {
  if tag == tag_head() {
    "head"
  } else if tag == tag_maxp() {
    "maxp"
  } else if tag == tag_hhea() {
    "hhea"
  } else if tag == tag_hmtx() {
    "hmtx"
  } else if tag == tag_loca() {
    "loca"
  } else if tag == tag_glyf() {
    "glyf"
  } else if tag == tag_cmap() {
    "cmap"
  } else if tag == tag_kern() {
    "kern"
  } else if tag == tag_name_table() {
    "name"
  } else if tag == tag_os2() {
    "OS/2"
  } else if tag == tag_post() {
    "post"
  } else if tag == tag_cff() {
    "CFF "
  } else if tag == 0x63767420 {
    "cvt "
  } else if tag == 0x6670676D {
    "fpgm"
  } else if tag == 0x70726570 {
    "prep"
  } else if tag == 0x67617370 {
    "gasp"
  } else if tag == 0x44534947 {
    "DSIG"
  } else if tag == 0x68646D78 {
    "hdmx"
  } else if tag == 0x4C545348 {
    "LTSH"
  } else if tag == 0x56444D58 {
    "VDMX"
  } else if tag == 0x76686561 {
    "vhea"
  } else if tag == 0x766D7478 {
    "vmtx"
  } else if tag == 0x47504F53 {
    "GPOS"
  } else if tag == 0x47535542 {
    "GSUB"
  } else if tag == 0x47444546 {
    "GDEF"
  } else if tag == 0x4A535446 {
    "JSTF"
  } else if tag == 0x50434C54 {
    "PCLT"
  } else if tag == 0x6D657461 {
    "meta"
  } else if tag == 0x4D415448 {
    "MATH"
  } else {
    "tag<\{tag}>"
  }
}

///|
/// One entry of the sfnt table directory.
pub(all) struct TableRecord {
  tag : Int
  offset : Int
  length : Int
}

///|
/// Horizontal metrics of a glyph: advance width and left side bearing.
pub(all) struct GlyphMetrics {
  advance : Int
  lsb : Int
}

///|
/// Font-wide metrics read from `head` and `hhea`.
pub(all) struct FontMetrics {
  units_per_em : Int
  ascent : Int
  descent : Int
  line_gap : Int
  bbox_xmin : Int
  bbox_ymin : Int
  bbox_xmax : Int
  bbox_ymax : Int
}

///|
/// A parsed sfnt (TrueType) font. It keeps the raw file bytes and the offsets
/// needed by the cmap, outline and rasterizer layers.
pub struct Font {
  priv data : Bytes
  priv tables : Array[TableRecord]
  priv metrics : FontMetrics
  priv num_glyphs : Int
  priv num_h_metrics : Int
  priv loca : Array[Int]
  priv cmap_format : Int
  priv cmap_subtable : Int
}

///|
/// Parses a font file held in memory.
pub fn Font::load(data : Bytes) -> Font raise FontError {
  let reader = Slice::new(data, 0, data.length())
  if data.length() < 12 {
    raise FontError::InvalidFormat("file is shorter than the sfnt header")
  }
  let version = reader.u32(0)
  // 0x00010000 is TrueType outlines, 'true' is the older Apple flavour.
  // 'OTTO' (0x4F54544F) means CFF outlines, which this library does not rasterize.
  if version == 0x4F54544F {
    raise FontError::Unsupported("CFF outlines are not supported yet")
  }
  if version != 0x00010000 && version != 0x74727565 {
    raise FontError::InvalidFormat("unknown sfnt version \{version}")
  }
  let num_tables = reader.u16(4)
  let tables : Array[TableRecord] = []
  for i = 0; i < num_tables; i = i + 1 {
    let rec_off = 12 + i * 16
    let tag_v = reader.u32(rec_off)
    let off = reader.u32(rec_off + 8)
    let len = reader.u32(rec_off + 12)
    if off + len > data.length() {
      raise FontError::OutOfBounds(off, len)
    }
    let rec : TableRecord = { tag: tag_v, offset: off, length: len }
    tables.push(rec)
  }
  let head = Slice::new(data, must_table(tables, tag_head()).offset, must_table(tables, tag_head()).length)
  let maxp = Slice::new(data, must_table(tables, tag_maxp()).offset, must_table(tables, tag_maxp()).length)
  let hhea = Slice::new(data, must_table(tables, tag_hhea()).offset, must_table(tables, tag_hhea()).length)
  let units_per_em = head.u16(18)
  if units_per_em == 0 {
    raise FontError::InvalidFormat("unitsPerEm is zero")
  }
  let index_to_loc_format = head.i16(50)
  let metrics : FontMetrics = {
    units_per_em,
    ascent: hhea.i16(4),
    descent: hhea.i16(6),
    line_gap: hhea.i16(8),
    bbox_xmin: head.i16(36),
    bbox_ymin: head.i16(38),
    bbox_xmax: head.i16(40),
    bbox_ymax: head.i16(42),
  }
  let num_glyphs = maxp.u16(4)
  let num_h_metrics = hhea.u16(34)
  if must_table(tables, tag_glyf()).length == 0 {
    raise FontError::MissingTable(tag_glyf())
  }
  let loca = parse_loca(tables, data, num_glyphs, index_to_loc_format)
  let cmap = must_table(tables, tag_cmap())
  let cmap_info = find_cmap_subtable(
    Slice::new(data, cmap.offset, cmap.length),
  )
  let font : Font = {
    data,
    tables,
    metrics,
    num_glyphs,
    num_h_metrics,
    loca,
    cmap_format: cmap_info.0,
    cmap_subtable: cmap_info.1,
  }
  font
}

///|
fn must_table(tables : Array[TableRecord], tag_v : Int) -> TableRecord raise FontError {
  for i = 0; i < tables.length(); i = i + 1 {
    let t = tables[i]
    if t.tag == tag_v {
      return t
    }
  }
  raise FontError::MissingTable(tag_v)
}

///|
/// Parses the `loca` table into absolute offsets into `glyf`.
fn parse_loca(
  tables : Array[TableRecord],
  data : Bytes,
  num_glyphs : Int,
  fmt : Int,
) -> Array[Int] raise FontError {
  let loca = must_table(tables, tag_loca())
  let view = Slice::new(data, loca.offset, loca.length)
  let offsets : Array[Int] = []
  let count = num_glyphs + 1
  if fmt == 0 {
    // Short format: offsets are 16-bit values that must be doubled.
    if loca.length < count * 2 {
      raise FontError::InvalidFormat("loca is too short for short format")
    }
    for i = 0; i < count; i = i + 1 {
      offsets.push(view.u16(i * 2) * 2)
    }
  } else if fmt == 1 {
    if loca.length < count * 4 {
      raise FontError::InvalidFormat("loca is too short for long format")
    }
    for i = 0; i < count; i = i + 1 {
      offsets.push(view.u32(i * 4))
    }
  } else {
    raise FontError::InvalidFormat("unknown indexToLocFormat \{fmt}")
  }
  offsets
}

///|
/// Chooses the best Unicode cmap subtable. Returns (format, subtable offset
/// relative to the start of the cmap table).
fn find_cmap_subtable(cmap : Slice) -> (Int, Int) raise FontError {
  let num_subtables = cmap.u16(2)
  if num_subtables == 0 {
    raise FontError::InvalidFormat("cmap has no subtables")
  }
  let mut best_format = 0
  let mut best_offset = 0
  // Prefer (platform 3, encoding 10) full Unicode, then (3, 1) BMP, then (0, *)
  // symbol/Unicode records. Only formats 4 and 12 are understood.
  let mut best_score = 99
  for i = 0; i < num_subtables; i = i + 1 {
    let rec = 4 + i * 8
    let platform = cmap.u16(rec)
    let encoding = cmap.u16(rec + 2)
    let sub_off = cmap.u32(rec + 4)
    let format = cmap.u16(sub_off)
    let mut score = 99
    if platform == 3 && encoding == 10 {
      score = 0
    } else if platform == 3 && encoding == 1 {
      score = 1
    } else if platform == 0 {
      score = 2
    }
    if score < best_score && (format == 4 || format == 12) {
      best_score = score
      best_format = format
      best_offset = sub_off
    }
  }
  if best_format == 0 {
    raise FontError::InvalidFormat("no supported Unicode cmap subtable found")
  }
  (best_format, best_offset)
}

///|
/// The font-wide metrics.
pub fn Font::metrics(self : Font) -> FontMetrics {
  self.metrics
}

///|
/// The format (4 or 12) of the Unicode cmap subtable in use.
pub fn Font::cmap_format(self : Font) -> Int {
  self.cmap_format
}

///|
/// Number of glyphs in the font.
pub fn Font::num_glyphs(self : Font) -> Int {
  self.num_glyphs
}

///|
/// The table directory, in file order.
pub fn Font::table_records(self : Font) -> Array[TableRecord] {
  self.tables
}

///|
/// True if the font file carries the given table.
pub fn Font::has_table(self : Font, tag_v : Int) -> Bool {
  for i = 0; i < self.tables.length(); i = i + 1 {
    if self.tables[i].tag == tag_v {
      return true
    }
  }
  false
}

///|
/// Exposes a table as a bounds checked slice.
pub fn Font::table(self : Font, tag_v : Int) -> Slice raise FontError {
  let rec = must_table(self.tables, tag_v)
  Slice::new(self.data, rec.offset, rec.length)
}

///|
/// Horizontal metrics of one glyph (advance width and left side bearing).
pub fn Font::glyph_metrics(self : Font, glyph_id : Int) -> GlyphMetrics raise FontError {
  if glyph_id < 0 || glyph_id >= self.num_glyphs {
    raise FontError::NoGlyph(glyph_id)
  }
  let hmtx = self.table(tag_hmtx())
  let idx = if glyph_id < self.num_h_metrics {
    glyph_id
  } else {
    // Monospaced tail: the last entry of the long metrics array is repeated.
    self.num_h_metrics - 1
  }
  let advance = hmtx.u16(idx * 4)
  let lsb = hmtx.i16(idx * 4 + 2)
  { advance, lsb }
}

///|
/// Advance width of one glyph, in font units.
pub fn Font::advance_width(self : Font, glyph_id : Int) -> Int raise FontError {
  self.glyph_metrics(glyph_id).advance
}

///|
/// Absolute offset of a glyph inside `glyf`, and its length. A zero length
/// means the glyph has no outline (a space, for example).
pub fn Font::glyph_range(self : Font, glyph_id : Int) -> (Int, Int) raise FontError {
  if glyph_id < 0 || glyph_id >= self.num_glyphs {
    raise FontError::NoGlyph(glyph_id)
  }
  let glyf = must_table(self.tables, tag_glyf())
  let start = self.loca[glyph_id]
  let end = self.loca[glyph_id + 1]
  if end < start || end > glyf.length {
    raise FontError::InvalidFormat("loca entry out of range")
  }
  (glyf.offset + start, end - start)
}
