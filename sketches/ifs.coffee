screen? w = 320, h = 200

transformers =
  ident     :         -> [ [ 1, 0, 0 ]
                           [ 0, 1, 0 ] ]

  rotate    : (theta) -> [ [ cos(theta), -sin(theta), 0]
                           [ sin(theta),  cos(theta), 0] ]

  skew      : (s)     -> [ [ 1, 0, s ]
                           [ 0, 1, 0 ] ]

  scale     : (x, y)  -> [ [ x, 0, 0 ]
                           [ 0, y, 0 ] ]

  translate : (x, y)  -> [ [ 1, 0, x ]
                           [ 0, 1, y ] ]

# requires b.length is a[0].length
matrixMult = (a, b) ->
  m = a   .length - 1
  n = b   .length - 1
  p = b[0].length - 1

  [0..m].map         (i  ) ->
    [0..p].map       (j  ) ->
      [0..n].map     (k  ) -> a[i][k] * b[k][j]
            .reduce  (a,b) -> a+b

multMatVec = (m, v) ->
  v2 = v.map (x) -> [x]

  matrixMult m, v2
    .map ([x]) -> x
