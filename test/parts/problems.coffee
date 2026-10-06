# Failures nobody asked about -- a rejection in main nobody caught, a
# settings file that will not read or save, a file of the app's own that
# will not load -- said in the console, where a player looks, and not only
# on a terminal a player never sees. The audit behind these is
# docs/research/unhandled-exceptions.md (Claude, 2026-10-06).

fsp      = require 'fs/promises'
path     = require 'path'
Settings = require '../../src/main/settings'

# Main has dealt with every rejection made before this resolves: Node reports
# unhandled ones once the microtasks run out, ahead of the next turn.
nextTurn = -> new Promise (resolve) -> setImmediate resolve

# How many times `text` appears in `shown`.
countIn = (shown, text) -> shown.split(text).length - 1

module.exports = (t) ->
  {check, waitFor, freshPage, consoleText, vimKeys, paths} = t
  {unserved, listening, loadPage} = paths

  # A rejection in main that nothing catches. Before, the terminal had a
  # warning and the window nothing at all.
  Promise.reject new Error 'problems: nobody caught this'
  said = await waitFor "return document.getElementById('console').textContent.includes('nobody caught this')"
  shown = await consoleText()
  check 'an unhandled rejection in main is said in the window console, once',
    said and countIn(shown, 'main: problems: nobody caught this') is 1, JSON.stringify shown

  # A settings file that will not save -- here its staging file is a folder --
  # costs the choice at the next launch, and says so now.
  staging = path.join paths.data, '.settings.json.saving'
  await fsp.mkdir staging
  try
    await vimKeys yes
    unsaved = await waitFor "return document.getElementById('console').textContent.includes('could not save')"
    shown   = await consoleText()
  finally
    await fsp.rm staging, recursive: yes, force: yes
    await vimKeys no
  check 'a settings file that will not save is said in the console',
    unsaved and shown.includes(path.join paths.data, 'settings.json') and shown.includes('lasts until CoffeeBEANS quits'),
    JSON.stringify shown

  # One that will not read is handed to whoever asked; a launch hands it to
  # the console through the same path as the two above.
  broken = path.join paths.data, 'settings-unreadable.json'
  await fsp.writeFile broken, '{"vim": tr', 'utf8'
  heard = []
  read  = Settings.read broken, (text) -> heard.push text
  await fsp.rm broken
  check 'a settings file that will not read says why to whoever asked, and reads as every default',
    JSON.stringify(read) is '{}' and heard.length is 1 and heard[0].startsWith('settings: ') and heard[0].endsWith('using the defaults'),
    JSON.stringify heard

  # A file of the app's own that will not load. Before, the page compiled the
  # 404's body as CoffeeScript, threw before any listener was up, and sat
  # dark with an empty console.
  unserved.add '/src/renderer/help.coffee'
  try
    page = await freshPage """
      const shown = document.getElementById('console').textContent
      return shown.includes('could not start') && {shown, editor: typeof Editor}
    """, 5000
  finally
    unserved.delete '/src/renderer/help.coffee'
  check 'a file of the app that will not load is said in the console, and nothing after it runs',
    page and page.shown.includes('/src/renderer/help.coffee') and page.shown.includes('not found') and page.editor is 'undefined',
    JSON.stringify page

  # A load another overtakes -- View > Reload while the window comes up --
  # fails with ERR_ABORTED, which is no failure and must say nothing; with
  # rejections made visible, it said `main: ERR_ABORTED ...`. Any other
  # failure is said. Handed windows whose loads fail as Electron 44's do
  # (the shape measured by Claude, 2026-10-06): a real overtaken load is
  # not reported to did-fail-load, so the check could not tell it happened.
  failing = (code) ->
    loadURL: -> Promise.reject Object.assign new Error("#{code} (-3) loading 'app://beans/'"), {code}
  await loadPage failing('ERR_ABORTED'), ''
  await loadPage failing('ERR_FAILED'), ''
  await nextTurn()
  await waitFor "return document.getElementById('console').textContent.includes('could not load')"
  shown = await consoleText()
  check 'a window load overtaken by another says nothing; any other failed load is said',
    not shown.includes('ERR_ABORTED') and shown.includes('the window could not load: ERR_FAILED'),
    JSON.stringify shown[-200..]

  # Said while no page is listening -- before the window, or while it reloads
  # -- it waits, and the next page to listen says it, once. Here the window
  # is taken off the list for the length of the check, as a reload would.
  away = [listening...]
  listening.clear()
  try
    Promise.reject new Error 'problems: while nobody listened'
    await nextTurn()
    early = await consoleText()
    later = await freshPage """
      const shown = document.getElementById('console').textContent
      return shown.includes('while nobody listened') && shown
    """
  finally
    listening.add contents for contents in away
  check 'a problem from while no page listened is held, and said once by the next page that does',
    not early.includes('while nobody listened') and countIn("#{later}", 'main: problems: while nobody listened') is 1,
    JSON.stringify {early: early[-200..], later}
