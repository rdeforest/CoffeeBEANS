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

  # Round-tripped through HSV so `setValue` means the same thing here as it
  # does on a probe. A grey has no hue to preserve, which is why setting the
  # saturation of one leaves it grey.
  replaceHSV: (hue, saturation, value) ->
    packed = fromHSV hue, saturation, value
    @r = (packed >>> 16) & 0xFF
    @g = (packed >>>  8) & 0xFF
    @b =  packed         & 0xFF
    this
  setHue:        (v) -> hsvInto @valueOf(), scratch; @replaceHSV v,         scratch[1], scratch[2]
  setSaturation: (v) -> hsvInto @valueOf(), scratch; @replaceHSV scratch[0], v,         scratch[2]
  setValue:      (v) -> hsvInto @valueOf(), scratch; @replaceHSV scratch[0], scratch[1], v

unit = (value) -> Math.min 1, Math.max 0, value

# Which channels carry the chroma, per 60 degree sector. A table rather than
# a six-armed conditional, because that is all the conditional would encode.
SECTORS = [
  (c, x) -> [c, x, 0]
  (c, x) -> [x, c, 0]
  (c, x) -> [0, c, x]
  (c, x) -> [0, x, c]
  (c, x) -> [x, 0, c]
  (c, x) -> [c, 0, x]
]

# Which channel is the maximum decides the formula, so the formulas are a
# table indexed by that rather than a chain asking the same question thrice.
HUE_FROM = [
  (r, g, b, span) -> ((g - b) / span) %% 6
  (r, g, b, span) -> (b - r) / span + 2
  (r, g, b, span) -> (r - g) / span + 4
]

ranked = [0, 0, 0]

# Writes into a caller-supplied array. The probe calls this once per pixel,
# so it must not allocate; toHSV below is the convenient wrapper over it.
hsvInto = (argb, out) ->
  r = ((argb >>> 16) & 0xFF) / 255
  g = ((argb >>>  8) & 0xFF) / 255
  b =  (argb         & 0xFF) / 255
  high = Math.max r, g, b
  span = high - Math.min r, g, b
  ranked[0] = r
  ranked[1] = g
  ranked[2] = b
  out[0] = if span is 0 then 0 else ((60 * HUE_FROM[ranked.indexOf high] r, g, b, span) %% 360)
  out[1] = if high is 0 then 0 else span / high
  out[2] = high
  out

scratch = [0, 0, 0]

fromHSV = (hue, saturation = 1, value = 1, alpha = 1) ->
  hue        = ((hue % 360) + 360) % 360
  saturation = unit saturation
  value      = unit value
  chroma     = value * saturation
  second     = chroma * (1 - Math.abs(((hue / 60) % 2) - 1))
  [r, g, b]  = SECTORS[Math.floor(hue / 60) % 6] chroma, second
  base       = value - chroma
  pack byte(alpha), byte(r + base), byte(g + base), byte(b + base)

COLORS =
  fromHSV:     fromHSV
  toHSV:       (value) ->
    [hue, saturation, brightness] = hsvInto toColor(value), [0, 0, 0]
    {hue, saturation, value: brightness}
  byName:      (name)          ->
    # A name we do not know used to come back as opaque black, which is a
    # colour, so a typo drew perfectly happily and invisibly. Own property
    # only: NAMED is a plain object, and `toString` is not a colour.
    unless Object.prototype.hasOwnProperty.call NAMED, name
      throw new Error "no colour named \"#{name}\" -- try COLORS.names()"
    rgb = NAMED[name]
    pack 255, (rgb >>> 16) & 0xFF, (rgb >>> 8) & 0xFF, rgb & 0xFF
  fromRGB:     (r, g, b, a = 1)-> pack byte(a),  byte(r),  byte(g),  byte(b)
  fromRGB256:  (r, g, b, a = 255) -> pack a, r, g, b
  create:      -> new ColorBuilder
  names:       -> Object.keys NAMED

COLORS[name] = COLORS.byName name for name of NAMED

# Anything that is not a colour says so. It used to coerce: `true` became
# 0x1, which is transparent, and null threw somewhere inside valueOf with a
# message about no colour at all.
toColor = (value, fallback) ->
  switch typeof value
    when 'undefined' then fallback
    when 'number'    then value >>> 0
    when 'string'    then COLORS.byName value
    else
      packed = value?.valueOf?()
      throw new Error "not a colour: #{describe value}" unless typeof packed is 'number'
      packed >>> 0

describe = (value) ->
  return 'null' if value is null
  if typeof value is 'object' then value.constructor?.name ? 'an object' else String value

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
globalThis.hsvInto      = hsvInto
globalThis.fromNative   = fromNative
