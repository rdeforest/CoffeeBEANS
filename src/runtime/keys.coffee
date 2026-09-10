# One bit per key, in a table both sides share. Using our own index rather
# than the deprecated keyCode means the mapping is explicit and stable.

letters = ("Key#{letter}" for letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')
digits  = ("Digit#{digit}" for digit in '0123456789')
funcs   = ("F#{n}" for n in [1..12])

CODES = [
  letters...
  digits...
  funcs...
  'ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'
  'Space', 'Enter', 'Escape', 'Tab', 'Backspace', 'Delete'
  'ShiftLeft', 'ShiftRight', 'ControlLeft', 'ControlRight', 'AltLeft', 'AltRight'
  'Home', 'End', 'PageUp', 'PageDown', 'Insert'
  'Minus', 'Equal', 'BracketLeft', 'BracketRight', 'Backslash'
  'Semicolon', 'Quote', 'Comma', 'Period', 'Slash', 'Backquote'
]

INDEX = {}
INDEX[code] = position for code, position in CODES

# What a sketch is allowed to type. A modifier name matches either side.
ALIASES =
  left:    ['ArrowLeft']
  right:   ['ArrowRight']
  up:      ['ArrowUp']
  down:    ['ArrowDown']
  space:   ['Space']
  enter:   ['Enter']
  return:  ['Enter']
  esc:     ['Escape']
  escape:  ['Escape']
  tab:     ['Tab']
  backspace: ['Backspace']
  del:     ['Delete']
  shift:   ['ShiftLeft', 'ShiftRight']
  ctrl:    ['ControlLeft', 'ControlRight']
  control: ['ControlLeft', 'ControlRight']
  alt:     ['AltLeft', 'AltRight']
  home:    ['Home']
  end:     ['End']
  pageup:  ['PageUp']
  pagedown:['PageDown']

ALIASES[letter.toLowerCase()] = ["Key#{letter}"] for letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
ALIASES[digit]                = ["Digit#{digit}"] for digit in '0123456789'
ALIASES["f#{n}"]              = ["F#{n}"] for n in [1..12]

globalThis.KEYTABLE =
  codes:   CODES
  index:   INDEX
  # A name may be one of our aliases or a raw KeyboardEvent.code.
  bitsFor: (name) ->
    codes = ALIASES[String(name).toLowerCase()] ? [name]
    (INDEX[code] for code in codes when INDEX[code]?)
