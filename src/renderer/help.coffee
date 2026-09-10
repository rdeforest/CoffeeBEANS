# Quick reference, shown by :help in the editor. Data rather than prose so
# `:help colors` can pick one section out without reformatting anything.

SECTIONS = [
  name:  'running'
  title: 'Running code'
  lines: [
    ['Ctrl-Enter',        'run the selection, or the paragraph at the cursor']
    ['Ctrl-r',            'same, from visual mode (normal mode keeps redo)']
    ['Ctrl-Shift-Enter',  'restart the worker, then run the whole buffer']
    ['Ctrl-.',            'stop a running sketch']
    ['Ctrl-e',            'show or hide the editor']
    [':run',              'run the whole buffer into the live worker']
    [':restart',          'fresh worker, empty scope -- this is RUN']
    [':w',                'force a save (edits autosave anyway)']
    [':help <topic>',     'this, or one section of it']
  ]
,
  name:  'screen'
  title: 'Screen'
  lines: [
    ['screen w, h',       'set resolution (default 320, 200)']
    ['cls()',             'clear to black']
    ['cls color',         'clear to a color']
    ['color c',           'set the current drawing color']
    ['point x, y',        'plot in the current color']
    ['point x, y, c',     'plot in a specific color']
    ['pget x, y',         'read a pixel back']
    ['print args...',     'write a line to this console']
  ]
,
  name:  'buffers'
  title: 'Buffers'
  lines: [
    ['buffer.on',         'draw to the back buffer, show the front']
    ['buffer.off',        'draw straight to the screen (default)']
    ['buffer.swap',       'show what you drew; blocks until it is on screen']
    ['buffer.fps n',      'pace swaps to n frames per second (0 = display rate)']
    ['wait n',            'wait n presented frames']
  ]
,
  name:  'colors'
  title: 'Colors'
  lines: [
    ['COLORS.red',              'and 20 other CSS names, including COLORS.coffee']
    ['COLORS.byName "red"',     'the same, by string']
    ['COLORS.fromRGB r, g, b',  'channels from 0..1, optional alpha']
    ['COLORS.fromRGB256 r,g,b', 'channels from 0..255, optional alpha']
    ['COLORS.create()',         'builder: .setRed .setGreen .setBlue .setAlpha']
    ['COLORS.names()',          'every name we know']
    ['',                        'anywhere a color is wanted, a number, a name']
    ['',                        'string, or a builder all work.']
  ]
,
  name:  'math'
  title: 'Math'
  lines: [
    ['sin cos sqrt floor',  'all of Math, lowercased, without the prefix']
    ['pi e',                'Math.PI, Math.E']
    ['rnd()',               '0..1']
    ['rnd n',               '0..n']
  ]
]

globalThis.HELP =
  sections: SECTIONS
  match: (topic) ->
    return SECTIONS unless topic
    wanted = topic.toLowerCase()
    (section for section in SECTIONS when section.name.startsWith wanted)
