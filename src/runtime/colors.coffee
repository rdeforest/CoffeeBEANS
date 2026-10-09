# Colors are plain 32-bit numbers in 0xAARRGGBB. Everything that accepts a
# color runs it through toColor, so names, colour objects (a Color or a plain
# {r, g, b, a, h, s, v}) and raw numbers are interchangeable at every call
# site.

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

# A colour object carries RGB and HSV side by side, so setting one model
# never loses what the other knew: a hue set on black is still there when the
# value comes up, which is the whole point of keeping h, s and v at all.
# Bytes (a, r, g, b) are 0..255, hue is degrees, saturation and value 0..1.
# Each of those is an accessor of the instance's own, so `c.h = 30` is
# setHueDegrees and both halves stay in step however a colour is changed.
# Own and enumerable, not on the prototype, so a Color still prints, spreads
# and stringifies as {a, r, g, b, h, s, v}.
class Color
  constructor: (a = 255, r = 0, g = 0, b = 0, h = 0, s = 0, v = 0) ->
    Object.defineProperty this, HELD, value: {a, r, g, b, h, s, v}
    Object.defineProperties this, ACCESSORS

  setAlphaByte:  (n) -> @[HELD].a = roundByte number 'alpha', n; this
  setRedByte:    (n) -> @[HELD].r = roundByte number 'red',   n; @rgbChanged()
  setGreenByte:  (n) -> @[HELD].g = roundByte number 'green', n; @rgbChanged()
  setBlueByte:   (n) -> @[HELD].b = roundByte number 'blue',  n; @rgbChanged()
  setAlphaLevel: (n) -> @setAlphaByte number('alpha', n) * 255
  setRedLevel:   (n) -> @setRedByte   number('red',   n) * 255
  setGreenLevel: (n) -> @setGreenByte number('green', n) * 255
  setBlueLevel:  (n) -> @setBlueByte  number('blue',  n) * 255

  setHueDegrees: (n) -> @[HELD].h = ((number('hue', n) % 360) + 360) % 360; @hsvChanged()
  setSaturation: (n) -> @[HELD].s = unit number 'saturation', n; @hsvChanged()
  setValue:      (n) -> @[HELD].v = unit number 'value', n; @hsvChanged()

  # A grey has no hue to read back and black no saturation either, so those
  # keep what they were rather than snapping to 0.
  rgbChanged: ->
    held = @[HELD]
    hsvInto pack(255, held.r, held.g, held.b), scratch
    held.h = scratch[0] unless scratch[1] is 0
    held.s = scratch[1] unless scratch[2] is 0
    held.v = scratch[2]
    this

  hsvChanged: ->
    held   = @[HELD]
    packed = fromHSV held.h, held.s, held.v
    held.r = (packed >>> 16) & 0xFF
    held.g = (packed >>>  8) & 0xFF
    held.b =  packed         & 0xFF
    this

  valueOf: ->
    held = @[HELD]
    pack held.a, held.r, held.g, held.b

# Where a Color keeps what its accessors show. A symbol, so it never prints
# and no sketch's own key can collide with it.
HELD = Symbol 'colour'

roundByte = (n) -> clamp Math.round n

# NaN would pack as 0 and draw black without a word.
number = (what, n) ->
  return n if typeof n is 'number' and isFinite n
  shown = if typeof n is 'string' then JSON.stringify n else describe n
  throw new Error "a colour's #{what} must be a number, got #{shown}"

# A plain object is read key by key in its own order, each key applied as
# its setter would be, so {r: 1, v: 0.5} is a red at half value.
COLOR_KEYS =
  a: 'setAlphaByte'
  r: 'setRedByte'
  g: 'setGreenByte'
  b: 'setBlueByte'
  h: 'setHueDegrees'
  s: 'setSaturation'
  v: 'setValue'

applyKeys = (color, object) ->
  any = false
  for own key, n of object
    unless Object.prototype.hasOwnProperty.call COLOR_KEYS, key
      throw new Error "not a colour key: #{key} -- a colour object takes a, r, g, b, h, s and v"
    color[COLOR_KEYS[key]] n
    any = true
  throw new Error 'not a colour: an object with none of a, r, g, b, h, s, v' unless any
  color

isPlain = (value) ->
  proto = Object.getPrototypeOf value
  proto is Object.prototype or proto is null

ACCESSORS = {}
for own key, setter of COLOR_KEYS then do (key, setter) ->
  ACCESSORS[key] =
    enumerable: true
    get:     -> @[HELD][key]
    set: (n) -> @[setter] n

# A maker may hand back an object for every pixel, so reading one reuses a
# single Color rather than allocating another.
reading = new Color

fromObject = (object) ->
  held = reading[HELD]
  held.a = 255
  held.r = held.g = held.b = held.h = held.s = held.v = 0
  applyKeys(reading, object).valueOf()

# What the COLORS.set* functions work on: a Color is changed in place, and
# anything else becomes a new one -- a plain object keeping the hue it gave.
asColor = (value) ->
  return value if value instanceof Color
  return applyKeys new Color, value if value? and typeof value is 'object' and isPlain value
  argb = toColor value
  new Color((argb >>> 24) & 0xFF, (argb >>> 16) & 0xFF, (argb >>> 8) & 0xFF, argb & 0xFF).rgbChanged()

SETTERS = ['setAlphaByte', 'setRedByte', 'setGreenByte', 'setBlueByte',
           'setAlphaLevel', 'setRedLevel', 'setGreenLevel', 'setBlueLevel',
           'setHueDegrees', 'setSaturation', 'setValue']

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
  create:      -> new Color
  names:       -> Object.keys NAMED

COLORS[name] = COLORS.byName name for name of NAMED
for setter in SETTERS then do (setter) ->
  COLORS[setter] = (color, n) -> asColor(color)[setter] n

# Anything that is not a colour says so. It used to coerce: `true` became
# 0x1, which is transparent, and null threw somewhere inside valueOf with a
# message about no colour at all.
toColor = (value, fallback) ->
  switch typeof value
    when 'undefined' then fallback
    when 'number'    then value >>> 0
    when 'string'    then COLORS.byName value
    else
      return value.valueOf() if value instanceof Color
      return fromObject value if value? and typeof value is 'object' and isPlain value
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
globalThis.Color        = Color
globalThis.toColor      = toColor
globalThis.toNative     = toNative
globalThis.hsvInto      = hsvInto
globalThis.fromNative   = fromNative
