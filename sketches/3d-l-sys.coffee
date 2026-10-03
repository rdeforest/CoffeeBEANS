degrees = (n) -> n * pi / 181

#show = (v) -> print JSON.stringify v, null, 2

angleStep      = degrees 5
drawScale      = 50
expansionDepth = 3
paramsChanged  = true

w  = 320; h  = 200
w2 = w/2; h2 = h/2

# Right hand universe, Z is into the screen
RIGHT = [ 1,  0,  0, 0]
LEFT  = [-1,  0,  0, 0]
UP    = [ 0,  1,  0, 0]
DOWN  = [ 0, -1,  0, 0]
BACK  = [ 0,  0,  1, 0]
FWD   = [ 0,  0, -1, 0]

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

worldToCamera = ([x3, y3, z3]) ->
  # XXX: implement me!
  [x3, y3, z3] = [x3, y3, z3]

worldToScreen = (x3, y3, z3) ->
  [x3, y3, z3] = worldToCamera [x3, y3, z3]

  x = view.near * x3 / z3
  y = view.near * y3 / z3

  [x, y]
  

line3d = (x1, y1, z1, x2, y2, z2, args...) ->
  [sx1, sy1] = worldToScreen x1, y1, z1
  [sx2, sy2] = worldToScreen x2, y2, z2

  line w2 + sx1, h2 - sy1, w2 + sx2, h2 - sy2, args...

cross = (a, b) -> [ a[1]*b[2] - a[2]*b[1]
                    a[2]*b[0] - a[0]*b[2]
                    a[0]*b[1] - a[1]*b[0] ]
 
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
  x: null, y: null, z: null, heading: null, left: null
  state: (newState) ->
    if arguments.length
      {@x, @y, @z, @heading, @left} = newState
    else
      {@x, @y, @z, @heading, @left}
  ops:
    '^':  (design) -> doTurn turtle, pitch:  1 * design.angle
    'v':  (design) -> doTurn turtle, pitch: -1 * design.angle
    '<':  (design) -> doTurn turtle, yaw:    1 * design.angle
    '>':  (design) -> doTurn turtle, yaw:   -1 * design.angle
    '\\': (design) -> doTurn turtle, roll:   1 * design.angle
    '/':  (design) -> doTurn turtle, roll:  -1 * design.angle

    '[':  (design) -> turtle.stack.push turtle.state()
    ']':  (design) -> turtle.state turtle.stack.pop()

    F: (design) ->
      {heading} = turtle.state()

      line3d turtle.x, turtle.y, turtle.z,
           turtle.x += drawScale * heading[0]
           turtle.y += drawScale * heading[1]
           turtle.z += drawScale * heading[2]

drawDesign = (design, depth) ->
  cls()

  turtle.x       = 0
  turtle.y       = -h2
  turtle.z       = view.near + (view.far - view.near) / 2
  turtle.heading = UP
  turtle.left    = LEFT

  for op from expander design, depth
    if 'function' is typeof handler = turtle.ops[op]
      handler design

  return

keyBindings =
  'leftbracket'  : -> expansionDepth       += +1
  'rightbracket' : -> expansionDepth       += -1
  'a'            : -> challengePlant.angle += angleStep * -1
  'd'            : -> challengePlant.angle += angleStep * +1
  's'            : -> drawScale            *= 1         - 0.05
  'w'            : -> drawScale            *= 1         + 0.05

keyWasDown = false

handleInput = ->
  if keyWasDown
    keyWasDown = keys.any
    return

  for keyName, handler of keyBindings
    if keys.down keyName
      #print "handling '#{keyName}'"
      handler()
      #print JSON.stringify {expansionDepth, angle: challengePlant.angle, drawScale}

      paramsChanged = true
      keyWasDown    = true

screen w, h

loop
  if paramsChanged
    drawDesign challengePlant, expansionDepth
    paramsChanged = false

  handleInput()
  wait 1
