# Says what the app came up with (t.launched) and makes no check of its own:
# its parent, the pauseonerror part, starts a second Electron on a data
# folder holding a settings.json of its own to run it, and reads the line.
# The app the suite runs in has long since read its settings, from a folder
# that started empty.

module.exports = (t) ->
  console.log "launched: #{JSON.stringify t.launched}"
