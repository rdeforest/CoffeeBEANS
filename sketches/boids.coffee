#show = (v) -> print JSON.stringify v, null, 2

w = 320; h = 200

screen w, h

crowding = 15

weight =
  flock:  1
  flee : -10
  align:  1

limits =
  speed: 0.02
  turn:  0.01
  sight: min(w,h) / 2

bugSight = limits.sight / 5
bugTurn  = limits.turn  / 10

# fold(foo) bar - like bar % foo, except foo/2 .. foo go to -foo .. 0
# (thank you Claude)
fold = (size) -> (x) -> x - size * round x / size
foldX = fold w; foldY = fold h
foldRadians = (theta) -> atan2(sin(theta), cos(theta))

addVector = (v1, v2, scale = 1) -> v1.map (x, i) -> x + v2[i] * scale

makeBug = (template = {}) ->
  { x = rnd(w), y = rnd(h), dir = pi * (1 - rnd 2) } = template
  { x, y, dir }

bugs = [1..10].map makeBug

aspects = "flock flee align".split ' '

scanFlock = (bug) ->
  angle = Object.assign (aspects.map (name) -> [name]: [0, 0])...

  for other in bugs when other isnt bug
    offset = [foldX(other.x - bug.x), foldY(other.y - bug.y)]
    dist   = hypot offset...
    dir    = atan2 offset[1], offset[0]

    continue if dist > bugSight

    angle.align   = addVector angle.align, [cos(other.dir), sin(other.dir)]

    if dist < crowding
      angle.flee  = addVector angle.flee , offset, (crowding - dist) / crowding
    else
      angle.flock = addVector angle.flock, offset, 1/dist

  angle

buffer.on

prevT = t = Date.now()

loop
  cls 'black'
  
  [prevT, t] = [t, Date.now()]
  dt = t - prevT

  if mouse.left
    bugSight = limits.sight * (mouse.x / w)
    bugTurn  = limits.turn  * (mouse.y / h)
    #show {bugSight, bugTurn}

  bugs =
  for bug, i in bugs
    angle = scanFlock ({x, y, dir} = bug)

    target = [0,0]
    aspects.forEach (aspect) -> target = addVector target, angle[aspect], weight[aspect]
    targetAngle = atan2 target[1], target[0]

    dir = foldRadians dir + max -bugTurn * dt, min bugTurn * dt, targetAngle

    x = (w + x + dt * limits.speed * cos dir) % w
    y = (h + y + dt * limits.speed * sin dir) % h
    
    #circle x, y, 5, 'white'
    line x, y, x + 5 * cos(dir), y + 5 * sin(dir), 'white'
    #circle x, y, crowding, 'red'
    #circle x, y, bugSight, 'green'
    
    makeBug { x, y, dir }

  buffer.swap
