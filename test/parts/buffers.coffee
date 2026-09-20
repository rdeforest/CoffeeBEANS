# Single and double buffering, what a swap means in each, the frame cap,
# and where a sketch can tell its drawing is landing.

module.exports = (t) ->
  {wait, check, setDoc, runAll, consoleText, clearConsole, click, settled} = t
  # 10. a swap in single-buffer mode must not flip away the drawing
  await setDoc "screen 320, 200\ncls()\npoint 10, 10, COLORS.white\nwait 1\nprint 'pget=' + pget(10, 10)\n"
  await wait 500
  await clearConsole()
  await runAll()
  text = await settled()
  check 'wait keeps the drawing in single-buffer mode',
    text.includes('pget=') and not text.includes('pget=0'), JSON.stringify text.trim()

  # 11. double buffering must still flip: after a swap you are drawing
  # into the buffer that was on screen, not the one you just filled.
  await setDoc "screen 320, 200\ncls()\nbuffer.on\ncls()\npoint 10, 10, COLORS.white\nbefore = pget(10, 10)\nbuffer.swap\nprint 'flipped=' + (pget(10, 10) isnt before)\n"
  await wait 500
  await clearConsole()
  await runAll()
  text = await settled()
  check 'double buffering flips on swap', text.includes('flipped=true'), JSON.stringify text.trim()

  # 12. pget must return the color point was given, not the stored byte order
  await setDoc "screen 320, 200\ncls()\npoint 5, 5, COLORS.red\nprint 'roundtrip=' + (pget(5, 5) is COLORS.red)\n"
  await wait 500
  await clearConsole()
  await runAll()
  text = await settled()
  check 'pget round-trips a color', text.includes('roundtrip=true'), JSON.stringify text.trim()

  # 38. a stopped double-buffered sketch must not leave the next sketch
  # drawing into the buffer that is not on screen, or over its leftovers
  await setDoc "screen 320, 200\nbuffer.on\nloop\n  cls()\n  point 10, 10, COLORS.red\n  buffer.swap\n"
  await wait 500
  await runAll()
  await wait 400
  await click 'stop'
  await wait 300
  await clearConsole()
  await setDoc "screen 320, 200\ncls()\npoint 20, 20, COLORS.white\nprint 'onScreen=' + display.onScreen\nprint 'oldGone=' + (pget(10, 10) isnt COLORS.red)\n"
  await wait 500
  await runAll()
  text = await settled()
  check 'next sketch after a stopped double-buffered one draws on screen', text.includes('onScreen=true') and text.includes('oldGone=true'), JSON.stringify text.trim()

  # 41. buffer.fps actually paces swaps instead of only storing a number
  await setDoc "screen 320, 200\nbuffer.on\nbuffer.fps 10\nbuffer.swap\nstart = elapsed\nn = 0\nwhile elapsed - start < 1\n  buffer.swap\n  n += 1\nprint 'swaps=' + n\nbuffer.fps 0\n"
  await wait 500
  await clearConsole()
  await runAll()
  text  = await settled()
  swaps = Number /swaps=(\d+)/.exec(text)?[1] ? -1
  check 'buffer.fps paces swaps', 4 <= swaps <= 25, "#{swaps} swaps in a second at fps 10"

  # 42. display.onScreen tells a sketch where its drawing is landing
  await setDoc "screen 320, 200\nprint 'single=' + display.onScreen\nbuffer.on\nprint 'doubled=' + display.onScreen\nbuffer.swap\nprint 'afterSwap=' + display.onScreen\n"
  await wait 500
  await clearConsole()
  await runAll()
  text = await settled()
  check 'display.onScreen distinguishes the buffers',
    text.includes('single=true') and text.includes('doubled=false') and text.includes('afterSwap=false'),
    JSON.stringify text.trim()
