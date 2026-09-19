screen SCREEN_WIDTH = 640, SCREEN_HEIGHT = 300

SCREEN_SIZE         = min SCREEN_WIDTH, SCREEN_HEIGHT

MAX_TURN_RATE       = 0.008 * pi      # radian per millisecond
STARTING_BUG_SPEED  = 0.08            # pixels per millisecond

BUG_LENGTH          = 5               # pixels
MIN_SPACING         = BUG_LENGTH  * 2 # pixels
MIN_VISION_DISTANCE = MIN_SPACING * 2 # pixels
BUG_WOBBLE          = MAX_TURN_RATE / 10

MAX_VISION_DISTANCE = SCREEN_SIZE / 2 # pixels

FLOCK_WEIGHT        = 1
FLEE_WEIGHT         = 100
ALIGN_WEIGHT        = 1

liveBugs            = 40

buffer.off
cls()
circle 320, 150, 'white'

class Vector
  @fromAngle: (theta) -> new Vector cos(theta), sin(theta)

  constructor: (@x = 0, @y = 0) ->

  angle  :         -> atan2  @y,        @x
  mag    :         -> hypot  @x,        @y
  unit   :         -> Vector.fromAngle @angle()

  plus   : (v2)    -> new Vector @x + v2.x, @y + v2.y
  minus  : (v2)    -> new Vector @x - v2.x, @y - v2.y
  times  : (n)     -> new Vector @x *    n, @y *    n

  lineTo : (v2, c) -> line @x, @y, v2.x, v2.y, c

class Bug
  constructor: (oldBug = {}) ->
    { @pos     = new Vector rnd(SCREEN_WIDTH), rnd(SCREEN_HEIGHT)
      @heading = rnd pi * 2
      @c       = COLORS.fromHSV 360 * rnd(), 0.5 + rnd() / 2, 1
    } = oldBug

  draw: ->
    @pos.lineTo @pos.plus(Vector.fromAngle(bug.heading).times(BUG_LENGTH)), bug.c
    circle @pos.x, @pos.y, BUG_LENGTH, bug.c
    circle @pos.x, @pos.y, visionDistance, 'cyan'
    circle @pos.x, @pos.y, MIN_SPACING, 'purple'
    
wrapScreen   = ([x, y])      -> [ (x + SCREEN_WIDTH ) % SCREEN_WIDTH, (y + SCREEN_HEIGHT) % SCREEN_HEIGHT ]

fold         = (size)        -> (d) -> d - size * round d / size # thank you Claude
foldX        = fold SCREEN_WIDTH
foldY        = fold SCREEN_HEIGHT

clamp        = (least, most) -> (value)   -> max least, min most, value
portionOf    = (begin, end)  -> (portion) -> begin + (end - begin) * portion

visionDial   = portionOf MIN_VISION_DISTANCE, MAX_VISION_DISTANCE
turnRateDial = portionOf 0, MAX_TURN_RATE


bugs           = [1 .. liveBugs].map -> new Bug
bugSpeed       = STARTING_BUG_SPEED

visionDistance = visionDial   0.5
turnRate       = turnRateDial 0.5

buffer.on

t = Date.now()

show = (stuff) -> print JSON.stringify stuff, null, 2

scanOtherBugs = (bug) ->
  flockTo  = new Vector 0, 0
  fleeFrom = new Vector 0, 0
  pointTo  = new Vector 0, 0

  for otherBug in bugs when otherBug isnt bug
    offset = otherBug.pos.minus bug.pos
    [offset.x, offset.y] = [foldX(offset.x), foldY(offset.y)]
    dist   = offset.mag()

    continue if visionDistance < dist

    offset = offset.unit() # normalize to not favor more distant bugs

    if dist < MIN_SPACING
      portion = (MIN_SPACING - dist) / MIN_SPACING
      show before: {dist, portion, fleeFrom, offset}
      feelFrom = fleeFrom.plus offset.times portion
      ff = new Vector
      ff = ff.plus offset.times portion
      show after: {dist, portion, fleeFrom, ff, offsetTimesPortion: offset.times portion}
    else
      flockTo  = flockTo .plus offset

    pointTo = pointTo.plus Vector.fromAngle otherBug.heading

  {flockTo, fleeFrom, pointTo}

show "--- debug ---"
bugs.push aBug = new Bug pos: aPos = new Vector 200, 200
scanOtherBugs aBug
show "--- end debug ---"

loop
  cls 'black'

  [oldT, t] = [t, Date.now()]
  dt = t - oldT

  if mouse.left
    visionDistance =      visionDial   mouse.x / SCREEN_WIDTH
    turnRate       = dt * turnRateDial mouse.y / SCREEN_HEIGHT

  bugs = for bug in bugs
    {pos, heading, c} = bug

    {flockTo, fleeFrom, pointTo} = scanOtherBugs bug

    heading += BUG_WOBBLE * (1 - rnd 2)

    target = (flockTo .unit().times FLOCK_WEIGHT)
       .minus(fleeFrom.unit().times  FLEE_WEIGHT)
       .plus (pointTo .unit().times ALIGN_WEIGHT)

    headingDiff    = target.angle() - heading
    heading        = heading + max -turnRate, min turnRate, headingDiff

    vel            = Vector.fromAngle(heading).times bugSpeed
    pos            = pos.plus vel.times dt
    [pos.x, pos.y] = wrapScreen [pos.x, pos.y]

    bug.draw()

    new Bug { pos, heading, c }

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
