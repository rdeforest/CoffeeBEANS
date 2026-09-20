# The worker as a live image: names persist between runs, stay out of
# globalThis, survive a throw, and cannot damage the API by shadowing it.

module.exports = (t) ->
  {js, wait, check, setDoc, cursorOnLine, runAll, consoleText, clearConsole,
   click, settled, runRegion} = t
  # 6. the worker is a live image: define in one region, call from another
  await setDoc "greet = (who) -> print \"hi \#{who}\"\n\ngreet 'robert'\n"
  await wait 500
  await clearConsole()
  await cursorOnLine 1
  await runRegion()
  await wait 400
  await cursorOnLine 3
  await runRegion()
  text = await settled()
  check 'worker keeps state between runs', text.includes('hi robert'), JSON.stringify text.trim()

  # 7. a sketch cannot sever the worker's inbox by naming a variable onmessage
  await setDoc "onmessage = 'clobbered'\nprint 'BEFORE'\n"
  await wait 500
  await clearConsole()
  await runRegion()
  await wait 400
  await setDoc "print 'AFTER'\n"
  await wait 500
  await runRegion()
  text = await settled()
  check 'sketch cannot clobber the worker inbox', text.includes('AFTER'), JSON.stringify text.trim()

  # 32. nothing in the worker's own bootstrap may shadow a runtime global
  await setDoc "print(name + '=' + typeof globalThis[name]) for name in ['load', 'get', 'put', 'text', 'surface', 'stamp', 'line']\n"
  await wait 500
  await clearConsole()
  await runAll()
  text4 = await settled()
  shadowed = (name for name in ['load', 'get', 'put', 'text', 'surface', 'stamp', 'line'] \
              when not text4.includes "#{name}=function")
  check 'runtime globals are not shadowed by the bootstrap', shadowed.length is 0,
    if shadowed.length then "shadowed: #{shadowed.join ', '}" else 'all reachable'

  # 47. a sketch's own names never reach globalThis
  await setDoc "mySketchThing = 42\nprint 'local=' + mySketchThing\nprint 'leaked=' + globalThis.mySketchThing?\n"
  await wait 500
  await clearConsole()
  await runAll()
  text = await settled()
  check 'sketch names stay out of globalThis',
    text.includes('local=42') and text.includes('leaked=false'), JSON.stringify text.trim()

  # 48. shadowing a command still works, but cannot damage the command
  await setDoc "line = 5\nprint 'shadowed=' + typeof line\nprint 'apiIntact=' + typeof globalThis.line\n"
  await wait 500
  await clearConsole()
  await runAll()
  text = await settled()
  shadowed = text.includes('shadowed=number') and text.includes('apiIntact=function')

  # the shadow lives in the image, so a later region still sees it
  await setDoc "print 'persists=' + typeof line\n"
  await wait 500
  await runAll()
  text = await settled()
  persists = text.includes('persists=number')

  # and a restart drops the image, leaving the API pristine
  await setDoc "print 'afterRestart=' + typeof line\n"
  await wait 500
  await clearConsole()
  await click 'restart'
  await wait 1200
  text = await consoleText()
  check 'a shadowed command is restored by a restart',
    shadowed and persists and text.includes('afterRestart=function'),
    "shadowed=#{shadowed} persists=#{persists} after=#{JSON.stringify text.trim()}"

  # 49. a sketch that throws keeps whatever it managed to define
  await setDoc "keeper = 7\nthrow new Error 'halt'\n"
  await wait 500
  await clearConsole()
  await runAll()
  await wait 700
  await setDoc "print 'kept=' + keeper\n"
  await wait 500
  await runAll()
  text = await settled()
  check 'definitions survive a sketch that throws', text.includes('kept=7'), JSON.stringify text.trim()
