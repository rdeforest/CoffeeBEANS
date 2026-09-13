# Four things this proves:
#   1. pixels reach the screen
#   2. a plain synchronous loop draws progressively, not all at the end
#   3. buffer.swap blocks until the frame is actually presented
#   4. Stop unwinds this without taking the window with it

screen 320, 200
cls()

print "drawing a slow spiral..."

color COLORS.coffee

# no double buffering yet -- you should watch this fill in
for i in [0...20000] by 1
  t = i / 200
  r = i / 260
  point 160 + r * cos(t), 100 + r * sin(t)

print "now animating, hit Stop to interrupt"

buffer.on

angle = 0
loop
  cls 0xFF101018
  angle += 0.05
  for k in [0...240] by 1
    t = k / 24 + angle
    r = 20 + k / 3.2
    point 160 + r * cos(t), 100 + r * sin(t), COLORS.fromRGB (0.5 + 0.5 * sin t), 0.8, (0.5 + 0.5 * cos t)
  buffer.swap
