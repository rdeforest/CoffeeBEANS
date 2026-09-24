###

3D space invaders?

TODO:
  * re-factor invaders and missiles to use a common base class
  * maybe walls and ship too?
  * .move method on ship is different from others
    * ship.move [dx, dy] => move that way
    * invader.move() => do a random move
    * missile.move() => move +1 z

###

SCREEN_WIDTH  = 320
SCREEN_HEIGHT = 200

DEPTH         = 10
CELL_SIZE     = floor SCREEN_HEIGHT / 6
MOVE_CHANCE   = 0.3
DROP_CHANCE   = 0.01

ART =
  invader: """
        x     x
         x   x
        xxxxxxx
       xx xxx xx
      xxxxxxxxxxx
      x xxxxxxx x
      x x     x x
         xx xx
    """
  ship: """
          x
         xxx
         x x
         x x
         xxx
        xxxxx
       xxxxxxx
      xxxxxxxxx
      xx xxx xx
          x
    """


main = ->
  world = init()

  loop
    drawWorld    world
    handleInput  world
    processWorld world

init = ->
  for name, value of ART
    ART[name] = convertArt value

  return makeWorld()

convertArt = (artStr) ->
  artStr
    .split '\n'
    .map (line, y) ->
      line
        .split ''
        .map (char, x) -> {char, x, y}
        .filter ({char}) -> char isnt ' '
        .map ({x, y}) -> [x, y]

drawWorld = (world) ->
  cls()
  world.invaders.forEach (invader) -> invader.draw()
  world.missiles.forEach (missile) -> missile.draw()
  world.walls.forEach (wall) -> wall.draw()
  world.ship.draw()

moveDirections =
  left:  [-1, 0]
  right: [ 1, 0]
  up:    [ 0,-1]
  down:  [ 0, 1]

handleInput = (world) ->
  for name, offset of moveDirections
    if keys.down name
      world.ship.move offset

  if keys.down 'space'
    world.ship.fireMissile()

processWorld = (world) ->
  world.missiles.forEach (missile) -> missile.move()
  world.invaders.forEach (invader) -> invader.move()

rndClr = -> (1 + rnd()) / 2 # 0.5 .. 0.999

clamper = (least, most) -> (n) -> min most, max least, n

clampLoc = clamper -2, 2

makeInvader = (world, i) ->
  world: world

  x:     2 - floor rnd 5 # -2 .. 2
  y:     2 - floor rnd 5 # -2 .. 2
  z:     DEPTH - i // 5  # DEPTH - 0 or 1

  color: COLORS.fromRGB ([0..2].map rndClr)...

  draw: ->
    scale = (DEPTH - @z + 2) / (DEPTH + 2) # 2/12 .. 12/12

    rescale = ([x, y]) -> [x + @x, y + @y]. map (n) -> n * scale

    for square in ART.invader
      color 'black'
      rectFill (p1 = rescale square[0..1])..., (p2 = rescale square[2..3])...
      color @color
      rect     p1..., p2...

  move: ->
    return unless MOVE_CHANCE > rnd()

    [x, y] = [@x, @y]
      .map (v) ->
        v = clampLoc v + floor -1 + rnd 3

    colliders = @world.getContents x, y, @z

    for obj in colliders
      if obj in world.missiles
        scoreHit world, @, obj
      else
        return

    [@x, @y] = x, y

isAt = (x, y, z) -> (item) ->
  item.x is x and
  item.y is y and
  item.z is z

makeMissile = (world, x, y, z) ->
  Object.assign {world, x, y, z},
    draw:
    move: ->
      @z += 1

makeShip = (world) ->
  world: world
  x: 0, y: 0, z: 0

  move: ([dx, dy]) ->
    @x += dx
    @y += dy

  fireMissile: ->
    # walls are at z = 1 and we're permitting firing through them
    world.missiles
      .push makeMissile world, @x, @y, 2

  draw: ->
    ART.ship.forEach (square) ->


makeWorld = ->
  world =
    invaders: [1..10].map (i) -> makeInvader world, i
    ship:     makeShip world
    walls:    makeWalls()
    missiles: []

    getContents: (x, y, z) ->
      collides = isAt(x, y, z)
      [@invaders..., @ship, @walls..., @missiles].filter collides

main()
