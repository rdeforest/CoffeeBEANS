SAFE_VELOCITY = 0.01 # derived experimentally

tau = 2 * pi

screen w = 320, h = 200
middleX = w/2; middleY = h/2

# Our coordinate system is upside down because of screen space, so 90 degrees
# is down and 270 is up. 0 and 180 are still right and left, respectively.
# Or to put it another way, +y is down, so sin(DOWN) has to be positive.

DOWN      = tau * 1 / 4; UP = DOWN * 3
G         = 1e-6

thrust    = G * 3.0
turnSpeed = tau / 360 # 1 degree

ship =
  x: middleX, y: middleY, dx: 0, dy: 0, heading: UP

  elapseTime: (dt) ->
    [ax, ay] = [ G * cos(DOWN), G * sin(DOWN) ]

    if @thruster
      [ax, ay] = [ax + thrust * cos(@heading), ay + thrust * sin(@heading) ]

    @dx += ax * dt; @x += @dx * dt
    @dy += ay * dt; @y += @dy * dt

  draw: ->
    points =
      [ [ ship.x + 12 * cos(@heading),        ship.y + 12 * sin(@heading)        ]
        [ ship.x +  4 * cos(@heading + DOWN), ship.y +  4 * sin(@heading + DOWN) ]
        [ ship.x +  4 * cos(@heading + UP),   ship.y +  4 * sin(@heading + UP)   ]
        [ ship.x + -6 * cos(@heading),        ship.y + -6 * sin(@heading)        ] ]

    color if ship.dy > SAFE_VELOCITY then 'pink' else 'coffee'

    for p, i in points[0..2]
      line p..., points[(i + 1) % 3]...

    if @thruster
      line ship.x, ship.y, points[3]..., 'yellow'

updateView = ->
  cls 0x202020
  rect 0, h, w, h-10, 0x808080
  ship.draw()

t = Date.now()

buffer.on

loop
  [oldTime, t] = [t, Date.now()]
  dt = t - oldTime

  if ship.y >= h
    if ship.dy > SAFE_VELOCITY
      print "Boom!"
    else
      print "Well done, captain."

    break

  ship.thruster = keys.down 'up' or keys.down 'space'

  if keys.down 'left'  then ship.heading -= turnSpeed
  if keys.down 'right' then ship.heading += turnSpeed

  ship.elapseTime dt
  updateView()
  
  buffer.swap
