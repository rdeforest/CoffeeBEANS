screen? w = 400, h = 400

transformers = # more than meets the eyes
  ident     :            -> [ [ 1, 0, 0 ]
                              [ 0, 1, 0 ]
                              [ 0, 0, 1 ] ]

  rotate    : (th)       -> [ [ cos(th), -sin(th), 0 ]
                              [ sin(th),  cos(th), 0 ]
                              [ 0, 0, 1 ] ]

  skew      : (sx, sy=0) -> [ [  1, sx, 0 ]
                              [ sy,  1, 0 ]
                              [  0,  0, 1 ] ]

  scale     : (x, y = x) -> [ [ x, 0, 0 ]
                              [ 0, y, 0 ]
                              [ 0, 0, 1 ] ]

  translate : (x, y = x) -> [ [ 1, 0, x ]
                              [ 0, 1, y ]
                              [ 0, 0, 1 ] ]

isMatrix = (v) ->
  return false unless Array.isArray v

  l = 0
  v .map    (r) -> Array.isArray(r) and l = r.length
    .filter (r) -> r isnt l
    .length is 0

# requires b.length is a[0].length
matrixMult = (a, b) ->
  if not Array.isArray(a   ) or not Array.isArray(a[0])
    throw new Error  "First arg to matrixMult (#{JSON.stringify a}) is not an arrays-of-arrays"
  if not Array.isArray(b   ) or not Array.isArray(b[0])
    throw new Error "Second arg to matrixMult (#{JSON.stringify b}) is not an arrays-of-arrays"

  m = a.length - 1
  n = b.length - 1

  if n isnt aWidth = a[0].length - 1
    throw new Error "width of first matrix (#{aWidth + 1}) and height of second matrix (#{n + 1}) must be the same"

  p = b[0].length - 1

  for row, i in a
    for col, j in b[0]
      t = 0
      t += a[i][k] * b[k][j] for k in [0 .. n]
      t

multMatVec = (m, v) ->
  v2 = v.map (x) -> [x]

  matrixMult m, v2
    .map ([x]) -> x

multVecMat = (v, m) -> matrixMult [v], m

iter = 0
pos = [0, 0, 1]

ct = composeTransforms = (w, ts...) ->
  m = transformers.ident()
  m = matrixMult m, t for t in ts
  [w, m]

example = do ->
  {ident, rotate, skew, scale, translate} = transformers
  # experimental
  [ ct 1, rotate(-pi/10), translate(-10, -10)
    ct 1, rotate( pi/10), translate( 10,  10) ]

  # Sierpinski triangle
  [ ct 1, scale(0.5), translate(   0, -h/2)
    ct 1, scale(0.5), translate(-h/2,  h/2)
    ct 1, scale(0.5), translate( h/2,  h/2)
  ]

  # Dragon curve
  [ ct 1, translate( h/5, 0), rotate(-pi/4), scale(1/sqrt 2)
    ct 1, translate(-h/5, 0), rotate( pi/4), scale(1/sqrt 2)
  ]

  # Fern
  [ [ 0.01, [ [     0,     0, 0    ]
              [     0,  0.25, 0    ]
              [     0,     0, 0    ] ] ]
    [ 0.85, [ [  0.85,  0.04, 0    ]
              [ -0.04,  0.85, 1.6  ]
              [     0,     0, 0    ] ] ]
    [ 0.07, [ [  0.20, -0.26, 0    ]
              [  0.23,  0.22, 1.6  ]
              [     0,     0, 0    ] ] ]
    [ 0.07, [ [ -0.15,  0.28, 0    ]
              [  0.23,  0.22, 0.44 ]
              [     0,     0, 0    ] ] ]
  ]

colors = [  'red',  'green',   'blue'
            'cyan', 'magenta', 'yellow'
            'white' ]

screenPos = (x, y) -> [x + w/2, y + h/2]

showExampleBoxes = (ex) ->
  {translate} = transformers

  for transform, i in ex
    [x1, y1] = screenPos (multMatVec ct(transform), [-w/2 + 1, -h/2 + 1, 1])...
    [x2, y2] = screenPos (multMatVec ct(transform), [ w/2 - 1,  h/2 - 1, 1])...

    c = colors[i]
    
    line x1, y1, x2, y1, c
    line x2, y1, x2, y2, c
    line x2, y2, x1, y2, c
    line x1, y2, x1, y1, c

weightSum = (tr) ->
  tr.map ([w]) -> w
    .reduce (a, b) -> a + b

weightedPicker = (list) ->
  picked = rnd()

  ws     = weightSum list
  list   = list.map (row, i) -> row[0] /= ws; {i, row}

  {i, row} = (list.find -> ({row: [w]}) -> not (w > picked and picked -= w))
  [i, row[1]]

while iter++ < 1000000
  [i, transform] = weightedPicker example
  pos = multMatVec transform, pos
  point screenPos(pos...)..., colors[i] if iter > 100

showExampleBoxes example
print "done"
