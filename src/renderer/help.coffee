# Quick reference, shown by :help in the editor. Data rather than prose so
# `:help colors` can pick one section out without reformatting anything.

SECTIONS = [
  name:  'running'
  title: 'Running code'
  lines: [
    ['Ctrl-Enter',        'eval the selection, or the paragraph at the cursor']
    ['Ctrl-r',            'same, from visual mode (normal mode keeps redo)']
    ['Ctrl-Shift-Enter',  'run -- fresh worker, then the whole buffer']
    ['Ctrl-.',            'stop a running sketch']
    ['Ctrl-e',            'show or hide the editor']
    [':eval',             'eval the whole buffer into the live worker']
    [':run',              'fresh worker, empty scope -- this is BASIC RUN']
    ['',                  'eval keeps everything the worker knows;']
    ['',                  'run throws it away and starts clean']
    ['> at the console',  'one line, evaluated in the same live worker']
    ['',                  'it answers between frames, so you can ask a']
    ['',                  'running sketch what it is doing -- and change it']
    ['Up / Down',         'earlier lines, at the prompt']
    [':w',                'force a save (edits autosave anyway)']
    [':e <name>',         'open a sketch, creating it if new; :e! discards edits']
    [':target <n>',       'flag the first source line past n; :target 0 clears']
    [':help <topic>',     'this, or one section of it']
  ]
,
  name:  'debug'
  title: 'Stopping to look'
  lines: [
    ['breakpoint',        'stop here, if something is watching -- BASIC STOP']
    ['',                  'and nothing at all if nothing is, so a sketch with']
    ['',                  'one left in still runs at full speed']
    ['',                  'DevTools sees it today: View -> Toggle Developer']
    ['',                  'Tools, then Sources, then Run']
    [':pause  :step',     'hold a sketch at a frame, then let one through']
    [':continue',         'let it go again; the > prompt works while paused']
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
    ['wait n',            'wait n presented frames']
  ]
,
  name:  'input'
  title: 'Input'
  lines: [
    ['',                  'click the screen to send keys to the sketch']
    ["keys.down 'left'",  'held right now']
    ["keys.hit 'space'",  'went down since the last frame, even a fast tap']
    ['keys.any',          'is anything held']
    ['keys.poll',         'claim hits by hand; buffer.swap already does']
    ['mouse.x  mouse.y',  'in screen pixels, not window pixels']
    ['mouse.left',        'and .right .middle .down']
    ['mouse.wheel',       'delta since you last read it -- reading consumes']
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
  ]
]

globalThis.HELP =
  sections: SECTIONS
  match: (topic) ->
    return SECTIONS unless topic
    wanted = topic.toLowerCase()
    (section for section in SECTIONS when section.name.startsWith wanted)
