degrees = (n) -> n * pi / 181

show = (v) -> #print JSON.stringify v, null, 2

angleStep      = degrees 5
drawScale      = 50
expansionDepth = 1
paramsChanged  = true
turnSpeed      = degrees 5
walkSpeed      = 50

w2 = 1/2 * w = 320
h2 = 1/2 * h = 200

# Right hand universe, Z is into the screen
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

challengePlant =
  axiom:        "A"
  rules:
    A:          "[vFA]/////[vFA]///////[vFA]"
    F:          "S/////F"
    S:          "F"
  angle:        degrees 22.5
  startHeading: UP
  startLeft:    LEFT

expander = (design, depth) ->
  str         = design.axiom
  pos         = 0
  designStack = [ {str, pos} ]
  str         = ''

  loop
    if pos >= str.length
      return unless designStack.length

      {str, pos} = designStack.pop()

    char = str[pos++]

    if (expanded = design.rules[char]) and designStack.length < depth
      designStack.push {str, pos}
      str = expanded
      pos = 0
    else
      yield char

wrapRadians = (angle) -> atan2 sin(angle), cos(angle)

angleDiff = (a1, a2) ->
  a1 = wrapRadians a1
  a2 = wrapRadians a2
  a2 - a1

worldToCamera = (p) ->
  p = p.map (x, i) -> x - camera.loc[i]

  pLeft = cross UP, p
  pAngle = angleDiff (atan2 FWD[2], FWD[0]), (atan2 camera.heading[2], camera.heading[0])
  [p, pLeft] = rotate p, pLeft, pAngle
  p
  

worldToScreen = (p) ->
  [x3, y3, z3] = worldToCamera p

  x = view.near * x3 / z3
  y = view.near * y3 / z3

  [x, y]
  

line3d = (p1, p2, args...) ->
  [sx1, sy1] = worldToScreen p1
  [sx2, sy2] = worldToScreen p2

  line w2 + sx1, h2 - sy1, w2 + sx2, h2 - sy2, args...
  show {p1, p2, sx1, sy1, sx2, sy2}

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

drawDesign = (design, depth) ->
  cls()

  corners = [ [ -w2,  h2, view.far  * 1.1 ]
              [  w2,  h2, view.far  * 1.1 ]
              [  w2, -h2, view.far  * 1.1 ]
              [ -w2, -h2, view.far  * 1.1 ]
              [ -w2, -h2, view.near * 1.1 ],
              [  w2, -h2, view.near * 1.1 ],
              [  w2,  h2, view.near * 1.1 ],
              [ -w2,  h2, view.near * 1.1 ],
            ]

  corners.forEach (p1, i) ->
    p2 = corners[(i + 1) % corners.length]
    line3d p1, p2

  turtle.loc     = [ 0, -h2, view.near + (view.far - view.near) / 2 ]
  turtle.heading = UP
  turtle.left    = LEFT

  for op from expander design, depth
    if 'function' is typeof handler = turtle.ops[op]
      handler design

  return

keyBindings =
  'leftbracket'  : -> expansionDepth       += +1
  'rightbracket' : -> expansionDepth       += -1
  ','            : -> challengePlant.angle += angleStep * -1
  '.'            : -> challengePlant.angle += angleStep * +1
  '-'            : -> drawScale            *= 1         - 0.05
  '+'            : -> drawScale            *= 1         + 0.05

  'w'            : -> camera.loc = camera.loc.map (x, i) -> x + camera.heading[i] * walkSpeed
  's'            : -> camera.loc = camera.loc.map (x, i) -> x - camera.heading[i] * walkSpeed

  'a'            : -> [camera.heading, camera.left] = rotate camera.heading, camera.left,  turnSpeed
  'd'            : -> [camera.heading, camera.left] = rotate camera.heading, camera.left, -turnSpeed

keyWasDown = false

handleInput = ->
  if keyWasDown
    keyWasDown = keys.any
    return

  for keyName in keys.down()
    if handler = keyBindings[keyName]
      print "handling '#{keyName}'"
      handler()
      #print JSON.stringify {expansionDepth, angle: challengePlant.angle, drawScale}

      paramsChanged = true
      keyWasDown    = true
    else
      print "No handler for key '#{keyName}'"

screen w, h

loop
  if paramsChanged
    drawDesign challengePlant, expansionDepth
    paramsChanged = false

  handleInput()
  wait 1
