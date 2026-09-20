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
  'editor', 'image', 'buffers', 'lifecycle'
  'drawing', 'color', 'loading', 'shell', 'input', 'perf'
]

module.exports = (win, paths) ->
  asked   = (name.trim() for name in (process.env.BEANS_TESTS ? '').split(',') when name.trim())
  unknown = (name for name in asked when name not in PARTS)
  if unknown.length
    console.log "no such part: #{unknown.join ', '}"
    console.log "have: #{PARTS.join ', '}"
    return 1
  chosen = if asked.length then (name for name in PARTS when name in asked) else PARTS

  t       = require('./toolkit') win, paths
  guarded = path.join paths.sketches, 'hello.coffee'
  await fsp.writeFile t.scratch, "print 'scratch'\n", 'utf8'
  before = await fsp.readFile guarded, 'utf8'

  await t.settle 15000            # the window is still coming up

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

  # Only ever remove a data directory the test run created inside the repo, and
  # only after a full green run -- a part on its own has not earned the claim
  # that everything is fine.
  disposable = process.env.BEANS_DATA_HOME and paths.data.startsWith paths.root + path.sep
  if disposable and not t.failures and not asked.length
    await fsp.rm paths.data, recursive: yes, force: yes
    console.log "removed #{paths.data}"
  else if disposable
    console.log "left #{paths.data} in place for troubleshooting"

  t.failures
