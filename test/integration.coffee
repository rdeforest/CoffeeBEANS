# Drives the real app through executeJavaScript. Covers the parts that can
# break without anything visibly failing: the disk bridge, region extraction,
# and whether the worker is genuinely a persistent image.
fsp  = require 'fs/promises'
path = require 'path'

wait = (ms) -> new Promise (resolve) -> setTimeout resolve, ms

module.exports = (win, ROOT) ->
  scratch = path.join ROOT, 'sketches', 'scratch.coffee'
  js      = (code) -> win.webContents.executeJavaScript "(async () => { #{code} })()", yes
  failures = 0

  check = (name, ok, detail = '') ->
    failures += 1 unless ok
    console.log "#{if ok then 'PASS' else 'FAIL'}  #{name}#{if detail then "   #{detail}" else ''}"

  setDoc = (text) -> js """
    const v = Editor.view()
    v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: #{JSON.stringify text} } })
    return v.state.doc.length
  """

  cursorOnLine = (n) -> js """
    const v = Editor.view()
    v.dispatch({ selection: { anchor: v.state.doc.line(#{n}).from } })
    return #{n}
  """

  selectLines = (a, b) -> js """
    const v = Editor.view()
    v.dispatch({ selection: { anchor: v.state.doc.line(#{a}).from, head: v.state.doc.line(#{b}).to } })
    return true
  """

  consoleText = -> js "return document.getElementById('console').textContent"
  clearConsole = -> js "document.getElementById('console').innerHTML = ''; return true"

  await wait 1200

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
  await js "Editor.runRegion(); return true"
  await wait 500
  text = await consoleText()
  check 'region runs paragraph at cursor', text.includes('SECOND') and not text.includes('FIRST'), JSON.stringify text.trim()

  # 4. a cursor inside a definition runs the whole definition
  await setDoc "sketchy = ->\n  print 'CALLED'\n\nsketchy()\n"
  await wait 500
  await clearConsole()
  await cursorOnLine 2
  await js "Editor.runRegion(); return true"
  await wait 400
  defined = await consoleText()
  await cursorOnLine 4
  await js "Editor.runRegion(); return true"
  await wait 400
  text = await consoleText()
  check 'cursor in a definition runs the definition', defined.trim() is '' and text.includes('CALLED'), JSON.stringify text.trim()

  # 5. an explicitly selected indented region is dedented before it compiles
  await setDoc "if true\n  print 'INDENTED'\n  print 'STILL'\n"
  await wait 500
  await clearConsole()
  await selectLines 2, 3
  await js "Editor.runRegion(); return true"
  await wait 500
  text = await consoleText()
  check 'selected indented region dedents', text.includes('INDENTED') and text.includes('STILL') and not text.toLowerCase().includes('error'), JSON.stringify text.trim()

  # 6. the worker is a live image: define in one region, call from another
  await setDoc "greet = (who) -> print \"hi \#{who}\"\n\ngreet 'robert'\n"
  await wait 500
  await clearConsole()
  await cursorOnLine 1
  await js "Editor.runRegion(); return true"
  await wait 400
  await cursorOnLine 3
  await js "Editor.runRegion(); return true"
  await wait 500
  text = await consoleText()
  check 'worker keeps state between runs', text.includes('hi robert'), JSON.stringify text.trim()

  # 7. a sketch cannot sever the worker's inbox by naming a variable onmessage
  await setDoc "onmessage = 'clobbered'\nprint 'BEFORE'\n"
  await wait 500
  await clearConsole()
  await js "Editor.runRegion(); return true"
  await wait 400
  await setDoc "print 'AFTER'\n"
  await wait 500
  await js "Editor.runRegion(); return true"
  await wait 500
  text = await consoleText()
  check 'sketch cannot clobber the worker inbox', text.includes('AFTER'), JSON.stringify text.trim()

  # 8. a write from outside (vim) is picked up
  await fsp.writeFile scratch, "print 'FROM VIM'\n", 'utf8'
  await wait 700
  doc = await js "return Editor.all()"
  check 'external write reloads editor', doc is "print 'FROM VIM'\n", JSON.stringify doc

  console.log "\n#{if failures then "#{failures} FAILED" else 'all passed'}"
  failures
