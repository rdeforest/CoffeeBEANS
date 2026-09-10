# The user's data directory. Every example is offered exactly once: deleting
# one keeps it deleted, and editing one keeps your edit, because the manifest
# records what was offered rather than comparing contents.
fsp  = require 'fs/promises'
os   = require 'os'
path = require 'path'

MANIFEST = '.seeded'

home = ->
  return path.resolve process.env.BEANS_DATA_HOME if process.env.BEANS_DATA_HOME
  share = process.env.XDG_DATA_HOME or path.join os.homedir(), '.local', 'share'
  path.join share, 'coffeebeans'

missingIsEmpty = (error, empty) ->
  throw error unless error.code is 'ENOENT'
  empty

coffeeFiles = (dir) ->
  try
    (name for name in await fsp.readdir dir when name.endsWith '.coffee').sort()
  catch error
    missingIsEmpty error, []

readManifest = (dir) ->
  try
    lines = (await fsp.readFile path.join(dir, MANIFEST), 'utf8').split '\n'
    {found: yes, names: (line for line in lines when line)}
  catch error
    missingIsEmpty error, {found: no, names: []}

prepare = (data, examples) ->
  sketches = path.join data, 'sketches'
  await fsp.mkdir sketches, recursive: yes

  manifest = await readManifest data
  # A data directory made before the manifest existed: whatever is already in
  # sketches/ counts as offered, or the next run would clobber edited copies.
  offered = if manifest.found then manifest.names else await coffeeFiles sketches

  fresh = (name for name in await coffeeFiles examples when name not in offered)
  await fsp.copyFile path.join(examples, name), path.join(sketches, name) for name in fresh

  if fresh.length or not manifest.found
    await fsp.writeFile path.join(data, MANIFEST), offered.concat(fresh).join('\n') + '\n', 'utf8'

  {sketches, added: fresh}

module.exports = {home, prepare, MANIFEST}
