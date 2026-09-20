show = (v) -> print JSON.stringify v, null, 2

w = 480; h = 300

screen w, h

crowding = 25

weight =
  flock  :  2
  flee   : -1
  align  :  1
  wobble :  1/10

limits =
  dt:    50
  speed: 0.02
  turn:  0.01
  sight: min(w, h) / 2

bugSight = limits.sight /  5
bugTurn  = limits.turn  / 10

# fold(foo) bar - like bar % foo, except foo/2 .. foo go to -foo .. 0
# (thank you Claude)
fold  = (size) -> (x) -> x - size * round x / size
foldX = fold w; foldY = fold h

foldRadians = (theta) -> atan2(sin(theta), cos(theta))

addVector = (v1, v2, scale = 1) -> v1.map (x, i) -> x + v2[i] * scale

makeBug = (template = {}) ->
  { x = rnd(w); y = rnd(h); dir = pi * (1 - rnd 2) } = template
  { x, y, dir }

bugs = [1..10].map makeBug

vectToAngle = (v) -> atan2 v[1], v[0]

scanFlock = (bug) ->
  vectors = {}

  for other in bugs when other isnt bug
    offset = [foldX(other.x - bug.x), foldY(other.y - bug.y)]
    dist   = hypot offset...
    dirToOther = vectToAngle offset

    continue if dist > bugSight

    vectors.align = addVector vectors.align ? [0, 0], [cos(other.dir ), sin(other.dir )]
    vectors.flock = addVector vectors.flock ? [0, 0], [cos(dirToOther), sin(dirToOther)]

  vectors

buffer.on

t = Date.now()

showAngle = (x, y, vect, color) ->
  angle = vectToAngle vect
  line x, y, x + 15 * cos(angle), y + 15 * sin(angle), color

loop
  cls 'black'
  
  [prevT, t] = [t, Date.now()]
  dt = min limits.dt, t - prevT

  if mouse.left
    bugSight = limits.sight * (mouse.x / w)
    bugTurn  = limits.turn  * (mouse.y / h)

  bugs =
    for bug, i in bugs
      vectors = scanFlock ({x, y, dir} = bug)
      wobble = dt/10000 * pi * (1 - rnd(2))
      targetVect = [weight.wobble * cos(dir + wobble), weight.wobble * sin(dir + wobble)]

      if vectors.flock
        targetVect = addVector targetVect, vectors.flock, weight.flock
        showAngle x, y, vectors.flock, COLORS.lime

      if vectors.align
        targetVect = addVector targetVect, vectors.align, weight.align
        showAngle x, y, vectors.align, COLORS.cyan

      showAngle x, y, targetVect, COLORS.yellow

      targetAngle = vectToAngle targetVect
      turn = foldRadians(targetAngle - dir)

      dir = foldRadians dir + max -bugTurn * dt, min bugTurn * dt, turn
      
      dx = dt * limits.speed * cos dir
      dy = dt * limits.speed * sin dir

      x = (w + x + dx) % w
      y = (h + y + dy) % h
      
      circle    x, y,   5, COLORS.white
      showAngle x, y, [5 * cos(dir), 5 * sin(dir)], COLORS.white

      #circle x, y, crowding, 'red'
      circle x, y, bugSight, COLORS.green
      
      { x, y, dir }

  buffer.swap

###
#
# For when I come back to this:
#
# The screen is your paper. You didn't want a pen, and you own a drawing toy.
# Draw bug zero's seek vector as a line, and a line to each neighbour it can
# see. A wrong sign becomes a line pointing the wrong way. That's the 1989
# move: make the machine show you.
#
# One rule at a time. Alignment alone has no positions, no offsets, no folds.
# You get a picture you can judge. Then add the next rule.
#
# Never refactor while it's broken. Classes, renames, and rewrites move bugs
# around without removing them. A vector type is a good instinct here, because
# it makes kinds visible. It's a tool for code that already works.
#
###


