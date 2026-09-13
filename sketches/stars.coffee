screen w = 320, h = 200

stars     = ([floor(rnd w), floor(rnd h)] for i in [1..100])
twinkle   = -> [r, g, b] = [1..3].map -> (1 + rnd()) / 2

drawStars = ->
  for [x, y] in stars
    point x, y, 'white' # COLORS.fromRGB(twinkle()...)

buffer.on

print "started"

loop
  cls()
  #for [x, y] in stars
  #  point x, y, COLORS.fromRGB(twinkle()...)
    
  drawStars()

  buffer.swap
  break if keys.down 'q'

print "done"
