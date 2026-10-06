# Drives the real app through executeJavaScript. Covers the parts that can
# break without anything visibly failing: the disk bridge, region extraction,
# and whether the worker is genuinely a persistent image.
#
# The suite is a list of parts, each of which can be run on its own:
#
#   npm test                                  every part
#   BEANS_TESTS=buffers npm test              one
#   BEANS_TESTS=buffers,lifecycle npm test    a few
#
# Each part starts from a reset app, so running one alone means the same thing
# as running it in the middle of everything else -- and a part that fails does
# not take the ones after it down with it.

fsp  = require 'fs/promises'
path = require 'path'

# Order matters only for reading the output: the cheap, foundational parts
# first, the slow ones last.
PARTS = [
  'startup', 'problems', 'editor', 'image', 'repl', 'buffers', 'stepping', 'debugging', 'focus', 'lifecycle'
  'drawing', 'color', 'loading', 'shell', 'about', 'report', 'input', 'random', 'names', 'sound', 'perf'
  'pauseonerror'
]

# Run only when named, never in a full run: `quit` ends the app it runs in, so
# the lifecycle part starts a second Electron to run it.
BY_NAME = ['quit']

module.exports = (win, paths) ->
  asked   = (name.trim() for name in (process.env.BEANS_TESTS ? '').split(',') when name.trim())
  unknown = (name for name in asked when name not in PARTS and name not in BY_NAME)
  if unknown.length
    console.log "no such part: #{unknown.join ', '}"
    console.log "have: #{PARTS.join ', '}, and by name only: #{BY_NAME.join ', '}"
    return 1
  chosen = if asked.length then (name for name in [PARTS..., BY_NAME...] when name in asked) else PARTS

  t       = require('./toolkit') win, paths
  guarded = path.join paths.sketches, 'hello.coffee'
  await fsp.writeFile t.scratch, "print 'scratch'\n", 'utf8'
  before = await fsp.readFile guarded, 'utf8'

  await t.settle 15000            # the window is still coming up

  # And until it is drawing. On GitHub's Xvfb Linux runner a page gets no
  # animation frames until its window is shown, and the suite starts before
  # that: in run 37410488931 the show came 3.4s after `=== editor ===`
  # (Claude, 2026-10-06). Why the show is that late there is not known. The
  # first part inherited the wait, and 'ticking Vim Keys switches to vim live'
  # failed in about half the pushes on 2026-10-05, its 3s spent waiting for
  # a cursor CodeMirror places only on a frame. Waited for once, here, so no
  # part has to know.
  unless await t.drawing()
    console.log "the test window drew no animation frame in 15s: no check after this could be trusted"
    return 1

  for name in chosen
    console.log "\n=== #{name} ==="
    started = t.failures
    await t.reset()
    # A part that throws is one failure, not the end of the run: the parts
    # after it are independent and still worth knowing about.
    try
      await require("./parts/#{name}") t
    catch error
      console.error "  #{name} crashed: #{error.stack ? error}"
      t.failures += 1
    fell = t.failures - started
    console.log "--- #{name}: #{if fell then "#{fell} failed" else 'all passed'}"

  # Whatever ran, the suite owns scratch.coffee and nothing else.
  console.log ''
  after = await fsp.readFile guarded, 'utf8'
  t.check 'suite does not touch real sketches', after is before, "hello.coffee #{after.length} bytes"

  # leave the user's layout the way we found it
  await t.js "localStorage.removeItem('panel.editor'); localStorage.removeItem('panel.console'); return true"

  console.log "\n#{if t.failures then "#{t.failures} FAILED" else 'all passed'}"

  # A full green run's data folder is removed by test/run.coffee once Electron
  # has exited: removing it from in here failed with EBUSY on Windows, where
  # Electron still holds its userData (DATA/electron) open. A part on its own
  # has not earned the claim that everything is fine, so it leaves it too.
  disposable = process.env.BEANS_DATA_HOME and paths.data.startsWith paths.root + path.sep
  if disposable and (t.failures or asked.length)
    console.log "left #{paths.data} in place for troubleshooting"

  t.failures
