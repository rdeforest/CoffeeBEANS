screen 480, 300
tau = pi * 2

a = -pi/8
b =  pi/8
c =  pi/2

transform =
  x: [cos(a), sin(a)]
  y: [cos(b), sin(b)]
  z: [cos(c), sin(c)]

offset = [50, 50]
scale = 1

translate = ([x, y, z]) ->
  point = {x, y, z}
  [0, 1].map (transformDim) ->
    "xyz"
      .split ''
      .map (axis) -> scale * point[axis] * transform[axis][transformDim] + offset[transformDim]
      .reduce (a, b) -> a + b

boxCorners = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]
              [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]]

addVectors = (vs...) ->
  for x, i in vs[0]
    t = 0
    t += v[i] for v in vs
    t

zLayers = {}

queuePoint = (p) ->
  screenPoint = translate p
  z = floor screenPoint[2]
  (zLayers[z] ?= []).push [p[0], p[1], p[3]]

drawAll = ->
  zLayerNames = Object
    .keys zLayers
    .map (s) -> parseFloat s
    .sort (a, b) -> b - a

  for zLayer in zLayerNames.map (name) -> zLayers[name]
    for p in zLayer
      point p...

for z in [1..10]
  for y in [1..10]
    for x in [1..10]
      c = COLORS.fromRGB (x + 0)/10, (y + 0)/10, (z + 0)/10
      queuePoint [x, y, z, c]

drawAll()
