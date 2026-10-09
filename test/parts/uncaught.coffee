# What a player's app does with an exception nobody catches in main, said
# for its parent to check: the startup part starts a second Electron with
# BEANS_UNCAUGHT=player, so that app takes the player's way instead of a test
# run's exit, and a fixture that throws in main before the window exists.
# The throws below are real ones -- the suite runs in main, so a timer of its
# own that throws is exactly what is being handled -- which is why this runs
# only in that second app: in the suite's own, the first would end the run.
# Makes no check of its own; prints `uncaught: <json>` once, at the end.

module.exports = (t) ->
  {js, waitFor, consoleText, quiet, wait, webContents} = t

  # Thrown from a timer, so nothing in the suite is on the stack to catch it.
  # `place` stands in for where it was thrown from: two errors made on the
  # same line of this file are one place to main unless told apart.
  throwLater = (message, place = 'here') -> setTimeout ->
    error = new Error message
    error.stack = "Error: #{message}\n    at #{place} (uncaught.coffee)"
    throw error

  shows = (text) -> "return document.getElementById('console').textContent.includes(#{JSON.stringify text})"
  seen  = {}

  # Until every throw queued so far has been dealt with by main -- timers of
  # one delay fire in order -- and whatever main said of them has reached the
  # console. Lines are sent as main handles each throw, ahead of quiet's own
  # message to the page, and quiet waits for the console's queue to drain.
  handled = ->
    await new Promise (resolve) -> setTimeout resolve
    await quiet()
    consoleText()

  # From before the window: held, then said once the page listened -- and
  # gone from the console by now, with the first reset (t.booted).
  seen.first = t.booted

  # The same place again and again, as a timer throwing every frame would:
  # said once. The last throw is a different place, for something to wait
  # on: once it is shown, everything before it has been dealt with.
  throwLater "again #{n}", 'loop' for n in [1..20]
  throwLater 'second place', 'second'
  await waitFor shows('second place'), 5000
  seen.repeated = await handled()

  # Many places: said up to the limit, then a line saying the rest are not.
  throwLater "place #{n}", "place#{n}" for n in [3..9]
  await waitFor shows('the rest go to the terminal only'), 5000
  seen.many = await handled()

  # A slip of the name does not reload; the whole name does, and the page
  # that comes up hears the next one afresh, offer and all.
  await js "Prompt.ask('/rel'); return true"
  await waitFor shows('/rel is not a command'), 3000
  seen.slip = await consoleText()
  loaded = new Promise (resolve) -> webContents.once 'did-finish-load', resolve
  await js "setTimeout(() => Prompt.ask('/reload'), 0); return true"
  seen.reloaded = await Promise.race [loaded.then(-> yes), wait(10000).then(-> no)]
  await waitFor shows('CoffeeBEANS '), 10000
  throwLater 'again 21', 'loop'
  await waitFor shows('again 21'), 5000
  seen.after = await consoleText()

  console.log "uncaught: #{JSON.stringify seen}"
