# How hard can it be?

screen w = 640, h = 400
w2 = w>>1
h2 = h>>1

timeScale     = 0.1
shipTurnSpeed = pi / 10000 # actually it's spin change speed
reloadTime    = 250
thrust        = 0.01
asteroidSpin  = pi / 200
missileFuel   = 5000 # milliseconds

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

makeBody = (info = {}, sprite) ->
  radius = min(sprite.width, sprite.height) / 2

  { loc      = [w2, h2]
    vel      = [0, 0]
    pointing = 0
    spin     = 0
    r2       = radius * radius
  } = info

  {loc, vel, pointing, spin, r2}

# makeBody(info, sprite) at end allows for overriding sprite
makeShip     = (info = {}) -> Object.assign {}, name: "ship",     makeBody(info, shipSprite)
makeMissile  = (info = {}) -> Object.assign {}, name: "missile",  makeBody(info, missileSprite), fuel: missileFuel
makeAsteroid = (info = {}) ->
  Object.assign {},
    makeBody(info, asteroidSprite)
    loc:    vAdd [w2, h2], angleToVector rnd() * 2 * pi, h2 / 2
    vel:    angleToVector rnd() * 2 * pi
    name:   "asteroid"
    size:   32
    spin:   asteroidSpin * (rnd() - 0.5)

bodies = [1..3].map makeAsteroid
bodies.push ship = makeShip()

# Vector ops
vAdd   = (a, b) -> [a[0] + b[0], a[1] + b[1]]
vScale = (v, s) -> [v[0] * s, v[1] * s]
vNeg   = (v) -> vScale v, -1

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

  for body, i in bodies
    if body.fuel
      body.dead = 0 >= body.fuel -= dt

    body.loc = screenWrap vAdd body.loc, vScale body.vel, dt
    body.pointing += body.spin * dt

    for other in bodies[i+1..] when i < bodies.length - 1

      diff = vAdd other.loc, vNeg body.loc
      distSqr = diff[0]**2 + diff[1]**2
      radii2  = other.r2 + body.r2
      
      if radii2 > distSqr
        # Asteroid shards are ephemeral until they are no longer touching
        next if body.splitting is other

        handleCollision body, other
      else
        if body.splitting is other
          body.splitting = other.splitting = false
        

handleCollision = (a, b) ->
  if "ship" in names = [a.name, b.name]
    return handleShipCollision a, b

  if "missile" in names
    return handleMissileCollision a, b

  if "asteroid" in names
    return handleAsteroidCollision

  throw new Error "Collisions not implemented for either body type #{names.join " or "}"

handleShipCollision = (ship, other) ->
  if other.name is "ship"
    [ship, other] = [other, ship]

  if other.name is "missile"
    return ownGoal ship, other

  if other.name is "asteroid"
    return shipOnRockAction ship, other

  throw new Error "Don't know how to collide a ship with a(n) #{other.name}"

ownGoal = (ship, missile) ->
  gameOver()

shipOnRockAction = (ship, rock) ->
  gameOver()

missileOnRockAction = (missile, rock) ->
  missile.dead = rock.dead = true
  {loc, vel, size} = rock
  vel1 = vAdd vel, asteroidBump()
  vel2 = vAdd vel, asteroidBump()
  size //= 2
  r2 = (size / 2) ** 2
  rock1 = makeAsteroid {loc, vel: vel1, size, r2}
  rock2 = makeAsteroid {loc, vel: vel2, size, r2}
  rock1.splitting = rock2
  rock2.splitting = rock1

  bodies.push rock1, rock2

handleMissileCollision = (missile, other) ->
  if missile.name isnt "missile"
    [missile, other] = [other, missile]

  if other.name is "missile"
    missile.dead = other.dead = true
    return

  if other.name is "asteroid"
    missileOnRockAction missile, other

  throw new Error "Don't know how to collide a missile with a(n) #{other.name}"

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
