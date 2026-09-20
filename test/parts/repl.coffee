# The console prompt: one line at a time into the same live worker the sketch
# runs in, answered at a yield point so a running sketch can be questioned
# without being stopped.

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
