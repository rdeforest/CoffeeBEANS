
screen w = 600, h = 300
cls COLORS.black

r = 30
theta = rnd pi * 2

sum = (xs) -> xs.reduce ((a, b) -> a + b), 0
map = (fn) -> (xs) -> xs.map fn
dist = (p1) -> (p2) -> hypot p2.x - p1.x, p2.y - p1.y

points = []

paint = maker (p) ->
  v = sum map((p2) -> sin dist(p)(p2)) points
  COLORS.fromHSV 0, 0, v
  
wasDown = false

loop
  down = mouse.down
  
  if down and not wasDown
    points = [
      {x: w/2, y: h/2}
      {x: mouse.x, y: mouse.y}
    ]

    rectFill 4, 4, w - 4, h - 4, paint

  wasDown = down
  wait 1