# Keys and mouse, from a DOM event through shared memory to the sketch.

module.exports = (t) ->
  {js, wait, check, setDoc, runAll, consoleText, clearConsole, key, settled} = t
  # 15. keyboard state reaches the sketch, and clears on keyup

  await setDoc "print 'down=' + keys.down('a')\n"
  await wait 500
  await key 'keydown', 'KeyA'
  await clearConsole()
  await runAll()
  text = await settled()
  check 'keys.down sees a held key', text.includes('down=true'), JSON.stringify text.trim()

  await key 'keyup', 'KeyA'
  await clearConsole()
  await runAll()
  text = await settled()
  check 'keys.down clears on keyup', text.includes('down=false'), JSON.stringify text.trim()

  # 16. a tap between frames is still caught, and claimed only once
  await setDoc "keys.poll\nprint 'hit=' + keys.hit('b')\n"
  await wait 500
  await key 'keydown', 'KeyB'
  await key 'keyup',   'KeyB'
  await clearConsole()
  await runAll()
  text = await settled()
  check 'keys.hit catches a tap between frames', text.includes('hit=true'), JSON.stringify text.trim()

  await clearConsole()
  await runAll()
  text = await settled()
  check 'keys.hit is claimed once', text.includes('hit=false'), JSON.stringify text.trim()

  # 17. losing focus must not leave a key stuck down
  await setDoc "print 'stuck=' + keys.down('c')\n"
  await wait 500
  await key 'keydown', 'KeyC'
  # Dispatched rather than calling .blur(), which does nothing when the
  # Electron window is not the OS-focused window. This exercises the
  # handler; that a real blur fires it is browser behaviour.
  await js "document.getElementById('stage').dispatchEvent(new FocusEvent('blur')); return true"
  await clearConsole()
  await runAll()
  text = await settled()
  check 'blur releases held keys', text.includes('stuck=false'), JSON.stringify text.trim()

  # 18. mouse position arrives in screen pixels, not window pixels
  await setDoc "print 'at=' + mouse.x + ',' + mouse.y\n"
  await wait 500
  await js """
    const c = document.getElementById('screen')
    const r = c.getBoundingClientRect()
    document.getElementById('stage').dispatchEvent(new PointerEvent('pointermove', {
      clientX: r.left + r.width * 0.25, clientY: r.top + r.height * 0.5, bubbles: true }))
    return true
  """
  await clearConsole()
  await runAll()
  text = await settled()
  check 'mouse maps into screen pixels', text.includes('at=80,100'), JSON.stringify text.trim()
