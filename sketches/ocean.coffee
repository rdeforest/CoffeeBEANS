screen w = 320, h = 200

SHARK_FOOD_TIMER  = 20
SHARK_SPAWN_TIMER = 20
FISH_SPAWN_TIMER  = 20
TURN_DURATION     = 100 # ms

theWater = kind: WATER = Symbol '~~WATER~~'

main = ->
  ocean = blankOcean()
  params =
    shark:
      spawnTimer: SHARK_SPAWN_TIMER
      foodTimer:  SHARK_FOOD_TIMER
    fish:
      spawnTimer: FISH_SPAWN_TIMER
    turnTimer:  TURN_DURATION

  loop
    handleInputs params

    if params.turnTimer <= Date.now() - lastTurn
      ocean = updateCreatures ocean, params

    updateDisplay()

updateCreatures = (ocean, params) ->
  newOcean = blankOcean()

  for row, y in ocean
    for cell, x in row when cell isnt theOcean
      continue if cell.food and not --cell.food # blub, blub

      neighbors = getNeighbors(ocean, x, y) .flat()

      if dest = cell.kind.pickDest neighbors
        newOcean[dest[1]][dest[0]] = cell

        if dest.kind is Fish
          cell.food = params.SHARK_FOOD_TIMER

        if not --cell.spawn
          newOcean[y][x] = kind.make()
          cell.spawn = params.kind.spawnTimer

  newOcean

isFish = ({kind}) -> kind  is Fish
isWater = (space) -> space is theOcean

Shark =
  name: "shark"
  make: ->
    kind:  Shark
    food:  params.SHARK_FOOD_TIMER
    spawn: params.SHARK_SPAWN_TIMER
    
  pickDest: (neighbors) ->
    food  = neighbors.filter isFish
    water = neighbors.filter isWater

    if food.length
      pickOne food
    else if water.length
      pickOne water

Fish =
  name: "fish"
  make: ->
    kind:  Fish
    spawn: params.FISH_SPAWN_TIMER
  pickDest: (neighbors) ->
    if water.length
      pickOne water

getNeighbors = (ocean, x, y) ->
  for dy in [-1..1]
    yy = y = (y + dy) % ocean.length
    for dx in [-1..1]
      xx = (x + dx) % ocean[0].length
      Object.assign {x, y}, ocean[yy][xx]
     
pickOne = (list) -> list[floor rnd list.length]

handleInputs = ->

blankOcean = -> (theWater) for x in [0 .. w - 1] for y in [0..h - 1]

