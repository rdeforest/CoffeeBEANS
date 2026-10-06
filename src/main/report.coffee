# The 📣🐞 button's report: drafted here, redacted, shown to the player to
# edit, and saved as a file they attach to an issue themselves. Nothing is
# sent anywhere -- decided by Robert, 2026-10-05.

fsp    = require 'fs/promises'
path   = require 'path'
Redact = require './redact'

# The engine's public home once play testers arrive (Robert, 2026-10-05).
ISSUES = 'https://github.com/thatsnice/CoffeeBEANS/issues'

# What the player brought: their words, the console, the sketch.
told = ({words, lines, sketch}) -> [
  "-- What happened\n#{words.trim() or '(nothing written)'}"
  "-- The last #{lines.length} console lines\n#{lines.join '\n'}"
  if sketch then "-- The sketch, #{sketch.name}.coffee\n#{sketch.text}" else '-- The sketch was not included'
].join '\n\n'

compose = (about, rest) -> "CoffeeBEANS report\n\n-- About\n#{about}\n\n#{rest}\n"

# All of it goes through the redactor, the sketch with it: a sketch can hold
# a path, a key or an address as easily as the console can. About skips the
# user and host names only (see Redact.redactor). `folders` are the ones
# main knows by name, the data folder and the app's own; `who` is there for
# the suite to stand in another machine.
draft = (ask, folders, who = Redact.identity folders) ->
  compose Redact.redactor(who, words: no)(ask.about), Redact.redactor(who) told ask

# Named for the moment it was saved, in UTC: a local time would put the
# player's time zone on the billboard. Colons are not allowed in a Windows
# file name. `wx` so two reports in one millisecond fail rather than one
# silently replacing the other.
save = (folder, text, now = new Date) ->
  await fsp.mkdir folder, recursive: yes
  file = path.join folder, "#{now.toISOString().replaceAll ':', '-'}.txt"
  await fsp.writeFile file, text, encoding: 'utf8', flag: 'wx'
  file

module.exports = {ISSUES, compose, draft, save}
