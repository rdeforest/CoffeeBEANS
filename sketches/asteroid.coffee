# How hard can it be?

screen w = 320, h = 200
w2 = w>>1
h2 = h>>1
timeScale = 0.1

makeSprite = (xSize, ySize, drawFn) ->
  drawTo (s = surface xSize, ySize), drawFn
  s

# XXX: just a triangle, amazing
shipSprite = makeSprite 7, 15, ->
  ll     = [ 0, 14]
  lr     = [ 6, 14]
  top    = [ 3,  0]
  #middle = [ 3,  3]
  
  line ll...,  lr...
  line ll...,  top...
  line top..., lr...

# XXX: we can do better than a square... later
asteroidSprite = makeSprite 32, 32, ->
  rect 2, 2, 29, 29

# XXX: a mere dot isn't enough, let's use an inverted cross
missileSprite = makeSprite 3, 6, ->
  line 1,0,1,5
  line 0,4,2,4

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
    vel:    [rnd() - 0.5, rnd() - 0.5]
    sprite: asteroidSprite
    name:   "asteroid"
    size:   32
    spin:   rnd() - 0.5

bodies = [1..3].map makeAsteroid
bodies.push ship = makeShip()

# Vector ops
vAdd   = (a, b) -> [a[0] + b[0], a[1] + b[1]]
vScale = (v, s) -> [v[0] * s, v[1] * s]

colliding = []

screenWrap = ([x, y]) -> [(x + w) % w, (y + h) % h]

physics = (dt) ->
  for body in bodies
    body.loc = screenWrap vAdd body.loc, vScale body.vel, dt
    body.pointing += body.spin * dt

display = ->
  cls 'black'

  for body in bodies
    stamp body.sprite, body.loc[0], body.loc[1]

  buffer.swap

input = ->

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
