///|
fn usage() -> Unit {
  println("moonbit-font — a pure MoonBit TrueType parser and rasterizer")
  println("")
  println("usage:")
  println("  moonbit-font info <font.ttf>")
  println("  moonbit-font render <font.ttf> <text> <size_px> [out.pgm]")
  println("  moonbit-font glyph <font.ttf> <char> <size_px> [out.pgm]")
  println("  moonbit-font outline <font.ttf> <char>")
  println("")
  println("example:")
  println("  moonbit-font render fixtures/MoonTest-Regular.ttf ABC 32 out.pgm")
}

///|
fn parse_int_arg(s : String) -> Int {
  let mut value = 0
  for c in s.to_array() {
    let digit = c.to_int() - 48
    if digit < 0 || digit > 9 {
      abort("size must be a decimal integer")
    }
    value = value * 10 + digit
  }
  value
}

///|
fn load_font(path : String) -> @lib.Font raise {
  let data = @fs.read_file_to_bytes(path)
  @lib.Font::load(data)
}

///|
fn run_info(path : String) -> Unit raise {
  let font = load_font(path)
  let m = font.metrics()
  let records = font.table_records()
  let mut names = ""
  for i = 0; i < records.length(); i = i + 1 {
    if i > 0 {
      names = names + " "
    }
    names = names + @lib.tag_name(records[i].tag)
  }
  println("font: \{path}")
  println("tables (\{records.length()}): \{names}")
  println("unitsPerEm: \{m.units_per_em}")
  println("numGlyphs: \{font.num_glyphs()}")
  println("ascent / descent / lineGap: \{m.ascent} / \{m.descent} / \{m.line_gap}")
  println("bbox: x \{m.bbox_xmin}..\{m.bbox_xmax}, y \{m.bbox_ymin}..\{m.bbox_ymax}")
  println("cmap format: \{font.cmap_format()}")
  let mut advances = ""
  let probe = if font.num_glyphs() < 8 { font.num_glyphs() } else { 8 }
  for gid = 0; gid < probe; gid = gid + 1 {
    if gid > 0 {
      advances = advances + " "
    }
    advances = advances + font.advance_width(gid).to_string()
  }
  println("advance widths (first \{probe} glyphs): \{advances}")
}

///|
fn run_render(
  font : @lib.Font,
  text : String,
  size : Int,
  out_path : String,
) -> Unit raise {
  let bmp = @lib.render_text(font, text, @lib.RenderOptions::new(size))
  @fs.write_string_to_file(out_path, bmp.to_pgm())
  println("rendered \{bmp.width} x \{bmp.height} px -> \{out_path}")
  println("ink=\{bmp.ink()} covered=\{bmp.covered_ratio()}")
  println(bmp.to_ascii_art())
}

///|
fn run_glyph(
  font : @lib.Font,
  ch : String,
  size : Int,
  out_path : String,
) -> Unit raise {
  let chars = ch.to_array()
  if chars.length() == 0 {
    println("empty character argument")
    return
  }
  let codepoint = chars[0].to_int()
  let gid = font.glyph_index(codepoint)
  if gid == 0 {
    println("font does not cover U+\{codepoint}")
    return
  }
  let bmp = @lib.render_glyph(font, gid, size)
  @fs.write_string_to_file(out_path, bmp.to_pgm())
  println("glyph U+\{codepoint} -> gid \{gid}, \{bmp.width} x \{bmp.height} px -> \{out_path}")
  println(bmp.to_ascii_art())
}

///|
fn run_outline(font : @lib.Font, ch : String, svg : Bool) -> Unit raise {
  let chars = ch.to_array()
  if chars.length() == 0 {
    println("empty character argument")
    return
  }
  let codepoint = chars[0].to_int()
  let gid = font.glyph_index(codepoint)
  if gid == 0 {
    println("font does not cover U+\{codepoint}")
    return
  }
  let outline = font.outline(gid)
  let box = outline.bbox()
  println("U+\{codepoint} -> gid \{gid}: \{outline.contours.length()} contour(s), \{outline.point_count()} point(s)")
  println("bbox: x \{box.x_min.to_int()}..\{box.x_max.to_int()}, y \{box.y_min.to_int()}..\{box.y_max.to_int()}")
  for c = 0; c < outline.contours.length(); c = c + 1 {
    let contour = outline.contours[c]
    let mut line = "contour \{c}:"
    for i = 0; i < contour.points.length(); i = i + 1 {
      let p = contour.points[i]
      let kind = if p.on_curve { "on" } else { "off" }
      line = line + " (\{p.x.to_int()},\{p.y.to_int()},\{kind})"
    }
    println(line)
  }
  if svg {
    let width = (box.x_max - box.x_min).to_int()
    let height = (box.y_max - box.y_min).to_int()
    println("")
    println("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \{width} \{height}\">")
    println("  <path fill-rule=\"nonzero\" transform=\"translate(\{(-box.x_min).to_int()} \{box.y_max.to_int()}) scale(1 -1)\" d=\"\{outline.to_svg_path()}\"/>")
    println("</svg>")
  }
}

///|
fn run_kern(font : @lib.Font, left : String, right : String) -> Unit raise {
  let left_chars = left.to_array()
  let right_chars = right.to_array()
  if left_chars.length() == 0 || right_chars.length() == 0 {
    println("usage: kern <font.ttf> <left_char> <right_char>")
    return
  }
  let left_gid = font.glyph_index(left_chars[0].to_int())
  let right_gid = font.glyph_index(right_chars[0].to_int())
  let adjustment = font.kern(left_gid, right_gid)
  println("kern(\{left},\{right}): gid \{left_gid},\{right_gid} = \{adjustment} font units")
}

///|
fn main raise {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  let cmd = args[1]
  if cmd == "info" {
    if args.length() < 3 {
      usage()
      return
    }
    run_info(args[2])
  } else if cmd == "render" {
    if args.length() < 5 {
      usage()
      return
    }
    let font = load_font(args[2])
    let size = parse_int_arg(args[4])
    let out_path = if args.length() >= 6 { args[5] } else { "out.pgm" }
    run_render(font, args[3], size, out_path)
  } else if cmd == "glyph" {
    if args.length() < 5 {
      usage()
      return
    }
    let font = load_font(args[2])
    let size = parse_int_arg(args[4])
    let out_path = if args.length() >= 6 { args[5] } else { "glyph.pgm" }
    run_glyph(font, args[3], size, out_path)
  } else if cmd == "outline" {
    if args.length() < 4 {
      usage()
      return
    }
    let font = load_font(args[2])
    let svg = args.length() >= 5 && args[4] == "--svg"
    run_outline(font, args[3], svg)
  } else if cmd == "kern" {
    if args.length() < 5 {
      usage()
      return
    }
    let font = load_font(args[2])
    run_kern(font, args[3], args[4])
  } else {
    usage()
  }
}
