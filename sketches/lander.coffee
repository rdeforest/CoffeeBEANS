tau   = 2 * pi

screen w = 320, h = 200
middleX = w/2; middleY = h/2

# Our coordinate system is upside down because of screen space, so 90 degrees
# is down and 270 is up. 0 and 180 are still right and left, respectively.
# Or to put it another way, +y is down, so sin(DOWN) has to be 1.
DOWN      = tau * 1 / 4
UP        = tau * 3 / 4
turnSpeed = tau     / 180 # 2 degrees
G         = 1
thrust    = 1.5

toCart = (mag, angle) -> [mag * cos(angle), mag * sin(angle)]

ship =
  x: middleX, y: middleY, dx: 0, dy: 0, heading: UP
  #, ax: 0, ay: 0

  addForce: (mag, angle) ->
    return
    [ax, ay] = toCart mag, angle

    if 'number' isnt typeof ax or 'number' isnt typeof ay
      throw new Error "toCart returned non-numbers?"

    @ax += ax; @ay += ay

  elapseTime: (dt) ->
    @addForce G, DOWN

    if @thruster
      @addForce @heading, thrust

    @dx += @ax * dt; @x += @dx * dt
    @dy += @ay * dt; @y += @dy * dt

    @ax  = @ay = 0

  draw: ->
    offset = ([x, y]) -> [@x + x, @y + y]
    [x1, y1] = offset toCart 9, @heading
    [x2, y2] = offset toCart 5, @heading + DOWN
    [x3, y3] = offset toCart 5, @heading + UP
    line x1, y1, x2, y2
    line         x2, y2, x3, y3
    line x1, y1,         x3, y3

    if @thruster then line @x, @y, offset toCart 3, -@heading

applyGravity = (o) -> o.addForce DOWN,      G
applyThrust  = (o) -> o.addForce o.heading, thrust

#stars  = ([rnd 320, rnd 170] for i in [1..100])
#twinkle = -> [r, g, b] = [1..3].map -> (1 + rnd()) / 2
#drawStars = -> point star.x, star.y, color COLORS.fromRGB(twinkle()...) for star in stars

#ground = ((h - 30) + floor rnd 30 for x in [1..w] by 16)
ground = [174,170,179,176,171,175,189,179,174,199,177,173,175,182,196,173,183,192,171,194]

drawGround = ->
  [x2, y2] = [0, ground[0]]

  for height, i in ground[1..]
    line ([x1, y1, x2, y2] = [x2, y2, (i + 1) * 20, height])...

updateView = ->
  cls 0x202020

  # Do we really need to re-draw the ground every frame? Not a performance
  # concern, just... philosophy.
  drawGround()

  ship.draw()

t = Date.now()

buffer.on

loop
  break if keys.down 'q'

  [oldTime, t] = [t, Date.now()]
  dt = t - oldTime

  #applyGravity ship
  ship.thruster = keys.down 'up' or keys.down 'space'
  if keys.down 'left'  then ship.heading -= turnSpeed
  if keys.down 'right' then ship.heading += turnSpeed

  ship.elapseTime dt
  updateView()
  if keys.down 'd' then print JSON.stringify ship

  buffer.swap

print "finished"
