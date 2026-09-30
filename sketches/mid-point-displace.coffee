# https://en.wikipedia.org/wiki/Diamond-square_algorithm
# sucked, let's do triangles instead.

# newHeight = mean + rnd(rnd_scale * diamond_size)
RND_SCALE    = 5
SCALE_FACTOR = 0.5

scale = 8

makeGrid = (size) ->
  Object.assign grid = [],
    size: size
    get: (x, y   ) ->
      grid[y * @size + x] ? 0
    set: (x, y, v) ->
      if x > size
        print "wrote to #{},#{}"
      grid[y * @size + x] = v

sum  = (l) -> l.reduce (a, b) -> a + b
mean = (l) -> sum(l)/l.length

displaceMid = (grid, x, y, dist, peers...) ->
  grid.set x, y, value = dist * RND_SCALE * (rnd() - 0.5) + mean peers
  #point grid.size / 2 - y/2 + x, y, 'red'
  value

min2 = (a, b) -> min a, b
max2 = (a, b) -> max a, b

doTri = (grid, x, y, s, up) ->
  h = s >> 1
  [xa, ya]   = [x   ,  y    ]
  [xb, yb]   = [x + s, y + s]
  [xd, yd]   = [x + h, y + h]

  # a f c
  # f d e
  # c e b
  if up
    [xc, yc] = [x    , y + s]
    [xe, ye] = [x + h, y + s]
    [xf, yf] = [x    , y + h]
  else
    [xc, yc] = [x + s, y    ]
    [xe, ye] = [x + s, y + h]
    [xf, yf] = [x + h, y    ]

  a = grid.get xa, ya
  b = grid.get xb, yb
  c = grid.get xc, yc

  d = displaceMid grid, xd, yd, h, a, b
  e = displaceMid grid, xe, ye, h, b, c
  f = displaceMid grid, xf, yf, h, c, a


gen = (scale) ->
  size = 2**scale + 1
  grid = makeGrid size

  grid.set 0,        0,        rnd(10) - 5
  grid.set size - 1, 0,        rnd(10) - 5
  grid.set 0,        size - 1, rnd(10) - 5
  grid.set size - 1, size - 1, rnd(10) - 5

  rndScale = RND_SCALE

  step = size >> 1
  while step > 1
    half = step >> 1

    for   y in [0 .. size - 2] by step
      for x in [0 ..    y - 1] by step
        doTri grid, x, y, step, yes

      # XXX preserve shape of overlap between left and right triangles.
      # Last step of previous loop set (y+half,y+half) based on (y,y) and
      # (y+step,y+step). We re-calculate it and then throw out the one
      # redundant point ('d'). The name 'd' comes from the six names of the
      # points of a triangle-in-progress. a-c are the corners, d-f are the
      # midpoints. 'd' is the midpoint between a and c.
      #d = grid.get y + half, y + half
      #doTri grid, y, y, step, no
      #grid.set y + half, y + half, d

      for x in [y + 1 .. size - 2] by step
        doTri grid, x, y, step, no

    step >>= 1
    rndScale *= SCALE_FACTOR

  grid.range =
    lo: grid.reduce min2
    hi: grid.reduce max2

  grid

screen w = (2**scale + 1) * 1.5, h = 2**scale + 1

grid  = gen scale

{lo, hi} = grid.range
depth = hi - lo

for   x in [0..grid.size - 1]
  for y in [0..grid.size - 1]
    value = (grid.get(x, y) - lo) / depth
    point grid.size / 2 - y / 2 + x, y, COLORS.fromHSV 0, 0, value

