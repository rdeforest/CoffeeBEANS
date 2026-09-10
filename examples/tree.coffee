# Recursive feedback. Draw a trunk, snapshot the whole picture, stamp two
# shrunken rotated copies at the top of the trunk, repeat. Every generation
# doubles the branches without any recursion in the code.
#
# It is drawn on an off-screen surface cleared to transparent, because the
# snapshot has to carry "nothing here" through each generation -- a black
# background would paint over the previous branches.
#
# Move the mouse: left and right spreads the branches, up and down changes
# how much each generation shrinks.

screen 320, 200
buffer.on

BASE_X      = 160
BASE_Y      = 199
TRUNK_TOP   = 148
GENERATIONS = 7

canvas = surface 320, 200

loop
  spread = 0.15 + mouse.x / 320 * 0.75
  shrink = 0.62 + mouse.y / 200 * 0.22

  drawTo canvas, ->
    cls 0x00000000
    line BASE_X, BASE_Y, BASE_X, TRUNK_TOP, COLORS.coffee

    for generation in [1..GENERATIONS]
      whole = get 0, 0, 319, 199
      for side in [-1, 1]
        stamp whole, BASE_X, TRUNK_TOP,
          scale:   shrink
          angle:   spread * side
          anchorX: BASE_X
          anchorY: BASE_Y

  cls 0xFF07070C
  put canvas, 0, 0
  buffer.swap
