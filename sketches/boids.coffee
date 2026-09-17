screen SCREEN_WIDTH = 600, SCREEN_HEIGHT = 300

SCREEN_SIZE         = min SCREEN_WIDTH, SCREEN_HEIGHT

MAX_TURN_RATE       = 0.002 * pi # radian per millisecond
BUG_WOBBLE          = MAX_TURN_RATE / 100
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

print JSON.stringify bugs, null, 2

wrapRadians = (angle)      -> atan2 sin(angle), cos(angle)
wobblyBug   = (bug)        -> bug.heading + (1 - rnd(2)) * BUG_WOBBLE * dt
toCart      = (mag, theta) -> [cos, sin].map (f) -> mag * f theta

print toCart 1, pi / 4
return

angleAverager = ->
  sum:     [0, 0], count: 0,
  add:     (theta) -> (@count++; [x, y] = toCart 1, theta; @sum[0] += x; @sum[1] += y; @)
  average:         -> ([x, y] = @sum.map (x) => x/@count; atan2 y, x)

buffer.on

t = Date.now()

loop
  cls 'black'

  oldT = t
  t    = Date.now()
  dt   = t - oldT

  if mouse.left
    visionDistance = MIN_VISION_DISTANCE + (mouse.x / SCREEN_WIDTH) * (MAX_VISION_DISTANCE - MIN_VISION_DISTANCE)
    turnRate       = (mouse.y / SCREEN_HEIGHT) * MAX_TURN_RATE

  bugs =
    for bug, i in bugs
      {x, y, heading, c} = bug

      tooClose = angleAverager()
      theRest  = angleAverager()
      angles   = angleAverager().add wobblyBug bug

      for otherBug, j in bugs when j isnt i
        dist = hypot (diff = [otherBug.x - x, otherBug.y - y])...

        switch
          when dist < MIN_SPACING    then tooClose.add atan2 diff[1], diff[0]
          when dist < visionDistance then theRest .add atan2 diff[1], diff[0]

      if tooClose.count then angles.add wrapRadians pi + tooClose.average()
      if theRest .count then angles.add wrapRadians      theRest .average()

      headingGoal = angles.average()
      offCourse   = wrapRadians headingGoal - heading
      turn        = (if offCourse < 0 then -1 else 1) * min abs(offCourse), turnRate * dt
      heading    += turn

      vel = toCart BUG_SPEED * dt, heading
      { x: (x + vel[0] + SCREEN_WIDTH ) % SCREEN_WIDTH
        y: (y + vel[1] + SCREEN_HEIGHT) % SCREEN_HEIGHT
        heading, c
      }

  locate 0, 0
  for bug in bugs
    color bug.c
    circle bug.x, bug.y, visionDistance
    text JSON.stringify(bug) + "\n"

    line bug.x, bug.y,
         bug.x + BUG_LENGTH * cos(bug.heading)
         bug.y + BUG_LENGTH * sin(bug.heading)

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


