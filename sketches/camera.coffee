w2 = 1/2 * w = 320 * 2
h2 = 1/2 * h = 200 * 2

UP    = [ 0,  1,  0]
#DOWN  = [ 0, -1,  0]
#RIGHT = [ 1,  0,  0]
#LEFT  = [-1,  0,  0]
#BACK  = [ 0,  0,  1]
#FWD   = [ 0,  0, -1]

# --- Maths ---

cross = (a, b) -> [ a[1] * b[2] - a[2] * b[1]
                    a[2] * b[0] - a[0] * b[2]
                    a[0] * b[1] - a[1] * b[0] ]
 
rotate = (A, B, t) ->
  [c, s] = [cos(t), sin(t)]
  [ A.map((a, i) ->  a * c + B[i] * s)
    A.map((a, i) -> -a * s + B[i] * c) ]

vScale      = (v, s)   -> v.map (x) -> x * s
vUnit       = (v)      -> vScale v, 1/hypot v...
vAdd        = (a, b)   -> a.map (x, i) -> x + b[i]

wrapRadians = (angle)  -> atan2 sin(angle), cos(angle)
angleDiff   = (a1, a2) -> (wrapRadians a2) - (wrapRadians a1)
vNeg        = (v)      -> v.map (x) -> -x
vMult       = (a, b)   -> a.map (x, i) -> x * b[i]
dot         = (a, b)   -> vMult(a, b).reduce (a, b) -> a + b

# --- Camera ---

view = null

camera = (loc, target) ->
  toTarget = vAdd  target,   vNeg loc
  heading  = vUnit toTarget
  left     = cross toTarget, UP
  left     = vUnit left

  Object.assign camera, {loc, heading, left}

  mag      = hypot toTarget...
  near     = mag / 2

  view = {near}

worldToCamera = (p) ->
  d = p.map (x, i) -> x - camera.loc[i]

  c_up    = cross camera.heading, camera.left
  c_right = vNeg camera.left

  x_c =     dot d, c_right
  y_c =     dot d, c_up
  z_c = 0 - dot d, camera.heading

  [x_c, y_c, z_c]

worldToScreen = (p) ->
  if view is null
    throw new Error "use `camera location, target` before drawing in 3D"

  [x3, y3, z3] = worldToCamera p

  x = view.near * x3 / z3
  y = view.near * y3 / z3

  [w2 + x, h2 - y]

point3d = (p, args...) ->
  [x, y] = worldToScreen p
  point x, y, args...

line3d = (p1, p2, args...) ->
  [sx1, sy1] = worldToScreen p1
  [sx2, sy2] = worldToScreen p2

  line sx1, sy1, sx2, sy2, args...

drawLines = (vertexes) ->
  vertexes.forEach (v, i, l) ->
    v2 = l[(i + 1) % l.length]
    line3d v, v2

drawStage = ->
  drawLines stage

drawBox = ->
  v = [ [0, 0, 0], [0, 0, h], [0, h, 0], [0, h, h]
        [h, 0, 0], [h, 0, h], [h, h, 0], [h, h, h] ]
  edges = [ [ v[0], v[1] ], [ v[0], v[2] ], [ v[0], v[4] ],
            [ v[1], v[3] ], [ v[1], v[5] ],
            [ v[2], v[3] ], [ v[2], v[6] ],
            [ v[4], v[5] ], [ v[4], v[6] ],
            [ v[7], v[3] ], [ v[7], v[5] ], [ v[7], v[6] ] ]

  edges.forEach ([p1, p2]) -> line3d (p1), (p2), 'coffee'

# --- demo --- 

screen w, h

hue = 0

p1 = loc: [0.25 * w, 0.25 * h, 0.25 * h], vel: [ rnd(),  rnd(),  rnd()]
p2 = loc: [0.75 * w, 0.75 * h, 0.75 * h], vel: [-rnd(), -rnd(), -rnd()]

bounce = (p) ->
  p.loc =
  p.loc.map (x, i) ->
    switch
      when 0 <= x <= h then x
      when      x < 0  then p.vel[i] = rnd()
      else              h + p.vel[i] = -rnd()

move = (p) -> p.loc = vAdd p.loc, p.vel

lines = []

buffer.on
camera [w2, h2, h * 1.75 ], [w2, h2, 0]
loop
  cls()

  drawBox()

  [p1, p2].forEach (p) -> move(p); bounce(p)
  mp = vScale (vAdd p2.loc, vNeg p1.loc), 0.5
  camera camera.loc, p1.loc
  hue = (hue + 1) % 360
  lines.push [p1.loc, p2.loc, COLORS.fromHSV hue, 1, 1]
  lines.shift() if lines.length > 200
  lines.forEach (l) -> line3d l...

  buffer.swap
