screen w = 320, h = 200

projectiles = []

G = 1
tScale = 0.001

boom = (p) ->
  [0..5].map ->
    {x, y, dx, dy} = p
    theta = 2*pi*rnd()
    dx += cos theta
    dy += sin theta
    [x, y, dx, dy, p.painter]

launch = (projectiles, x, y, dx, dy, painter) ->
  p = {x, y, dx, dy, painter}
  print JSON.stringify p, null, 2
  projectiles.concat p

drawFrame = (projectiles, dt) ->
  kids = []
  projectiles =
  for projectile in projectiles
    {x, y, dx, dy, painter = 'white'} = projectile
    x += dx * dt
    y += (dy += G * dt) * dt
    if dy > 0
      kids = kids.concat boom projectile
      
    point x, y, painter

    continue if y > h

    Object.assign projectile, {x, y, dx, dy}
  projectiles.concat kids

t = Date.now()

#buffer.on

#trails = surface w, h

loop
  [prevT, t] = [t, Date.now()]
  dt = (t - prevT) * tScale

  if projectiles.length < 5
    projectiles = launch projectiles, rnd(w), h, rnd(5), -15 + rnd(5), 'white'

  #cls()
  projectiles = drawFrame projectiles, dt
  #buffer.swap
