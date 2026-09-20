# Everything around the sketch: panels, the File menu, and seeding the
# data directory from examples/.

fsp     = require 'fs/promises'
path    = require 'path'
{Menu}  = require 'electron'
seeding = require '../../src/main/data'

module.exports = (t) ->
  {js, wait, check, paths} = t
  # 14. panels resize, clamp at both ends, and remember the last size
  await js "Panels.set('editor', 400); return true"
  await wait 150
  width = await js "return Math.round(Panels.size('editor'))"
  check 'editor panel resizes', width is 400, "#{width}px"

  await js "Panels.set('editor', 10); return true"
  await wait 150
  narrow = await js "return Math.round(Panels.size('editor'))"
  check 'editor panel clamps to a minimum', narrow >= 200 and narrow < 400, "#{narrow}px"

  await js "Panels.set('editor', 99999); return true"
  await wait 150
  wide  = await js "return Math.round(Panels.size('editor'))"
  total = await js "return window.innerWidth"
  check 'editor panel clamps to available room', wide < total - 100, "#{wide}px of #{total}px"

  await js "Panels.set('console', 200); return true"
  await wait 150
  tall = await js "return Math.round(Panels.size('console'))"
  remembered = await js "return Number(localStorage.getItem('panel.console'))"
  check 'console panel resizes and is remembered', tall is 200 and remembered is 200, "#{tall}px stored=#{remembered}"

  # 19. the data directory was seeded from examples/
  seeded   = (await fsp.readdir paths.sketches).filter (name) -> name.endsWith '.coffee'
  examples = (await fsp.readdir path.join paths.root, 'examples').filter (name) -> name.endsWith '.coffee'
  missing  = (name for name in examples when name not in seeded)
  check 'data directory seeded from examples', missing.length is 0, "have #{seeded.join ', '}"

  # 20. the File menu can get the user to their own files
  menu = Menu.getApplicationMenu()
  file = menu?.items.find (item) -> item.label is 'File'
  open = file?.submenu?.items.find (item) -> item.label is 'Open Data Folder'
  check 'File menu opens the data folder', open? and open.enabled, "#{file?.submenu?.items.length} items under File"

  # 24. seeding offers each example once, and never at the cost of your edits
  sandbox  = path.join paths.data, 'seedcheck'
  fakeEx   = path.join sandbox, 'examples'
  fakeData = path.join sandbox, 'data'
  await fsp.mkdir fakeEx, recursive: yes
  await fsp.writeFile path.join(fakeEx, 'one.coffee'), 'print 1\n', 'utf8'

  first = await seeding.prepare fakeData, fakeEx
  check 'seeding copies a new example', first.added.join(',') is 'one.coffee', first.added.join ','

  mine = path.join fakeData, 'sketches', 'one.coffee'
  await fsp.writeFile mine, 'print "mine"\n', 'utf8'
  await fsp.writeFile path.join(fakeEx, 'two.coffee'), 'print 2\n', 'utf8'
  second = await seeding.prepare fakeData, fakeEx
  kept   = await fsp.readFile mine, 'utf8'
  check 'a new example arrives without clobbering an edited one',
    second.added.join(',') is 'two.coffee' and kept is 'print "mine"\n',
    "added=#{second.added.join ','} kept=#{JSON.stringify kept}"

  await fsp.rm path.join(fakeData, 'sketches', 'two.coffee')
  third = await seeding.prepare fakeData, fakeEx
  gone  = not (await fsp.readdir path.join fakeData, 'sketches').includes 'two.coffee'
  check 'a deleted example stays deleted', third.added.length is 0 and gone,
    "added=#{third.added.join ','} gone=#{gone}"

  # A data directory predating the manifest must not have its contents
  # treated as never-offered, or an upgrade would overwrite every edit.
  legacy = path.join sandbox, 'legacy'
  await fsp.mkdir path.join(legacy, 'sketches'), recursive: yes
  await fsp.writeFile path.join(legacy, 'sketches', 'one.coffee'), 'print "old"\n', 'utf8'
  fourth = await seeding.prepare legacy, fakeEx
  survived = await fsp.readFile path.join(legacy, 'sketches', 'one.coffee'), 'utf8'
  check 'a pre-manifest data folder keeps its edits',
    survived is 'print "old"\n' and fourth.added.join(',') is 'two.coffee',
    "added=#{fourth.added.join ','} kept=#{JSON.stringify survived}"

  # 44. seeding never writes over a sketch already on disk
  guardDir = path.join sandbox, 'guarded'
  await fsp.mkdir path.join(guardDir, 'sketches'), recursive: yes
  await fsp.writeFile path.join(guardDir, 'sketches', 'two.coffee'), "print 'not yours'\n", 'utf8'
  await fsp.writeFile path.join(guardDir, '.seeded'), "one.coffee\n", 'utf8'
  guarded2 = await seeding.prepare guardDir, fakeEx
  survivor = await fsp.readFile path.join(guardDir, 'sketches', 'two.coffee'), 'utf8'
  recorded = await fsp.readFile path.join(guardDir, '.seeded'), 'utf8'
  check 'seeding does not overwrite a sketch already on disk',
    survivor is "print 'not yours'\n" and recorded.includes('two.coffee') and guarded2.added.length is 0,
    "added=#{guarded2.added.join ','} kept=#{guarded2.kept.join ','}"
