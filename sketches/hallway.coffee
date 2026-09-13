# The hallway effect. Lines from a vanishing point out to every edge, and
# the moire panelling is the aliasing doing it for free.
#
# Click the screen, then move the mouse to drag the vanishing point around.

screen w = 640, h = 400
buffer.on

drawHall = (cx, cy) ->
  for x in [0...w] by 6
    line cx, cy, x,     0
    line cx, cy, x, h - 1

  for y in [0...h] by 6
    line cx, cy,     0, y
    line cx, cy, w - 1, y
    
rescaler  = (scale, vanishingPoint = {x: w/2, y: h/2}) ->
  (x, y) ->
    { x: vpx
      y: vpy
    } = vanishingPoint

    scaled =
      x: vpx + (x - vpx) * scale
      y: vpy + (y - vpy) * scale

print JSON.stringify rescaler(0.5) 3, 4

loop
  cls()
  cx = mouse.x
  cy = mouse.y
  
  t = (Date.now() % 10000) / 10000

  color COLORS.coffee
  drawHall w/2, h/2

  scaled = rescaler t
  
  color 'red'
  { x: sx, y: sy } = scaled(cx, cy)
  circle sx, sy, 20 * t

  buffer.swap

     