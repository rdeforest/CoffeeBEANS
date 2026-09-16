screen SCREEN_WIDTH = 320, SCREEN_HEIGHT = 200

SCREEN_SIZE         = min SCREEN_WIDTH, SCREEN_HEIGHT

MAX_TURN_RATE       = 0.002 * pi # radian per millisecond
BUG_SPEED           = 0.02       # pixels per millisecond
BUG_LENGTH          = 5          # pixels

MIN_VISION_DISTANCE = 5               # pixels
MAX_VISION_DISTANCE = SCREEN_SIZE / 2 # pixels

MIN_SPACING         = 20              # pixels

turnRate            = MAX_TURN_RATE / 10
visionDistance      = MIN_VISION_DISTANCE

bugs = [1 .. 20].map (_, i) ->
  theta = rnd() * pi * 2
  dist  = rnd MAX_VISION_DISTANCE

  x:       SCREEN_WIDTH  / 2 + dist * cos theta
  y:       SCREEN_HEIGHT / 2 + dist * sin theta
  heading: rnd pi * 2
  c:       COLORS.fromHSV 360 * rnd(), 0.5 + rnd() / 2, 1

#inRange = (x, y, range, bugs) ->
#  bugs.filter (bug) ->
#    range > hypot (bug.x - x), (bug.y - y)

averageLocation = (bugs) ->
  tx = ty = 0
  (tx += x; ty += y) for {x, y} in bugs
  x: tx / bugs.length, y: ty / bugs.length

averageHeading = (bugs) -> averageAngle bugs.map (b) -> b.heading

averageAngle = (angles) ->
  {x, y} = averageLocation angles.map (angle) -> x: cos(angle), y: sin(angle)
  atan2 y, x

buffer.on

loop
  cls 'black'

  oldT = t
  t    = Date.now()
  dt   = t - oldT

  if mouse.left
    visionDistance = MIN_VISION_DISTANCE + (mouse.x / SCREEN_WIDTH) * (MAX_VISION_DISTANCE - MIN_VISION_DISTANCE)
    turnRate       = (mouse.y / SCREEN_HEIGHT) * MAX_TURN_RATE

  bugs =
    for {x, y, heading, c}, i in bugs
      tooClose  = []
      theRest   = []
      angles    = [heading + (1 - rnd(2)) * dt * pi / 30]
      distances = bugs.map ({x, y}) -> hypot x, y

      for dist, j in distances when j isnt i
        if dist < MIN_SPACING
          tooClose.push bugs[j]
        else if dist < visionDistance
          theRest .push bugs[j]

      if tooClose.length
        target = averageLocation tooClose
        angles.push pi + atan2 target.y - y, target.x - x

      if theRest.length
        target = averageLocation theRest
        angles.push  atan2 target.y - y, target.x - x
        angles.push  averageHeading theRest

      if angles.length
        headingGoal  = averageAngle angles
        offCourse    = headingGoal - heading

        turn         = min abs(offCourse), MAX_TURN_RATE * dt
        turn         = turn + pi if offCourse < 0

        heading     += turn

      x += BUG_SPEED * dt * cos heading
      y += BUG_SPEED * dt * sin heading
      p = x: (x + SCREEN_WIDTH) % SCREEN_WIDTH, y: (y + SCREEN_HEIGHT) % SCREEN_HEIGHT

      Object.assign p, {heading, c}

  for bug in bugs
    color bug.c
    circle bug.x, bug.y, visionDistance
    line bug.x, bug.y, bug.x + BUG_LENGTH * cos bug.heading, bug.y + BUG_LENGTH * sin bug.heading

  buffer.swap

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
#
# ---
#
# Challenge part 2: Boids
#
# Each bug looks at the others within some distance and follows three rules:
# steer away from the ones too close, steer toward the average position of the
# rest, and turn toward their average heading. Wrap the screen so a bug
# leaving the right edge arrives on the left.
#
# The knobs: mouse x sets how far a boid can see, from a few pixels to half
# the screen. Mouse y is the turn cap again.
#
# The wall: forty lines, one array, the three rules fixed at whatever weights
# you tune by hand. Don't build a rule system.
#
# The trap, which is today's lesson wearing a new hat: you cannot average
# angles. Two boids heading plus and minus 170 degrees average to zero, which
# is backwards. Average the cosines and sines instead, then atan2 your way
# back. That's pattern two doing a job you wouldn't have guessed.
#
# Done means: you've watched a flock form, split around nothing, and rejoin.
# And you can say in one sentence what changed in the picture when you doubled
# the sight radius.
#
###


