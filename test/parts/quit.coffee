# Ends the process it runs in and makes no check of its own: its parent, the
# lifecycle part, starts a second Electron on a data folder of its own to run
# it, and reads the disk and the exit once that one has gone.
#
# An edit the autosave has not taken, then Quit (File, or the app menu on
# macOS), the item Cmd-Q reaches; on macOS, what Cmd-Q sends. The save is
# held for BEANS_QUIT_HOLD ms (main's `faults`): 1.5s, as Windows' rename
# retry can hold one, is past the 500ms Chromium waits for a closing page, so
# only main holding the quit for it (will-quit) gets it to disk; a minute
# stands for a save that hangs, which the quit gives up on.

fsp    = require 'fs/promises'
path   = require 'path'
{Menu} = require 'electron'

module.exports = (t) ->
  file = path.join t.paths.sketches, 'quit-edit.coffee'
  await fsp.writeFile file, "print 'OLD'\n", 'utf8'
  await t.js "await Editor.load('quit-edit'); return true"
  await t.setDoc "print 'QUIT'\n"
  t.paths.faults.slow = Number process.env.BEANS_QUIT_HOLD
  # On macOS a quit role is native: click() from here does nothing, and Cmd-Q
  # reaches the app as Cocoa's terminate: action, so that is what is sent.
  # The item must be there either way, or the quit would be unreachable.
  items = Menu.getApplicationMenu().items.flatMap (top) -> top.submenu?.items ? []
  quit  = items.find (item) -> item.role is 'quit'
  throw new Error 'no quit item in the menu' unless quit
  if process.platform is 'darwin'
    Menu.sendActionToFirstResponder 'terminate:'
  else
    quit.click()
  # The suite never gets past this: the app is on its way out.
  await new Promise ->
