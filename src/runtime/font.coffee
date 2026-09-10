# An 8x8 bitmap font, one row per byte, least significant bit leftmost.
# Public domain, from Daniel Hepper's font8x8, itself derived from the
# public domain VGA fonts by Marcel Sondaar. Kept as readable hex rather
# than packed binary so a glyph can be edited by hand -- which, for a
# drawing toy, someone will eventually want to do.

WIDTH  = 8
HEIGHT = 8

GLYPHS =
  ' ':   '0000000000000000'
  '!':   '183C3C1818001800'
  '"':   '3636000000000000'
  '#':   '36367F367F363600'
  '$':   '0C3E031E301F0C00'
  '%':   '006333180C666300'
  '&':   '1C361C6E3B336E00'
  "'":   '0606030000000000'
  '(':   '180C0606060C1800'
  ')':   '060C1818180C0600'
  '*':   '00663CFF3C660000'
  '+':   '000C0C3F0C0C0000'
  ',':   '00000000000C0C06'
  '-':   '0000003F00000000'
  '.':   '00000000000C0C00'
  '/':   '6030180C06030100'
  '0':   '3E63737B6F673E00'
  '1':   '0C0E0C0C0C0C3F00'
  '2':   '1E33301C06333F00'
  '3':   '1E33301C30331E00'
  '4':   '383C36337F307800'
  '5':   '3F031F3030331E00'
  '6':   '1C06031F33331E00'
  '7':   '3F3330180C0C0C00'
  '8':   '1E33331E33331E00'
  '9':   '1E33333E30180E00'
  ':':   '000C0C00000C0C00'
  ';':   '000C0C00000C0C06'
  '<':   '180C0603060C1800'
  '=':   '00003F00003F0000'
  '>':   '060C1830180C0600'
  '?':   '1E3330180C000C00'
  '@':   '3E637B7B7B031E00'
  'A':   '0C1E33333F333300'
  'B':   '3F66663E66663F00'
  'C':   '3C66030303663C00'
  'D':   '1F36666666361F00'
  'E':   '7F46161E16467F00'
  'F':   '7F46161E16060F00'
  'G':   '3C66030373667C00'
  'H':   '3333333F33333300'
  'I':   '1E0C0C0C0C0C1E00'
  'J':   '7830303033331E00'
  'K':   '6766361E36666700'
  'L':   '0F06060646667F00'
  'M':   '63777F7F6B636300'
  'N':   '63676F7B73636300'
  'O':   '1C36636363361C00'
  'P':   '3F66663E06060F00'
  'Q':   '1E3333333B1E3800'
  'R':   '3F66663E36666700'
  'S':   '1E33070E38331E00'
  'T':   '3F2D0C0C0C0C1E00'
  'U':   '3333333333333F00'
  'V':   '33333333331E0C00'
  'W':   '6363636B7F776300'
  'X':   '6363361C1C366300'
  'Y':   '3333331E0C0C1E00'
  'Z':   '7F6331184C667F00'
  '[':   '1E06060606061E00'
  '\\':  '03060C1830604000'
  ']':   '1E18181818181E00'
  '^':   '081C366300000000'
  '_':   '00000000000000FF'
  '`':   '0C0C180000000000'
  'a':   '00001E303E336E00'
  'b':   '0706063E66663B00'
  'c':   '00001E3303331E00'
  'd':   '3830303E33336E00'
  'e':   '00001E333F031E00'
  'f':   '1C36060F06060F00'
  'g':   '00006E33333E301F'
  'h':   '0706366E66666700'
  'i':   '0C000E0C0C0C1E00'
  'j':   '300030303033331E'
  'k':   '070666361E366700'
  'l':   '0E0C0C0C0C0C1E00'
  'm':   '0000337F7F6B6300'
  'n':   '00001F3333333300'
  'o':   '00001E3333331E00'
  'p':   '00003B66663E060F'
  'q':   '00006E33333E3078'
  'r':   '00003B6E66060F00'
  's':   '00003E031E301F00'
  't':   '080C3E0C0C2C1800'
  'u':   '0000333333336E00'
  'v':   '00003333331E0C00'
  'w':   '0000636B7F7F3600'
  'x':   '000063361C366300'
  'y':   '00003333333E301F'
  'z':   '00003F190C263F00'
  '{':   '380C0C070C0C3800'
  '|':   '1818180018181800'
  '}':   '070C0C380C0C0700'
  '~':   '6E3B000000000000'

MISSING = 'FF818181818181FF'      # a hollow box, for anything we lack

unpack = (hex) -> (parseInt hex.substr(index * 2, 2), 16 for index in [0...HEIGHT])

rows = {}
rows[character] = unpack hex for own character, hex of GLYPHS
absent = unpack MISSING

globalThis.FONT =
  width:  WIDTH
  height: HEIGHT
  has:    (character) -> rows[character]?
  rows:   (character) -> rows[character] ? absent
  glyphs: -> Object.keys rows
