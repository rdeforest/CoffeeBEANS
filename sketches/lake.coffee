screen w = 160, h = 100

tension   = 0.0001 # dz += tension * (neighbors/9 - z)
timeScale = 1     # dt = (now - then) * timeScale

show = (v) -> print JSON.stringify v, null, 2

main = ->
  print "starting"
  
  {water} = init()

  t = Date.now()

  loop
    [prevT, t] = [t, Date.now()]
    dt = t - prevT

    water =
    update water, dt * timeScale
    render water

    if mouse.down
      addWave water, mouse.x, mouse.y, mouse.left * 2 - 1

    if keys.hit 'q'
      break

    wait 1

  print "stopping"

init = ->
  water:
    [0 .. h - 1]  .map ->
      [0 .. w - 1].map ->
        [0, 0] # z, dz

update = (water, dt) ->
  for row, y in water
    for cell, x in row
      updateCell water, dt, x, y, cell

getNeighbors = (water, x, y) ->
  water[max(0, y - 1)..min(h, y + 1)]
    .map (row) ->
      row[max(0, x - 1)..min(w, x + 1)]
        .map ([z]) -> z

sumNeighbors = (water, x, y) ->
  values = getNeighbors(water, x, y).flat()
  (values.reduce (a, b) -> a + b) / values.length

updateCell = (water, dt, x, y, cell) ->
  [z, dz] = cell

  avg = sumNeighbors(water, x, y) / 9

  dz += tension * (avg - z)
  z  += dz * dt
  [z, dz]

render = (water) ->
  for row, y in water
    for [z, dz], x in row
      if z > 0
        c = COLORS.fromRGB z, z, 1
      else
        c = COLORS.fromRGB 0, 0, z + 1

      point x, y, c

  true

addWave = (water, x, y, z) ->
  water[y][x] = [ z, 0 ]

main()