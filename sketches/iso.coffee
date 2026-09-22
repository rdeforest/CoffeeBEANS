tau = pi * 2

a = -pi/6
b =  pi/6
c =  pi/2

transform =
  x: [cos(a), sin(a)]
  y: [cos(b), sin(b)]
  z: [cos(c), sin(c)]

offset = [0, 0]

show = (value) -> print JSON.stringify value, null, 2

scale = 1

translate = (x, y, z) ->
  point = {x, y, z}
  [0, 1].map (transformDim) ->
    "xyz"
      .split ''
      .map (axis) -> scale * point[axis] * transform[axis][transformDim] + offset[transformDim]
      .reduce (a, b) -> a + b

drawBlock = (x, y, z) ->
  line 160, 100, (p1 = translate [x    , y    , z])..., 'gray'
  line 160, 100, (p2 = translate [x + 1, y    , z])..., 'gray'
  line 160, 100, (p3 = translate [x + 1, y + 1, z])..., 'gray'
  line 160, 100, (p4 = translate [x    , y + 1, z])..., 'gray'

  line 160, 100, (p5 = translate [x    , y    , z + 1])..., 'gray'
  p6 = null # irrelevant, never visible
  line 160, 100, (p7 = translate [x + 1, y + 1, z + 1])..., 'gray'
  line 160, 100, (p8 = translate [x    , y + 1, z + 1])..., 'gray'

  line p1..., p2...
  line p2..., p3...
  line p3..., p4...
  line p4..., p1...

  line p1..., p5...
  line p3..., p7...
  line p4..., p8...

  line p7..., p8...
  line p8..., p5...

for x in [1..10]
  for y in [1..10]
    for z in [1..10]
      color COLORS.fromRGB x/10, y/10, z/10
      drawBlock x, y, z
