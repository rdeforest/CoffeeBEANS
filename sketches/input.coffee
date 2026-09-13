# Click the screen first, or the editor keeps your keystrokes.
#   arrows  move the dot        space   leave a mark
#   mouse   drag to paint       wheel   resize the dot

screen 320, 200
cls()
print "click the screen, then drive with the arrow keys"

buffer.on

x = 160
y = 100
size = 3

loop
  cls 0xFF0A0A12

  x += 2 if keys.down 'right'
  x -= 2 if keys.down 'left'
  y -= 2 if keys.down 'up'
  y += 2 if keys.down 'down'

  size = min 24, max 1, size - mouse.wheel / 120

  print "mark at #{round x}, #{round y}" if keys.hit 'space'

  for dy in [-size..size] by 1
    for dx in [-size..size] by 1
      point x + dx, y + dy, COLORS.coffee if dx * dx + dy * dy <= size * size

  point mouse.x, mouse.y, COLORS.red
  point mouse.x, mouse.y, COLORS.white if mouse.left

  buffer.swap
