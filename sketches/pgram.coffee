screen w = 320, h = 200

origin = [ w2 = w / 2
           h2 = h / 2 ]

cross = (a, b) -> a[0] * b[1] - b[0] * a[1]

buffer.on

vAdd   = (a, b) -> a.map (x, i) -> x + b[i]
vScale = (v, s) -> v.map (x)    -> x * s
vNeg   = (v)    -> vScale v, -1

toScreen   = (v) -> vAdd v,      origin
fromScreen = (v) -> vAdd v, vNeg origin

line2d = (p1, p2, args...) -> line toScreen(p1)..., toScreen(p2)..., args...

u = [rnd(w2), rnd(h2)]

loop
  cls()

  ptr    = fromScreen [mouse.x, mouse.y]
  tip    = vAdd u, ptr
  middle = vScale tip, 1/2
  area   = cross u, ptr

  line2d [0, 0], u
  line2d [0, 0], ptr

  line2d u     , tip
  line2d ptr   , tip

  fill toScreen(middle)..., 'blue'

  line2d [0,0], middle, 'yellow'
  line2d middle, tip, 'green'
  line2d tip, textPoint = vAdd(tip, [8, 8]), 'red'

  textAt toScreen(textPoint)..., "x = #{area}"

  buffer.swap

