params =
  size: 6
  neighborThreshold: 1
  states: 24, dist: 1
  stableColors: no
  range: no
  colorOffset: 0

main = ->
  resize(0) params
  params.running = params.init = yes

  loop
    if params.init
      screen params.w, params.h
      buffer.on
      params.init = no
      grid = makeGrid params
      params.palette = [0 .. params.states - 1].map (c) -> COLORS.fromHSV 360 * c / params.states, 1, 1

    if params.running
      grid = iterateGrid grid, params
    params = handleInput params

toggle = (name) -> (params) -> params[name] = not params[name]

setSize = (size) -> (params) ->
  params.size = size
  params.w = size * 160
  params.h = size * 100
  params.init = yes
  params

resize = (dSize) -> (params) -> setSize(max 1, min 3, params.size + dSize) params

controls =
  w: (params) -> params.states++; params.init = yes
  s: (params) -> params.states--; params.init = yes

  a: (params) -> params.neighborThreshold = max(1, params.neighborThreshold - 1); params.init = yes
  d: (params) -> params.neighborThreshold = min(5, params.neighborThreshold + 1); params.init = yes

  r: toggle "range"
  c: toggle "stableColors"

  '-': resize -1
  '_': resize -1
  '+': resize  1
  '=': resize  1
  '1': setSize 1
  '2': setSize 2
  '3': setSize 3
  '4': setSize 4
  '5': setSize 5
  '6': setSize 6
  '7': setSize 7
  '8': setSize 8
  '9': setSize 9

  space: toggle "running"

handleInput = (params) ->
  for k, cmd of controls
    if keys.hit k
      cmd params
      print "did: " + k

  params

makeGrid = ({w, h, states}) -> [0 .. h - 1].map -> [0 .. w - 1].map -> floor rnd states

iterateGrid = (grid, params) ->
  {neighborThreshold, states, palette, w, h} = params

  dist = if params.range then 2 else 1

  colorOffset =
    if params.stableColors
      params.colorOffset += states - 1
    else
      0

  newGrid =
  for row, y in grid
    for n, x in row
      nextN = (n + 1) % states
      match = 0

      n = do ->
        for   yy in [y - dist .. y + dist]
          yy = (yy + h) % h
          for xx in [x - dist .. x + dist]
            xx = (xx + w) % w

            if grid[yy][xx] is nextN
              match++
              if match >= neighborThreshold
                return nextN

        return n

      point x, y, palette[(n + colorOffset) % states]
      n

  rectFill 0, 0, w, 8, 'black'
  disp = {states, neighborThreshold, dist}
  textAt 0, 0, "#{JSON.stringify disp}"
  buffer.swap
  newGrid

main()
