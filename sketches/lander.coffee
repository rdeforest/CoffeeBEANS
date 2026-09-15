tau = 2 * pi

SAFE_VELOCITY = 0.01 # derived experimentally
VERTICAL_THRESHOLD = cos(tau / 36)

screen w = 320, h = 200
middleX = w/2; middleY = h/2

# Our coordinate system is upside down because of screen space, so 90 degrees
# is down and 270 is up. 0 and 180 are still right and left, respectively.
# Or to put it another way, +y is down, so sin(DOWN) has to be positive.

DOWN      = tau * 1 / 4; UP = DOWN * 3
G         = 1e-6

thrust    = G * 3.0
turnSpeed = tau / 360 # 1 degree

ground    = (h - floor rnd 30 for x in [0 .. w] by 16)
pad       = floor rnd x // 16
padHeight = max ground[pad .. pad + 1]...
ground.splice pad, 2, padHeight, padHeight

ship =
  x: middleX, y: middleY, dx: 0, dy: 0, heading: UP

  speeding: -> @dy > SAFE_VELOCITY
  landed: ->
    ( pad * 16 <= @x <= (pad + 1) * 16        ) and
    ( not @speeding()                         ) and
    ( abs(@dx) < SAFE_VELOCITY                ) and
    ( cos(@heading - UP) > VERTICAL_THRESHOLD ) and
    ( 2 > (padHeight - @y)                    )

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

    color if @speeding() then 'pink' else 'coffee'

    line p..., points[(i + 1) % 3]... for p, i in points[0..2]

    if @thruster then line ship.x, ship.y, points[3]..., 'yellow'

updateView = ->
  color 'gray'
  line i * 16, ground[i], (i+1) * 16, ground[i + 1] for _, i in ground[..-2]
  line pad * 16, ground[pad], (pad + 1) * 16, ground[pad], 'lime'
  ship.draw()

t = Date.now()

buffer.on

loop
  cls 0x202020
  [oldTime, t] = [t, Date.now()]
  dt = t - oldTime

  if ship.landed()
    print "Well done, captain."
    break

  if ship.y > max (ground[ cell = ship.x // 16 .. cell + 1])...
    print "Boom!"
    break

  ship.thruster = keys.down 'up' or keys.down 'space'

  ship.heading -= turnSpeed if keys.down 'left'
  ship.heading += turnSpeed if keys.down 'right'

  ship.elapseTime dt

  updateView()
  
  buffer.swap
