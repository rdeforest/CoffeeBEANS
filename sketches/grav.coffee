screen w = 320, h = 200

G             = 0.00001
MAX_DT        = 100
velocityScale = 0.0002
timeScale     = 0.2
launchMass    = 100

makeBody   = (m, loc, vel, color = 'white') -> {m, loc, vel, color}

addVector   = (a, b) -> a.map (x, i) -> x + b[i]
subVector   = (a, b) -> a.map (x, i) -> x - b[i]
scaleVector = (s, v) -> v.map (x   ) -> s * x

bodies = [
  makeBody 100000, [160, 100], [0,   0], 'yellow'
  makeBody    100, [ 70, 100], [0, 0.1], COLORS.fromRGB 0.5, 0.7, 1
]

makeTimer = (maxDt = MAX_DT) ->
  t = prev = Date.now()

  elapsed = ->
    [prev, t] = [t, Date.now()]
    min maxDt, (t - prev) * timeScale

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

trailsBuffer = surface w, h

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

display = ->
  drawTo trailsBuffer, ->
    for a in bodies
      point a.loc..., a.color

  cls 'black'
  put trailsBuffer, 0, 0
  circle a.loc..., Math.log(a.m), a.color for a in bodies

  line launcher.start..., launcher.end... if launcher.on

  buffer.swap

wasDown = false
input = ->
  if keys.hit 'c'
    drawTo trailsBuffer, -> cls 'black'

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
