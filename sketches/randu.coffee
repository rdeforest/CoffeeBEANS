degrees = (n) -> n * pi / 180

show = (v) -> print JSON.stringify v, null, 2

paramsChanged  = true
turnSpeed      = degrees 5
walkSpeed      = 50
plantTurnSpeed = degrees 1
plantTurning   = false
plantAngle     = 0
TWO_TO_THE_31  = 2**31

w2 = 1/2 * w = 320 * 2
h2 = 1/2 * h = 200 * 2

RIGHT = [ 1,  0,  0]
LEFT  = [-1,  0,  0]
UP    = [ 0,  1,  0]
DOWN  = [ 0, -1,  0]
BACK  = [ 0,  0,  1]
FWD   = [ 0,  0, -1]

camera =
  loc:     [0, 0, 0]
  heading: FWD
  left:    LEFT

# For eye at 0,0,0 looking down the Z axis, with the screen surface height
# times two away and the far plane double that.
view =
  near:   -h * 2
  far:    -h * 4
  left:   -w
  right:   w
  top:     h
  bottom: -h

wrapRadians = (angle) -> atan2 sin(angle), cos(angle)

angleDiff = (a1, a2) ->
  a1 = wrapRadians a1
  a2 = wrapRadians a2
  a2 - a1

negateVec = (v) -> v.map (x) -> -x

dot = (a, b) ->
  a .map    (x, i) -> x * b[i]
    .reduce (a, b) -> a + b

worldToCamera = (p) ->
  d = p.map (x, i) -> x - camera.loc[i]

  c_up    = cross camera.heading, camera.left
  c_right = negateVec camera.left

  x_c =     dot d, c_right
  y_c =     dot d, c_up
  z_c = 0 - dot d, camera.heading

  [x_c, y_c, z_c]

worldToScreen = (p) ->
  [x3, y3, z3] = worldToCamera p

  x = view.near * x3 / z3
  y = view.near * y3 / z3

  [x, y]

point3d = (p, args...) ->
  [x, y] = worldToScreen p
  point w2 + x, h2 - y, args...

line3d = (p1, p2, args...) ->
  [sx1, sy1] = worldToScreen p1
  [sx2, sy2] = worldToScreen p2

  line w2 + sx1, h2 - sy1, w2 + sx2, h2 - sy2, args...
  #show {p1, p2, sx1, sy1, sx2, sy2}

cross = (a, b) -> [ a[1] * b[2] - a[2] * b[1]
                    a[2] * b[0] - a[0] * b[2]
                    a[0] * b[1] - a[1] * b[0] ]
 
rotate = (A, B, t) ->
  [c, s] = [cos(t), sin(t)]
  [ A.map((a, i) ->  a * c + B[i] * s)
    A.map((a, i) -> -a * s + B[i] * c) ]

doTurn = (object, turn) ->
  {heading, left} = object

  for name, amount of turn
    if name isnt 'yaw'
      up = cross heading, left
    switch name
      when 'yaw'   then [ heading, left ] = rotate heading, left, amount
      when 'pitch' then [ heading, up   ] = rotate heading, up,   amount
      when 'roll'  then [ left,    up   ] = rotate left,    up,   amount
    object.heading = heading
    object.left    = left
 
turtle =
  stack: []
  # x: null, y: null, z: null, heading: null, left: null
  state: (newState) ->
    if arguments.length
      {@loc, @heading, @left} = newState
    else
      {@loc, @heading, @left}
  ops:
    '^':  (design) -> doTurn turtle, pitch:  1 * design.angle
    'v':  (design) -> doTurn turtle, pitch: -1 * design.angle
    '<':  (design) -> doTurn turtle, yaw:    1 * design.angle
    '>':  (design) -> doTurn turtle, yaw:   -1 * design.angle
    '\\': (design) -> doTurn turtle, roll:   1 * design.angle
    '/':  (design) -> doTurn turtle, roll:  -1 * design.angle

    '[':  (design) -> turtle.stack.push turtle.state()
    ']':  (design) -> turtle.state turtle.stack.pop()

    F: (design) -> line3d turtle.loc,
      turtle.loc =
        turtle.loc.map (x, i) ->
          x + drawScale * turtle.heading[i]

drawStage = ->
  drawLines stage

drawBox = ->
  corners = [ [0, 0, 0]   # 0
              [0, 0, 1]   # 1
              [0, 1, 0]   # 2
              [0, 1, 1]   # 3
              [1, 0, 0]   # 4
              [1, 0, 1]   # 5
              [1, 1, 0]   # 6
              [1, 1, 1] ] # 7
  edges = [ [ corners[0], corners[1] ]
            [ corners[0], corners[2] ]
            [ corners[0], corners[4] ]
            [ corners[1], corners[3] ]
            [ corners[1], corners[5] ]
            [ corners[2], corners[3] ]
            [ corners[2], corners[6] ]
            [ corners[4], corners[5] ]
            [ corners[4], corners[6] ]
            [ corners[7], corners[3] ]
            [ corners[7], corners[5] ]
            [ corners[7], corners[6] ] ]
  color 'red'
  #corners.forEach (c) -> line3d scaleToStage([0.5, 0.5, 0.5]), scaleToStage(c)
  edges.forEach ([p1, p2]) -> line3d scaleToStage(p1), scaleToStage(p2)
  color 'white'

keyBindings =
  'leftbracket'  : -> expansionDepth       += +1
  'rightbracket' : -> expansionDepth       += -1
  'comma'        : -> challengePlant.angle += angleStep * -1
  'period'       : -> challengePlant.angle += angleStep * +1
  'minus'        : -> drawScale            *= 1         - 0.05
  'equals'       : -> drawScale            *= 1         + 0.05

  'w'            : -> camera.loc = camera.loc.map (x, i) -> x + camera.heading[i] * walkSpeed
  's'            : -> camera.loc = camera.loc.map (x, i) -> x - camera.heading[i] * walkSpeed

  'a'            : -> [camera.heading, camera.left] = rotate camera.heading, camera.left,  turnSpeed
  'd'            : -> [camera.heading, camera.left] = rotate camera.heading, camera.left, -turnSpeed

  'space'        : -> plantTurning = not plantTurning

keyWasDown = false

handleInput = ->
  if keyWasDown
    keyWasDown = keys.any
    return

  for keyName in keys.down()
    if handler = keyBindings[keyName]
      #print "handling '#{keyName}'"
      handler()
      #print JSON.stringify {expansionDepth, angle: challengePlant.angle, drawScale}

      keyWasDown    = true
    else
      print "No handler for key '#{keyName}'"

randu = (z) -> z * 65539 & 0x7FFF_FFFF

drawPoints = (fn) ->
  z1 = fn  1; p1 = z1 / TWO_TO_THE_31
  z2 = fn z1; p2 = z2 / TWO_TO_THE_31
  z3 = fn z2; p3 = z3 / TWO_TO_THE_31
  #low = min p1, p2, p3
  #hi  = max p1, p2, p3

  for i in [1..100000]
    p = [x,y,z] = scaleToStage [p1, p2, p3]
    #line3d scaleToStage([0.5,0.5,0.5]), p
    point3d p
    #show {x, y, z, p, screenP}

    [z1, z2, z3] = [z2, z3, fn z3]
    [p1, p2, p3] = [p2, p3, z3 / TWO_TO_THE_31]
    #low = min low, p3
    #hi  = max hi,  p3
    #show {z1,z2,z3,p1,p2,p3}

  #show {low, hi}
  color 'yellow'
  for x in [1..11]
    for y in [1..11]
      for z in [1..11]
        point scaleToStage([x / 12, y / 12, z / 12])
  color 'white'
  return

stage =
  [ [ -w2,  h2, view.far  * 1.1 ]
    [ -w2, -h2, view.far  * 1.1 ]
    [ -w2, -h2, view.near * 1.1 ]
    [  w2, -h2, view.near * 1.1 ]
    [  w2, -h2, view.far  * 1.1 ]
    [  w2,  h2, view.far  * 1.1 ]
    [  w2,  h2, view.near * 1.1 ]
    [ -w2,  h2, view.near * 1.1 ]
  ]

# x, y and z come in 0-1 and come out mapped to the stage
scaleToStage = ([x, y, z]) ->
  [ -w2       + x * w
    -h2       + y * h
    view.near + z * (view.far - view.near)
  ]

drawLines = (corners) ->
  corners.forEach (p1, i) ->
    p2 = corners[(i + 1) % corners.length]
    line3d p1, p2

screen w, h

buffer.on
loop
  cls()
  drawPoints randu
  #drawStage()
  drawBox()
  handleInput()
  buffer.swap
