# Quick reference, shown by /help (or :help). Data rather than prose so
# `/help colors` can pick one section out, and `/help wheel` can pick lines
# out of every section, without reformatting anything.

SECTIONS = [
  name:  'running'
  title: 'Running code'
  lines: [
    ['Ctrl-Enter',        'eval the selection, or the paragraph at the cursor']
    ['Ctrl-r',            'same, from visual mode (normal mode keeps redo)']
    ['Ctrl-Shift-Enter',  'run -- fresh worker, then the whole buffer']
    ['Ctrl-.',            'stop a running sketch']
    ['Ctrl-e',            'show or hide the editor']
    ['/eval',             'eval the whole buffer into the live worker']
    ['/run',              'fresh worker, empty scope -- this is BASIC RUN']
    ['',                  'eval keeps everything the worker knows;']
    ['',                  'run throws it away and starts clean']
    ['',                  'run and /eval give the canvas the keyboard;']
    ['',                  'region eval leaves it in the editor']
    ['',                  'a syntax error takes the cursor to it; a runtime']
    ['',                  'one lists its stack -- click a frame to go there']
    ['> at the console',  'one line, evaluated in the same live worker']
    ['',                  'it answers between frames, so you can ask a']
    ['',                  'running sketch what it is doing -- and change it']
    ['Up / Down',         'earlier lines, at the prompt']
    ['/w',                'force a save (edits autosave anyway)']
    ['/e <name>',         'open a sketch, creating it if new; /e! discards edits']
    ['',                  'folders are part of the name: /e challenges/ocean']
    ['Cmd/Ctrl-O',        'open a sketch with the system file picker']
    ['/target <n>',       'flag the first source line past n; /target 0 clears']
    ['/help <word>',      'this, or one section, or an object like keys,']
    ['',                  'or else every line that mentions the word']
    ['/ or : commands',   'typed at the > prompt, or after : in vim;']
    ['',                  'a line starting with either is always a command,']
    ['',                  'so CoffeeScript opening with a regex goes in']
    ['',                  'parens: (/x/).test s']
  ]
,
  name:  'debug'
  title: 'Stopping to look'
  lines: [
    ['breakpoint',        'stop here -- BASIC STOP. The line about to run lights']
    ['',                  'up, and the names it can see appear beside the console']
    ['',                  'the > prompt asks the paused call, and can change it']
    ['',                  'a getter there reads (getter, not run) until clicked;']
    ['',                  'each click runs it once']
    ['Cmd/Ctrl-\\  F8',    'stop right now on whatever line is running;']
    ['',                  'pressed again, carry on']
    ['F10  /line',        'step to the next line that runs, wherever it is']
    ['/pause  /step',     'hold a sketch at a frame, then let one through;']
    ['',                  'from a stopped line, /step runs on to the next frame']
    ['/continue',         'let it go again, from either kind of pause']
    ['',                  'with DevTools open, breakpoint does nothing']
  ]
,
  name:  'screen'
  title: 'Screen'
  lines: [
    ['screen w, h',       'resolution; also resets every drawing mode --']
    ['',                  'buffering, fps cap, drawTo, colour, text cursor']
    ['cls()',             'clear to black']
    ['cls color',         'clear to a color']
    ['color c',           'set the current drawing color']
    ['point x, y',        'plot in the current color']
    ['point x, y, c',     'plot in a specific color']
    ['pget x, y',         'read a pixel back']
    ['print args...',     'write a line to this console']
  ]
,
  name:  'shapes'
  title: 'Shapes'
  lines: [
    ['line x1,y1,x2,y2',        'clipped, so huge coordinates are cheap']
    ['rect x1,y1,x2,y2',        'outline, corner to corner like line']
    ['rectFill x1,y1,x2,y2',    'filled']
    ['circle cx,cy,r',          'outline']
    ['circleFill cx,cy,r',      'filled']
    ['ellipse cx,cy,rx,ry',     'outline']
    ['ellipseFill cx,cy,rx,ry', 'filled']
    ['',                        'every one takes an optional colour last']
  ]
,
  name:  'text'
  title: 'Text'
  lines: [
    ['text "hi", n',        'draw at the cursor in the current colour']
    ['locate col, row',     'move the cursor, in 8x8 character cells']
    ['textAt x, y, "hi"',   'draw at pixel coordinates, cursor untouched']
    ['textScale 2',         'chunkier characters; cells scale with it']
    ['textBackground c',    'fill behind the glyphs; null for none']
    ['textWidth "hi"',      'how wide that would be, in pixels']
    ['',                    'text obeys drawTo, so it lands on surfaces too']
  ]
,
  name:  'timing'
  title: 'Timing'
  lines: [
    ['elapsed',   'seconds since this sketch started']
    ['frames',    'frames presented since the app did']
    ['',          'the header shows fps and what your frame costs']
  ]
,
  name:  'loading'
  title: 'Loading images'
  lines: [
    ['load "https://..."',   'returns a surface; blocks until it arrives']
    ['load "assets/cat.png"','a file in your data folder']
    ['',                     'downloads are cached in assets/, so a sketch']
    ['',                     'still runs on bad wifi or a dead URL']
  ]
,
  name:  'fill'
  title: 'Filling'
  lines: [
    ['fill x, y',              'flood what matches the pixel you started on']
    ['fill x, y, c',           'and paint it c instead of the current colour']
    ['fill x, y, c, border b', 'cross anything that is not b -- BASIC PAINT']
    ['fill x, y, c, matching m', 'only pixels that are m']
    ['fill x, y, c, where fn',  'fn p decides; no colour needed before a rule']
    ['',                       'p.x p.y p.color p.seed']
    ['',                       'p.red p.green p.blue p.alpha       0..1']
    ['',                       'p.hue p.saturation p.value         hue in degrees']
    ['',                       'p.up p.down p.left p.right         null past the edge']
  ]
,
  name:  'paints'
  title: 'Paints'
  lines: [
    ['',                       'anywhere a colour goes, a paint goes too --']
    ['',                       'cls, point, line, rect, circle, text, fill']
    ['maker (p) -> ...',       'p is the probe the fill rules take']
    ['tile surface',           'repeat a surface across the target']
    ['gradient a, b, opts',    'angle:, length:, x:, y:']
    ['radial a, b, opts',      'x:, y:, radius:']
    ['color maker (p) -> ...', 'a paint can be the current colour']
    ['COLORS.toHSV c',         'hue, saturation, value back out of a colour']
    ['.setHue .setSaturation .setValue', 'on COLORS.create(), beside setRed']
  ]
,
  name:  'surfaces'
  title: 'Surfaces'
  lines: [
    ['surface w, h',        'a new off-screen surface, cleared transparent']
    ['get x1,y1,x2,y2',     'capture a region of the current target']
    ['put s, x, y',         'blit it back, skipping transparent pixels']
    ["put s, x, y, 'xor'",  "also 'copy', 'or', 'and' -- PUT's old actions"]
    ['stamp s, x, y, opts', 'scale:, angle:, anchorX:, anchorY:, mode:']
    ['drawTo s, -> ...',    'send every drawing command to s instead']
    ['drawTo s',            'same, but as a mode until you drawTo display']
    ['overlaps a,ax,ay,b,bx,by', 'pixel-accurate, not just bounding boxes']
  ]
,
  name:  'buffers'
  title: 'Buffers'
  lines: [
    ['buffer.on',         'draw to the back buffer, show the front']
    ['buffer.off',        'draw straight to the screen (default)']
    ['buffer.swap',       'show what you drew; blocks until it is on screen']
    ['buffer.fps n',      'pace swaps to n per second; 0 is the display rate']
    ['display.onScreen',  'is drawing landing on the buffer you can see']
    ['wait n',            'sleep n frames; never flips, only buffer.swap does']
  ]
,
  name:  'input'
  title: 'Input'
  lines: [
    ['',                  'click the screen to send keys to the sketch']
    ["keys.down 'left'",  'held right now']
    ["keys.hit 'space'",  'went down since the last frame, even a fast tap']
    ["keys.up 'space'",   'went up since the last frame: the other edge']
    ['keys.down()',       'with no name, a list -- hold a key and ask what it is']
    ['keys.any',          'is anything held']
    ['keys.poll',         'claim hits by hand; buffer.swap already does']
    ['mouse.x  mouse.y',  'in screen pixels, not window pixels']
    ['mouse.left',        'and .right .middle .down']
    ['mouse.wheel',       'delta since you last read it -- reading consumes']
  ]
,
  name:  'sound'
  title: 'Sound'
  lines: [
    ['sound 440, 0.5',    'Hz and seconds; queues the note and returns at once']
    ["sound 'C4', 0.5",   "or a note name: 'F#3', 'Bb2' -- A4 is 440"]
    ["  voice: 'bass'",   'any number or name, made on first use; each plays']
    ['',                  'its notes in turn: one voice a tune, several chords']
    ["  wave: 'square'",  'sine (the default), square, triangle, saw, noise,']
    ['',                  'an array of -1..1 for one period, or (phase) -> ...']
    ['  volume: 0.3',     '0..1, or (t, u) -> ... for a shape over the note']
    ['',                  't is seconds in, u runs 0 to 1; frequency takes one too']
    ["sound.hz 'A4'",     'a note name as a frequency, for doing arithmetic on']
    ['sound 0, 0.25',     'a rest']
    ["held = sound 'C4'", 'no length: plays until stopped. Every sound hands']
    ['',                  'back its note, to change or stop while it plays:']
    ["held.frequency = 'D4'", 'and held.volume; takes effect within a few ms']
    ['held.stop 0.2',     'fade out over 0.2s; held.stop() is the 5ms minimum']
    ["sound.stop 'bass'", 'a voice and its queue; sound.stop() is everything']
    ['',                  'Stop and Run silence everything; a pause holds it']
  ]
,
  name:  'colors'
  title: 'Colors'
  lines: [
    ['COLORS.red',              'and 20 other CSS names, including COLORS.coffee']
    ['COLORS.byName "red"',     'the same, by string']
    ['COLORS.fromRGB r, g, b',  'channels from 0..1, optional alpha']
    ['COLORS.fromRGB256 r,g,b', 'channels from 0..255, optional alpha']
    ['COLORS.fromHSV h, s, v',  'hue in degrees, the rest 0..1; wraps']
    ['COLORS.toHSV c',          'and back again']
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
    ['randomize 42',        'the same rnd numbers every run from here on']
    ['randomize()',         'fresh numbers again, as every run starts with']
    ['rnd.currentSeed',     'randomize this later to carry on from here']
  ]
]

# The longer story for the objects and commands a sketch pokes at: every
# member, what the section line had no room for, and an example to paste.
# Asked for by the exact name.
OBJECTS = [
  name:  'keys'
  title: 'keys -- the keyboard, polled'
  lines: [
    ["keys.down 'left'",  'true while that key is held']
    ["keys.hit 'space'",  'went down since the last frame; sticky until then,']
    ['',                  'so a tap that starts and ends between frames counts']
    ["keys.up 'space'",   'went up since the last frame; sticky the same way.']
    ['',                  'Losing focus counts as letting go']
    ['keys.down()',       'no name: a list of what is held. keys.hit() and']
    ['',                  'keys.up() list theirs. Hold a key and ask its name']
    ['keys.any',          'true while any key is held -- no (), like poll']
    ['keys.poll',         'claim hits by hand; buffer.swap and wait already do,']
    ['',                  'so only a loop that does neither needs it']
    ['names',             'a..z  0..9  f1..f12  left right up down  space']
    ['',                  'enter return  esc escape  tab  backspace  delete del']
    ['',                  'home end pageup pagedown insert']
    ['',                  'shift ctrl control alt -- either side of the keyboard']
    ['',                  'minus equals leftbracket rightbracket backslash']
    ['',                  'semicolon quote comma period slash backquote']
    ['',                  "or the character on the key: ';' \"'\" ',' '.' '/' '['"]
    ['',                  "or a KeyboardEvent code in any case: 'ShiftLeft'"]
    ['',                  'a name nobody knows is an error, not a quiet false']
    ['',                  'click the screen first, or the editor keeps the keys']
  ]
  example: [
    'buffer.on'
    'x = 160'
    'loop'
    "  x -= 2 if keys.down 'left'"
    "  x += 2 if keys.down 'right'"
    "  print 'fire!' if keys.hit 'space'"
    '  cls()'
    '  circleFill x, 100, 4'
    '  buffer.swap'
  ]
,
  name:  'mouse'
  title: 'mouse -- the pointer, polled'
  lines: [
    ['mouse.x  mouse.y',  'in screen pixels, not window pixels']
    ['mouse.left',        'true while that button is held; .right .middle too']
    ['mouse.down',        'true while any button is held']
    ['mouse.wheel',       'movement since you last read it -- reading consumes,']
    ['',                  'so read it once a frame into a variable']
  ]
  example: [
    'buffer.on'
    'loop'
    '  cls()'
    "  circleFill mouse.x, mouse.y, 4, (if mouse.left then 'red' else 'white')"
    '  buffer.swap'
  ]
,
  name:  'buffer'
  title: 'buffer -- what you see while you draw'
  lines: [
    ['buffer.off',        'the default: drawing lands on screen as it happens']
    ['buffer.on',         'draw into a back buffer while the front one shows']
    ['buffer.swap',       'show the back buffer, and draw into the old front;']
    ['',                  'blocks until the frame is on screen']
    ['buffer.fps n',      'pace swaps to n per second; 0 is the display rate']
    ['wait n',            'sleep n frames; never flips, in either mode']
    ['display.onScreen',  'is drawing landing on the buffer you can see']
    ['',                  'screen turns buffering off, so put buffer.on after it']
  ]
  example: [
    'buffer.on'
    'x = 0'
    'loop'
    '  cls()'
    '  circleFill x, 100, 8'
    '  x = (x + 2) % 320'
    '  buffer.swap'
  ]
,
  name:  'stamp'
  title: 'stamp -- put, but turned and scaled'
  lines: [
    ['stamp s, x, y',     'like put, except x, y is where the anchor lands']
    ['  angle: a',        'radians; positive turns clockwise, since y runs down']
    ['  scale: 2',        'or scaleX: and scaleY: apart']
    ['  anchorX: ax',     'with anchorY:, the point in s that lands on x, y and']
    ['',                  'that it turns around. 0, 0 unless you say, so pass']
    ['',                  'the middle to spin in place']
    ["  mode: 'xor'",     'the same modes as put']
    ['',                  'nearest neighbour on purpose: the crunch is the look']
  ]
  example: [
    'buffer.on'
    'ship = surface 9, 9'
    'drawTo ship, -> line 0, 8, 4, 0; line 4, 0, 8, 8'
    'heading = 0'
    'loop'
    '  cls()'
    '  stamp ship, 160, 100, angle: heading, anchorX: 4.5, anchorY: 4.5'
    '  heading += 0.05'
    '  buffer.swap'
  ]
,
  name:  'overlaps'
  title: 'overlaps -- do two surfaces touch'
  lines: [
    ['overlaps a,ax,ay,b,bx,by', 'true if an opaque pixel of a lands on an']
    ['',                  'opaque pixel of b. ax, ay and bx, by are top-left']
    ['',                  'corners, the same as put']
    ['',                  'transparent pixels never touch anything, so it is']
    ['',                  'the shape that counts, not the box around it']
    ['',                  'it takes the surfaces as they are -- no angle or']
    ['',                  'scale. For a turned sprite, stamp it into a scratch']
    ['',                  'surface big enough for any angle, and test that']
  ]
  example: [
    'rock = surface 16, 16'
    "drawTo rock, -> circleFill 8, 8, 7, 'gray'"
    'ship = surface 9, 9'
    'drawTo ship, -> line 0, 8, 4, 0; line 4, 0, 8, 8'
    'print overlaps ship, 100, 100, rock, 104, 96'
    '# turned: 13 is past the diagonal of 9, and the middles'
    '# line up, so the box sits 2 up and left of the ship'
    'turned = surface 13, 13'
    'drawTo turned, ->'
    '  cls 0                # clear back to transparent'
    '  stamp ship, 6.5, 6.5, angle: pi / 4, anchorX: 4.5, anchorY: 4.5'
    'print overlaps turned, 98, 98, rock, 104, 96'
  ]
]

# A line whose syntax is blank continues the entry above it, so a search
# keeps the whole entry rather than half a sentence.
entriesOf = (lines) ->
  entries = []
  for line in lines
    if line[0] or not entries.length
      entries.push [line]
    else
      entries[entries.length - 1].push line
  entries

search = (wanted) ->
  found = []
  for section in SECTIONS
    hits = (entry for entry in entriesOf(section.lines) when entry.some (line) -> line.join(' ').toLowerCase().includes wanted)
    found.push title: section.title, lines: [].concat hits... if hits.length
  found

globalThis.HELP =
  sections: SECTIONS
  objects:  OBJECTS
  # An object by its exact name, then sections by prefix (so `/help col` is
  # still Colors), then a search of every line.
  match: (topic) ->
    return SECTIONS unless topic
    wanted = topic.toLowerCase()
    object = (entry for entry in OBJECTS when entry.name is wanted)
    return object if object.length
    sections = (section for section in SECTIONS when section.name.startsWith wanted)
    return sections if sections.length
    search wanted
