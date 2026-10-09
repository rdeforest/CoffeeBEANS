# Getting the data folder ready before there is a window. What a launch does
# with each kind of folder is checked through data.prepare in this process;
# what the player is shown when that fails is checked by launching a second
# CoffeeBEANS, since this one is already past it.

fsp       = require 'fs/promises'
path      = require 'path'
{spawn}   = require 'child_process'
dataHome  = require '../../src/main/data'

# A link to a folder. A junction on Windows, which needs no privilege there;
# elsewhere the type is ignored. A junction's target must be absolute.
linkTo = (target, link) -> fsp.symlink path.resolve(target), link, 'junction'

exists = (place) -> fsp.stat(place).then (-> yes), (-> no)

# A second app, on its own data folder, until it exits or `limit` runs out.
# BEANS_TEST keeps it off the screen and answering its startup box from
# BEANS_STARTUP_ANSWERS. Should it ever get as far as a window, it runs the
# suite, and BEANS_TESTS naming a part that is not there has the suite print
# "no such part" and exit 1 at once rather than start a second full run --
# the same exit as Quit, so the checks count boxes as well.
launch = (paths, home, answers, more = {}, limit = 20000) -> new Promise (resolve) ->
  env = {process.env..., BEANS_TEST: '1', BEANS_DATA_HOME: home, BEANS_STARTUP_ANSWERS: answers, BEANS_TESTS: 'startup-child', more...}
  child  = spawn process.execPath, [paths.root], {cwd: paths.root, env}
  output = ''
  child.stdout.on 'data', (chunk) -> output += chunk
  child.stderr.on 'data', (chunk) -> output += chunk
  timer = setTimeout (-> child.kill 'SIGKILL'), limit
  # 'close', not 'exit': the child can be gone with its last lines still in
  # the pipe, and those are the boxes being counted.
  child.on 'close', (code, signal) ->
    clearTimeout timer
    resolve {code, signal, output}

# What it printed after `label`, a line each.
printed = (output, label) ->
  line[label.length..] for line in output.split('\n') when line.startsWith label

# The boxes it would have shown, and the folders it would have opened.
boxesIn  = (output) -> JSON.parse box for box in printed output, 'startup box: '
openedIn = (output) -> printed output, 'openPath: '

# How many times `text` appears in `shown`.
countIn = (shown, text) -> shown.split(text).length - 1

module.exports = (t) ->
  {check, paths} = t
  sandbox  = path.join paths.data, 'startup'
  examples = path.join paths.root, 'examples'
  await fsp.mkdir sandbox, recursive: yes

  # A data folder that is not there yet is made, as on a first launch.
  fresh = path.join sandbox, 'fresh'
  made  = await dataHome.prepare fresh, examples
  check 'a missing data folder is created and seeded',
    (await exists path.join fresh, 'sketches', 'hello.coffee') and made.added.length > 0,
    "added #{made.added.length}"

  # sketches/ a link to a folder that is there: used as it is.
  drive  = path.join sandbox, 'drive'
  linked = path.join sandbox, 'linked'
  await fsp.mkdir path.join(drive, 'sketches'), recursive: yes
  await fsp.mkdir linked
  await linkTo path.join(drive, 'sketches'), path.join(linked, 'sketches')
  through = await dataHome.prepare linked, examples
  check 'a sketches link to a real folder is used',
    (await exists path.join drive, 'sketches', 'hello.coffee'),
    "added #{through.added.length} through the link"

  # sketches/ a link to a folder that is not there, on a "drive" that is: an
  # unmounted mount point. Refused, naming both ends, and nothing made.
  gone     = path.join sandbox, 'unmounted', 'sketches'
  dangling = path.join sandbox, 'dangling'
  link     = path.join dangling, 'sketches'
  await fsp.mkdir path.dirname(gone), recursive: yes
  await fsp.mkdir dangling
  await linkTo gone, link
  refused = await dataHome.prepare(dangling, examples).then (-> null), (error) -> error
  check 'a dangling sketches link is refused, naming the link and its target',
    refused?.code is 'EDANGLING' and refused.link is link and refused.target is path.resolve(gone),
    "#{refused?.code}: #{refused?.message}"
  check 'a dangling sketches link is not repaired by creating its target',
    not await exists gone

  # The same folder, launched: a box saying so, Try Again looks again, Quit
  # leaves -- and no unhandled rejection on the way. Before 2026-10-05 this
  # launch sat with no window until the limit killed it.
  {code, signal, output} = await launch paths, dangling, 'Try Again,Quit'
  boxes = boxesIn output
  check 'a dangling sketches link stops the launch with a box, and Quit exits',
    code is 1 and boxes.length is 2 and boxes.every((box) -> box.folder is dangling),
    "exit #{code ? signal}, #{boxes.length} boxes#{if boxes.length then '' else ": #{JSON.stringify output[-400..]}"}"
  check 'the box names where the link points',
    boxes[0]?.message.includes(link) and boxes[0]?.detail.includes(path.resolve gone),
    JSON.stringify boxes[0]?.message
  check 'a launch on a dangling link has no unhandled rejection',
    not /Unhandled/i.test(output), output.match(/.*Unhandled.*/i)?[0] ? ''
  check 'a launch on a dangling link does not create its target',
    not await exists gone

  # Open Folder opens the folder the link is in, and asks again.
  opened = await launch paths, dangling, 'Open Folder,Try Again,Quit'
  asked  = boxesIn opened.output
  check 'Open Folder opens the folder holding the link, then the box comes back',
    opened.code is 1 and asked.length is 3 and openedIn(opened.output).join() is dangling,
    "exit #{opened.code ? opened.signal}, #{asked.length} boxes, opened #{JSON.stringify openedIn opened.output}"

  # A link whose target is relative, below a link: followed from where the
  # link really is, as the system follows it, not from the path as written.
  # Here that is real/sketches; read off the path, home/.local/sketches.
  layout = path.join sandbox, 'relative'
  real   = path.join layout, 'real'
  await fsp.mkdir path.join(real, 'share', 'coffeebeans'), recursive: yes
  await fsp.mkdir path.join(layout, 'home', '.local'), recursive: yes
  await linkTo path.join(real, 'share'), path.join(layout, 'home', '.local', 'share')
  home = path.join layout, 'home', '.local', 'share', 'coffeebeans'
  await fsp.symlink path.join('..', '..', 'sketches'), path.join(home, 'sketches'), 'dir'
  meant = path.join (await fsp.realpath real), 'sketches'
  relative = await launch paths, home, 'Quit'
  named    = boxesIn(relative.output)[0]?.detail ? relative.output[-400..]
  check 'a relative link below another link is named where it really points',
    named.includes("a link to #{meant}."), JSON.stringify named

  # Any other reason the folder cannot be made gets the same box, saying what
  # failed: here sketches is a file.
  blocked = path.join sandbox, 'blocked'
  await fsp.mkdir blocked
  await fsp.writeFile path.join(blocked, 'sketches'), 'not a folder\n', 'utf8'
  other = await launch paths, blocked, 'Quit'
  shown = boxesIn other.output
  check 'any other data folder failure stops the launch with a box saying why',
    other.code is 1 and shown.length is 1 and shown[0].folder is blocked and shown[0].detail.includes(path.join blocked, 'sketches'),
    "exit #{other.code ? other.signal}, #{shown.length} boxes: #{JSON.stringify shown[0]?.detail ? other.output[-400..]}"

  # An exception nobody catches in main. Electron answers it with a modal box
  # that blocks main until somebody clicks it, and a hidden test run has
  # nobody to click: twice on 2026-10-06 one sat on the box until killed. A
  # test run says it and exits 1. Thrown by a fixture NODE_OPTIONS preloads,
  # as soon as the app is ready, ahead of its window. Forward slashes,
  # because NODE_OPTIONS reads a backslash inside quotes as an escape.
  thrower = path.join(paths.root, 'test', 'fixtures', 'throw-in-main.js').split(path.sep).join '/'
  began   = Date.now()
  threw   = await launch paths, path.join(sandbox, 'threw'), '', {NODE_OPTIONS: "--require \"#{thrower}\""}, 15000
  check 'an uncaught exception in main ends a test run, saying so, instead of waiting on a box',
    threw.code is 1 and threw.output.includes('uncaught exception: Error: startup: thrown in main'),
    "exit #{threw.code ? threw.signal} after #{Date.now() - began}ms: #{JSON.stringify threw.output[-400..]}"

  # The same exception in a player's app (Robert, 2026-10-08): said in the
  # window's console, with /reload offered, and the app carries on. The
  # child takes the player's way through BEANS_UNCAUGHT and runs the
  # `uncaught` part, which throws more from main and prints what its console
  # showed at each step. Against the old code it took a test run's exit.
  player  = await launch paths, path.join(sandbox, 'player'), '', {NODE_OPTIONS: "--require \"#{thrower}\"", BEANS_UNCAUGHT: 'player', BEANS_TESTS: 'uncaught'}, 60000
  report  = printed(player.output, 'uncaught: ')[0]
  seen    = try JSON.parse report catch then {}
  tail    = JSON.stringify player.output[-600..]
  offer   = '/reload reloads the window'
  check 'an uncaught exception in main lets a player\'s app carry on, its stack still on the terminal',
    player.code is 0 and report? and not player.output.includes('and saying it failed') and
      player.output.includes('uncaught exception: Error: startup: thrown in main\n') and player.output.includes('throw-in-main.js'),
    "exit #{player.code ? player.signal}: #{tail}"
  check 'one thrown before the window is said there once it is up, offering /reload and saying the app may not work properly',
    countIn(seen.first ? '', 'main: startup: thrown in main') is 1 and
      seen.first.includes(offer) and seen.first.includes('may not work properly'),
    JSON.stringify seen.first ? tail
  check 'one thrown again and again from one place is said once, and only the first of all offers /reload',
    countIn(seen.repeated ? '', 'main: again ') is 1 and countIn(seen.repeated ? '', offer) is 0 and
      (seen.repeated ? '').includes('main: second place'),
    JSON.stringify seen.repeated
  check 'the terminal counts the repeats rather than printing each',
    player.output.includes('uncaught exception, 2 times now: Error: again 2') and
      player.output.includes('uncaught exception, 10 times now: Error: again 10') and
      not player.output.includes('3 times now'),
    tail
  many = seen.many ? ''
  check 'from many places, five are said and then one line says the rest go to the terminal',
    ['place 3', 'place 4'].every((said) -> many.includes "main: #{said}") and
      not ['place 5', 'place 6', 'place 9'].some((said) -> many.includes "main: #{said}") and
      countIn(many, 'the rest go to the terminal only') is 1 and
      player.output.includes('uncaught exception: Error: place 9'),
    JSON.stringify many
  check '/rel does not reload the window; /reload does, and the new page hears the next one afresh, with the offer',
    (seen.slip ? '').includes('/rel is not a command') and seen.reloaded and
      not (seen.after ? '').includes('place 3') and
      countIn(seen.after ? '', 'main: again 21') is 1 and (seen.after ? '').includes(offer),
    JSON.stringify seen.after ? tail
  odd = seen.odd ? ''
  check 'a thrown value that will not go into a string is still said, and the app carries on',
    ['main: [object Object]', 'main: Symbol(odd)', 'main: bad stack'].every((said) -> odd.includes said),
    JSON.stringify odd
  check '/reload after the crash recovery\'s load does not say again that the app crashed',
    seen.crashSaid and seen.crashReloaded and not seen.crashUrl?.includes('crashed') and
      not (seen.crashAfter ? '').includes('the app crashed'),
    JSON.stringify {url: seen.crashUrl, after: seen.crashAfter}

  # Thrown while main.coffee is still loading, before the window is asked
  # for: no console will ever come, so a player's app shows a box of its own
  # and exits. A test run prints the box instead (onDesktop). Early is
  # before mainFailed exists, late after it. Against the first version of
  # this both sat with no window until killed.
  for at in ['early', 'late']
    began  = Date.now()
    loader = await launch paths, path.join(sandbox, "loading-#{at}"), '', {NODE_OPTIONS: "--require \"#{thrower}\"", BEANS_UNCAUGHT: 'player', BEANS_THROW_LOADING: at}, 20000
    shown  = printed(loader.output, 'error box: ')[0]
    boxed  = try JSON.parse shown catch then null
    check "an uncaught exception while main is loading (#{at}) shows a box and exits",
      loader.code is 1 and boxed?.title is 'CoffeeBEANS could not start' and
        boxed.content.includes("startup: thrown while loading") and not loader.output.includes('and saying it failed'),
      "exit #{loader.code ? loader.signal} after #{Date.now() - began}ms: #{JSON.stringify loader.output[-400..]}"
