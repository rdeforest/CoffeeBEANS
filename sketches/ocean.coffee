screen w = 320, h = 200

W = w
H = h - 32

WATER   = 'WATER'
SHARK   = 'SHARK'
FISH    = 'FISH'

SHARK_FOOD_TIMER  = 3
SPAWN_TIMER       =
  [FISH ]: 4
  [SHARK]: 10
TURN_DURATION     = 100 # ms

STARTING_POPULATION =
  [WATER]: 0.65
  [FISH ]: 0.25
  [SHARK]: 0.10

history = []
history.max = [FISH]: 0, [SHARK]: 0, total: 0

newFish  = -> kind: FISH , spawn: 0
newShark = -> kind: SHARK, spawn: 0, food: SHARK_FOOD_TIMER
newWater = -> kind: WATER

pickKind = ->
  dieRoll = rnd()

  for kind, percent of STARTING_POPULATION
    if dieRoll < percent
      return kind
    else
      dieRoll -= percent

  throw new Error "population percentages not normalized?"

makeOcean = ->
  for y   in [0 .. H - 1]
    for x in [0 .. W - 1]
      switch kind = pickKind()
        when FISH  then newFish()
        when SHARK then newShark()
        when WATER then newWater()
        else throw new Error "Unknown kind: #{kind}"

drawOcean = (ocean) ->
  for row, y in ocean
    for cell, x in row
      switch
        when isShark cell then point x, y, COLORS.fromRGB 1 - (cell.food / SHARK_FOOD_TIMER), 0.5, 0.5
        when isFish  cell then point x, y, 'coffee'
        else                   point x, y, 'blue'

isShark  = (cell) -> cell.kind is SHARK
isFish   = (cell) -> cell.kind is FISH
isWater  = (cell) -> cell.kind is WATER

neighbors = (x, y) ->
  them = []

  for   dy in [ -1 .. 1 ]
    for dx in [ -1 .. 1 ]
      continue unless dx or dy

      xx = (x + dx + W) % W
      yy = (y + dy + H) % H

      them.push x: xx, y: yy

  them

potentialMoves = (oldOcean, newOcean, x, y) ->
  found = empty: [], food: []

  for move in neighbors x, y
    [oldCell, newCell] = [oldOcean[move.y][move.x], newOcean[move.y][move.x]]

    if isWater(oldCell) and isWater(newCell)
      found.empty.push move

    else if isFish(oldCell)
      found.food.push move

  return found

pickOne = (l) -> l[floor rnd l.length]

countAny = (kind) -> history[0][kind]++

processCell = (oldOcean, newOcean, cell, x, y) ->
  return if isWater cell

  moves = potentialMoves oldOcean, newOcean, x, y

  if isShark cell
    if --cell.food <= 0
      newOcean[y][x] = newWater()
      return

    if dest = pickOne moves.food
      cell.food = SHARK_FOOD_TIMER
      oldOcean[dest.y][dest.x] = newWater() # mark fish eaten
    else
      dest = pickOne moves.empty

    countAny SHARK

  if isFish cell
    dest = pickOne moves.empty

    countAny FISH

  cell.spawn++

  if dest
    newOcean[dest.y][dest.x] = cell
    newOcean[y][x] =
      if cell.spawn >= SPAWN_TIMER[cell.kind]
        spawn cell
      else
        newWater()

    oldOcean[y][x] = newWater()

  else
    newOcean[y][x] = cell

spawn = (cell) ->
  child =
  ({ [FISH ]: newFish
     [SHARK]: newShark }[cell.kind])()
  cell.spawn = 0
  child.gen = (cell.gen ? 0) + 1
  child

iterateOcean = (ocean) ->
  history.unshift [FISH]: 0, [SHARK]: 0

  newOcean = ocean.map (row) -> row.map newWater

  for row, y in ocean
    for cell, x in row
      processCell ocean, newOcean, cell, x, y

  history[0].total = Object.values(history[0]).reduce (a, b) -> a + b

  for kind in [FISH, SHARK, 'total']
    history.max[kind] = max history.max[kind], history[0][kind]

  newOcean

lastTurn = 0
turn     = 0
ocean    = makeOcean()

buffer.on

loop
  if TURN_DURATION <= Date.now() - lastTurn
    lastTurn = Date.now()
    turn++
    ocean = iterateOcean ocean

  drawOcean ocean

  if history.length > w
    history.pop()

  rectFill 0, h - 32, history.length, h - 1, 'black'

  for turn, x in history
    sharks = turn[SHARK] / history.max.total
    fish   = turn[FISH]  / history.max.total
    total  = turn.total  / history.max.total

    point x, h - (sharks * 32), 'gray'
    point x, h - (fish   * 32), 'coffee'
    #point x, h - (total  * 32), 'white'
  
  buffer.swap
