# Line stepping. Everything that speaks V8's inspector protocol is in this
# file; the renderer asks for a pause, a step, a resume or a value, in the
# app's words, and hears back where the sketch stopped and what it holds.
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
ITEMS       = 200            # members listed when an object is opened

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

describe = (property) ->
  name = property.name
  unless property.value
    return {name, text: '(getter, not run)', getter: yes} if property.get
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

module.exports = (win) ->
  contents = win.webContents
  cdp      = contents.debugger

  wanted   = no          # the buffer holds a breakpoint
  forced   = no          # armed only for a line pause asked for by key
  session  = null        # the sketch worker's flattened session
  enabled  = no          # the Debugger domain is on in that session
  ready    = null        # resolves once it is
  scripts  = new Map     # scriptId -> {url, mapUrl, map}
  stopped  = null        # the pause we are sitting in: {frames, where, seq}
  chase    = null        # a step or pause still looking for a sketch line
  seq      = 0
  devtools = no

  tell = (payload) ->
    contents.send 'debug:event', payload unless contents.isDestroyed()

  send = (method, params = {}) -> cdp.sendCommand method, params, session

  within = (ms, promise) ->
    timer = null
    limit = new Promise (_, reject) ->
      timer = setTimeout (-> reject new Error "timed out after #{ms}ms"), ms
    try
      await Promise.race [promise, limit]
    finally
      clearTimeout timer

  scriptOf = (frame) -> scripts.get frame.location.scriptId

  mapOf = (script) ->
    script.map ?= mapFromUrl script.mapUrl
    script.map

  # Where a frame is in the author's terms, or null if it is not somewhere
  # the author wrote.
  locate = (frame) ->
    script = scriptOf frame
    return null unless script and SKETCH.test script.url
    map = mapOf script
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
    session = null
    enabled = no
    ready   = null
    scripts.clear()
    chase = null
    if stopped
      stopped = null
      tell type: 'resumed'

  # Armed is the Debugger domain on; disarmed is it off. Attachment itself is
  # for good once made: re-attaching to a worker we have let go of leaves
  # Debugger.enable hanging forever (Electron 44), so we never let go --
  # except to DevTools, which gives us no choice.
  enable = ->
    return null unless session
    return ready if enabled
    enabled = yes
    id = session
    ready = do ->
      try
        await within SETUP_LIMIT, do ->
          await cdp.sendCommand 'Debugger.enable', {}, id
          await cdp.sendCommand 'Debugger.setBlackboxPatterns', {patterns: IGNORED}, id
      catch error
        enabled = no if session is id
        tell type: 'problem', text: "debugger: #{error.message}"
      undefined

  disable = ->
    return if stopped or chase or not enabled or not session
    enabled = no
    ready   = null
    send('Debugger.disable').catch ->

  setUp = (id, waiting) ->
    session = id
    scripts.clear()
    stopped = null
    chase   = null
    enabled = no
    ready   = null
    try
      await enable() if wanted or forced
    finally
      # Without this the worker waits for us forever and the app sits on
      # `booting` with nothing said anywhere.
      if waiting
        cdp.sendCommand('Runtime.runIfWaitingForDebugger', {}, id).catch ->

  attach = ->
    return true if cdp.isAttached()
    if devtools
      tell type: 'problem', text: 'breakpoints are off while DevTools is open'
      return false
    try
      cdp.attach '1.3'
      # Answered only after the existing worker, if any, has been attached,
      # so `session` is set by the time this resolves.
      await cdp.sendCommand 'Target.setAutoAttach',
        autoAttach: yes, waitForDebuggerOnStart: yes, flatten: yes
      true
    catch error
      tell type: 'problem', text: "debugger: #{error.message}"
      false

  settle = ->
    if wanted or forced
      return false unless await attach()
      await enable()
      enabled
    else
      disable()
      false

  # `fresh` is for after the prompt has run something. A local scope is a
  # copy V8 took when it paused, so `b = 10` lands in the frame but not in
  # the copy; each local is read again from the frame itself. Enclosing
  # scopes live on the heap and are read directly.
  scopesOf = (frame, fresh = no) ->
    shown = []
    for scope in frame.scopeChain when scope.type in SHOWN
      {result} = await send 'Runtime.getProperties',
        objectId: scope.object.objectId, ownProperties: yes, generatePreview: yes
      # The sketch's own top level carries the wrapper's plumbing, which is
      # also how it is recognised.
      top  = result.some (p) -> p.name is '__image'
      mine = (p for p in result when not p.name.startsWith '__')
      if fresh and scope.type is 'local'
        for p in mine
          {result: value} = await send 'Debugger.evaluateOnCallFrame',
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

  report = (frames) ->
    top   = frames[0]
    where = locate top
    stopped = {frames, where, seq: ++seq}
    tell {type: 'paused', seq, where, scopes: await scopesOf top}

  # Every pause comes through here, wanted or not, and most are not the one to
  # show: the breakpoint's own frame, a helper, our plumbing, or the same line
  # a step started on. Those are stepped past without the renderer hearing.
  onPaused = (params) ->
    frames = params.callFrames
    top    = frames[0]
    script = scriptOf top

    # One frame below the author's line, because that is where the statement
    # is. V8 will not step out of it on its own: it cannot be ignore-listed.
    if script?.url is BREAKPOINT
      return onward 'Debugger.stepOut'

    if chase
      chase.count += 1
      if chase.count < CHASE_LIMIT
        return onward 'Debugger.stepOut' if ours top
        where = locate top
        same  = where and chase.line? and where.line is chase.line and
          frames.length is chase.depth and top.location.scriptId is chase.scriptId
        return onward chase.method if not where or same
    chase = null
    report frames

  onward = (method) ->
    send(method).catch (error) -> tell type: 'problem', text: "debugger: #{error.message}"

  cdp.on 'message', (event, method, params, sessionId) ->
    try
      switch method
        when 'Target.attachedToTarget'
          setUp params.sessionId, params.waitingForDebugger if params.targetInfo.type is 'worker'
        when 'Target.detachedFromTarget'
          resetSession() if params.sessionId is session
        when 'Debugger.scriptParsed'
          if sessionId is session
            scripts.set params.scriptId, {url: params.url, mapUrl: params.sourceMapURL}
        when 'Debugger.paused'
          await onPaused params if sessionId is session
        when 'Debugger.resumed'
          if sessionId is session and stopped
            stopped = null
            tell type: 'resumed'
            # A pause asked for by key armed us for itself alone.
            forced = no unless chase
            settle()
    catch error
      tell type: 'problem', text: "debugger: #{error.message}"

  # Detaching resumes a paused target, so the renderer must hear that too.
  cdp.on 'detach', (event, reason) ->
    resetSession()
    tell type: 'problem', text: "debugger detached: #{reason}" unless devtools or reason is 'target closed'

  # The two cannot both hold the page. DevTools wins, and says so.
  contents.on 'devtools-opened', ->
    devtools = yes
    if cdp.isAttached()
      cdp.detach()
      resetSession()          # which says `resumed` if we were paused
      tell type: 'problem', text: 'breakpoints are off while DevTools is open'
  # The worker we had cannot be attached again (see enable), so breakpoints
  # come back with the next worker, which Run makes.
  contents.on 'devtools-closed', ->
    devtools = no
    tell type: 'problem', text: 'DevTools closed -- breakpoints work again from the next Run' if wanted

  # The renderer's whole vocabulary.
  arm = (want) ->
    wanted = want
    forced = no unless stopped or chase
    armed = await settle()
    # A Stop sets pauses aside so the sketch can unwind; the next run wants
    # them back.
    await send('Debugger.setSkipAllPauses', skip: no).catch(->) if enabled
    armed

  # Suspend now, wherever the sketch is. Arms on demand, since this is the
  # one way in that does not need `breakpoint` in the source.
  pause = ->
    return true if stopped
    forced = yes
    return false unless await settle()
    chase = {method: 'Debugger.stepInto', count: 0}
    await send 'Debugger.pause'
    true

  # To the next line that runs, wherever it is: into a sketch function, back
  # out to its caller, round a loop. The runtime is ignore-listed, so `print`
  # and `buffer.swap` are one step, not a walk through their insides.
  step = ->
    return false unless stopped
    top   = stopped.frames[0]
    where = locate top
    chase =
      method:   'Debugger.stepInto'
      line:     where?.line
      depth:    stopped.frames.length
      scriptId: top.location.scriptId
      count:    0
    await send 'Debugger.stepInto'
    true

  # `skip` is for Stop: the sketch has to run to its next yield point to
  # notice the interrupt, and must not stop at a breakpoint on the way.
  resume = (skip = no) ->
    return false unless enabled
    chase = null
    await send('Debugger.setSkipAllPauses', skip: yes).catch(->) if skip
    return true unless stopped
    await send 'Debugger.resume'
    true

  # The `>` prompt, against the paused frame rather than the image: the
  # author asked about *this* call's `angle`. Assignments reach the frame.
  evaluate = (source) ->
    return null unless stopped
    try
      js = CoffeeScript.compile source, bare: yes
    catch error
      return {error: error.message, kind: 'err'}
    # Bare compilation declares every assigned name with a leading `var`,
    # which inside an evaluation would make a new variable and leave the
    # frame's own untouched -- `angle = 0` would change nothing.
    js = js.replace /^\s*var [^;]*;\s*/, ''
    top = stopped.frames[0]
    {result, exceptionDetails} = await send 'Debugger.evaluateOnCallFrame',
      callFrameId: top.callFrameId, expression: js, generatePreview: yes
    if exceptionDetails
      text = exceptionDetails.exception?.description?.split('\n')[0] ? exceptionDetails.text
      return {text, kind: 'err'}
    # Shown the way the worker shows an answer anywhere else, by the same
    # function, so a paused answer and a running one read alike.
    text = if result.objectId
      shown = await send 'Runtime.callFunctionOn',
        objectId: result.objectId, returnByValue: yes
        functionDeclaration: 'function () { return REPL.show(this) }'
      shown.result?.value ? remoteText result
    else
      remoteText result
    # The answer may have changed what the pane shows, so the pane comes back
    # with it: the author sees `b = 10` land before the prompt is free again.
    {text, kind: 'value', pane: {seq: stopped.seq, where: stopped.where, scopes: await scopesOf top, yes}}

  # Opening an object in the pane. Only while the pause that produced the id
  # is still the one we are in; after a resume the id means nothing.
  members = (pauseSeq, id) ->
    return null unless stopped?.seq is pauseSeq
    {result} = await send 'Runtime.getProperties',
      objectId: id, ownProperties: yes, generatePreview: yes
    # Own enumerable members, plus getters, which are exactly the ones the
    # author needs to see are there and not being run.
    listed = (describe p for p in result when p.name isnt '__proto__' and (p.enumerable or p.get))
    extra  = listed.length - ITEMS
    listed = listed[0...ITEMS]
    listed.push {name: '...', text: "#{extra} more"} if extra > 0
    listed

  id = contents.id
  controllers.set id, {arm, pause, step, resume, evaluate, members}
  win.on 'closed', -> controllers.delete id
  undefined
