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

MAX_TURN_RATE = 40 * pi # radian per second
BUG_SPEED     = 0.01    # pixels per second

screen SCREEN_WIDTH = 320, SCREEN_HEIGHT = 200

[middleX, middleY] = [SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2]

corners = [ [ middleX - 20, middleY - 20 ]
            [ middleX + 20, middleY - 20 ]
            [ middleX + 20, middleY + 20 ]
            [ middleX - 20, middleY + 20 ] ]

liveBugs = undefined

initBugs = (liveBugs) ->
  [1..liveBugs].map (_, i) ->
    corner = corners[floor i / liveBugs * 4]

    [ corner[0] + 4 - rnd 10
      corner[1] + 4 - rnd 10
      rnd pi * 2 ]

bugs = []

t = Date.now()
loop
  dt = Date.now() - t
  t  = Date.now()

  if mouse.left
    cls 'black'
    liveBugs =        3 + floor(10 * mouse.x / SCREEN_WIDTH)
    bugs = initBugs liveBugs
    turnSpeed = MAX_TURN_RATE * dt * mouse.y / SCREEN_HEIGHT

  if liveBugs
    for bugA, i in bugs
      bugB = bugs[(i + 1) % liveBugs]

      dx = bugB[0] - bugA[0]
      dy = bugB[1] - bugA[1]

      angleToB   = atan2 dy, dx
      turnNeeded = angleToB - bugA[2]

      bugA[2] += max -turnSpeed, min turnNeeded, turnSpeed

      bugA[0] += BUG_SPEED * dt * cos(bugA[2])
      bugA[1] += BUG_SPEED * dt * sin(bugA[2])
      point (p = bugA[0..1])...

