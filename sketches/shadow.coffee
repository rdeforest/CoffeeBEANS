screen w = 320, h = 200

w2 = w / 2
h2 = h / 2

dot = (a, b) ->
  a .map    (x, i) -> x * b[i]
    .reduce (a, b) -> a + b

buffer.on

loop
  cls()

  iHat  = [1, 0]
  mouse = [mouse.x - w2, mouse.y - h2]

  line 0,  h2, w,       h2
  line w2, h2, mouse.x, mouse.y

  px = w2 + dot(iHat, mouse)

  line px, h2, px, mouse.y

  textAt px + 8, mouse.y + 8, "#{px}"

  buffer.swap

