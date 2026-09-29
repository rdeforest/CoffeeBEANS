###
# The challenge is pursuit. Put a handful of bugs on the corners of a regular
# polygon. Each bug walks at constant speed directly toward the next one
# around the ring. That's the whole rule. Draw the paths, not just the bugs.
#
# The knobs: mouse x sets how many bugs, three to twelve. Mouse y caps how
# fast a bug can turn, from "instantly" down to "barely", which changes the
# picture completely.
#
# The wall: thirty lines, no objects, three arrays. Every step is one of the
# five patterns above, and the turn cap is the fourth one.
#
# Done means: you've seen the spiral, you can say in one sentence why the bugs
# never catch each other, and you've found the turn rate where they stop
# spiralling and start doing something else.
###

MAX_TURN_RATE = 0.001 * pi # radian per millisecond
BUG_SPEED     = 0.02       # pixels per millisecond

screen SCREEN_WIDTH = 320, SCREEN_HEIGHT = 200

[middleX, middleY] = [SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2]

radius = 7 / 10 * min middleX, middleY

initBugs = (liveBugs) ->
  [1..liveBugs].map (_, i) ->
    theta = pi * 2 * i / liveBugs

    [ middleX + radius * cos theta
      middleY + radius * sin theta
      rnd pi * 2 # heading
      COLORS.fromHSV theta / pi * 180, 1, 1
    ]

bugs = initBugs 3

trailsBuffer = surface SCREEN_WIDTH, SCREEN_HEIGHT

buffer.on
t = Date.now()

clamp = (least, value, most) -> max least, min most, value

wrapRadians = (angle) -> atan2 sin(angle), cos(angle)

turnRate = MAX_TURN_RATE / 10

loop
  cls 'black'

  oldT = t
  t  = Date.now()
  dt = t - oldT

  if mouse.left
    drawTo trailsBuffer, -> cls 'black'
    bugs     = initBugs 3 + floor(10 * mouse.x      / SCREEN_WIDTH)
    turnRate =        MAX_TURN_RATE * (mouse.y + 1) / SCREEN_HEIGHT

  newBugs =
    for bugA, i in bugs
      [x, y, heading, color] = bugA
      bugB = bugs[(i + 1) % bugs.length]

      dx = bugB[0] - x; dy = bugB[1] - y

      angleToB   = atan2 dy, dx
      turn       = wrapRadians angleToB - heading
      maxTurn    = turnRate * dt
      newHeading = heading + clamp -maxTurn, turn, maxTurn

      newX       = x + BUG_SPEED * dt * cos newHeading
      newY       = y + BUG_SPEED * dt * sin newHeading

      newBug = [newX, newY, newHeading, color]

  bugs = newBugs
  
  drawTo trailsBuffer, ->
    for bug in bugs
      point bug[0..1]..., bug[3]

  put trailsBuffer, 0, 0

  for bug in bugs
    line bug[0..1]..., bug[0] + 3 * cos(bug[2]), bug[1] + 3 * sin(bug[2]), 'yellow'

  buffer.swap

