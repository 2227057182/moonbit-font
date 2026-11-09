// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html

name = "2227057182/moonbit-font"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/2227057182/moonbit-font"

license = "Apache-2.0"

keywords = [
  "font",
  "ttf",
  "truetype",
  "glyph",
  "rasterizer",
  "text",
  "opentype",
]

preferred_target = "wasm"

description = "Pure-MoonBit TrueType font parser, glyph rasterizer and text layout engine"

import {
  "moonbitlang/x@0.5.6",
}
