screen 320, 200
keyboard =
  a             : 'A3'
  w             : 'A#3'
  s             : 'B3'
  d             : 'C4'
  r             : 'C#4'
  f             : 'D4'
  t             : 'D#4'
  g             : 'E4'
  h             : 'F4'
  u             : 'F#4'
  j             : 'G4'
  i             : 'G#4'
  k             : 'A4'
  o             : 'A#4'
  l             : 'B4'
  "semicolon"   : 'C5'
  "leftbracket" : 'C#5'
  "quote"       : 'D5'

buffer.on
playing = {}
unbound = []

loop
  for key, note of keyboard
    playing[key] ?= sound note, voice: key if keys.hit key
    if playing[key] and keys.up key
      playing[key].stop 0.1
      delete playing[key]

  for key in keys.down() when not playing[key]
    if key not in unbound
      unbound.push key
      print "unbound key: #{key}"

  buffer.swap
