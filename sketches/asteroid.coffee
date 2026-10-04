# How hard can it be?

screen w = 3 * 160, h = 3 * 100
w2 = w>>1
h2 = h>>1

# 'constants'
asteroidSize  = 32
timeScale     = 0.1
shipTurnSpeed = pi / 10000 # actually it's spin change speed
reloadTime    = 250
thrust        = 0.01
asteroidSpin  = pi / 200
missileFuel   = 500
missileSpeed  = 1
minRockSize   = 8

# game state
gameStarted   =
gameOver      = false
score         = 0
quarterSeen   = 0
ship = bodies = null

angleToVector = (theta, mag = 1) -> [mag * cos(theta), mag * sin(theta)]

# Vector ops
vAdd   = (a, b) -> [a[0] + b[0], a[1] + b[1]]
vScale = (v, s) -> [v[0] * s, v[1] * s]
vNeg   = (v) -> vScale v, -1

makeSprite = (xSize, ySize, drawFn) ->
  drawTo (s = surface xSize, ySize), drawFn
  s

shipSprite = makeSprite 17, 17, ->
  ll  = [  0,  4]
  lr  = [  0, 12]
  top = [ 16,  8]

  line ll...,  lr...
  line ll...,  top...
  line top..., lr...

asteroidSprite = (size) -> makeSprite size, size, ->
  [0..10]
    .map         -> 2 * pi * rnd()
    .sort (a, b) -> a - b
    .map (theta) ->
      mid = floor size / 2
      vAdd [mid, mid], angleToVector theta, mid - 1
    .forEach (p1, i, l) ->
      p2 = l[(i + 1) % l.length]
      line p1..., p2...

missileSprite = makeSprite 6, 3, ->
  line 0,1,5,1
  line 1,0,1,2

defaultShow = (body) ->
  {sprite, x, y, pointing} = body
  
  midx  = sprite.width  / 2
  midy  = sprite.height / 2

  stamp sprite, x, y,
    angle:   pointing,
    anchorX: midx
    anchorY: midy
 

makeBody = (info = {}, sprite) ->
  size   = min sprite.width, sprite.height
  radius = size / 2
  r2     = radius * radius

  { loc      = [w2, h2]
    vel      = [0, 0]
    pointing = 0
    spin     = 0
    show     = defaultShow
  } = info

  {loc, vel, pointing, spin, size, r2, sprite}

makeShip     = (info = {}) ->
  Object.assign {},
    name: "ship"
    makeBody(info, shipSprite)
    show: (body) ->
      defaultShow(body) if Date.now() % 2
        
makeMissile  = (info = {}) -> Object.assign {}, name: "missile",  makeBody(info, missileSprite), fuel: missileFuel
makeAsteroid = (info = {}) ->
  info.loc  ?= vAdd [w2, h2], angleToVector rnd() * 2 * pi, h2 / 2
  info.vel  ?= angleToVector rnd() * 2 * pi
  info.spin ?= asteroidSpin * (rnd() - 0.5)
  Object.assign {},
    makeBody(info, asteroidSprite info.size ?= asteroidSize)
    name:   "asteroid"

nextWave = ->
  ship        = makeShip()
  bodies      = [1..3].map -> makeAsteroid()

  bodies.push ship

initGame = ->
  gameOver    = false
  quarterSeen = 0
  score       = 0

  nextWave()

screenWrap = ([x, y]) -> [(x + w) % w, (y + h) % h]

launchMissile = (ship) ->
  if not ship.reloading or Date.now() > ship.reloading
    ship.reloading = Date.now() + reloadTime
    missile        = makeMissile ship
    missile.vel    = vAdd missile.vel, angleToVector ship.pointing, missileSpeed
    bodies.push missile

physics = (dt) ->
  if ship.thrust    then ship.vel = vAdd ship.vel, vScale [cos(ship.pointing), sin(ship.pointing)], thrust * dt
  if ship.fire      then launchMissile ship
  switch
    when ship.turnLeft  then ship.spin -= dt * shipTurnSpeed
    when ship.turnRight then ship.spin += dt * shipTurnSpeed
    else                     ship.spin *= 0.99

  bodies =
  for body in bodies
    body.dead      = 0 >= body.fuel -= dt if body.fuel

    body.loc       = screenWrap vAdd body.loc, vScale body.vel, dt
    body.pointing += body.spin * dt
    body

  checkCollisions() if gameStarted

checkCollisions = ->
  rocks    = bodies.filter (b) -> b.name is "asteroid"
  missiles = bodies.filter (b) -> b.name is "missile"

  if rocks.length is 0
    return nextWave()

  for rock in rocks
    if colliding       ship, rock
      shipOnRockAction ship, rock

  for missile in missiles
    for rock in rocks
      if colliding          missile, rock
        missileOnRockAction missile, rock

  bodies = bodies.filter (b) -> not b.dead

colliding = (a, b) ->
  diff    = vAdd b.loc, vNeg a.loc
  distSqr = diff[0] ** 2 + diff[1] ** 2
  radii2  = b.r2 + a.r2

  #line a.loc..., b.loc..., if radii2 < distSqr then 'green' else 'red'

  return distSqr < radii2

shipOnRockAction = (ship, rock) -> gameOver = true

asteroidBump = -> angleToVector 2 * pi * rnd()

missileOnRockAction = (missile, rock) ->
  score++
  missile.dead = rock.dead = true

  {loc, vel, size, spin} = rock

  size //= 2
  return if size < minRockSize

  r2 = (size / 2) ** 2

  bodies.push makeChildRock {loc, vel, size, spin, r2}
  bodies.push makeChildRock {loc, vel, size, spin, r2}

makeChildRock = ({loc, vel, size, spin, r2}) ->
  vel  = vAdd vel, asteroidBump()
  spin = spin + 1 - 0.5 * rnd()
  makeAsteroid {loc, size, r2, vel, spin}

showBody = (body) ->
  {sprite, pointing, loc: [x, y]} = body


display = ->
  textAt 0, 0, "SCORE: #{score * 100}"
  bodies.forEach showBody

input = ->
  if gameOver
    if quarterSeen > 0
      s = ("quarter")[..quarterSeen - 1]
      tWidth = textWidth s
      textAt w2 - tWidth/2, 0, s

    if keys.down ("quarter")[quarterSeen]
      quarterSeen++

    if quarterSeen is ("quarter").length
      initGame()
  else if gameStarted
    ship.thrust    = keys.down 'w'
    ship.turnLeft  = keys.down 'a'
    ship.turnRight = keys.down 'd'
    ship.fire      = keys.down 'space'
  else
    gameStarted  or= keys.down()

buffer.on

time = Date.now()
initGame()

loop
  [prevTime, time] = [time, Date.now()]
  dt = time - prevTime

  cls()
  physics dt * timeScale
  display()

  if gameOver
    ship.thrust    =
    ship.turnLeft  =
    ship.turnRight =
    ship.fire      = no

    tWidth = textWidth "GAME OVER"
    textAt w2 - tWidth/2, h2, "GAME OVER"

  input()

  buffer.swap
