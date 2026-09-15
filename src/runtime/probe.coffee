# What a fill rule and a paint maker both receive. One concept, learned once:
#
#   fill 10, 10, where  (p) -> p.value < 0.5      # which pixels
#   color       maker   (p) -> ...                # what colour each becomes
#
# Everything is computed on demand, including the colour already at the
# position. A maker that reads only p.x should not pay to read the
# destination, and nothing should pay for an HSV conversion it never asks
# about. A fill can test or paint tens of thousands of pixels, so this is
# the difference between a cheap walk and an expensive one.
#
# The object is reused for every pixel. It is valid during the call and not
# after; keep a reference and you will watch it change underneath you.

create = ->
  at =
    view: null, x: 0, y: 0, seed: 0
    colour: 0, hasColour: no
    hsv: no, hue: 0, saturation: 0, value: 0
  parts = [0, 0, 0]           # reused; allocating one per pixel is the cost

  colourAt = (x, y) ->
    {view} = at
    return null if x < 0 or y < 0 or x >= view.width or y >= view.height
    fromNative view.pixels[view.base + y * view.width + x]

  colour = ->
    unless at.hasColour
      at.colour    = colourAt at.x, at.y
      at.hasColour = yes
    at.colour

  channel   = (shift) -> -> ((colour() >>> shift) & 0xFF) / 255
  neighbour = (dx, dy) -> -> colourAt at.x + dx, at.y + dy

  resolveHSV = ->
    return if at.hsv
    at.hsv = yes
    hsvInto colour(), parts
    at.hue        = parts[0]
    at.saturation = parts[1]
    at.value      = parts[2]
    undefined

  fromHSV = (name) -> -> resolveHSV(); at[name]

  probe = {}
  Object.defineProperties probe,
    x:          get: -> at.x
    y:          get: -> at.y
    seed:       get: -> at.seed
    color:      get: colour
    alpha:      get: channel 24
    red:        get: channel 16
    green:      get: channel 8
    blue:       get: channel 0
    hue:        get: fromHSV 'hue'
    saturation: get: fromHSV 'saturation'
    value:      get: fromHSV 'value'
    up:         get: neighbour  0, -1
    down:       get: neighbour  0,  1
    left:       get: neighbour -1,  0
    right:      get: neighbour  1,  0

  place: (view, x, y, seed = 0) ->
    at.view      = view
    at.x         = x
    at.y         = y
    at.seed      = seed
    at.hasColour = no
    at.hsv       = no
    probe

globalThis.PROBE = {create}
