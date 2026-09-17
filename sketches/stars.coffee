screen w = 320, h = 200

# events per millisecond
twinkleRate = 10000
shootingStarRate = 0.00001

shootingStars = []
shootingStarLifetime = 1000
shootingStarVelocity = 0.1

shootingStarAdded = Date.now()

stars   = ([rnd(w), rnd(h), Date.now()] for i in [1..100])
twinkle = -> [r, g, b] = [1..3].map -> 0.6 + rnd() * 0.4

drawStars = ->
  cls()
  now = Date.now()

  stars =
    for star, i in stars
      [x, y, prevTime, starColor] = star
      dt = now - prevTime
  
      if (2 * rnd() * twinkleRate) < dt
        star[2] = now
        star[3] = starColor = COLORS.fromRGB(twinkle()...)
        
      point x, y, starColor
      star

  dt = now - shootingStarAdded
  if rnd() < dt * shootingStarRate 
    shootingStarAdded = now
    v = (1 + rnd()) * shootingStarVelocity
    theta = 2 * pi * rnd()
    
    shootingStars.push s = [
        rnd(w), rnd(h)
        v * cos(theta), v * sin(theta)
        shootingStarLifetime
      ]
    
  shootingStars =
    for star in shootingStars when star[4] > 0
      [x, y, dx, dy, life] = star
      life -= dt
      xNew = x + dx * dt
      yNew = y + dy * dt
      line x, y, xNew, yNew, 'white'
      [xNew, yNew, dx, dy, life]

  buffer.swap

buffer.on

loop
  drawStars()