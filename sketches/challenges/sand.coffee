screen w = 320, h = 200

SAND   = COLORS.yellow
ERASE  = COLORS.black

grains = []
piles  = [0..w].map -> 0 # XXX: pile is from h - height to h

buffer.on

loop
  cls ERASE

  if mouse.down and not grains.find (grain) -> grain.x is mouse.x and grain.y is mouse.y
    grains.push x: mouse.x, y: mouse.y

  grains =
    for {x, y} in grains
      y += 1

      switch
        when (h - piles[x    ]) > y then   x
        when (h - piles[x - 1]) > y then --x
        when (h - piles[x + 1]) > y then ++x
        else
          piles[x]++
          continue

      {x, y}

  for {x, y} in grains
    point x, y, SAND

  for height, x in piles
    line x, h - height, x, h, SAND

  buffer.swap

###
#
# Falling sand. A trig holiday, by rule. No sine, no cosine, no atan2, no
# floats.
# 
# The world is a grid of cells, empty or sand. Each frame, a grain falls one
# cell if the cell below is empty. If not, it slides down-left or down-right
# if one of those is empty. That's everything. Hold the mouse to pour.
# 
# The wall: forty lines, no classes, one grid. If you like, zero grids,
# because the screen can be the grid. Reading the pixel below you and drawing
# yourself there is exactly how this was done in 1989. Drop to 160 by 100 if
# it's slow.
# 
# There's one classic trap, and it concerns the order you visit cells. I won't
# say more, because unlike the boids bugs, this one announces itself on screen
# the moment you hit it. Those are the fun kind.
# 
# Done means: you've poured a pile and noticed the slope it settles at. You've
# met the trap and can say in one sentence why it happened. If you still want
# more after that, add water, which is sand that also moves sideways.
#
###

