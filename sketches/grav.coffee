screen w = 320, h = 200

G             = 0.0000001
MAX_DT        = 100
velocityScale = 0.0002
timeScale     = 0.1
launchMass    = 100
showTrails    = no
showField     = no

makeBody   = (m, loc, vel, color = 'white') -> {m, loc, vel, color}

addVector   = (a, b) -> a.map (x, i) -> x + b[i]
subVector   = (a, b) -> a.map (x, i) -> x - b[i]
scaleVector = (s, v) -> v.map (x   ) -> s * x

bodies = [
  makeBody 10000000, [160,  90], [-0.1,   0], 'yellow'
  makeBody 10000000, [160, 110], [ 0.1,   0], 'yellow'
  makeBody      100, [ 40, 100], [ 0  , 0.1], COLORS.fromRGB 0.5, 0.7, 1
]

makeTimer = (maxDt = MAX_DT) ->
  t = prev = Date.now()

  elapsed = ->
    [prev, t] = [t, Date.now()]
    min maxDt, (t - prev) * timeScale

fieldStrength = (x, y) ->
  force = [0, 0]

  for b in bodies
    offset      = subVector b.loc, [x, y]
    distSquared = offset[0]**2 + offset[1]**2

    force = addVector force, scaleVector sqrt(distSquared), offset

  force

calc = (dt = 1) ->
  for a, ai in bodies[       .. -2]
    for b   in bodies[ai + 1 .. ]
      offset    = subVector b.loc, a.loc
      distCubed = hypot(offset...)**3

      dv = scaleVector G / distCubed * dt, offset

      a.vel = addVector a.vel, scaleVector  b.m, dv
      b.vel = addVector b.vel, scaleVector -a.m, dv

  a.loc = addVector a.loc, scaleVector dt, a.vel for a in bodies

  return

trailsBuffer    = surface w, h
gravFieldBuffer = surface w, h

launcher = on: false, start: [0, 0], end: [0, 0]

launchBody = (launcher) ->
  offset = subVector launcher.end, launcher.start

  # offset * hypot(offset) gives a wider range of input velocities without
  # having to provide a way to adjust velocityScale at game time.
  mag    = hypot offset...
  vel    = scaleVector mag * velocityScale, offset
  loc    = launcher.end
  m      = launchMass

  bodies.push makeBody m, loc, vel, COLORS.fromHSV rnd(360), rnd(0.5) + 0.5, 1

getField = ->
  least =  Infinity
  most  = -Infinity
  field =
    for y in [0..h - 1]
      for x in [0..w - 1]
        f     = fieldStrength x, y
        mag   = hypot f...
        least = min least, mag
        most  = max most , mag
        {f, mag}

  {field, least, most}

display = ->
  drawTo trailsBuffer, ->
    for a in bodies
      point a.loc..., a.color

  if showField
    drawTo gravFieldBuffer, ->
      {field, least, most} = getField()

      least = sqrt least
      most  = sqrt most
      range = most - least

      for y in [0..h - 1]
        for x in [0..w - 1]
          {f, mag} = field[y][x]

          value = ((sqrt mag) - least) / range

          point x, y, COLORS.fromRGB value, value, value

  cls 'black'
  put gravFieldBuffer, 0, 0 if showField
  put trailsBuffer,    0, 0 if showTrails
  circle a.loc..., Math.log(a.m), a.color for a in bodies

  line launcher.start..., launcher.end... if launcher.on

  buffer.swap

wasDown = false
input = ->
  if keys.hit 'c'
    drawTo trailsBuffer, -> cls 'black'

  showField  = not showField  if keys.hit 'f'
  showTrails = not showTrails if keys.hit 't'

  if isDown = mouse.down
    if wasDown
      launcher.end = [mouse.x, mouse.y]
    else
      launcher.end = launcher.start = [mouse.x, mouse.y]
      launcher.on  = yes
  else if wasDown
    launchBody launcher
    launcher.on    = no

  wasDown = isDown

buffer.on

elapsed = makeTimer()

loop
  calc elapsed()

  display()

  input()
