# How hard can it be?

screen w = 640, h = 400
w2 = w>>1
h2 = h>>1

timeScale     = 0.1
shipTurnSpeed = pi / 10000 # actually it's spin change speed
reloadTime    = 250
thrust        = 0.01
asteroidSpin  = pi / 200

angleToVector = (theta, mag = 1) -> [mag * cos(theta), mag * sin(theta)]

makeSprite = (xSize, ySize, drawFn) ->
  drawTo (s = surface xSize, ySize), drawFn
  s

# XXX: just a triangle, amazing
shipSprite = makeSprite 17, 17, ->
  # .................
  # 0   4   8   C   G
  ll     = [  0,  4]
  lr     = [  0, 12]
  top    = [ 16,  8]
  
  line ll...,  lr...
  line ll...,  top...
  line top..., lr...

# XXX: we can do better than a square... later
asteroidSprite = makeSprite 32, 32, ->
  rect 0, 0, 31, 31

# XXX: a mere dot isn't enough, let's use an inverted cross
missileSprite = makeSprite 6, 3, ->
  line 0,1,5,1
  line 1,0,1,2

makeBody = (info = {}) ->
  { loc      = [w2, h2]
    vel      = [0, 0]
    pointing = 0
    spin     = 0
  } = info
  {loc, vel, pointing, spin}

# makeBody(info) at end allows for overriding sprite
makeShip     = (info = {}) -> Object.assign {}, sprite: shipSprite,     name: "ship",     makeBody(info)
makeMissile  = (info = {}) -> Object.assign {}, sprite: missileSprite,  name: "missile",  makeBody(info)
makeAsteroid = (info = {}) ->
  Object.assign {},
    makeBody(info)
    loc:    angleToVector rnd() * 2 * pi, h2 / 2
    vel:    angleToVector rnd() * 2 * pi
    sprite: asteroidSprite
    name:   "asteroid"
    size:   32
    spin:   asteroidSpin * (rnd() - 0.5)

bodies = [1..3].map makeAsteroid
bodies.push ship = makeShip()

# Vector ops
vAdd   = (a, b) -> [a[0] + b[0], a[1] + b[1]]
vScale = (v, s) -> [v[0] * s, v[1] * s]

colliding = []

screenWrap = ([x, y]) -> [(x + w) % w, (y + h) % h]

launchMissile = (ship) ->
  if not ship.reloading or Date.now() > ship.reloading
    ship.reloading = Date.now() + reloadTime
    bodies.push missile = makeMissile ship
    missile.vel = vAdd missile.vel, angleToVector ship.pointing
    missile.loc = vAdd missile.loc, angleToVector ship.pointing, 4


physics = (dt) ->
  if ship.thrust    then ship.vel = vAdd ship.vel, vScale [cos(ship.pointing), sin(ship.pointing)], thrust * dt
  if ship.turnLeft  then ship.spin -= dt * shipTurnSpeed
  if ship.turnRight then ship.spin += dt * shipTurnSpeed
  if ship.stabilize then ship.spin *= 0.99
  if ship.fire      then launchMissile ship

  for body in bodies
    body.loc = screenWrap vAdd body.loc, vScale body.vel, dt
    body.pointing += body.spin * dt

showBody = (body) ->
  {sprite, pointing, loc: [x, y]} = body
  midx = sprite.width  / 2
  midy = sprite.height / 2
  stamp sprite, x, y,
    angle: pointing,
    anchorX: midx
    anchorY: midy

display = ->
  cls 'black'

  bodies.forEach showBody
  buffer.swap

mouseWasDown = null

input = ->
  ship.thrust    = keys.down 'w'
  ship.turnLeft  = keys.down 'a'
  ship.turnRight = keys.down 'd'
  ship.stabilize = keys.down 's'
  ship.fire      = keys.down 'space'

  if mouse.down
    if not mouseWasDown
      mouseWasDown = true
      print JSON.stringify ship
    ship.spin = 0
    ship.pointing = atan2 (vAdd [mouse.y, mouse.x], vScale ship.loc, -1)...
  else
    mouseWasDown = false

    

buffer.on

lastReport =
time = Date.now()

loop
  [prevTime, time] = [time, Date.now()]
  dt = time - prevTime

  physics dt * timeScale
  display()
  input()

# if 1000 < time - lastReport
#   lastReport = time
#   for body in bodies
#     {name, loc, vel, pointing, spin} = body
#     print JSON.stringify {name, loc, vel, pointing, spin}
