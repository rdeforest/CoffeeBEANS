jprint = (args...) ->
  print args.map(JSON.stringify)...
  
screen w = 320, h = 200

cls   'black'
color 'coffee'

nextStateMaker = (rule) ->
  rule = rule
    .toString 2
    .padStart 8, '0'
    .split ''
    .map (d) -> parseInt d
    .reverse()

  #jprint {rule}

  (state) ->
    newState = (
      [0, state..., 0].map (_, i, l) ->
        return 0 unless 0 < i < l.length - 1

        bits = l[i - 1 .. i + 1]
        
        n = (bits[0] << 2) + (bits[1] << 1) + bits[2]
            
        #jprint {bits, n, r: rule[n]}
        rule[n]
        )[1 .. -2]

freshState = ->
  state = [1..w].map -> 0
  state[w // 2] = 1
  state

print "..."

#jprint nextState [0, 0, 0, 1, 0, 0, 0]

drawState = (state, y) ->
  for cell, x in state when cell
    point x, y

drawRule = (rule) ->
  state = freshState()
  nextState = nextStateMaker rule

  cls 'black'
  drawState state, 0

  for y in [1 .. h - 1]
    state = nextState state
    drawState state, y

loop
  rule = floor 256 * mouse.x / (w - 1)
  
  if keys.down 'q'
    break

  if mouse.left
    drawRule rule
    print rule