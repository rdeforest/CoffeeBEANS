# The console prompt: one line at a time into the same live worker the sketch
# runs in, answered at a yield point so a running sketch can be questioned
# without being stopped.

{BrowserWindow} = require 'electron'

module.exports = (t) ->
  {js, wait, check, setDoc, evalAll, consoleText, clearConsole,
   click, status, settle, settled, ask} = t

  # 1. a line comes back with its value
  await clearConsole()
  answer = await ask '6 * 7'
  check 'a line at the prompt answers with its value', answer.includes('42'),
    JSON.stringify answer.trim()

  # 2. it is the same image the sketch runs in, in both directions
  await setDoc "fromSketch = 11\n"
  await wait 500
  await clearConsole()
  await evalAll()
  await settled()
  answer = await ask 'fromSketch + 1'
  sees   = answer.includes '12'

  await clearConsole()
  await ask "fromPrompt = 'hello'"
  await setDoc "print 'sketchSees=' + fromPrompt\n"
  await wait 500
  await evalAll()
  answer = await settled()
  check 'the prompt and the sketch share one image',
    sees and answer.includes('sketchSees=hello'), "sees=#{sees} #{JSON.stringify answer.trim()}"

  # 3. a question answered between frames of a sketch that never stops, and an
  # answer that reaches back into it. This is the whole point of going through
  # shared memory rather than postMessage.
  await setDoc "screen 320, 200\nbuffer.on\nticks = 0\nstep = 1\nloop\n  ticks += step\n  cls()\n  buffer.swap\n"
  await wait 500
  await clearConsole()
  await evalAll()
  await wait 400
  went  = await status()

  count = (text) -> Number /(-?\d+)/.exec(text)?[1] ? -1

  # Asked until it has actually ticked once, so the first reading is not a
  # race with the sketch's first frame.
  deadline = Date.now() + 5000
  loop
    first = await ask 'ticks'
    break if count(first) > 0 or Date.now() > deadline

  await wait 300
  second = await ask 'ticks'
  await ask 'step = 100'
  await wait 300
  third  = await ask 'ticks'
  still  = await status()
  await click 'stop'
  await settle()

  a = count first
  b = count second
  c = count third
  check 'the prompt answers a running sketch between frames',
    went is 'running' and still is 'running' and 0 < a < b,
    "first=#{a} #{JSON.stringify first} second=#{b} #{JSON.stringify second} status=#{still}"
  check 'and what it changes reaches the running sketch',
    c - b > (b - a) * 5, "before=#{b} after=#{c} (step went 1 -> 100)"

  # 4. a bad line is reported and the prompt still works after it
  await clearConsole()
  broken = await ask 'this is not coffee ('
  after  = await ask '1 + 1'
  check 'a bad line is reported without wedging the prompt',
    broken.length > 0 and not broken.includes('2') and after.includes('2'),
    "broken=#{JSON.stringify broken.trim()} after=#{JSON.stringify after.trim()}"

  # 5. the keystroke path, and the history behind it
  await clearConsole()
  typed = (line) -> js """
    const p = document.getElementById('promptLine')
    p.value = #{JSON.stringify line}
    p.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))
    return true
  """
  arrow = (key) -> js """
    document.getElementById('promptLine')
      .dispatchEvent(new KeyboardEvent('keydown', { key: '#{key}', bubbles: true }))
    return document.getElementById('promptLine').value
  """
  await typed '3 + 4'
  await wait 400
  text    = await consoleText()
  recalled = await arrow 'ArrowUp'
  cleared  = await arrow 'ArrowDown'
  check 'Enter runs the line and Up recalls it',
    text.includes('7') and recalled is '3 + 4' and cleared is '',
    "console=#{JSON.stringify text.trim()} up=#{JSON.stringify recalled} down=#{JSON.stringify cleared}"

  # --- readline's keys -----------------------------------------------------------

  # Real key events, through Chromium's own input path rather than
  # dispatchEvent, so a key the prompt fails to claim still does whatever the
  # browser would do with it -- select all, for one. They are queued, not
  # delivered by the time sendInputEvent returns, so each press waits for its
  # keyup to arrive.
  #
  # Menu accelerators do not see these: Ctrl-R sent this way reloaded nothing
  # even from the canvas (Claude, 2026-10-05). So whether the prompt's Ctrl-R
  # beats the View menu's reload is not something this part can show. It was
  # measured with real X keys instead (xdotool, by Claude, 2026-10-05, Linux
  # X11 only): with the prompt's preventDefault a real Ctrl-R searches and
  # does not reload; without it, the window reloads. Windows and macOS are
  # unmeasured.
  win  = BrowserWindow.getAllWindows()[0]
  MODS = C: 'control', M: 'alt', S: 'shift'

  until_ = (probe, limit = 5000) ->
    deadline = Date.now() + limit
    loop
      value = await probe()
      return value if value or Date.now() > deadline
      await wait 20

  keyups = -> js """
    if (!window.__keyupsCounted) {
      window.__keyupsCounted = true
      window.__keyups = 0
      window.addEventListener('keyup', () => window.__keyups++, true)
    }
    return window.__keyups
  """

  send = (keyCode, modifiers, char) ->
    before = await keyups()
    win.webContents.sendInputEvent {type: 'keyDown', keyCode, modifiers}
    win.webContents.sendInputEvent {type: 'char',    keyCode, modifiers} if char
    win.webContents.sendInputEvent {type: 'keyUp',   keyCode, modifiers}
    await until_ -> (await keyups()) > before

  # 'C-S-Backspace' is Ctrl+Shift+Backspace; the last part is the key.
  press = (chords...) ->
    for chord in chords
      parts = chord.split /-(?=.)/
      await send parts.pop(), (MODS[mod] for mod in parts), no
    undefined

  typeText = (text) -> await send character, [], yes for character in text

  promptAt = (value, from, to = from) -> js """
    const p = document.getElementById('promptLine')
    p.focus()
    p.value = #{JSON.stringify value}
    p.setSelectionRange(#{from}, #{to})
    return true
  """
  promptNow = -> js """
    const p = document.getElementById('promptLine')
    return {value: p.value, from: p.selectionStart, to: p.selectionEnd,
            mark: document.getElementById('promptMark').textContent,
            focused: document.activeElement === p}
  """

  # 6. each binding against readline's own behaviour (lib/internal/readline/
  # interface.js in Node 24). Option is not Meta on a Mac, so the Alt rows
  # are skipped there. Ctrl-Shift-Backspace has no row: Chromium on Linux
  # already deletes to the start for it, so a row would pass without the
  # binding (found by Claude, 2026-10-05).
  EDITS = [
    # what it does                          line            caret  keys                         after          caret
    ['Ctrl-A goes to the start of the line',  'hello world',   5,   ['C-a'],                     'hello world',   0]
    ['Ctrl-E goes to the end of the line',    'hello world',   5,   ['C-e'],                     'hello world',  11]
    ['Ctrl-B goes back a character',          'hello world',   5,   ['C-b'],                     'hello world',   4]
    ['Ctrl-B steps over a whole emoji',       'a\u{1F600}b',   3,   ['C-b'],                     'a\u{1F600}b',   1]
    ['Ctrl-F goes forward a character',       'hello world',   5,   ['C-f'],                     'hello world',   6]
    ['Ctrl-H deletes left',                   'hello world',   5,   ['C-h'],                     'hell world',    4]
    ['Ctrl-D deletes right',                  'hello world',   5,   ['C-d'],                     'helloworld',    5]
    ['Ctrl-U deletes to the start',           'hello world',   5,   ['C-u'],                     ' world',        0]
    ['Ctrl-K deletes to the end',             'hello world',   5,   ['C-k'],                     'hello',         5]
    ['Ctrl-Shift-Delete deletes to the end',  'hello world',   5,   ['C-S-Delete'],              'hello',         5]
    ['Ctrl-W deletes the word before',        'foo bar baz',  11,   ['C-w'],                     'foo bar ',      8]
    ['Alt-B goes back a word',                'foo bar baz',  11,   ['M-b'],                     'foo bar baz',   8]
    ['Alt-F goes forward a word',             'foo bar baz',   0,   ['M-f'],                     'foo bar baz',   4]
    ['Alt-D deletes the word after',          'foo bar baz',   4,   ['M-d'],                     'foo baz',       4]
    ['Alt-Delete deletes the word after',     'foo bar baz',   4,   ['M-Delete'],                'foo baz',       4]
    ['Alt-Backspace deletes the word before', 'foo bar baz',   7,   ['M-Backspace'],             'foo  baz',      4]
    ['Ctrl-Y yanks back what Ctrl-K cut',     'hello world',   5,   ['C-k', 'C-a', 'C-y'],       ' worldhello',   6]
    ['Alt-Y swaps the yank for the cut before it', 'one two',  3,   ['C-k', 'C-u', 'C-y', 'M-y'], ' two',         4]
  ]
  for [what, line, at, keys, after, landed] in EDITS
    continue if process.platform is 'darwin' and keys.some (key) -> key.startsWith 'M-'
    await promptAt line, at
    await press keys...
    got = await promptNow()
    check "#{what}, at the prompt", got.value is after and got.from is landed and got.to is landed,
      JSON.stringify got

  # 7. edits keep the input's own undo, which assigning the value would wipe
  await promptAt 'hello world', 5
  await press 'C-u'
  cut = (await promptNow()).value
  await press 'C-z'
  back = (await promptNow()).value
  check 'Ctrl-Z undoes a Ctrl-U', cut is ' world' and back is 'hello world',
    "after Ctrl-U #{JSON.stringify cut}, after Ctrl-Z #{JSON.stringify back}"

  # 7b. a click moves the caret out from under a yank, so Alt-Y after one has
  # nothing to swap. The kill ring outlives promptAt, which only sets the value.
  clicks = -> js """
    if (!window.__mouseupsCounted) {
      window.__mouseupsCounted = true
      window.__mouseups = 0
      window.addEventListener('mouseup', () => window.__mouseups++, true)
    }
    return window.__mouseups
  """
  clickAt = (x, y) ->
    before = await clicks()
    win.webContents.sendInputEvent {type: 'mouseDown', x, y, button: 'left', clickCount: 1}
    win.webContents.sendInputEvent {type: 'mouseUp',   x, y, button: 'left', clickCount: 1}
    await until_ -> (await clicks()) > before

  await promptAt 'one two', 3
  await press 'C-k', 'C-u'
  await promptAt 'xyz', 0
  await press 'C-y'
  yanked = await promptNow()
  box = await js """
    const r = document.getElementById('promptLine').getBoundingClientRect()
    return {x: Math.round(r.right - 3), y: Math.round(r.top + r.height / 2)}
  """
  await clickAt box.x, box.y
  clicked = await promptNow()
  await press 'M-y'
  popped = await promptNow()
  unless process.platform is 'darwin'
    check 'Alt-Y after a click elsewhere in the line leaves the line alone',
      yanked.value is 'onexyz' and clicked.from is 6 and popped.value is 'onexyz',
      "yanked=#{JSON.stringify yanked} clicked=#{JSON.stringify clicked} after Alt-Y=#{JSON.stringify popped}"

  # 7c. Ctrl+Alt is only AltGr when it types something; with Enter it is not Enter
  await promptAt 'hello', 5
  await press 'C-M-Enter'
  check 'Ctrl-Alt-Enter does not run the line', (await promptNow()).value is 'hello',
    JSON.stringify await promptNow()

  # 8. Ctrl-C: the ordinary key where there is a selection, readline's
  # .break where there is not
  await js """
    if (!window.__copiesCounted) {
      window.__copiesCounted = true
      window.__copies = 0
      document.addEventListener('copy', () => window.__copies++)
    }
    return true
  """
  copiesBefore = await js "return window.__copies"
  await promptAt 'hello', 0, 2
  await press 'C-c'
  kept   = await promptNow()
  copied = (await js "return window.__copies") - copiesBefore
  await promptAt 'hello', 2
  await press 'C-c'
  dropped = await promptNow()
  check 'Ctrl-C copies a selection, and without one clears the line',
    kept.value is 'hello' and kept.from is 0 and kept.to is 2 and copied is 1 and dropped.value is '',
    "with selection #{JSON.stringify kept} copies=#{copied}; without #{JSON.stringify dropped}"

  # 9. the prompt's keys beat the app's, but only while it has focus
  solo = -> js "return document.getElementById('main').classList.contains('solo')"
  was  = await solo()
  await promptAt 'hello', 0
  await press 'C-e'
  inPrompt = await solo()
  await js "document.getElementById('stage').focus(); return true"
  await press 'C-e'
  fromCanvas = await solo()
  await press 'C-e' if fromCanvas isnt was
  check 'Ctrl-E in the prompt is end of line, and from the canvas still shows or hides the editor',
    inPrompt is was and fromCanvas isnt was and (await solo()) is was,
    "solo before=#{was} after prompt Ctrl-E=#{inPrompt} after canvas Ctrl-E=#{fromCanvas}"

  # 10. history, typed for real so Enter is the thing that records it
  enter = (line) ->
    await promptAt line, line.length
    await press 'Enter'
    await until_ -> not await js "return Prompt.pending()"
    await t.quiet()
  await enter 'alpha = 1'
  await enter 'beta = 2'
  await enter 'alpha + beta'

  await promptAt '', 0
  seen = []
  for key in ['C-p', 'C-p', 'C-n']
    await press key
    seen.push (await promptNow()).value
  check 'Ctrl-P and Ctrl-N walk the history', seen.join('|') is 'alpha + beta|beta = 2|alpha + beta',
    JSON.stringify seen

  # 11. reverse-i-search, as the node REPL has it
  await promptAt 'draft', 5
  await press 'C-r'
  await typeText 'alp'
  first  = await promptNow()
  await press 'C-r'
  second = await promptNow()
  await press 'Escape'
  undone = await promptNow()
  check 'Ctrl-R finds the newest match, again the one before, and Esc puts the line back',
    first.value is 'alpha + beta' and first.mark is 'bck-i-search: alp_' and
    second.value is 'alpha = 1' and second.from is 0 and
    undone.value is 'draft' and undone.from is 5 and undone.mark is '>',
    "first=#{JSON.stringify first} second=#{JSON.stringify second} esc=#{JSON.stringify undone}"

  await promptAt 'draft', 5
  await press 'C-r'
  await typeText 'alp'
  await press 'C-r', 'C-s'
  forward = await promptNow()
  await press 'Escape'
  check 'Ctrl-S turns the search round, back to the newer match',
    forward.value is 'alpha + beta' and forward.mark is 'fwd-i-search: alp_',
    JSON.stringify forward

  await promptAt '', 0
  await press 'C-r'
  await typeText 'zzz'
  failed = await promptNow()
  await press 'C-c'
  check 'a search that finds nothing says so', failed.mark is 'failed-bck-i-search: zzz_' and failed.value is '',
    JSON.stringify failed

  before = (await consoleText()).length
  await promptAt '', 0
  await press 'C-r'
  await typeText 'beta'
  await press 'Enter'
  await until_ -> not await js "return Prompt.pending()"
  await t.quiet()
  ran   = (await consoleText())[before..]
  after = await promptNow()
  check 'Enter takes the match and runs it',
    ran.includes('> alpha + beta') and ran.includes('3') and after.value is '' and after.mark is '>',
    "console=#{JSON.stringify ran} prompt=#{JSON.stringify after}"

  # Half a character -- a dead key -- leaves the search going, and a
  # character outside the BMP, one key but two UTF-16 units, extends it.
  # Dispatched, not sent: sendInputEvent cannot make a keydown whose key is
  # outside the BMP or is Dead (tried by Claude, 2026-10-05: the emoji
  # arrived as some other key and was then typed into the line).
  await enter "smile = '\u{1F600}!'"
  await promptAt '', 0
  await press 'C-r'
  await js """
    const p = document.getElementById('promptLine')
    for (const key of ['Dead', '\u{1F600}'])
      p.dispatchEvent(new KeyboardEvent('keydown', {key, bubbles: true, cancelable: true}))
    return true
  """
  wide = await promptNow()
  await press 'Escape'
  check 'Ctrl-R carries on past a dead key and searches for a character outside the BMP',
    wide.value is "smile = '\u{1F600}!'" and wide.mark is 'bck-i-search: \u{1F600}_',
    JSON.stringify wide

  # 12. Ctrl-L clears the console, as it clears the screen
  await promptAt '', 0
  had = (await consoleText()).length
  await press 'C-l'
  check 'Ctrl-L clears the console', had > 0 and (await consoleText()) is '',
    "before=#{had} after=#{JSON.stringify await consoleText()}"

  # 13. the keys that work from anywhere still work from the prompt. These
  # guard against the prompt swallowing them; they pass against the code
  # before readline's keys too.
  await setDoc "screen 320, 200\nbuffer.on\nloop\n  cls()\n  buffer.swap\n"
  await wait 500
  await evalAll()
  await until_ -> (await status()) is 'running'
  # :eval hands the canvas the keyboard a tick late; take it back after that.
  await until_ -> js "return document.activeElement.id === 'stage'"
  await promptAt '', 0
  # AltGr+ß types a backslash on a German keyboard, and on Windows AltGr
  # is Ctrl+Alt: that must reach the prompt, not pause. Chromium types
  # nothing for a sent Ctrl+Alt character, so the check is that the key got
  # past the window's pause listener, which stops what it takes.
  await js """
    window.__backslashes = 0
    window.addEventListener('keydown', (e) => { if (e.key === '\\\\') window.__backslashes++ })
    return true
  """
  await press 'C-M-\\'
  passedOn = await js "return window.__backslashes"
  check 'Ctrl-Alt-\\ is left for typing rather than pausing',
    passedOn is 1 and (await status()) is 'running',
    "reached the window's bubble phase #{passedOn} times, status=#{await status()}"
  await promptAt '', 0
  steps = []
  for [key, wanted] in [['F8', 'line paused'], ['C-\\', 'running'], ['F10', 'line paused'], ['F8', 'running'], ['C-.', 'ready']]
    await press key
    steps.push "#{key}:#{await until_ (-> s = await status(); s if s is wanted), 10000}"
  focusedAfter = (await promptNow()).focused
  check 'F8, Ctrl-\\, F10 and Ctrl-. still work with the prompt focused',
    steps.join(' ') is 'F8:line paused C-\\:running F10:line paused F8:running C-.:ready',
    "#{steps.join ' '} prompt still focused=#{focusedAfter} console=#{JSON.stringify (await consoleText())[-200..]}"
  await setDoc ''
