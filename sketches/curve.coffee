# Draw figures from sine waves.

tau = 2 * pi

screen w = 640, h = 400

middleX = w / 2
middleY = h / 2
middle = [middleX, middleY]

degrees = (d) -> d * tau / 360

if true
  waves =
    [1..20]
      .map (n) ->
        [ rnd(25 - n), degrees rnd 180 ]

else
  waves = [
    [ 80, degrees   0]
    [  0, degrees  30]
    [  0, degrees  60]
    [  0, degrees  90]
    [  0, degrees 120]
    [  0, degrees 150]
    [  0, degrees 180]
    [  0, degrees 210]
    [  0, degrees   0]
    [  0, degrees   0]
    [  0, degrees   0]
    [  0, degrees   0]
    [  0, degrees   0]
    [  0, degrees   0]
    [ 20, degrees  30]
  ]


#fullCycleTime = 1000 # milliseconds

converter = (offset, theta) ->
  theta = (theta + offset) % 360

  switch
    when theta < 120 then 1
    when theta < 180 then (180 - theta) / 60
    when theta < 300 then 0
    else                  (theta - 300) / 60

rainbow = (angle) ->
  angle = angle / tau * 360

  r = converter   0, angle
  g = converter 240, angle
  b = converter 120, angle

  COLORS.fromRGB r, g, b

cls 'black'

theta = 0
dTheta = 2**-20

calculate = (angle) ->
  [x, y] = middle

  for [amp, phase], i in waves when amp
    x += amp * cos phase + (theta * (i + 1))
    y += amp * sin phase + (theta * (i + 1))

  [x, y]

distSquared = (a, b) -> (a[0]-b[0]) ** 2 + (a[1]-b[1]) ** 2

print "starting..."

while theta <= tau
  prevTheta = theta
  prevPos   = pos

  theta     = prevTheta + dTheta
  pos       = calculate theta

  color rainbow theta
  point pos...

print "done."
