# A standalone probe for docs/research/pause-on-error.md (Claude, 2026-10-05).
# Not the app: a page, a worker shaped like worker-boot.js in three ways, and
# a main process speaking the same CDP the app's debugger.coffee speaks. It
# answers what V8 itself does -- which exceptions pause, where, with what --
# and what each arrangement costs a sketch that throws and catches.
#
#   flock .../tmp/suite.lock electron research/pause-on-error/probe > out 2>&1
#
# PROBE_PART=semantics|cost|all (default all). Prints one JSON line per result.

{app, BrowserWindow} = require 'electron'
fs   = require 'fs'
path = require 'path'

HERE    = __dirname
LIB     = fs.readFileSync path.join(HERE, 'lib.js'),  'utf8'
BOOT    = fs.readFileSync path.join(HERE, 'boot.js'), 'utf8'
IGNORED = ['^beans-runtime/', '/src/renderer/']        # as debugger.coffee
SKETCH  = /^beans-run-\d+\.coffee$/
PART    = process.env.PROBE_PART ? 'all'

say = (record) -> console.log JSON.stringify record

# --- sketches ---------------------------------------------------------------

SKETCHES =
  # An author's own mistake, two calls deep, with locals worth seeing.
  own: """
    var angle = 41, ball = null
    function addAngle(a, b) { var sum = a + b; return ball.x + sum }
    addAngle(angle, 1)
    """
  # Bad input to the runtime: the throw is in ignore-listed code.
  lib: """
    var hue = 'mauvish'
    colour(hue)
    """
  # The author catches it: must not pause.
  ownCaught: """
    var got = 'none'
    try { null.x } catch (e) { got = 'caught' }
    got
    """
  libCaught: """
    var got = 'none'
    try { colour('x') } catch (e) { got = 'caught' }
    got
    """
  # What Stop throws from a yield point: must not pause.
  interrupted: """
    var n = 5
    yieldPoint()
    """

# Each counts iterations for a second; a time check every 1000 so that
# performance.now() is not what is being measured.
loopOf = (body) -> """
  var n = 0, t0 = performance.now()
  while (performance.now() - t0 < 1000) for (var k = 0; k < 1000; k++) { #{body}; n++ }
  RESULT = n
  """

LOOPS =
  plain:     loopOf 'Math.sqrt(n)'
  throwOwn:  loopOf "try { throw new Error('x') } catch (e) {}"
  throwNull: loopOf 'try { null.x } catch (e) {}'
  throwLib:  loopOf "try { colour('x') } catch (e) {}"

# --- the session ------------------------------------------------------------

win      = null
cdp      = null
session  = null
config   = {armed: no}   # what the next worker to attach is set up with
pauses   = []
runSeq   = 0
scripts  = new Map

js = (code) -> win.webContents.executeJavaScript code, yes

send = (method, params = {}) -> cdp.sendCommand method, params, session

attachedTo = (id, waiting) ->
  session = id
  scripts.clear()
  try
    if config.armed
      await cdp.sendCommand 'Debugger.enable', {}, id
      await cdp.sendCommand 'Debugger.setBlackboxPatterns', {patterns: config.ignored ? IGNORED}, id
      try
        await cdp.sendCommand 'Debugger.setPauseOnExceptions', {state: config.state}, id
      catch error
        say {problem: "setPauseOnExceptions #{config.state}: #{error.message}"}
  finally
    cdp.sendCommand('Runtime.runIfWaitingForDebugger', {}, id).catch(->) if waiting

# What the app would show: the first frame the author wrote, its locals, and
# whether a value can be read from it (the prompt's evaluateOnCallFrame).
inspect = (params) ->
  frames = params.callFrames
  urls   = (scripts.get(f.location.scriptId) ? '?' for f in frames)
  mine   = urls.findIndex (u) -> SKETCH.test u
  record =
    reason:   params.reason
    uncaught: params.data?.uncaught
    error:    params.data?.className ? params.data?.description?.split('\n')[0]
    top:      "#{urls[0]}:#{frames[0].functionName or '(top)'}:#{frames[0].location.lineNumber}"
    mine:     mine
  return record if mine < 0 or not config.look
  frame = frames[mine]
  record.at = "#{frame.functionName or '(top)'}:#{frame.location.lineNumber}"
  local = frame.scopeChain.find (s) -> s.type is 'local'
  {result} = await send 'Runtime.getProperties', objectId: local.object.objectId, ownProperties: yes
  record.locals = ("#{p.name}=#{p.value?.description ? p.value?.value}" for p in result)
  # The prompt while paused at an error: a read, and a line that itself throws.
  for expression in config.look
    answer = await Promise.race [
      send('Debugger.evaluateOnCallFrame', {callFrameId: frame.callFrameId, expression, timeout: 2000})
      new Promise (resolve) -> setTimeout (-> resolve 'TIMED OUT'), 4000
    ]
    record["eval #{expression}"] = answer.result?.description ? answer.result?.value ?
      answer.exceptionDetails?.exception?.description?.split('\n')[0] ? answer
  record

attach = ->
  cdp = win.webContents.debugger
  cdp.attach '1.3'
  cdp.on 'message', (event, method, params, sessionId) ->
    switch method
      when 'Target.attachedToTarget'
        attachedTo params.sessionId, params.waitingForDebugger if params.targetInfo.type is 'worker'
      when 'Debugger.scriptParsed'
        scripts.set params.scriptId, params.url if sessionId is session
      when 'Debugger.paused'
        return unless sessionId is session
        # Way (a) at its cheapest: every pause is answered with a resume, no
        # questions asked. Whatever deciding costs comes on top of this.
        if config.look
          pauses.push await inspect params
        else
          pauses.push 1
        send('Debugger.resume').catch (error) -> say {problem: "resume: #{error.message}"}
  await cdp.sendCommand 'Target.setAutoAttach',
    autoAttach: yes, waitForDebuggerOnStart: yes, flatten: yes

runOne = (style, source) ->
  await js "boot(#{JSON.stringify LIB}, #{JSON.stringify BOOT})"
  pauses = []
  answer = await js "run(#{JSON.stringify style}, #{JSON.stringify source}, 'beans-run-#{++runSeq}.coffee')"
  {answer, pauses}

# --- the two parts ----------------------------------------------------------

semantics = ->
  look = ['typeof sum !== "undefined" ? sum : hue', 'ball.y']
  configs = [
    {state: 'uncaught', ignored: IGNORED}
    {state: 'uncaught', ignored: []}         # does ignore-listing the catcher change V8's mind?
    {state: 'all',      ignored: IGNORED}
    {state: 'caught',   ignored: IGNORED}    # newer CDP; may be refused
  ]
  for base in configs
    for style in ['catch', 'escape', 'dispatch', 'dispatchInCatch']
      for name, source of SKETCHES
        config = {base..., armed: yes, look}
        {answer, pauses: seen} = await runOne style, source
        say {part: 'semantics', state: base.state, ignoreList: base.ignored.length > 0, style, sketch: name, answer, pauses: seen}

median = (xs) -> xs.slice().sort((a, b) -> a - b)[xs.length >> 1]

cost = ->
  configs = [
    {label: 'armed none',     armed: yes, state: 'none'}
    {label: 'armed uncaught', armed: yes, state: 'uncaught'}
    {label: 'armed all',      armed: yes, state: 'all'}
  ]
  for base in configs
    for style in ['catch', 'escape', 'dispatch']
      for name, source of LOOPS
        config = {base...}
        counts = []
        resumed = 0
        for _ in [1..3]
          {answer, pauses: seen} = await runOne style, source
          counts.push answer.result
          resumed += seen.length
        say {part: 'cost', config: base.label, style, loop: name, perSecond: median(counts), runs: counts, pausesResumed: resumed}

# Before anything attaches: the cost of a sketch nobody is watching.
unwatched = ->
  for name, source of LOOPS
    counts = []
    for _ in [1..3]
      await js "boot(#{JSON.stringify LIB}, #{JSON.stringify BOOT})"
      answer = await js "run('catch', #{JSON.stringify source}, 'beans-run-#{++runSeq}.coffee')"
      counts.push answer.result
    say {part: 'cost', config: 'not attached', style: 'catch', loop: name, perSecond: median(counts), runs: counts}

app.whenReady().then ->
  win = new BrowserWindow show: no, webPreferences: {backgroundThrottling: no}
  await win.loadFile path.join HERE, 'page.html'
  say {electron: process.versions.electron, chrome: process.versions.chrome, v8: process.versions.v8}
  try
    await unwatched() if PART in ['cost', 'all']
    await attach()
    await semantics() if PART in ['semantics', 'all']
    await cost()      if PART in ['cost', 'all']
  catch error
    say {problem: error.stack}
  app.exit 0
