# Click a region to flood it. Hold shift and the fill crosses anything that
# is not white instead, so it floods the whole diagram at once -- that is the
# difference between "spread over what matches where I started" and "spread
# until you reach a border".
#
# Right-click fills only the dark parts, wherever the walk can reach, by
# asking each pixel how bright it is.

screen w = 320, h = 200
cls COLORS.black

color COLORS.white
rect 4, 4, 315, 195
circle  110, 100, 70
circle  210, 100, 70
circle  160,  60, 55

hue      = 0
wasDown  = false

loop
  down = mouse.down
  if down and not wasDown
    hue   = (hue + 57) %% 360
    #paint = COLORS.fromHSV hue, 0.75, 0.95
    paint = maker (p) ->
      r = (p.x % 160)/160
      g = (p.y % 100)/100
      b = ((p.x + p.y)%260) / 260
      COLORS.fromRGB r,g,b

    if mouse.right
      fill mouse.x, mouse.y, paint, where (p) -> p.value < 0.5
    else if keys.down 'shift'
      fill mouse.x, mouse.y, paint, border COLORS.white
    else
      fill mouse.x, mouse.y, paint

  wasDown = down
  wait 1