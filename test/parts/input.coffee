# Keys and mouse, from a DOM event through shared memory to the sketch.

module.exports = (t) ->
  {js, wait, check, setDoc, evalAll, consoleText, clearConsole, key, settled} = t
  # 15. keyboard state reaches the sketch, and clears on keyup

  await setDoc "print 'down=' + keys.down('a')\n"
  await wait 500
  await key 'keydown', 'KeyA'
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'keys.down sees a held key', text.includes('down=true'), JSON.stringify text.trim()

  await key 'keyup', 'KeyA'
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'keys.down clears on keyup', text.includes('down=false'), JSON.stringify text.trim()

  # 16. a tap between frames is still caught, and claimed only once
  await setDoc "keys.poll\nprint 'hit=' + keys.hit('b')\n"
  await wait 500
  await key 'keydown', 'KeyB'
  await key 'keyup',   'KeyB'
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'keys.hit catches a tap between frames', text.includes('hit=true'), JSON.stringify text.trim()

  await clearConsole()
  await evalAll()
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
  await evalAll()
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
  await evalAll()
  text = await settled()
  check 'mouse maps into screen pixels', text.includes('at=80,100'), JSON.stringify text.trim()

  # 55. keys.any is a property, like keys.poll. As a method, `not keys.any`
  # tested the function object and was always false.
  await setDoc "print 'any=' + keys.any\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'keys.any is false with nothing held', text.includes('any=false'), JSON.stringify text.trim()

  await key 'keydown', 'KeyD'
  await clearConsole()
  await evalAll()
  text = await settled()
  await key 'keyup', 'KeyD'
  check 'keys.any sees a held key', text.includes('any=true'), JSON.stringify text.trim()

  # 56. with no name, each lists the keys it would say yes to -- how you find
  # out what a key is called
  await key 'keydown', 'KeyA'
  await key 'keydown', 'Semicolon'
  await setDoc "print 'held=' + keys.down().join(',')\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'keys.down() lists what is held, by name', text.includes('held=a,semicolon'), JSON.stringify text.trim()

  # 57. punctuation answers to its character, its word, or the browser's code
  await setDoc """
names = [';', 'semicolon', 'Semicolon', 'SEMICOLON']
print 'semi=' + (keys.down(n) for n in names).join(',')
print 'quote=' + keys.down("'") + ',' + keys.down('apostrophe') + ',' + keys.down('quote')
"""
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'punctuation has names', text.includes('semi=true,true,true,true') and text.includes('quote=false,false,false'),
    JSON.stringify text.trim()
  await key 'keyup', 'KeyA'
  await key 'keyup', 'Semicolon'

  # 58. keys.up is the falling edge: sticky until the next frame, like hit
  await setDoc "keys.poll\nprint 'up=' + keys.up('b') + ' ups=' + keys.up().join(',') + ' hits=' + keys.hit().join(',')\n"
  await wait 500
  await evalAll()                  # claims taps left over from earlier checks
  await settled()
  await key 'keydown', 'KeyB'
  await key 'keyup',   'KeyB'
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'keys.up catches a release between frames, and the lists agree',
    text.includes('up=true ups=b hits=b'), JSON.stringify text.trim()
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'keys.up is claimed once', text.includes('up=false ups= hits='), JSON.stringify text.trim()

  # 59. losing focus lets go of held keys, and says so
  await key 'keydown', 'KeyC'
  await js "document.getElementById('stage').dispatchEvent(new FocusEvent('blur')); return true"
  await setDoc "keys.poll\nprint 'upOnBlur=' + keys.up('c')\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'blur counts as letting go', text.includes('upOnBlur=true'), JSON.stringify text.trim()

  # 60. a name nobody knows is an error, not a quiet false
  await setDoc "print keys.down 'semi-colon'\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  check 'an unknown key name says so', text.includes('no key called "semi-colon"') and text.includes('keys.down()'),
    JSON.stringify text.trim()
