# An off-screen block of pixels, shaped exactly like the screen target so
# every drawing primitive works on one without knowing the difference.
# Sprites, captured regions, loaded images and font glyphs are all this.

class Surface
  constructor: (width, height) ->
    @width  = Math.max 1, width  | 0
    @height = Math.max 1, height | 0
    @base   = 0
    @pixels = new Uint32Array @width * @height

# PUT's actions in GW-BASIC were PSET, PRESET, AND, OR and XOR. These are
# the same idea; `over` is the one BASIC had no need for, since nothing on
# an EGA screen was transparent.
BLIT =
  over: (under, over) -> over
  copy: (under, over) -> over
  or:   (under, over) -> (under | over) >>> 0
  and:  (under, over) -> (under & over) >>> 0
  xor:  (under, over) -> (under ^ over) >>> 0

opaque = (pixel) -> (pixel >>> 24) isnt 0

blit = (dest, dx, dy, source, mode = 'over') ->
  combine = BLIT[mode]
  throw new Error "unknown put mode \"#{mode}\" -- try #{Object.keys(BLIT).join ', '}" unless combine
  skipClear = mode is 'over'

  left   = Math.max 0, -dx
  top    = Math.max 0, -dy
  right  = Math.min source.width,  dest.width  - dx
  bottom = Math.min source.height, dest.height - dy
  return undefined if left >= right or top >= bottom

  for y in [top...bottom] by 1
    sourceRow = source.base + y * source.width
    destRow   = dest.base + (dy + y) * dest.width + dx
    for x in [left...right] by 1
      pixel = source.pixels[sourceRow + x]
      continue if skipClear and not opaque pixel
      at = destRow + x
      dest.pixels[at] = combine dest.pixels[at], pixel
  undefined

# Sampled per destination pixel and inverse-transformed back into the
# source. Forward mapping would leave holes wherever the transform magnifies.
# Nearest neighbour on purpose: the crunch is the aesthetic.
stamp = (dest, x, y, source, options = {}) ->
  mode    = options.mode ? 'over'
  combine = BLIT[mode]
  throw new Error "unknown stamp mode \"#{mode}\" -- try #{Object.keys(BLIT).join ', '}" unless combine
  skipClear = mode is 'over'

  scaleX = options.scaleX ? options.scale ? 1
  scaleY = options.scaleY ? options.scale ? 1
  return undefined if scaleX is 0 or scaleY is 0

  angle   = options.angle ? 0
  anchorX = options.anchorX ? 0
  anchorY = options.anchorY ? 0
  cos     = Math.cos angle
  sin     = Math.sin angle

  # Where the four source corners land, so we only walk pixels that matter.
  xs = []
  ys = []
  for [cx, cy] in [[0, 0], [source.width, 0], [0, source.height], [source.width, source.height]]
    ux = (cx - anchorX) * scaleX
    uy = (cy - anchorY) * scaleY
    xs.push x + ux * cos - uy * sin
    ys.push y + ux * sin + uy * cos

  left   = Math.max 0,               Math.floor Math.min xs...
  top    = Math.max 0,               Math.floor Math.min ys...
  right  = Math.min dest.width  - 1, Math.ceil  Math.max xs...
  bottom = Math.min dest.height - 1, Math.ceil  Math.max ys...
  return undefined if left > right or top > bottom

  for py in [top..bottom] by 1
    destRow = dest.base + py * dest.width
    for px in [left..right] by 1
      rx = px - x
      ry = py - y
      sx = Math.floor(( rx * cos + ry * sin) / scaleX + anchorX)
      sy = Math.floor((-rx * sin + ry * cos) / scaleY + anchorY)
      continue if sx < 0 or sy < 0 or sx >= source.width or sy >= source.height
      pixel = source.pixels[source.base + sy * source.width + sx]
      continue if skipClear and not opaque pixel
      at = destRow + px
      dest.pixels[at] = combine dest.pixels[at], pixel
  undefined

# Bounding boxes first, then the actual pixels. Computed on demand rather
# than from a cached 1-bit mask, because a cached mask has to be invalidated
# every time anything draws into the surface and that is a bug waiting.
overlaps = (first, fx, fy, second, sx, sy) ->
  fx = Math.round fx; fy = Math.round fy; sx = Math.round sx; sy = Math.round sy
  left   = Math.max fx, sx
  top    = Math.max fy, sy
  right  = Math.min fx + first.width,  sx + second.width
  bottom = Math.min fy + first.height, sy + second.height
  return false if left >= right or top >= bottom

  for y in [top...bottom] by 1
    rowFirst  = first.base  + (y - fy) * first.width  - fx
    rowSecond = second.base + (y - sy) * second.width - sx
    for x in [left...right] by 1
      continue unless opaque first.pixels[rowFirst + x]
      return true if opaque second.pixels[rowSecond + x]
  false

globalThis.SURFACE = {Surface, BLIT, blit, stamp, overlaps, opaque}
