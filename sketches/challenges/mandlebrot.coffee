screen w = 300, h = 200

minX = -2
minY = -1
maxX =  1
maxY =  1

maxIter = 2000

window = [[minX, minY], [maxX, maxY]]

main = ->
  loop
    redraw window
    bg = get 0, 0, w - 1, h - 1
    inputLoop bg

selectionBrush = maker (p) ->
  t = (p.x + p.y + elapsed)
  c = (t - floor t)
  COLORS.fromRGB c, c, c

inputLoop = (bg) ->
  wasDown = no
  nextWindow =
    start  : []
    end    : []
    zoomIn : undefined

  loop
    wait 1

    if mouse.down
      if not wasDown
        print "starting selection"

        nextWindow.start  = [mouse.x, mouse.y]
        nextWindow.zoomIn = mouse.left
      else
        put bg, 0, 0
        rect nextWindow.start..., mouse.x, mouse.y, selectionBrush

    else
      if wasDown
        print "ending selection"
        nextWindow.end    = [mouse.x, mouse.y]
        window            = getWindow nextWindow
        break

    wasDown = mouse.down

mapInner = (window, [x, y]) ->
  px = w/x
  py = h/y
  dx = window[1][0] - window[0][0]
  dy = window[1][1] - window[0][1]

  [ window[0][0] + px * dx
    window[0][1] + py * dy
  ]

mapOuter = (window, [x, y]) ->
  px = w/x
  py = h/y
  dx = window[1][0] - window[0][0]
  dy = window[1][1] - window[0][1]

  [ window[0][0] + px * dx
    window[0][1] + py * dy
  ]


getWindow = (nextWindow) ->
  {start, end, zoomIn} = nextWindow
  if start[0] > end[0] then [start[0], end[0]] = [end[0], start[0]]
  if start[1] > end[1] then [start[1], end[1]] = [end[1], start[1]]

  if zoomIn
    window = [ mapInner window, start
               mapInner window, end]
  else
    window = [ mapOuter window, start
               mapOuter window, end]


redraw = (window) ->
  [[x1, y1], [x2, y2]] = window

  step = [(x2 - x1) / w
          (y2 - y1) / h]

  y = y1
  for sy in [0..h - 1]
    x = x1
    line 0, sy, w, sy, 'white'
    for sx in [0..w - 1]
      i = calc [x, y]
      point sx, sy, COLORS.fromHSV 0, 0, log(i) / log(maxIter)
      x += step[0]
    y += step[1]

  return


calc = (c) ->
  z    = c
  iter = 1

  loop
    escaped = 4 <=  ( zrsq = z[0]**2 )
                  + ( zisq = z[1]**2)

    return iter if escaped or iter++ >= maxIter

    z = [ zrsq - zisq     + c[0]
          2 * z[0] * z[1] + c[1] ]

  return

main()

###

- The screen-to-plane map is upside down. Lines 59 and 60 compute the width
  divided by the pixel. The fraction of the screen a pixel sits at is the
  pixel divided by the width. This is the offset-versus-position class again,
  one more time: a pixel coordinate is a position, and the map needs it as a
  fraction of a size. Zooming should feel wrong right now, landing somewhere
  other than the rectangle you drew.

- Zoom out is a copy of zoom in. Both maps are the same function. Zooming out
  means the current window should end up inside the new one, at the rectangle
  you drew, which is the same map run backwards.

- The escape test takes a square root two thousand times per pixel. Compare
  the squared magnitude to four instead. Same answer, no root, and at your
  iteration limit it's most of the frame.

- The algebra in the comment is wrong while the code is right. Squaring a plus
  b i gives a squared minus b squared, plus two a b i, which is what lines 119
  and 120 do. A comment that disagrees with correct code will cost the next
  reader an hour.
