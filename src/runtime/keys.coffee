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

# Every key's one name, the one the lists use. Lowercase, and a word rather
# than a character, because a list printed to the console should read
# plainly and each name should go straight back into keys.down as a string.
NAMES =
  ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down'
  Space: 'space', Enter: 'enter', Escape: 'escape', Tab: 'tab'
  Backspace: 'backspace', Delete: 'delete'
  ShiftLeft: 'shift', ShiftRight: 'shift', ControlLeft: 'ctrl', ControlRight: 'ctrl'
  AltLeft: 'alt', AltRight: 'alt'
  Home: 'home', End: 'end', PageUp: 'pageup', PageDown: 'pagedown', Insert: 'insert'
  Minus: 'minus', Equal: 'equals', BracketLeft: 'leftbracket', BracketRight: 'rightbracket'
  Backslash: 'backslash', Semicolon: 'semicolon', Quote: 'quote', Comma: 'comma'
  Period: 'period', Slash: 'slash', Backquote: 'backquote'
NAMES["Key#{letter}"]   = letter.toLowerCase() for letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
NAMES["Digit#{digit}"]  = digit for digit in '0123456789'
NAMES["F#{n}"]          = "f#{n}" for n in [1..12]

# What a sketch may call a key: its name, and whatever else someone is likely
# to try first -- the character on the keycap, a common other word, or the
# browser's own code in any case. Looked up lowercased.
ALIASES = {}
alias = (name, codes...) ->
  known = ALIASES[name] ?= []
  known.push code for code in codes when code not in known
alias name, code for code, name of NAMES
alias code.toLowerCase(), code for code in CODES
alias 'esc', 'Escape'
alias 'return', 'Enter'
alias 'del', 'Delete'
alias 'control', 'ControlLeft', 'ControlRight'
alias 'equal', 'Equal'
alias 'dot', 'Period'
alias 'apostrophe', 'Quote'
alias 'backtick', 'Backquote'
alias 'grave', 'Backquote'
alias 'dash', 'Minus'
alias 'hyphen', 'Minus'
for character, code of {'-': 'Minus', '=': 'Equal', '[': 'BracketLeft', ']': 'BracketRight', '\\': 'Backslash', ';': 'Semicolon', "'": 'Quote', ',': 'Comma', '.': 'Period', '/': 'Slash', '`': 'Backquote', ' ': 'Space'}
  alias character, code

globalThis.KEYTABLE =
  codes:   CODES
  index:   INDEX
  # Unknown names throw. A misspelt key that silently reads false looks
  # exactly like a key nobody is pressing, which is a long way from the typo.
  bitsFor: (name) ->
    codes = ALIASES[String(name).toLowerCase()]
    throw new Error "keys: no key called #{JSON.stringify name} -- keys.down() lists what is held right now" unless codes
    (INDEX[code] for code in codes when INDEX[code]?)
  # The names for a set of bits, each once: both shifts held is one 'shift'.
  namesFor: (isSet) ->
    names = []
    for code, bit in CODES when isSet(bit) and NAMES[code] not in names
      names.push NAMES[code]
    names
