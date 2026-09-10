# The hallway effect. Lines from a vanishing point out to every edge, and
# the moire panelling is the aliasing doing it for free.
#
# Click the screen, then move the mouse to drag the vanishing point around.

screen 320, 200
buffer.on

loop
  cls()
  cx = mouse.x
  cy = mouse.y

  for x in [0...320] by 6
    line cx, cy, x, 0,   COLORS.coffee
    line cx, cy, x, 199, COLORS.coffee

  for y in [0...200] by 6
    line cx, cy, 0,   y, COLORS.coffee
    line cx, cy, 319, y, COLORS.coffee

  buffer.swap
