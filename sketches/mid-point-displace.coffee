# https://en.wikipedia.org/wiki/Diamond-square_algorithm

screen w = 257, h = 257

makeGrid = (size) ->
  Object.assign grid = [],
    get: (x, y) -> grid[y * size + x] ? 0
    set: (x, y, v) -> grid[y * size + x] = v

peers = (grid, x, y, size, diag) ->

gen = (grid, corners) ->
  [[x1, y1], [x2, y2]] = corners
  size = x2 - x1
  halfSize = size // 2
  
  e = (a + b + c + d) / 4 + size * (0.5 - rnd())
  grid.set xm, ym, e
  
map = gen w