# The editor is the program: mounting, vim, region extraction,
# autosave, reloads from disk, :e, :target and :help.

fsp     = require 'fs/promises'
path    = require 'path'

# How vim saves by default: the old file renamed aside, a new one written in
# its place, the backup removed. Every save is a new inode -- the case that
# broke Linux reloads on 2026-10-04, and one an in-place writeFile never
# exercises, because it keeps the inode.
vimSave = (file, text) ->
  await fsp.rename file, "#{file}~"
  await fsp.writeFile file, text, 'utf8'
  await fsp.rm "#{file}~"

module.exports = (t) ->
  {js, wait, check, setDoc, cursorOnLine, selectLines, consoleText,
   clearConsole, handleEx, linesText, overLine, overRed, paths, scratch,
   settled, evalRegion, untilDoc} = t
  # 1. editor is mounted and vim is driving it
  mounted = await js "return !!document.querySelector('.cm-editor')"
  fatCursor = await js "return !!document.querySelector('.cm-fat-cursor') || !!document.querySelector('.cm-vim-panel')"
  check 'editor mounts',        mounted
  check 'vim mode active',      fatCursor, '(block cursor present)'

  await js "await Editor.load('scratch'); return true"

  # 2. edits reach disk without an explicit save
  await setDoc "print 'autosave check'\n"
  await wait 600
  onDisk = await fsp.readFile scratch, 'utf8'
  check 'autosave writes to disk', onDisk is "print 'autosave check'\n", JSON.stringify onDisk

  # 3. eval-region runs only the paragraph under the cursor
  await setDoc "print 'FIRST'\n\nprint 'SECOND'\n"
  await wait 500
  await clearConsole()
  await cursorOnLine 3
  await evalRegion()
  text = await settled()
  check 'region runs paragraph at cursor', text.includes('SECOND') and not text.includes('FIRST'), JSON.stringify text.trim()

  # 4. a cursor inside a definition runs the whole definition
  await setDoc "sketchy = ->\n  print 'CALLED'\n\nsketchy()\n"
  await wait 500
  await clearConsole()
  await cursorOnLine 2
  await evalRegion()
  defined = await settled()
  await cursorOnLine 4
  await evalRegion()
  text = await settled()
  check 'cursor in a definition runs the definition', defined.trim() is '' and text.includes('CALLED'), JSON.stringify text.trim()

  # 5. an explicitly selected indented region is dedented before it compiles
  await setDoc "if true\n  print 'INDENTED'\n  print 'STILL'\n"
  await wait 500
  await clearConsole()
  await selectLines 2, 3
  await evalRegion()
  text = await settled()
  check 'selected indented region dedents', text.includes('INDENTED') and text.includes('STILL') and not text.toLowerCase().includes('error'), JSON.stringify text.trim()

  # 8. a write from outside (vim) is picked up
  await fsp.writeFile scratch, "print 'FROM VIM'\n", 'utf8'
  await wait 700
  doc = await js "return Editor.all()"
  check 'external write reloads editor', doc is "print 'FROM VIM'\n", JSON.stringify doc

  # 8b. ...and keeps being picked up when every save is a new file. On Linux,
  # Node's recursive watch tracked each file's inode, so the first such save
  # was seen and every later one was not (Claude, 2026-10-04).
  seen = []
  for round in [1..3]
    text = "print 'VIM SAVE #{round}'\n"
    await vimSave scratch, text
    seen.push await untilDoc text
  check 'every rename-style save reloads, not just the first',
    seen.every((doc, index) -> doc is "print 'VIM SAVE #{index + 1}'\n"),
    JSON.stringify seen

  # A folder made by someone else while the app runs has to be watched too,
  # and a file in it saved the same way, more than once.
  outside = path.join paths.sketches, 'made-outside'
  await fsp.rm outside, recursive: yes, force: yes
  await fsp.mkdir outside
  later = path.join outside, 'later.coffee'
  await fsp.writeFile later, "print 'START'\n", 'utf8'
  await js "await Editor.load('made-outside/later'); return true"
  seen = []
  for round in [1..2]
    text = "print 'LATER #{round}'\n"
    await vimSave later, text
    seen.push await untilDoc text
  check 'a folder created outside the app is watched, every save',
    seen.every((doc, index) -> doc is "print 'LATER #{index + 1}'\n"),
    JSON.stringify seen
  await js "await Editor.load('scratch'); return true"
  await fsp.rm outside, recursive: yes, force: yes

  # 9. :help goes through the real ex parser
  await clearConsole()
  await js "CM.Vim.handleEx(CM.getCM(Editor.view()), 'help'); return true"
  await wait 300
  text = await consoleText()
  check ':help lists every section',
    text.includes('Running code') and text.includes('Colors') and text.includes('Buffers')

  await clearConsole()
  await js "CM.Vim.handleEx(CM.getCM(Editor.view()), 'help colors'); return true"
  await wait 300
  text = await consoleText()
  check ':help <topic> narrows to one section',
    text.includes('Colors') and not text.includes('Running code')

  # 56. :help takes an object's name for its long form, and anything else
  # that is not a section is searched for, line by line
  helpFor = (topic) ->
    await clearConsole()
    await js "CM.Vim.handleEx(CM.getCM(Editor.view()), #{JSON.stringify "help #{topic}"}); return true"
    await wait 300
    consoleText()

  text = await helpFor 'keys'
  check ':help keys is the long form', text.includes('keys -- the keyboard') and text.includes('pagedown') and not text.includes('mouse.x'),
    JSON.stringify text.trim()[..200]

  text = await helpFor 'wheel'
  check ':help searches lines when no section matches',
    text.includes('mouse.wheel') and text.includes('Input') and not text.includes('keys.down'), JSON.stringify text.trim()

  text = await helpFor 'where fn'
  check ':help search keeps continuation lines and takes spaces',
    text.includes('where fn') and text.includes('p.hue'), JSON.stringify text.trim()

  text = await helpFor 'zzzz'
  check ':help with no match says so', text.includes('no help for "zzzz"'), JSON.stringify text.trim()

  # An example that does not run is worse than none, so the one that ends
  # (the others loop) is run as written: straight, then turned to touch.
  text = await helpFor 'overlaps'
  check ':help overlaps shows an example',
    text.includes('Example') and text.includes('turned = surface 13, 13'), JSON.stringify text.trim()[..200]

  example = await js "return HELP.match('overlaps')[0].example.join('\\n')"
  await setDoc example
  await clearConsole()
  await handleEx 'eval'
  text = await settled()
  check 'the overlaps example runs and both tests hit',
    text.trim() is 'truetrue', JSON.stringify text.trim()

  # 13. switching sketches must not drop an edit the autosave has not flushed
  await js "await Editor.load('scratch'); return true"
  await setDoc "print 'PENDING EDIT'\n"
  await js "await Editor.load('hello'); return true"
  await wait 700
  onDisk = await fsp.readFile scratch, 'utf8'
  check 'switching sketches flushes a pending edit', onDisk.includes('PENDING EDIT'), JSON.stringify onDisk
  # Back to scratch at once: anything that edits while a real sketch is
  # current would autosave test content straight over it.
  await js "await Editor.load('scratch'); return true"

  # 13a. the status line counts source lines, and a :target flags the overrun.
  # Goes through the real ex parser, the same path :help uses.


  await setDoc "# a comment\nprint 'one'\n\nprint 'two'\n"
  await wait 300
  check 'status line counts only source lines', (await linesText()) is '2 lines', JSON.stringify await linesText()

  # A comment is a comment however it is indented. `[^ #]` matched a tab, so a
  # tab-indented comment counted as source and so did a line of only tabs.
  await setDoc "print 'one'\n\t# tabbed comment\n\t\nprint 'two'\n"
  await wait 300
  check 'a tab-indented comment is not a source line',
    (await linesText()) is '2 lines', JSON.stringify await linesText()

  await setDoc "# a comment\nprint 'one'\n\nprint 'two'\n"
  await wait 300

  await handleEx 'target 3'
  await wait 200
  check 'a target above the count reads count/limit', (await linesText()) is '2/3 lines', JSON.stringify await linesText()
  check 'within the target nothing is flagged', (await overLine()) is null and (await overRed()) is false

  await handleEx 'target 1'
  await wait 200
  check 'over the target the count turns red', (await overRed()) is true
  check 'the first line past the target is flagged', (await overLine()) is "print 'two'", JSON.stringify await overLine()

  await handleEx 'target 0'
  await wait 200
  check ':target 0 clears the limit', (await overLine()) is null and (await overRed()) is false

  # 13b. :e switches sketches, creates them when new, and honours the dirty guard.
  await handleEx 'e hello'
  await wait 300
  check ':e switches to an existing sketch', (await js "return Editor.name()") is 'hello'

  created = path.join paths.sketches, 'ecreate.coffee'
  await fsp.rm created, force: yes
  await handleEx 'e ecreate.coffee'          # the .coffee he would type is stripped
  await wait 400
  made = false
  try
    await fsp.access created
    made = true
  listed = await js "return (await beans.list()).includes('ecreate')"
  check ':e newname creates, opens, and lists the sketch',
    (await js "return Editor.name()") is 'ecreate' and made and listed,
    "name=#{await js "return Editor.name()"} disk=#{made} listed=#{listed}"

  # Names are paths under sketches/, so folders work end to end.
  nested = path.join paths.sketches, 'sub', 'nested.coffee'
  await fsp.rm path.join(paths.sketches, 'sub'), recursive: yes, force: yes
  await handleEx 'e sub/nested'
  await wait 400
  onDisk = false
  try
    await fsp.access nested
    onDisk = true
  listed = await js "return (await beans.list()).includes('sub/nested')"
  check ':e sub/name creates the folder and lists the sketch by its path',
    (await js "return Editor.name()") is 'sub/nested' and onDisk and listed,
    "name=#{await js "return Editor.name()"} disk=#{onDisk} listed=#{listed}"
  await fsp.writeFile nested, "print 'NESTED FROM VIM'\n", 'utf8'
  await wait 700
  doc = await js "return Editor.all()"
  check 'an outside write in a folder reloads too', doc is "print 'NESTED FROM VIM'\n", JSON.stringify doc
  escaped = await js "try { await beans.read('../../escape'); return 'read' } catch (e) { return 'refused' }"
  check 'a name cannot climb out of sketches/', escaped is 'refused', escaped
  await js "await Editor.load('scratch'); return true"
  await fsp.rm path.join(paths.sketches, 'sub'), recursive: yes, force: yes

  await js "await Editor.load('scratch'); return true"
  await setDoc "print 'PENDING'\n"           # dirty: inside the 250ms save debounce
  await handleEx 'e hello'                    # must refuse and stay put
  await wait 100
  check ':e refuses to abandon a pending edit', (await js "return Editor.name()") is 'scratch'
  await wait 400                             # let that edit flush back to scratch
  await setDoc "print 'DISCARD ME'\n"
  await handleEx 'e! hello'                   # the bang drops it and switches
  await wait 400
  check ':e! discards the pending edit and switches', (await js "return Editor.name()") is 'hello'

  await fsp.rm created, force: yes
  # Back to scratch: the setDoc-heavy tests below must not autosave over a real one.
  await js "await Editor.load('scratch'); return true"

  # 45. saving leaves no staging files behind in the sketches folder
  await js "await Editor.load('scratch'); return true"
  await setDoc "print 'atomic'\n"
  await wait 700
  strays = (await fsp.readdir paths.sketches).filter (name) -> not name.endsWith '.coffee'
  check 'atomic save leaves nothing behind', strays.length is 0, strays.join ', '
