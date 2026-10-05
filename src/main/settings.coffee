# What the app remembers about how it is used, as against what is made with
# it. In the data folder rather than the renderer's localStorage because the
# menu shows it, and the menu is built before any page loads; and the data
# folder is the one place BEANS_DATA_HOME already keeps a test run away from
# (decided by Claude, 2026-10-05). Missing means every default.
#
# Its own module so the suite can read a broken file through the same code a
# launch does.

fs   = require 'fs'
path = require 'path'

plainObject = (value) -> value? and Object.getPrototypeOf(value) is Object.prototype

# A settings file that will not parse costs the preferences, not the app. Nor
# does one that parses to something else: `null` would crash the menu, and
# `5` or `"x"` would quietly forget every choice made after it.
read = (file) ->
  try
    found = JSON.parse fs.readFileSync file, 'utf8'
    throw new Error "not an object: #{JSON.stringify found}" unless plainObject found
    found
  catch error
    console.log "settings: #{error.message} -- using the defaults" unless error.code is 'ENOENT'
    {}

# Synchronous, so two clicks in quick succession cannot interleave their
# writes, and the file is on disk before any window hears of the change.
# Staged and renamed into place, as sketch:write does, so a crash mid-write
# leaves the old settings rather than an empty file.
save = (file, settings) ->
  staging = path.join path.dirname(file), ".#{path.basename file}.saving"
  try
    fs.writeFileSync staging, JSON.stringify(settings, null, 2) + '\n', 'utf8'
    fs.renameSync staging, file
  catch error
    console.log "could not save #{file}: #{error.message}"

module.exports = {read, save}
