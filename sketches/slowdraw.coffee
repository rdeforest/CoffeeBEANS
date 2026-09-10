# Single buffered, no swap, no yield point anywhere. Two things to watch:
# pixels should appear while this is still running, and Stop has to fall
# back to terminate because there is nothing here to interrupt.
screen 320, 200
cls()
print "slow draw, no swap, no yield point"

for i in [0...30000000] by 1
  t = i / 4000
  r = (i % 400000) / 4200
  point 160 + r * cos(t), 100 + r * sin(t), COLORS.fromRGB (i % 977) / 977, 1, 0.35

print "finished"
