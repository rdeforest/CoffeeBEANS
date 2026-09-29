# https://en.wikipedia.org/wiki/Diamond-square_algorithm

# newHeight = mean + rnd(rnd_scale * diamond_size)
RND_SCALE    = 5
SCALE_FACTOR = 0.3

makeGrid = (size) ->
  Object.assign grid = [],
    size: size
    get: (x, y   ) -> grid[y * @size + x] ? 0
    set: (x, y, v) -> grid[y * @size + x] = v

sqrt2 = sqrt 2

sum  = (l) -> l.reduce (a, b) -> a + b
mean = (l) -> sum(l)/l.length

displaceMid = (grid, x, y, dist, peers...) ->
  grid.set x, y, value = dist * RND_SCALE * (rnd() - 0.5) + mean peers
  value

gen = (scale) ->
  size = 2**scale + 1
  grid = makeGrid size

  grid.set 0,        0,        rnd(10) - 5
  grid.set size - 1, 0,        rnd(10) - 5
  grid.set size - 1, size - 1, rnd(10) - 5
  grid.set 0,        size - 1, rnd(10) - 5

  grid.range =
  range = hi: -Infinity, lo: Infinity
  rndScale = RND_SCALE

  step = size >> 1
  while step > 1
    halfStep = step >> 1

    for y in [0..size - 2] by step
      for x in [0..size - 2] by step
        xm = x + halfStep
        ym = y + halfStep

        a = grid.get x       , y
        b = grid.get x + step, y
        c = grid.get x + step, y + step
        d = grid.get     step, y + step

        e = grid.get xm       , ym - step
        f = grid.get xm + step, ym
        g = grid.get xm       , ym + step
        h = grid.get xm - step, ym

        i = displaceMid grid, xm,       ym,       rndScale, a, b, c, d

        j = displaceMid grid, xm,       y,        rndScale, a, e, b, i
        k = displaceMid grid, x + step, ym,       rndScale, b, f, c, i
        l = displaceMid grid, xm,       y + step, rndScale, c, g, d, i
        m = displaceMid grid, x,        ym,       rndScale, d, h, a, i

        range.lo = min range.lo, i, j, k, l, m
        range.hi = max range.hi, i, j, k, l, m

    step >>= 1
    rndScale *= SCALE_FACTOR
  grid

grid = gen 10

screen w = grid.size, w

depth = grid.range.hi - grid.range.lo

print "hi: #{grid.range.hi}, lo: #{grid.range.lo}, depth: #{depth}"

for x in [0..grid.size - 1]
  for y in [0..grid.size - 1]
    value = (grid.get(x, y) - grid.range.lo) / depth
    #print "#{x}, #{y}, #{value}"
    point x, y, COLORS.fromHSV 0, 0, value

