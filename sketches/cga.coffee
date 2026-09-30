screen width = 320, height = 200

map = (fn) -> (l) -> l.map fn
div = (divisor) -> (n) -> n / divisor

[midX, midY] = (map div 2) [width, height]

color 'yellow'

for x in [0..width] by 8
  line x,          0, midX, midY
  line x, height - 1, midX, midY
for y in [0..height] by 8
  line 0,          y, midX, midY
  line width - 1,  y, midX, midY

color 'white'  
rectFill 0, 0, width, 15, 'black'
textAt 0, 0, "Help, I'm stuck in a computer"
textAt 0, 8, "with a CGA adapter!"