# A starting point for a game. Mouse moves the paddle; miss and it resets.
# Click the screen first if you want the keyboard too.

screen 320, 200
buffer.on

WALL   = 4
PADDLE = 40

newBall = -> x: 160, y: 60, dx: 1.7, dy: 1.3

ball  = newBall()
score = 0
best  = 0

loop
  cls 0xFF07070C

  paddleX = min 320 - WALL - PADDLE, max WALL, mouse.x - PADDLE / 2

  ball.x += ball.dx
  ball.y += ball.dy
  ball.dx *= -1 if ball.x < WALL + 2 or ball.x > 320 - WALL - 2
  ball.dy *= -1 if ball.y < WALL + 2

  if ball.y > 186 and ball.y < 192 and ball.dy > 0
    if ball.x > paddleX and ball.x < paddleX + PADDLE
      ball.dy *= -1
      ball.dx += (ball.x - (paddleX + PADDLE / 2)) / 40
      score += 1

  if ball.y > 200
    best  = max best, score
    ball  = newBall()
    score = 0

  rect WALL, WALL, 320 - WALL, 195, 0xFF1E1E28
  rectFill paddleX, 188, paddleX + PADDLE, 191, COLORS.coffee
  circleFill ball.x, ball.y, 3, COLORS.white

  color COLORS.coffee
  locate 1, 1
  text "SCORE #{score}"
  locate 1, 2
  color 0xFF6A6A78
  text "BEST  #{best}"

  buffer.swap
