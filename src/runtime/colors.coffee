# Colors are plain 32-bit numbers in 0xAARRGGBB. Everything that accepts a
# color runs it through toColor, so names, builders and raw numbers are
# interchangeable at every call site.

NAMED =
  black:   0x000000
  white:   0xFFFFFF
  red:     0xFF0000
  green:   0x008000
  lime:    0x00FF00
  blue:    0x0000FF
  cyan:    0x00FFFF
  magenta: 0xFF00FF
  yellow:  0xFFFF00
  orange:  0xFFA500
  purple:  0x800080
  gray:    0x808080
  grey:    0x808080
  silver:  0xC0C0C0
  navy:    0x000080
  teal:    0x008080
  olive:   0x808000
  maroon:  0x800000
  pink:    0xFFC0CB
  brown:   0xA52A2A
  coffee:  0xC0FFEE

clamp = (n) -> if n < 0 then 0 else if n > 255 then 255 else n | 0
byte  = (n) -> clamp Math.round n * 255

pack = (a, r, g, b) ->
  ((clamp(a) << 24) | (clamp(r) << 16) | (clamp(g) << 8) | clamp(b)) >>> 0

class ColorBuilder
  constructor: (@a = 255, @r = 0, @g = 0, @b = 0) ->
  setAlpha: (v) -> @a = byte v; this
  setRed:   (v) -> @r = byte v; this
  setGreen: (v) -> @g = byte v; this
  setBlue:  (v) -> @b = byte v; this
  valueOf:  -> pack @a, @r, @g, @b

COLORS =
  byName:      (name)          -> rgb = NAMED[name]; pack 255, (rgb >>> 16) & 0xFF, (rgb >>> 8) & 0xFF, rgb & 0xFF
  fromRGB:     (r, g, b, a = 1)-> pack byte(a),  byte(r),  byte(g),  byte(b)
  fromRGB256:  (r, g, b, a = 255) -> pack a, r, g, b
  create:      -> new ColorBuilder
  names:       -> Object.keys NAMED

COLORS[name] = COLORS.byName name for name of NAMED

toColor = (value, fallback) ->
  switch typeof value
    when 'undefined' then fallback
    when 'number'    then value >>> 0
    when 'string'    then COLORS.byName value
    else                  (value.valueOf() ) >>> 0

# Little-endian byte order in the framebuffer is R,G,B,A, so a Uint32 store
# wants 0xAABBGGRR. Converted once per color, never per pixel.
toNative = (argb) ->
  a = (argb >>> 24) & 0xFF
  r = (argb >>> 16) & 0xFF
  g = (argb >>>  8) & 0xFF
  b =  argb         & 0xFF
  ((a << 24) | (b << 16) | (g << 8) | r) >>> 0

# Swapping R and B is its own inverse, so this is toNative again -- named
# separately because the direction is what matters at the call site.
fromNative = toNative

globalThis.COLORS       = COLORS
globalThis.ColorBuilder = ColorBuilder
globalThis.toColor      = toColor
globalThis.toNative     = toNative
globalThis.fromNative   = fromNative
