# Canaries, not benchmarks. The bounds are far below what the machine
# does, so they only fire when something has fallen off a fast path.

module.exports = (t) ->
  {wait, check, setDoc, evalAll, consoleText, clearConsole, settled} = t
  # 52. the solid path stays fast. The bound is deliberately far below what
  # the machine does, so this is a canary for a primitive quietly falling
  # onto the per-pixel path, not a benchmark.
  await setDoc "screen 320, 200\ncls()\nt = performance.now()\npoint i %% 320, (i / 320) %% 200, COLORS.red for i in [0...2000000] by 1\nrate = 2000000 / ((performance.now() - t) / 1000)\nprint 'rate=' + round(rate / 1000000)\n"
  await wait 500
  await clearConsole()
  await evalAll()
  text = await settled()
  rate = Number /rate=(\d+)/.exec(text)?[1] ? 0
  check 'solid drawing stays on the fast path', rate >= 3, "#{rate}M points/sec"
