w = 320; h = 200

screen w, h

# fold(foo) bar - like bar % foo, except foo/2 .. foo go to -foo .. 0
# (thank you Claude)
fold = (size) -> (x) -> x - size * round x / size
foldX = fold w
foldY = fold h

bugs = [1..40].map -> { x: w, y: h, dir: pi * (1 - rnd 2) }

bugSight = min(w, h) / 2
crowding = 10

buffer.on

addAngle = (p, a, s = 1) -> [p[0] + s * cos(a), p[1] + s * sin(a)]

weight =
  flock:  1
  flee : -1
  align:  1

loop
  cls 'black'

  for bug in bugs
    angle =
      flock : [0, 0]
      flee  : [0, 0]
      align : [0, 0]

    for other in bugs when other isnt bug
      offset = [foldX(other.x) - foldX(bug.x), foldY(other.y) - foldY(bug.y)]
      dist   = hypot offset...
      dir    = atan2 offset[1], offset[0]

      continue if dist > bugSight

      align = addAngle angle.align, other.dir

      group = if dist < crowding then angle.flee else angle.flock

      group = addAngle group, dir

    angle.flock = atan2 flock[1], flock[0]
    angle.flee  = atan2  flee[1],  flee[0]
    angle.align = atan2 align[1], align[0]

    target = [0,0]
    "flock flee align" .split(' ') .forEach (aspect) -> target = addAngle target, angle[aspect], weight[aspect]

    targetAngle = atan2 target[1], target[0]

    bug.heading += min -MAX_TURN_RATE * dt, max MAX_TURN_RATE * dt, targetAngle

    bug.x += dt * bugSpeed * cos bug.heading
    bug.y += dt * bugSpeed * sin bug.heading

    point bug.x, bug.y

  buffer.swap
