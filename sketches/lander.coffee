tau = 2 * pi

screen w = 320, h = 200
middleX = w/2; middleY = h/2

# Our coordinate system is upside down because of screen space, so 90 degrees
# is down and 270 is up. 0 and 180 are still right and left, respectively.
# Or to put it another way, +y is down, so sin(DOWN) has to be positive.
DOWN      = tau * 1 / 4
UP        = tau * 3 / 4
turnSpeed = tau     / 360 # 1 degree
G         = 1e-7
thrust    = G * 3.0

toCart  = (mag, angle) -> [mag * cos(angle), mag * sin(angle)]
addCart = ([x1, y1]) -> ([x2, y2]) -> [x1 + x2, y1 + y2]

ship =
  x: middleX, y: middleY, dx: 0, dy: 0, heading: UP, ax: 0, ay: 0

  addForce: (mag, angle) ->
    [ax, ay] = toCart mag, angle
    [@ax, @ay] = (addCart [@ax, @ay]) [ax, ay]

  elapseTime: (dt) ->
    @addForce G, DOWN

    if @thruster
      @addForce thrust, @heading

    @dx += @ax * dt; @x += @dx * dt
    @dy += @ay * dt; @y += @dy * dt

  updateSprite: ->
    @sprite = surface 32, 32
    drawTo @sprite, => @draw()
    
  draw: ->
    points =
      [ toCart 12, @heading
        toCart  4, @heading + DOWN
        toCart  4, @heading + UP
        toCart -3, @heading
      ].map addCart [16, 16]

    for p, i in points[0..2]
      line p..., points[(i + 1) % 3]...

    if @thruster
      line 16, 16, points[3], 'yellow'

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
  color 'gray'   ; drawGround()
  ship.updateSprite()
  color 'coffee' ; put ship.sprite, ship.x, ship.y

t = Date.now()

buffer.on

loop
  if ship.y > h
    print "crashed? (#{ship.y})"
    break

  break if keys.down 'q'

  [oldTime, t] = [t, Date.now()]
  dt = t - oldTime

  ship.thruster = keys.down 'up' or keys.down 'space'
  if keys.down 'left'  then ship.heading -= turnSpeed
  if keys.down 'right' then ship.heading += turnSpeed
  ship.heading -= tau while ship.heading > tau
  ship.heading += tau while ship.heading < 0


  ship.elapseTime dt
  updateView()
  
  if keys.down 'd'
    locate 0, 0
    {x, y, dx, dy} = ship
    text (JSON.stringify {x, y, dx, dy})

  buffer.swap