# The other axis. A rule decides which pixels a fill touches; a paint decides
# what colour each one becomes. Both take the same probe, so learning one
# teaches the other.
#
# A solid colour stays a plain number all the way down: `painter` hands back
# an object carrying it, and plot and span fill runs with it in one call.
# Only a maker costs a call per pixel, and only where one is used.

class Paint
  constructor: (@at) ->

maker = (produce) -> new Paint produce

# Repeats a surface across the target. The classic 8x8 fill pattern, except
# nothing here cares how big it is.
tile = (source, offsetX = 0, offsetY = 0) ->
  {width, height, pixels, base} = source
  maker (p) ->
    x = (p.x - offsetX) %% width
    y = (p.y - offsetY) %% height
    fromNative pixels[base + y * width + x]

mix = (from, to, amount) ->
  blend = (shift) ->
    start = (from >>> shift) & 0xFF
    Math.round start + (((to >>> shift) & 0xFF) - start) * amount
  COLORS.fromRGB256 blend(16), blend(8), blend(0), blend(24)

# A linear ramp along `angle`, measured over the distance the gradient spans.
# Defaults to the width of the current screen, which is what you want when
# you are washing a background and do not want to think about it.
gradient = (from, to, options = {}) ->
  start  = toColor from
  finish = toColor to
  angle  = options.angle  ? 0
  length = options.length ? LAYOUT.MAX_WIDTH
  originX = options.x ? 0
  originY = options.y ? 0
  alongX = Math.cos angle
  alongY = Math.sin angle
  maker (p) ->
    reach = ((p.x - originX) * alongX + (p.y - originY) * alongY) / length
    mix start, finish, Math.min 1, Math.max 0, reach

# Distance from a centre rather than along a line. Same ramp, different
# measure, so it is the same function with one line changed.
radial = (from, to, options = {}) ->
  start   = toColor from
  finish  = toColor to
  centreX = options.x ? 0
  centreY = options.y ? 0
  length  = options.radius ? 100
  maker (p) ->
    reach = Math.hypot(p.x - centreX, p.y - centreY) / length
    mix start, finish, Math.min 1, Math.max 0, reach

globalThis.PAINT = {Paint, maker, tile, gradient, radial, mix}
