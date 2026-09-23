w = 600; h = w
show = (v) -> print JSON.stringify v, null, 2

primesFound = []

primes = ->
  primesFound = found = [2, 3]

  yield from found
  p = found.at -1

  loop
    p += 2

    for q in primes
      continue unless p % q

    found.push p
    yield p

factor = (n) ->
  pi = 0
  f  = []
  fi = new Set

  for p from primes()
    while (0 is n % p) and (p <= n)
      n /= p
      f.push p
      fi.add pi

    break if n is 1
    console.log JSON.stringify {p, n}
    pi++

  [f, fi]

#console.log factor process.argv[2] if process.argv[2]

if 'undefined' isnt typeof screen
  screen w, h
  nMax = w*h
  pixelColors = []

  pixelColors[n] = 0 for n in [2 .. nMax]

  pi = 0
  nextLoc = (loc) ->
    {x, y, dir, len} = loc

    switch dir
      when 0 then x++;         dir=1  if x - middle     >= len
      when 1 then y--;         dir=2  if     middle - y >= len
      when 2 then x--;         dir=3  if     middle - x >= len
      when 3 then y++; (len++; dir=0) if y - middle     >= len

    {x, y, dir, len}
  
  for p from primes()
    break if p > nMax

    n = p
    bit = 2 ** pi
    pi++

    while n < nMax
      mask = pixelColors[n] |= bit

      n += p

  loc = { x:   1 + middle = w//2
          y:   0 + middle
          dir: 1
          len: 1 }

  for mask in pixelColors
    if false
      r =  mask       & 15
      g = (mask >> 4) & 15
      b = (mask >> 8) & 15

      c = COLORS.fromRGB r * 16, g * 16, b * 16

    else
      if mask in primesFound
        c = 'white'
      else
        c = 'black'

    point loc.x, loc.y, c
    loc = nextLoc loc
