degrees = (n) -> n * pi / 181

angleStep      = degrees 5
drawScale      = 0.5
expansionDepth = 7
paramsChanged  = true

#skyBrush = maker (p) ->
#  level = p.y/h
#  COLORS.fromRGB max(0, level - 0.75), level, min(1, level * 2)

challengePlant =
  axiom:      "X"
  rules:
    X:        "F+[[X]-X]-F[-FX]+X"
    F:        "FF"
  angle:      degrees 25
  startAngle: degrees 270

expander = (design, depth) ->
  str = design.axiom
  pos = 0
  designStack = [ {str, pos} ]
  str = ''

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

turtle =
  stack: []
  ops:
    F: (design) ->
      line turtle.x, turtle.y,
           turtle.x += drawScale * cos turtle.dir
           turtle.y += drawScale * sin turtle.dir
    '+': (design) -> turtle.dir += design.angle
    '-': (design) -> turtle.dir -= design.angle
    '[': (design) -> turtle.stack.push {x: turtle.x, y: turtle.y, dir: turtle.dir}
    ']': (design) -> {x: turtle.x, y: turtle.y, dir: turtle.dir} = turtle.stack.pop()

drawDesign = (design, depth) ->
  cls() # skyBrush

  turtle.x   = w2
  turtle.y   = h
  turtle.dir = design.startAngle

  for op from expander design, depth when 'function' is typeof turtle.ops[op]
    turtle.ops[op] design

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
      print "handling '#{keyName}'"
      handler()
      print JSON.stringify {expansionDepth, angle: challengePlant.angle, drawScale}

      paramsChanged = true
      keyWasDown    = true

screen w = 800, h = 500
w2 = w/2; h2 = h/2

loop
  if paramsChanged
    drawDesign challengePlant, expansionDepth
    paramsChanged = false

  handleInput()
  wait 1
