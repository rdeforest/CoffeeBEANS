# Flood fill. Every rule is the same walk with a different answer to one
# question: may the fill continue into this pixel. "Stop at anything unlike
# where I started" and "stop at black" are not two features, they are two
# predicates.
#
# The walk knows nothing about colour. It is handed a writer for a run of
# pixels, which is how a fill gets patterns and gradients for free the
# moment span does.

class Rule
  constructor: (@test, @fast = null) ->

asking = PROBE.create()

where = (test) -> new Rule test

matching = (value) ->
  wanted = toNative toColor value
  new Rule ((p) -> p.color is fromNative wanted), (pixel) -> pixel is wanted

border = (value) ->
  edge = toNative toColor value
  new Rule ((p) -> p.color isnt fromNative edge), (pixel) -> pixel isnt edge

SAME_AS_SEED = new Rule ((p) -> p.color is p.seed), (pixel, seed) -> pixel is seed

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
flood = (view, startX, startY, write, rule = SAME_AS_SEED) ->
  {width, height, base} = view
  return undefined if startX < 0 or startY < 0 or startX >= width or startY >= height

  seen = marks width * height
  seed = view.pixels[base + startY * width + startX]
  same = fromNative seed

  allowed =
    if rule.fast?
      (index) -> rule.fast view.pixels[base + index], seed
    else
      (index) ->
        x = index % width
        rule.test asking.place view, x, (index - x) / width, same

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

    # Marked before writing: a maker is free to read the pixel it is
    # replacing, and must not be invited to walk into it a second time.
    seen[y * width + column] = 1 for column in [left..right] by 1
    write y, left, right

    for scan in [y - 1, y + 1] when 0 <= scan < height
      running = false
      for column in [left..right] by 1
        if open column, scan
          stack.push column, scan unless running
          running = true
        else
          running = false
  undefined

globalThis.FILL = {Rule, flood, where, matching, border}
