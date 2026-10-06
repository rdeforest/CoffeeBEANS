# The user's data directory. Every example is offered exactly once: deleting
# one keeps it deleted, and editing one keeps the player's edit, because the
# manifest records what was offered rather than comparing contents.
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

# Every folder from the root down to `dir`, outermost first.
ancestry = (dir) ->
  up = path.dirname dir
  if up is dir then [dir] else [(ancestry up)..., dir]

# A link on the way to `dir` that points at nothing is refused, never made
# good. It is what a sketches/ on a drive that is not mounted looks like
# (Robert's laptop, 2026-10-05), and creating the folder it names would
# quietly collect new sketches somewhere other than the drive. Checked before
# mkdir rather than read off its failure: on Linux that is a bare ENOENT
# naming the link, not where it points, and what mkdir does with a dangling
# link on macOS and Windows was not checked (Claude, 2026-10-05).
refuseDanglingLink = (dir) ->
  for place in ancestry dir
    try
      stats = await fsp.lstat place
    catch error
      throw error unless error.code is 'ENOENT'
      return                         # from here down is ours to create
    continue unless stats.isSymbolicLink()
    try
      await fsp.stat place
    catch error
      throw error unless error.code is 'ENOENT'
      # From where the link really is: a relative target is followed from
      # there, not from the path as written, which may run through a link
      # above it.
      target = path.resolve (await fsp.realpath path.dirname place), await fsp.readlink place
      throw Object.assign new Error("#{place} is a link to #{target}, which is not there"),
        code: 'EDANGLING', link: place, target: target
  undefined

prepare = (data, examples) ->
  sketches = path.join data, 'sketches'
  await refuseDanglingLink sketches
  await fsp.mkdir sketches, recursive: yes

  manifest = await readManifest data
  # A data directory made before the manifest existed: whatever is already in
  # sketches/ counts as offered, or the next run would clobber edited copies.
  offered = if manifest.found then manifest.names else await coffeeFiles sketches

  # Offered but not yet recorded, which on a pre-manifest directory is
  # everything. A name already on disk is someone's own sketch, so it is
  # recorded as offered without being written over.
  onDisk    = await coffeeFiles sketches
  candidates = (name for name in await coffeeFiles examples when name not in offered)
  fresh      = (name for name in candidates when name not in onDisk)
  await fsp.copyFile path.join(examples, name), path.join(sketches, name) for name in fresh

  if candidates.length or not manifest.found
    await fsp.writeFile path.join(data, MANIFEST), offered.concat(candidates).join('\n') + '\n', 'utf8'

  {sketches, added: fresh, kept: (name for name in candidates when name in onDisk)}

module.exports = {home, prepare, MANIFEST}
