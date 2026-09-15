# Flood fill. Every rule is the same walk with a different answer to one
# question: may the fill continue into this pixel. "Stop at anything unlike
# where I started" and "stop at black" are not two features, they are two
# predicates.

class Rule
  constructor: (@test, @fast = null) ->

# The probe a `where` predicate receives. One object, reused for every pixel
# tested: a fill can test tens of thousands, and building an object with an
# HSV conversion for each would cost more than the walk it is guiding. The
# getters compute on demand, so a predicate reading only p.color pays for
# nothing else. It is valid during the call and not after.
probe = {}

at =
  x: 0, y: 0, colour: 0, seed: 0, view: null
  hsv: no, hue: 0, saturation: 0, value: 0

channel = (shift) -> -> ((at.colour >>> shift) & 0xFF) / 255

neighbour = (dx, dy) -> ->
  x = at.x + dx
  y = at.y + dy
  return null if x < 0 or y < 0 or x >= at.view.width or y >= at.view.height
  fromNative at.view.pixels[at.view.base + y * at.view.width + x]

# Which channel is the maximum decides the formula, so the formulas are a
# table indexed by that rather than a chain asking the same question thrice.
HUE_FROM = [
  (r, g, b, span) -> ((g - b) / span) %% 6
  (r, g, b, span) -> (b - r) / span + 2
  (r, g, b, span) -> (r - g) / span + 4
]

triple = [0, 0, 0]          # reused; allocating one per pixel is the whole cost

resolveHSV = ->
  return if at.hsv
  at.hsv = yes
  r    = ((at.colour >>> 16) & 0xFF) / 255
  g    = ((at.colour >>>  8) & 0xFF) / 255
  b    =  (at.colour         & 0xFF) / 255
  high = Math.max r, g, b
  span = high - Math.min r, g, b
  at.value      = high
  at.saturation = if high is 0 then 0 else span / high
  triple[0] = r
  triple[1] = g
  triple[2] = b
  at.hue        = if span is 0 then 0 else 60 * HUE_FROM[triple.indexOf high] r, g, b, span
  undefined

hsvGetter = (name) -> -> resolveHSV(); at[name]

Object.defineProperties probe,
  x:          get: -> at.x
  y:          get: -> at.y
  color:      get: -> at.colour
  seed:       get: -> at.seed
  alpha:      get: channel 24
  red:        get: channel 16
  green:      get: channel 8
  blue:       get: channel 0
  hue:        get: hsvGetter 'hue'
  saturation: get: hsvGetter 'saturation'
  value:      get: hsvGetter 'value'
  up:         get: neighbour  0, -1
  down:       get: neighbour  0,  1
  left:       get: neighbour -1,  0
  right:      get: neighbour  1,  0

# --- the rules --------------------------------------------------------------

where = (test) -> new Rule test

matching = (value) ->
  wanted = toNative toColor value
  new Rule ((p) -> p.color is fromNative wanted), (pixel) -> pixel is wanted

border = (value) ->
  edge = toNative toColor value
  new Rule ((p) -> p.color isnt fromNative edge), (pixel) -> pixel isnt edge

SAME_AS_SEED = new Rule ((p) -> p.color is p.seed), (pixel, seed) -> pixel is seed

# --- the walk ---------------------------------------------------------------

# Kept and regrown rather than allocated per call, so a fill inside an
# animation loop does not make a new one every frame. Without it a rule that
# still accepts the colour being painted -- `fill x, y` where the fill colour
# equals the seed is the easy one to write -- would never terminate.
scratch = new Uint8Array 0

marks = (size) ->
  scratch = new Uint8Array size if scratch.length < size
  scratch.fill 0, 0, size
  scratch

# Scanline spans, not a pixel at a time: a 320x200 region is 64,000 pixels
# and a per-pixel queue is both slower and enormous. Four-way, not eight,
# because eight leaks through diagonal hairlines.
flood = (view, startX, startY, pixel, rule = SAME_AS_SEED) ->
  {width, height, base} = view
  return undefined if startX < 0 or startY < 0 or startX >= width or startY >= height

  seen = marks width * height
  seed = view.pixels[base + startY * width + startX]

  at.view = view
  at.seed = fromNative seed

  allowed =
    if rule.fast?
      (index) -> rule.fast view.pixels[base + index], seed
    else
      (index) ->
        at.x      = index % width
        at.y      = (index - at.x) / width
        at.colour = fromNative view.pixels[base + index]
        at.hsv    = no
        rule.test probe

  open = (x, y) ->
    index = y * width + x
    return false if seen[index]
    allowed index

  stack = [startX, startY]
  while stack.length
    y = stack.pop()
    x = stack.pop()
    continue unless open x, y

    left = x
    left  -= 1 while left > 0 and open(left - 1, y)
    right = x
    right += 1 while right < width - 1 and open(right + 1, y)

    row = base + y * width
    for column in [left..right] by 1
      view.pixels[row + column] = pixel
      seen[y * width + column] = 1

    for scan in [y - 1, y + 1] when 0 <= scan < height
      running = false
      for column in [left..right] by 1
        if open column, scan
          stack.push column, scan unless running
          running = true
        else
          running = false
  undefined

globalThis.FILL = {Rule, flood, where, matching, border, probe}
