screen w = 320, h = 200

G = 1

bodies =
  sun     :
    m     : 1000
    loc   : makeVector 160, 100
    vel   : makeVector 0, 0

  earth   :
    m     : 1
    loc   : makeVector -190, 0
    vel   : makeVector 0, 3


viewPort = do ->
  left   =  bodies.earth.loc.x
  right  = -left

  height = (right - left) * h/w
  top    = -height / 2
  bottom =  height / 2

  x1: left, y1: top, x2: right, y2: bottom

trailsBuffer = surface w, h

buffer.on

loop
  pairAnalysis =
    for a, i in bodies[..-2]
      for b, j in bodies[i+1..]
        offset      = vectDiff b.pos, a.pos
        massProd    = a.m * b.m
        distSquared = offset.x ** 2 + offset.y ** 2
        fg          = G * massSum / distSquared

        {offset, massProd, distSquared}

  newBodies = {}
  for name, body of bodies

