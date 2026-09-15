# A paint is a function of position, which is all a pattern or a gradient
# really is. Every fill primitive takes one, so none of this is special to
# any particular command -- and a paint takes the same probe a fill rule
# takes, so there is only one idea here, not two.

screen 320, 200

sky = gradient COLORS.fromHSV(205, 0.55, 0.95), COLORS.fromHSV(235, 0.35, 0.30),
      angle: pi / 2, length: 200
cls sky

circleFill 255, 40, 26,
  radial COLORS.white, COLORS.fromHSV(38, 1, 0.95), x: 255, y: 40, radius: 26

# A tile is just a small surface, repeated. Eight by eight because that is
# what every paint program of the era used, not because anything requires it.
ground = surface 8, 8
drawTo ground, ->
  cls COLORS.fromHSV 105, 0.45, 0.40
  rectFill 0, 0, 3, 3, COLORS.fromHSV 105, 0.55, 0.30
  rectFill 4, 4, 7, 7, COLORS.fromHSV 105, 0.55, 0.30

rectFill 0, 150, 319, 199, tile ground

# A maker can read the pixel it is replacing, so this darkens whatever is
# underneath rather than painting over it.
rectFill 0, 120, 319, 149, maker (p) ->
  COLORS.fromRGB p.red * 0.55, p.green * 0.55, p.blue * 0.6

# Text is drawn through the same plot as everything else, so it takes a
# paint too.
textScale 2
color gradient COLORS.fromHSV(50, 1, 1), COLORS.fromHSV(340, 0.9, 1), length: 200
textAt 20, 20, 'COFFEEBEANS'

textScale 1
color COLORS.white
textAt 20, 44, 'every fill takes a paint'
