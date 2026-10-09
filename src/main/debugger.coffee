# Line stepping, and stopping on a run's uncaught error. Everything that
# speaks V8's inspector protocol is in this file; the renderer asks for a
# pause, a step, a resume or a value, in the app's words, and hears back
# where the sketch stopped and what it holds. The debugger is armed for every
# run, not on demand as it was before pausing on errors (Robert, 2026-10-05):
# an error can only be stopped on if the Debugger domain is already on when
# it is thrown.
# Nothing raw crosses the bridge -- a renderer that could send arbitrary
# protocol commands could read and write anything in any process we debug.
#
# The facts this is built on were established against a real session in
# Electron 44 and are listed in AGENTS.md. The two that shape it most:
# a page-level auto-attach hands us the sketch worker as a flattened session,
# and `callFrame.url` comes back empty, so scripts are known by id.

{ipcMain} = require 'electron'
CoffeeScript = require 'coffeescript'

SKETCH     = /^beans-run-\d+\.coffee$/
BREAKPOINT = 'beans-breakpoint.js'
BOOT       = '/src/renderer/worker-boot.js'

# Whether a run's uncaught error stops where it was thrown. One switch for the
# app: the Stop on Errors preference sets it (track E2), and so does the
# suite, which turns it off for every part but the one that tests it.
errorStops = yes
pauseState = -> if errorStops then 'uncaught' else 'none'

# The two reasons V8 gives for stopping on something thrown.
THROWN = ['exception', 'promiseRejection']

# Only pause in the author's code. The runtime is one family by design; the
# worker bootstrap and the vendored compiler live under src/renderer/.
# breakpoint.coffee must never match: a debugger skips `debugger` statements
# inside an ignored script, and the command would quietly stop working.
IGNORED = ['^beans-runtime/', '/src/renderer/']

# Scopes worth showing. `global` is the whole worker; `script` is its
# top-level lexical scope, which the bootstrap keeps empty on purpose.
SHOWN = ['local', 'closure', 'block', 'catch']

# CoffeeScript's own helpers that are real functions rather than borrowed
# natives. They are emitted into the sketch's script and mapped to its first
# line, so a step into `a %% b` would otherwise stop on a line that has
# nothing to do with it.
HELPERS = ['modulo', 'boundMethodCheck']

# A step is one JS statement; a CoffeeScript line is often several, and some
# JS has no line of its own. Steps are repeated until the sketch reaches a
# new line -- DevTools does the same over a source map. The cap is for a
# one-line `loop`, which would otherwise never arrive anywhere new.
CHASE_LIMIT = 200

SETUP_LIMIT = 2000

# The debugger is on for every run, so what it keeps per script has to stay
# small for the life of a worker. Every named script keeps its url, which is
# all that says whose code a frame is in: a function a region defined long ago
# can still be called, and must still read as the author's. The source map,
# tens of kilobytes inline in a sketch's script, is fetched from V8 when a
# pause first needs it and kept for the newest MAPS_KEPT; V8 has the source of
# any script a frame is in. Its cache of scripts the heap has let go of is
# unbounded unless told. Both sizes are choices, not measurements.
MAPS_KEPT    = 32
SCRIPT_CACHE = 8 * 1024 * 1024

# How long the prompt may run against a paused frame before V8 is told to
# give up. `Array.from forever()` never returns, and while it runs nothing
# else may reach the worker: a step sent into an evaluation makes V8 pause
# inside JS the inspector itself is running, and the renderer segfaults.
EVAL_LIMIT  = 3000
ITEMS       = 200            # members listed when an object is opened

# The one name an expression of ours looks up in a paused frame; see onParked.
PARKED      = '__beansParked'

# For the suite: called, and waited for, while a pause is being set up and
# before the renderer has heard of it -- 'exception' as an error pause starts,
# 'report' once a pause is numbered -- and, `stopping`, while a Stop has taken
# V8's pause but not yet set breakpoints aside. On its own each window is a
# few milliseconds; a check holds it open to land a Stop, a stale line or a
# step's landing in it. `arming`, the same way, before each arm does its
# work: an arming takes about 4ms (measured by a Claude reviewer,
# 2026-10-06), and the renderer's `arming` is held open to Stop and run again
# inside it. Null outside those checks.
hooks = {pausing: null, stopping: null, arming: null}

# For the suite: the rule EVAL_LIMIT is there for, kept count of. Nothing may
# reach V8 in a session while an evaluation -- ours or the author's -- is
# running there. Under BEANS_TEST every command goes through `watched`, which
# notes each one sent to a session with an evaluation out, and the suite
# checks after every part that none was. Otherwise commands go straight to
# the session and nothing is counted.
EVALUATIONS = ['Debugger.evaluateOnCallFrame', 'Runtime.callFunctionOn']
crossings   = []

watched = (sendCommand) ->
  out = new Map                     # session -> evaluations out in it
  (method, params, id) ->
    held = out.get(id) ? 0
    crossings.push "#{method} sent while #{held} evaluation(s) out" if id and held
    return sendCommand method, params, id unless method in EVALUATIONS
    out.set id, held + 1
    try
      await sendCommand method, params, id
    finally
      out.set id, out.get(id) - 1

# --- source maps ------------------------------------------------------------

BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
DIGIT  = {}
DIGIT[c] = i for c, i in BASE64

vlq = (text) ->
  values = []
  value = shift = 0
  for c in text
    digit  = DIGIT[c]
    value += (digit & 31) << shift
    if digit & 32
      shift += 5
    else
      values.push if value & 1 then -(value >>> 1) else value >>> 1
      value = shift = 0
  values

# Per generated line, [column, source line] pairs in column order. Only the
# fields we use are decoded; the rest are carried along because every field
# in a v3 map is relative to the one before it.
decodeMap = (json) ->
  map   = JSON.parse json
  lines = []
  sourceLine = 0
  for group in map.mappings.split ';'
    column   = 0
    segments = []
    for segment in group.split ',' when segment
      fields = vlq segment
      column += fields[0]
      if fields.length >= 4
        sourceLine += fields[2]
        segments.push [column, sourceLine]
    lines.push segments
  {lines, name: map.sources?[0] ? 'sketch'}

mapFromUrl = (url) ->
  return null unless url?.startsWith 'data:'
  comma = url.indexOf ','
  body  = url[comma + 1..]
  json  = if url[0...comma].endsWith ';base64'
    Buffer.from(body, 'base64').toString 'utf8'
  else
    decodeURIComponent body
  decodeMap json

# The CoffeeScript line for a pause, or null for JS that has none: the
# wrapper's prologue, a harvest, the sketch's closing `finally`. Unlike the
# traceback, this does not walk back to an earlier line -- a line of our own
# plumbing should be stepped through, not shown as the author's.
coffeeAt = (map, line, column) ->
  segments = map.lines[line]
  return null unless segments?.length
  best = segments[0]
  best = segment for segment in segments when segment[0] <= column
  best[1] + 1

# --- values -----------------------------------------------------------------

functionName = (description = '') ->
  /^(?:async\s+)?function\*?\s*([\w$]*)/.exec(description)?[1] or 'anonymous'

previewText = (preview) ->
  shown = for property in preview.properties
    value = switch property.type
      when 'string'   then JSON.stringify property.value
      when 'accessor' then '(getter)'
      when 'function' then '[function]'
      when 'object'
        if property.subtype is 'null' then 'null'
        else if property.subtype is 'array' then '[...]'
        else '{...}'
      else property.value
    if preview.subtype is 'array' then value else "#{property.name}: #{value}"
  shown.push '...' if preview.overflow
  body = shown.join ', '
  if preview.subtype is 'array'
    "[#{body}]"
  else
    named = preview.description isnt 'Object' and not preview.description.startsWith 'Object'
    "#{if named then preview.description + ' ' else ''}{#{body}}"

# What a value reads as in the pane. Never anything that runs code: a getter
# is shown as a getter, because `buffer.swap` draws a frame and `keys.poll`
# claims a keypress, and opening an object must not advance the program.
remoteText = (value) ->
  switch value.type
    when 'undefined' then 'undefined'
    when 'string'    then JSON.stringify value.value
    when 'function'  then "[function #{functionName value.description}]"
    when 'object'
      return 'null' if value.subtype is 'null'
      return value.description if value.subtype is 'typedarray'
      if value.preview then previewText value.preview else value.description
    else value.description ? String value.value

# `owner` is the object a member was listed from, which is what a click on a
# getter needs to run it; a scope's own names have none.
describe = (property, owner) ->
  name = property.name
  unless property.value
    # A symbol-keyed getter cannot be named in the expression that runs it.
    runnable = owner unless property.symbol
    return {name, text: '(getter, not run)', getter: yes, owner: runnable} if property.get
    return {name, text: '(setter only)'}
  value = property.value
  entry = {name, text: remoteText value}
  expandable = value.type is 'object' and value.subtype not in ['null', 'typedarray']
  entry.id = value.objectId if expandable and value.objectId
  entry

# --- the session ------------------------------------------------------------

# One per window, found by the sender of each request, so a renderer can only
# ever drive its own worker. Registered once: ipcMain refuses a second handler
# for a channel, and macOS makes a new window on activate.
controllers = new Map

answer = (channel, verb) ->
  ipcMain.handle channel, (event, args...) ->
    controllers.get(event.sender.id)?[verb] args...

answer 'debug:arm',     'arm'
answer 'debug:pause',   'pause'
answer 'debug:step',    'step'
answer 'debug:resume',  'resume'
answer 'debug:eval',    'evaluate'
answer 'debug:members', 'members'
answer 'debug:getter',  'getter'

module.exports = (win) ->
  contents = win.webContents
  cdp      = contents.debugger

  session  = null        # the sketch worker's flattened session
  target   = null        # that worker's targetId, which outlives the session
  dropped  = null        # the targetId of the worker last let go of; see stale
  enabled  = no          # the Debugger domain is on in that session
  ready    = null        # resolves once it is
  scripts  = new Map     # scriptId -> {url}, for every named script
  maps     = new Map     # scriptId -> decoded source map, newest last
  halted   = null        # V8's pause, its Debugger.paused params, until we move it on
  stopped  = null        # the pause the renderer is shown: {frames, where, seq}
  chase    = null        # a step or pause still looking for a sketch line
  asking   = null        # JS run in the paused worker -- the prompt's, a getter's, ours -- while it runs
  skipped  = no          # a Stop told V8 to skip every pause in this session
  left     = null        # settles once the session we are on has gone; see takeTurn
  leave    = null        # which settles it
  seq      = 0
  devtools = no

  tell = (payload) ->
    contents.send 'debug:event', payload unless contents.isDestroyed()

  command = (method, params, id) -> cdp.sendCommand method, params, id
  command = watched command if process.env.BEANS_TEST

  # For one command, sent straight after a check made in the same tick.
  send = (method, params = {}) -> command method, params, session

  # Commands for the session current when it is made, refused once that has
  # gone. Work that takes several round trips -- setting a pause up, the
  # prompt's line, a getter, a Stop -- talks through one made as it starts:
  # a Run or a detach can move us to another worker between any two of its
  # commands, and the next one used to land in that worker regardless, maybe
  # in the middle of its own evaluation (a reviewer of cbe904b, 2026-10-06:
  # a replaced worker's line sent REPL.show into the next one's, 3 of 3).
  speaker = ->
    mine = session
    talk = (method, params = {}) ->
      return Promise.reject new Error 'the worker has gone' unless talk.live()
      command method, params, mine
    talk.live = -> mine? and session is mine
    talk

  # `send` once no turn is out. The check and the send are one step: an
  # await between them would leave a gap for a turn to start in.
  whenFree = (work) ->
    await asking.catch(->) while asking
    work()

  # For a command whose failure nobody else hears. Failed because its session
  # has gone is the session going, not news.
  sayUnlessGone = (talk) -> (error) ->
    tell type: 'problem', text: "debugger: #{error.message}" if talk.live()

  within = (ms, promise) ->
    timer = null
    limit = new Promise (_, reject) ->
      timer = setTimeout (-> reject new Error "timed out after #{ms}ms"), ms
    try
      await Promise.race [promise, limit]
    finally
      clearTimeout timer

  scriptOf = (frame) -> scripts.get frame.location.scriptId

  # A command to a worker that has gone -- shot by Stop's deadline, replaced by
  # a Run -- is never answered (measured by a reviewer of 1389d44, 2026-10-06:
  # a setup stuck in a thrown object's getter held the turn for good, and
  # every later Stop and switch of error stops waited on it). So a turn ends
  # with the session it was taken in, answered or not, and comes back empty:
  # our own calls then fail, and the prompt and a getter say it moved on. The
  # prompt's own evaluation is not stranded that way -- V8 still answers it,
  # at EVAL_LIMIT at the latest, after a Run (the same reviewer, of cbe904b)
  # -- but by then its turn is over, so what it does next goes through its
  # speaker, which refuses.
  takeTurn = (work) ->
    turn = asking = Promise.race [work, left]
    try
      await turn
    finally
      asking = null if asking is turn

  sessionGone = ->
    asking  = null
    skipped = no
    leave?()
    left = new Promise (resolve) -> leave = resolve

  sessionGone()

  # Whether V8 is still halted in this pause. Setting a pause up takes several
  # round trips, and a Stop or a Run can end it in any of them; work for a
  # pause that is over goes no further, and its V8 commands, sent after the
  # resume, fail -- that failure is the pause being over, not news.
  current = (halt) -> halted is halt

  # Only scripts with a name. The prompt's lines and our own evaluations have
  # none and come several to a line typed; unknown reads as ours everywhere,
  # which is what they are.
  remember = ({scriptId, url}) ->
    scripts.set scriptId, {url} if url

  # The map is the script's own sourceMappingURL comment, which V8 hands back
  # with the rest of its source.
  mapOf = (talk, scriptId) ->
    unless maps.has scriptId
      {scriptSource} = await talk 'Debugger.getScriptSource', {scriptId}
      maps.set scriptId, mapFromUrl /\/\/# sourceMappingURL=(\S+)\s*$/.exec(scriptSource)?[1]
      maps.delete old for old in [...maps.keys()][...-MAPS_KEPT]
    maps.get scriptId

  # Where a frame is in the author's terms, or null if it is not somewhere
  # the author wrote.
  locate = (talk, frame) ->
    script = scriptOf frame
    return null unless script and SKETCH.test script.url
    map = await mapOf talk, frame.location.scriptId
    return null unless map
    line = coffeeAt map, frame.location.lineNumber, frame.location.columnNumber
    return null unless line?
    fn = frame.functionName
    fn = null if not fn or fn is 'eval'
    {line, name: map.name, fn}

  # A helper is one line: its body sits on the line that declares it. No
  # function CoffeeScript writes for the author ever looks like that.
  inHelper = (frame) ->
    frame.functionName in HELPERS and
      frame.functionLocation?.lineNumber is frame.location.lineNumber

  # Code that is ours rather than the author's, whoever called it: the
  # runtime, the bootstrap, the compiled prompt line, and the two closures the
  # wrapper hands the prompt. Stepping *into* from here never stops on the way
  # back to the sketch -- V8 only stops a step-in on a call -- so these are
  # stepped *out* of, which V8 carries past every ignore-listed frame.
  ours = (frame) ->
    script = scriptOf frame
    return true unless script and SKETCH.test script.url
    inHelper(frame) or frame.functionName in ['harvest', 'restore']

  resetSession = ->
    sessionGone()
    session = null
    enabled = no
    ready   = null
    halted  = null
    scripts.clear()
    maps.clear()
    chase = null
    if stopped
      stopped = null
      tell type: 'resumed'

  # Armed is the Debugger domain on; disarmed is it off. Attachment itself is
  # for good once made: re-attaching to a worker we have let go of leaves
  # Debugger.enable hanging while that worker is busy (Electron 44), so we
  # never let go -- except to DevTools, which gives us no choice.
  #
  # That worker is attached again with the next attach, which Target's
  # auto-attach makes for whatever worker is there, but never enabled: the
  # first Run after DevTools closed, made over a sketch still running, sat at
  # `arming` for SETUP_LIMIT and said the debugger had timed out (found by a
  # Claude review of I1, 2026-10-06). Breakpoints and error stops come back
  # with the next worker, as devtools-closed says. A worker born while
  # DevTools held the page was never ours to let go of, and is enabled as
  # any other; with a real DevTools, which attaches it too, that is untested.
  #
  # `target` is kept when the session goes: letting go reports
  # Target.detachedFromTarget, which resets the session, before either caller
  # of dropSession runs (seen by Claude in the suite, 2026-10-06).
  stale = -> session? and target is dropped

  dropSession = ->
    dropped = target
    resetSession()

  enable = ->
    return null if not session or stale()
    return ready if enabled
    enabled = yes
    mine = session
    ready = do ->
      try
        await within SETUP_LIMIT, do ->
          await command 'Debugger.enable', {maxScriptsCacheSize: SCRIPT_CACHE}, mine
          await command 'Debugger.setBlackboxPatterns', {patterns: IGNORED}, mine
          await command 'Debugger.setPauseOnExceptions', {state: pauseState()}, mine
      catch error
        enabled = no if session is mine
        tell type: 'problem', text: "debugger: #{error.message}"
      undefined

  # The switch, flipped while this session is live.
  exceptions = ->
    return unless enabled and session
    await ready
    # The session current once the turn is free: a setting, not a step in
    # anyone's work, and a new session takes it as it is enabled anyway.
    await whenFree(-> send 'Debugger.setPauseOnExceptions', state: pauseState() if session).catch (error) ->
      tell type: 'problem', text: "debugger: #{error.message}"

  setUp = (id, waiting, targetId) ->
    sessionGone()
    session = id
    target  = targetId
    talk    = speaker()
    scripts.clear()
    maps.clear()
    halted  = null
    stopped = null
    chase   = null
    enabled = no
    ready   = null
    try
      await enable()
    finally
      # Without this the worker waits for us forever and the app sits on
      # `booting`. If it fails, that is said: until 2026-10-06 the failure
      # was dropped, and the app sat on `booting` with nothing said anywhere
      # (found by a Claude review of main at 404fb07). Sent to the worker
      # whether or not it is still current; said only if it is.
      if waiting
        command('Runtime.runIfWaitingForDebugger', {}, id).catch sayUnlessGone talk

  attach = ->
    return true if cdp.isAttached()
    if devtools
      tell type: 'problem', text: 'breakpoints and error stops are off while DevTools is open'
      return false
    try
      cdp.attach '1.3'
      # Answered only after the existing worker, if any, has been attached,
      # so `session` is set by the time this resolves.
      await command 'Target.setAutoAttach',
        autoAttach: yes, waitForDebuggerOnStart: yes, flatten: yes
      true
    catch error
      tell type: 'problem', text: "debugger: #{error.message}"
      false

  settle = ->
    return false unless await attach()
    await enable()
    enabled

  # `fresh` is for after the prompt has run something. A local scope is a
  # copy V8 took when it paused, so `b = 10` lands in the frame but not in
  # the copy; each local is read again from the frame itself. Enclosing
  # scopes live on the heap and are read directly.
  scopesOf = (talk, frame, fresh = no) ->
    shown = []
    for scope in frame.scopeChain when scope.type in SHOWN
      {result} = await talk 'Runtime.getProperties',
        objectId: scope.object.objectId, ownProperties: yes, generatePreview: yes
      # The sketch's own top level carries the wrapper's plumbing, which is
      # also how it is recognised.
      top  = result.some (p) -> p.name is '__image'
      mine = (p for p in result when not p.name.startsWith '__')
      if fresh and scope.type is 'local'
        for p in mine
          {result: value} = await talk 'Debugger.evaluateOnCallFrame',
            callFrameId: frame.callFrameId, expression: p.name,
            throwOnSideEffect: yes, generatePreview: yes
          p.value = value if value
      vars = (describe p for p in mine)
      title = if top
        'sketch'
      else if scope.type is 'local'
        frame.functionName or 'sketch'
      else
        scope.name or scope.type
      shown.push {title, vars} if vars.length or scope.type is 'local'
    shown

  # `at` is the frame to show: the top one, except at an error thrown inside
  # the runtime, where it is the first one the author wrote. `error` is the
  # report the run would have made, for an error pause.
  #
  # `owner` is which worker stopped (H.OWNER, which start() in the renderer
  # bumps before a new one boots), so the renderer can drop the pause of a
  # worker a Run has already replaced.
  #
  # The renderer learns the pause's number only once every V8 command for it
  # here has been answered, so a line or a listing naming it never lands in
  # the middle of them. A Stop does not need the number: it goes by `halted`.
  report = (talk, halt, at = 0, error = null) ->
    frames = halt.callFrames
    top    = frames[at]
    here   = stopped = {frames, at, where: null, error, seq: ++seq}
    await hooks.pausing 'report' if hooks.pausing
    here.where = await locate talk, top
    return unless current halt
    owner = await ownerOf talk, top
    return unless current halt
    scopes = await scopesOf talk, top
    return unless current halt
    tell {type: 'paused', seq: here.seq, owner, where: here.where, error, scopes}

  # The frame a pause shows, and the one the prompt and the pane work in.
  pausedFrame = -> stopped.frames[stopped.at]

  # A run's own error comes up through the worker's dispatch of it; one thrown
  # once the run is over -- a timer, a promise callback, after an await -- has
  # nothing of the bootstrap beneath it. See dispatchRun in worker-boot.js.
  inRun = (frames) ->
    frames.some (frame) -> frame.functionName is 'dispatchRun' and scriptOf(frame)?.url?.endsWith BOOT

  # JS of ours run in the paused worker while a pause is set up. It takes the
  # prompt's turn, so a Stop landing meanwhile waits for it rather than
  # sending a resume into running JS: a step sent into a running evaluation
  # segfaults the renderer (AGENTS.md), and a resume has not been shown to be
  # any safer.
  callInPause = (work) ->
    reply = await takeTurn work
    throw new Error 'the worker has gone' unless reply
    reply

  # JS run on a value we hold an id for, bounded. Only evaluateOnCallFrame can
  # be told to give up (Runtime.callFunctionOn has no timeout), and it takes
  # an expression, not a value. So the value is parked on the worker's global
  # first, and the expression takes it off again before it runs anything of
  # the author's -- `body`, which names it `v` and the global `home`. If the
  # evaluation fails for any reason but being given up on, the value stays
  # parked there, which is harmless: nothing reads it, and the next worker
  # starts without it.
  #
  # The expression runs in the author's scope, so it looks nothing up by name
  # but PARKED: it named `globalThis` once, and a sketch's own `globalThis`
  # -- a parameter, or a top-level one kept in the image -- turned every
  # pause into "could not pause" (a reviewer of 5d16bc3, 2026-10-06). The
  # parking itself runs on the global, `this`, where no sketch name reaches.
  # A sketch could still name a variable PARKED; names starting `__` are the
  # wrapper's plumbing (`__image`, `__frames`), which the pane hides too, and
  # a sketch that takes one has reached into it.
  onParked = (talk, frame, value, body, more = {}) ->
    global = frame.scopeChain.find (scope) -> scope.type is 'global'
    await talk 'Runtime.callFunctionOn',
      objectId: global.object.objectId, arguments: [value]
      functionDeclaration: "function (v) { this.#{PARKED} = {v, home: this} }"
    talk 'Debugger.evaluateOnCallFrame', {
      callFrameId: frame.callFrameId, throwOnSideEffect: no, timeout: EVAL_LIMIT
      expression: "(function ({v, home}) { delete home.#{PARKED}; return #{body} })(#{PARKED})"
      more...
    }

  # REPL is on the worker's global, where a sketch can clobber it. Unread,
  # the owner would be undefined and the renderer would drop a live worker's
  # pause as a replaced one's, leaving it halted with nothing said. Read in
  # the frame, bounded, since a sketch could as well make it a getter that
  # never returns -- which is why REPL is read by `body`, not by the parking.
  ownerOf = (talk, frame) ->
    {result, exceptionDetails} = await callInPause onParked talk, frame, {value: null},
      'home.REPL.owner', returnByValue: yes
    throw new Error exceptionDetails.exception?.description ? exceptionDetails.text if exceptionDetails
    # Replaced rather than nulled, REPL reads without a murmur.
    throw new Error "REPL.owner reads #{typeof result.value}, not a number" unless typeof result.value is 'number'
    result.value

  # The first frame the author wrote, innermost first, or -1.
  authorsFrame = (talk, frames) ->
    for frame, depth in frames when not ours(frame) and await locate talk, frame
      return depth
    -1

  # A thrown value as an argument: by reference if it is an object, by value
  # if not -- `throw 'oops'` comes back as a primitive with no objectId.
  argumentFor = (thrown) ->
    return {objectId: thrown.objectId} if thrown.objectId
    return {unserializableValue: thrown.unserializableValue} if thrown.unserializableValue
    {value: thrown.value}

  # The report the run would have made, asked of the worker, so an error that
  # stops and one that just ends the run say the same thing. Bounded: making
  # it reads the thrown value, which can be the author's object with getters
  # of its own.
  failureOf = (talk, thrown, frame) ->
    {result, exceptionDetails} = await callInPause onParked talk, frame, argumentFor(thrown),
      'home.REPL.failure(v)', returnByValue: yes
    throw new Error exceptionDetails.exception?.description ? exceptionDetails.text if exceptionDetails
    result.value

  # Where a run's uncaught error stops, frame live. Everything else V8 stops
  # on for a throw goes straight on, the renderer never hearing of it, to be
  # reported the ordinary way: a Stop's Interrupted, which is the sketch
  # being let go; a rejection, which never ends a run; an error thrown after
  # the run ended, which Robert decided is reported and never stopped on
  # (2026-10-05); and one with nothing of the author's on the stack, ours.
  #
  # A Run while the worker is asked replaces the session, and a Stop resumes
  # V8; either way the pause is over (`current`), and reported it would land
  # in the new run's console or over the Stop.
  onException = (talk, halt) ->
    frames = halt.callFrames
    goOn   = not errorStops or halt.reason isnt 'exception' or
      halt.data?.className is 'Interrupted' or not inRun frames
    return onward (chase?.method ? 'Debugger.resume') if goOn
    try
      await hooks.pausing 'exception' if hooks.pausing
      at = await authorsFrame talk, frames
      return unless current halt
      return onward (chase?.method ? 'Debugger.resume') if at < 0
      chase = null
      failure = await failureOf talk, halt.data, frames[at]
      return unless current halt
      # A thrown string or number has no stack to find its line in; the
      # pause knows it.
      failure.line ?= (await locate talk, frames[at]).line
      return unless current halt
      await report talk, halt, at, failure
    catch error
      return unless current halt
      letGo 'stop at the error', error

  # A pause that could not be set up is let go and said. Left halted, the
  # renderer, never told of it, could neither show it nor continue it, and
  # only Stop would get the sketch back. An error then ends its run the
  # ordinary way, reported by the worker as it would have been with error
  # stops off.
  letGo = (what, error) ->
    stopped = null
    chase   = null
    tell type: 'problem', text: "debugger: could not #{what} -- #{error.message.split('\n')[0]}"
    onward 'Debugger.resume'

  # Every pause comes through here, wanted or not, and most are not the one to
  # show: the breakpoint's own frame, a helper, our plumbing, or the same line
  # a step started on. Those are stepped past without the renderer hearing.
  # Whatever it takes to find out, it asks of this pause's own session.
  onPaused = (halt) ->
    talk = speaker()
    return onException talk, halt if halt.reason in THROWN
    frames = halt.callFrames
    top    = frames[0]
    script = scriptOf top

    # One frame below the author's line, because that is where the statement
    # is. V8 will not step out of it on its own: it cannot be ignore-listed.
    if script?.url is BREAKPOINT
      return onward 'Debugger.stepOut'

    try
      if chase
        chase.count += 1
        if chase.count < CHASE_LIMIT
          return onward 'Debugger.stepOut' if ours top
          where = await locate talk, top
          return unless current halt
          same  = where and chase.line? and where.line is chase.line and
            frames.length is chase.depth and top.location.scriptId is chase.scriptId
          return onward chase.method if not where or same
      chase = null
      await report talk, halt
    catch error
      return unless current halt
      letGo 'pause', error

  onward = (method) ->
    halted = null
    send(method).catch (error) -> tell type: 'problem', text: "debugger: #{error.message}"

  cdp.on 'message', (event, method, params, sessionId) ->
    try
      switch method
        when 'Target.attachedToTarget'
          {targetInfo} = params
          setUp params.sessionId, params.waitingForDebugger, targetInfo.targetId if targetInfo.type is 'worker'
        when 'Target.detachedFromTarget'
          resetSession() if params.sessionId is session
        when 'Debugger.scriptParsed'
          remember params if sessionId is session
        when 'Debugger.paused'
          if sessionId is session
            halted = params
            await onPaused params
        when 'Debugger.resumed'
          halted = null if sessionId is session
          if sessionId is session and stopped
            stopped = null
            tell type: 'resumed'
    catch error
      tell type: 'problem', text: "debugger: #{error.message}"

  # Detaching resumes a paused target, so the renderer must hear that too,
  # and that the debugger is not armed any more, so its next run arms first
  # (armFirst in the renderer).
  cdp.on 'detach', (event, reason) ->
    dropSession()
    tell type: 'detached'
    tell type: 'problem', text: "debugger detached: #{reason}" unless devtools or reason is 'target closed'

  # The two cannot both hold the page. DevTools wins, and says so. The
  # renderer hears it is disarmed, so the next Run arms again, and the one
  # after DevTools closes attaches.
  contents.on 'devtools-opened', ->
    devtools = yes
    tell type: 'detached'
    if cdp.isAttached()
      cdp.detach()
      dropSession()           # which says `resumed` if we were paused
      tell type: 'problem', text: 'breakpoints and error stops are off while DevTools is open'
  # The worker we had is never enabled again (see stale), so breakpoints
  # come back with the next worker, which Run makes.
  contents.on 'devtools-closed', ->
    devtools = no
    tell type: 'problem', text: 'DevTools closed -- breakpoints and error stops work again from the next Run'

  # The renderer's whole vocabulary.
  arm = ->
    await hooks.arming() if hooks.arming
    armed = await settle()
    # A Stop sets pauses aside so the sketch can unwind; the next run wants
    # them back. Only then, and never into a turn: every arm used to send
    # this, and an arm made while the prompt's endless line was out sent it
    # into that line (a reviewer of cbe904b, 2026-10-06).
    if enabled and skipped
      skipped = no
      talk    = speaker()
      await whenFree(-> talk 'Debugger.setSkipAllPauses', skip: no).catch sayUnlessGone talk
    armed

  # Suspend now, wherever the sketch is. The debugger is armed already for
  # every run; settle only says whether it is (not while DevTools has it).
  #
  # In the session current when asked, or not at all: a pause still being
  # set up can hold the turn for seconds, and a Run in that time used to have
  # this pause the new worker at its first line, or leave `chase` set for
  # whatever paused next (found by a Claude review of main at 404fb07).
  # There may be no session yet when asked -- after DevTools, until settle
  # attaches -- so the speaker is taken once settle has made one: taken
  # before, the first Ctrl-\ after DevTools closed always failed (found by a
  # Claude review of I1, 2026-10-06).
  #
  # Answers true, false, or 'stale' for a worker we let go of (see stale).
  pause = ->
    return true if stopped
    asked = session
    armed = await settle()
    return false if asked? and asked isnt session
    return 'stale' if stale()
    return false unless armed
    talk = speaker()
    # A pause still being set up can be running JS of ours in the worker.
    await whenFree ->
      return true if stopped
      return false unless talk.live()
      # Set before the command, as it always was: which arrives first, the
      # pause or the command's answer, is not known.
      chase = mine = {method: 'Debugger.stepInto', count: 0}
      talk('Debugger.pause').then (-> true), (error) ->
        chase = null if chase is mine
        sayUnlessGone(talk) error
        false

  # To the next line that runs, wherever it is: into a sketch function, back
  # out to its caller, round a loop. The runtime is ignore-listed, so `print`
  # and `buffer.swap` are one step, not a walk through their insides.
  #
  # Not from an error, decided by Claude for Robert to overrule (2026-10-05):
  # nothing catches it, so the next line that runs is never the author's --
  # the run can only unwind and end. The prototype made Step a Continue
  # there, which ends the run under a key that means "one line"; refused,
  # the renderer says why and Continue does it on purpose.
  step = ->
    return false unless stopped
    return 'evaluating' if asking
    return 'error' if stopped.error
    # The pause's own where, not located again: an await here would leave a
    # gap for the prompt to start an evaluation the step then lands in. A
    # step is never from an error pause, so the frame shown is the top one.
    top   = stopped.frames[0]
    where = stopped.where
    chase =
      method:   'Debugger.stepInto'
      line:     where?.line
      depth:    stopped.frames.length
      scriptId: top.location.scriptId
      count:    0
    halted = null
    await send 'Debugger.stepInto'
    true

  # `skip` is for Stop: the sketch has to run to its next yield point to
  # notice the interrupt, and must not stop at a breakpoint on the way.
  #
  # By V8's own state, not by whether the renderer has been shown the pause:
  # a Stop can land while an error pause is still being set up, and went
  # nowhere when this asked `stopped` -- V8 stayed halted until Stop's
  # deadline shot the worker, blaming a missing yield point.
  #
  # Each wait for the turn is followed by its command in the same tick, so no
  # turn can start between the two.
  resume = (skip = no) ->
    return false unless enabled
    return 'evaluating' if asking and not skip
    talk = speaker()
    # Stop has to get through, so it waits out the evaluation, which
    # EVAL_LIMIT bounds; anything else is the author's to retry. Waited out
    # until none is left: setting a pause up runs one after another.
    await asking.catch(->) while asking
    # A worker gone meanwhile took its pause with it, and this Stop is done.
    return true unless talk.live()
    # Over from here, before anything else is awaited: a pause still being set
    # up sees that and starts nothing more in the worker.
    was    = halted
    halted = null
    chase  = null
    if skip
      await hooks.stopping() if hooks.stopping
      # The renderer is told here, not left to assume it from having asked.
      # A Stop waiting out the prompt's line sets this seconds after it was
      # pressed, and an arm in between -- a Run, or then an edit adding or
      # removing `breakpoint` -- found nothing to take back; the renderer then
      # thought nothing was skipped, and the next run went past its
      # breakpoint without a word (a reviewer of E1, 2026-10-06).
      skipped = yes
      tell type: 'skipping'
      await whenFree(-> talk 'Debugger.setSkipAllPauses', skip: yes).catch sayUnlessGone talk
      # A step sent just before the Stop can land while that was out; its
      # pause, set up or still being set up, is let go as well.
      await asking.catch(->) while asking
      return true unless talk.live()
      was   or= halted
      halted  = null
    await talk 'Debugger.resume' if was
    true

  # The `>` prompt, against the paused frame rather than the image: the
  # author asked about *this* call's `angle`. Assignments reach the frame.
  # Only in the pause it was typed at, as with a getter: a line sent before
  # the renderer heard a step had begun, or that pause was over, must not
  # land in the next one, possibly while it is still being set up.
  evaluate = (pauseSeq, source) ->
    return null unless stopped?.seq is pauseSeq and not chase
    return {text: '*** still evaluating the last line ***', kind: 'sys'} if asking
    takeTurn answerFor speaker(), source

  answerFor = (talk, source) ->
    try
      js = CoffeeScript.compile source, bare: yes
    catch error
      return {text: error.message, kind: 'err'}
    # Bare compilation declares every assigned name with a leading `var`,
    # which inside an evaluation would make a new variable and leave the
    # frame's own untouched -- `angle = 0` would change nothing.
    js = js.replace /^\s*var [^;]*;\s*/, ''
    here = stopped
    top  = pausedFrame()
    try
      {result, exceptionDetails} = await talk 'Debugger.evaluateOnCallFrame',
        callFrameId: top.callFrameId, expression: js, generatePreview: yes, timeout: EVAL_LIMIT
    catch error
      throw error unless /terminated/.test error.message
      return {text: "*** gave up after #{EVAL_LIMIT / 1000}s -- does it ever finish? ***", kind: 'err'}
    if exceptionDetails
      text = exceptionDetails.exception?.description?.split('\n')[0] ? exceptionDetails.text
      return {text, kind: 'err'}
    # Shown the way the worker shows an answer anywhere else, by the same
    # function, so a paused answer and a running one read alike. Showing it
    # can run the author's code -- a Proxy's traps, a getter -- so it is
    # bounded too: unbounded, a trap that looped held the turn, and every
    # Stop with it, for good (a reviewer of cbe904b, 2026-10-06).
    text = remoteText result
    if result.objectId
      try
        shown = await onParked talk, top, {objectId: result.objectId}, 'home.REPL.show(v)', returnByValue: yes
        text = shown.result.value ? text unless shown.exceptionDetails
      catch error
        throw error unless /terminated/.test error.message
        text += " -- gave up showing it after #{EVAL_LIMIT / 1000}s"
    # The answer may have changed what the pane shows, so the pane comes back
    # with it: the author sees `b = 10` land before the prompt is free again.
    {text, kind: 'value', pane: {seq: here.seq, where: here.where, scopes: await scopesOf talk, top, yes}}

  # Opening an object in the pane. Only while the pause that produced the id
  # is still the one we are in; after a resume the id means nothing. Not while
  # an evaluation is out either: nothing may reach V8 until it is back.
  members = (pauseSeq, id) ->
    return null unless stopped?.seq is pauseSeq
    return 'evaluating' if asking
    # Bounded like an evaluation, though nothing of the author's runs: the
    # renderer holds step, continue and the prompt until every listing is in,
    # so one that never answered -- the worker torn down by a Run, DevTools
    # taking the session -- would hold them for good.
    {result} = await within EVAL_LIMIT, send 'Runtime.getProperties',
      objectId: id, ownProperties: yes, generatePreview: yes
    # Own enumerable members, plus getters, which are exactly the ones the
    # author needs to see are there and not being run.
    listed = (describe p, id for p in result when p.name isnt '__proto__' and (p.enumerable or p.get))
    extra  = listed.length - ITEMS
    listed = listed[0...ITEMS]
    listed.push {name: '...', text: "#{extra} more"} if extra > 0
    listed

  # A getter the author clicked in the pane, run once. It is an evaluation in
  # the paused frame like the prompt's, so it takes the same turn -- step,
  # continue and the prompt are refused while it runs, Stop waits it out --
  # and the same limit. A step already on its way means the pause it was
  # clicked in is over.
  getter = (pauseSeq, owner, name) ->
    return null unless stopped?.seq is pauseSeq and not chase
    return 'evaluating' if asking
    takeTurn runGetter speaker(), owner, name

  # Bounded by onParked. Whatever happens, the pane comes back with the
  # answer: a getter can change what the rest of it shows.
  runGetter = (talk, owner, name) ->
    here  = stopped
    top   = pausedFrame()
    reply = await getterValue talk, top, owner, name
    reply.pane = {seq: here.seq, where: here.where, scopes: await scopesOf talk, top, yes}
    reply

  # Thrown and given up read as errors, said in the pane's voice rather than
  # the console's.
  getterValue = (talk, top, owner, name) ->
    try
      {result, exceptionDetails} = await onParked talk, top, {objectId: owner},
        "v[#{JSON.stringify name}]", generatePreview: yes
    catch error
      throw error unless /terminated/.test error.message
      return {text: "gave up after #{EVAL_LIMIT / 1000}s", kind: 'err'}
    if exceptionDetails
      thrown = exceptionDetails.exception?.description?.split('\n')[0] ? exceptionDetails.text
      return {text: "threw #{thrown}", kind: 'err'}
    {text: remoteText(result), kind: 'value'}

  id = contents.id
  kept = -> {scripts: scripts.size, maps: maps.size}
  controllers.set id, {arm, pause, step, resume, evaluate, members, getter, exceptions, kept}
  win.on 'closed', -> controllers.delete id
  undefined

# Not a channel: the renderer cannot reach it, only main (the preference) and
# the suite. Resolves once every live session has it.
module.exports.stopOnErrors = (stop) ->
  errorStops = Boolean stop
  await Promise.all (controller.exceptions() for controller from controllers.values())
  errorStops

# For the suite: the switch as it stands, without moving it.
module.exports.errorStops = -> errorStops

module.exports.hooks = hooks

# For the suite: how many scripts and source maps each live session is keeping.
module.exports.kept = -> (controller.kept() for controller from controllers.values())

# For the suite: every command sent into a running evaluation so far (see
# `watched`). Always empty outside BEANS_TEST.
module.exports.crossings = -> crossings[..]
