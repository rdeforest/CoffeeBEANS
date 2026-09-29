w = 320
h = 200

hue = 0
sat = 0
val = 0

screen w, h

clamp = (low, value, high) -> max low, min high, value

point w/2, h/2, 'white'

loop
  switch floor rnd 4
    when 0 then [x, y] = [       floor(rnd w),     0]
    when 1 then [x, y] = [    0, floor(rnd h)       ]
    when 2 then [x, y] = [       floor(rnd w), h - 1]
    when 3 then [x, y] = [w - 1, floor(rnd h),     0]

  wandering = true

  while wandering
    [dx, dy] = [(1 - floor rnd 3), (1 - floor rnd 3)]
    x = clamp 0, (x + dx), w - 1
    y = clamp 0, (y + dy), h - 1

    for y1   in [max(0, y - 1) .. min(h - 1, y + 1)]
      for x1 in [max(0, x - 1) .. min(w - 1, x + 1)]
        if COLORS.toHSV(pget x1, y1).value > 0.5
          hue = (hue + 1) % 360
          sat = (sat + 1) % 50
          val = (val + 1) % 70
          point x, y, COLORS.fromHSV hue, (50 + sat) / 100, (30 + val) / 100
          wandering = false

