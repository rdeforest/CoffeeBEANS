# The worker as a live image: names persist between runs, stay out of
# globalThis, survive a throw, and cannot damage the API by shadowing it.

module.exports = (t) ->
  {js, wait, check, setDoc, cursorOnLine, evalAll, consoleText, clearConsole,
   click, settled, evalRegion, ask} = t
  # 6. the worker is a live image: define in one region, call from another
  await setDoc "greet = (who) -> print \"hi \#{who}\"\n\ngreet 'robert'\n"
  await wait 500
  await clearConsole()
  await cursorOnLine 1
  await evalRegion()
  await wait 400
  await cursorOnLine 3
  await evalRegion()
  text = await settled()
  check 'worker keeps state between runs', text.includes('hi robert'), JSON.stringify text.trim()

  # 7. a sketch cannot sever the worker's inbox by naming a variable onmessage
  await setDoc "onmessage = 'clobbered'\nprint 'BEFORE'\n"
  await wait 500
  await clearConsole()
  await evalRegion()
  await wait 400
  await setDoc "print 'AFTER'\n"
  await wait 500
  await evalRegion()
  text = await settled()
  check 'sketch cannot clobber the worker inbox', text.includes('AFTER'), JSON.stringify text.trim()

  # 32. nothing in the worker's own bootstrap may shadow a runtime global
  await setDoc "print(name + '=' + typeof globalThis[name]) for name in ['load', 'get', 'put', 'text', 'surface', 'stamp', 'line']\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text4 = await settled()
  shadowed = (name for name in ['load', 'get', 'put', 'text', 'surface', 'stamp', 'line'] \
              when not text4.includes "#{name}=function")
  check 'runtime globals are not shadowed by the bootstrap', shadowed.length is 0,
    if shadowed.length then "shadowed: #{shadowed.join ', '}" else 'all reachable'

  # 47. a sketch's own names never reach globalThis
  await setDoc "mySketchThing = 42\nprint 'local=' + mySketchThing\nprint 'leaked=' + globalThis.mySketchThing?\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'sketch names stay out of globalThis',
    text.includes('local=42') and text.includes('leaked=false'), JSON.stringify text.trim()

  # 48. shadowing a command still works, but cannot damage the command
  await setDoc "line = 5\nprint 'shadowed=' + typeof line\nprint 'apiIntact=' + typeof globalThis.line\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  shadowed = text.includes('shadowed=number') and text.includes('apiIntact=function')

  # the shadow lives in the image, so a later region still sees it
  await setDoc "print 'persists=' + typeof line\n"
  await wait 500
  await evalAll()
  text = await settled()
  persists = text.includes('persists=number')

  # and a run drops the image, leaving the API pristine
  await setDoc "print 'afterRun=' + typeof line\n"
  await wait 500
  await clearConsole()
  await click 'runFresh'
  # Until the fresh worker has answered: a fixed 1200ms read the console
  # mid-boot on a slow machine. The console was cleared, so nothing from
  # before the run can satisfy this.
  deadline = Date.now() + 15000
  await wait 25 until (await consoleText()).includes('afterRun=') or Date.now() > deadline
  text = await settled()
  check 'a shadowed command is restored by a run',
    shadowed and persists and text.includes('afterRun=function'),
    "shadowed=#{shadowed} persists=#{persists} after=#{JSON.stringify text.trim()}"

  # 49. a sketch that throws keeps whatever it managed to define
  await setDoc "keeper = 7\nthrow new Error 'halt'\n"
  await wait 500
  await clearConsole()
  await evalAll()
  await wait 700
  await setDoc "print 'kept=' + keeper\n"
  await wait 500
  await evalAll()
  text = await settled()
  check 'definitions survive a sketch that throws', text.includes('kept=7'), JSON.stringify text.trim()

  # A sketch that opens with comments keeps its names. CoffeeScript 2 puts a
  # sketch's leading `#` lines ahead of the `var` that declares its names, and
  # declaredNames in worker-boot.js once read past block comments only, so a
  # first-line comment left the prompt answering `hashName is not defined`
  # (found by a reviewer of E1, 2026-10-06). Asked at the prompt, which sees
  # the image and nothing else.
  keeps = (doc, line, run = evalAll) ->
    await setDoc doc
    await wait 500
    await run()
    await settled()
    await ask line

  answer = await keeps "# a comment\nhashName = 101\n", 'hashName'
  check 'a sketch whose first line is a comment keeps its names',
    answer.includes('101'), JSON.stringify answer.trim()

  answer = await keeps "# one\n# two\n\n# three\nmanyA = 102\nmanyB = 103\n", '[manyA, manyB]'
  check 'a sketch opening with several comment lines keeps every name',
    answer.includes('[102, 103]'), JSON.stringify answer.trim()

  # The order matters to CoffeeScript, not to us: this one compiles to a `//`
  # line and then two `/* */` blocks, all ahead of the `var`.
  answer = await keeps "# a line\n###\na block\n###\n### another ###\nmixed = 104\n", 'mixed'
  check 'line and block comments mixed ahead of the names are both skipped',
    answer.includes('104'), JSON.stringify answer.trim()

  # A region usually opens with the comment that says what it defines.
  answer = await keeps "regionTop = 0\n\n# what the region is for\nregionName = 105\n", 'regionName', ->
    await cursorOnLine 4
    await evalRegion()
  check 'a region whose first line is a comment keeps its names',
    answer.includes('105'), JSON.stringify answer.trim()
