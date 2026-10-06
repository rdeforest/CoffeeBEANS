// Everything here lives inside a function on purpose. A classic worker's
// top-level `const` goes into the global LEXICAL environment, which shadows
// globalThis for indirect-eval'd code -- so a helper named `load` here would
// quietly hide the runtime's `load` from every sketch. Same failure class as
// `history` shadowing window.history in the renderer; the cure is the same,
// which is to declare nothing anyone else can collide with.
;(() => {
  importScripts('/src/renderer/vendor/coffeescript.js')

  // Our own modules compile wrapped, so their top-level names cannot collide
  // with globals. Sketches compile bare on purpose: their definitions have to
  // survive into the worker scope so a later eval-region can call them. That
  // is the live image.
  // Our own modules compile wrapped and are not mapped: they are compile
  // tested, and a stack frame in them is our problem, not a sketch author's.
  //
  // They are named, though. Anonymous eval scripts cannot be pointed at, and
  // a debugger needs to be told to ignore this family so that stepping into
  // circleFill steps over it instead of landing in a Bresenham loop, and so a
  // bare pause stops on the author's line rather than six frames down in
  // doSwap. One pattern, beans-runtime/, covers the lot.
  //
  // Except breakpoint.coffee, which must stay outside that pattern -- see the
  // comment at the top of it. Naming is also why traceback() can keep dropping
  // these frames: it matches beans-run-N.coffee and nothing else.
  const moduleUrl = (path) => {
    const name = path.split('/').pop().replace(/\.coffee$/, '')
    return name === 'breakpoint' ? 'beans-breakpoint.js' : `beans-runtime/${name}.js`
  }

  const loadModule = async (path) => {
    const response = await fetch(path)
    const source = await response.text()
    const js = CoffeeScript.compile(source, { bare: false, filename: path })
    ;(0, eval)(`${js}\n//# sourceURL=${moduleUrl(path)}`)
  }

  // Sketches get a real source map and a script id that is safe to put in a
  // regex, because the error path has to find their frames in a stack. The
  // id is not the sketch name: names carry spaces and parentheses.
  //
  // Every run's source is kept for the life of the worker: a function a region
  // defined a hundred runs ago is still in the image, can still throw, and its
  // frames still need mapping. Capping the runs instead lost them (a reviewer
  // of E1, 2026-10-06: `at old` dropped out of the report after 32 region
  // evals). The source is no more than the author has sent this worker, and a
  // Run starts a fresh one. The compiled map is the heavy part -- objects per
  // mapped column -- so only the newest RUNS_MAPPED keep theirs, and an older
  // run's is compiled again when a traceback reaches it: the same source and
  // options give the same map.
  const RUNS_MAPPED = 32
  const runs = new Map()        // id -> {source, name}
  const mapped = new Map()      // id -> {map, lines, src, name, offset}, newest last
  let runSeq = 0

  // The live image. A sketch runs inside a function, so its names never
  // touch globalThis and can never collide with the runtime API or with
  // anything the worker owns. Persistence -- the thing bare compilation was
  // buying -- comes from copying names in and out of this object instead.
  // Shadowing still works: a sketch that says `line = 5` gets a local `line`
  // that hides the drawing command for as long as the image lives, without
  // damaging the command itself. A restart drops the image and the API is
  // pristine again.
  const image = Object.create(null)

  // The frame of the run that is currently on the stack, if any. A sketch's
  // names live in its wrapper's scope and only reach the image when the run
  // ends -- which for a `loop` is never. These two closures are the way in:
  // harvest publishes the running sketch's locals, restore takes back
  // whatever the prompt changed. Without them `boids.length` typed at a
  // flying sketch is a ReferenceError, which is not much of a REPL.
  const frames = []

  const IDENTIFIER = /^[A-Za-z_$][\w$]*$/

  // CoffeeScript puts every top-level name of a compilation unit into one
  // leading `var` statement, which is all we need to know what to harvest.
  // Comments can precede it, line and block in any mix: a sketch that opens
  // with `#` lines compiles to `//` lines ahead of the `var`. So can a
  // statement that is nothing but a literal -- a docstring, a number, a
  // backtick of JavaScript that is more than a comment -- and that is not
  // skipped: a sketch that opens with one keeps none of its names.
  const LEADING_COMMENTS = /^(?:\s*(?:\/\/.*|\/\*[\s\S]*?\*\/))*\s*/
  const declaredNames = (js) => {
    const head = js.replace(LEADING_COMMENTS, '')
    if (!head.startsWith('var ')) return []
    const stop = head.indexOf(';')
    if (stop < 0) return []
    return head
      .slice(4, stop)
      .split(',')
      .map((part) => part.trim().split('=')[0].trim())
      .filter((name) => IDENTIFIER.test(name))
  }

  // Lines the wrapper adds before the sketch's own first line. Stack frames
  // are mapped back through the source map, so this has to be exact.
  const PROLOGUE_LINES = 3

  // btoa takes a binary string, and a sketch's source is UTF-8. Encode first,
  // then widen each byte, or an accented character in a comment corrupts the
  // whole map.
  const base64 = (text) => {
    const bytes = new TextEncoder().encode(text)
    let binary = ''
    for (const byte of bytes) binary += String.fromCharCode(byte)
    return btoa(binary)
  }

  // The map CoffeeScript hands back is already what DevTools wants, except
  // that its lines are relative to the compiled JS while `wrapped` puts
  // PROLOGUE_LINES ahead of it. A v3 mappings string is one group per
  // generated line separated by ';', so shifting the whole thing down is
  // exactly that many semicolons -- nothing to re-encode.
  //
  // With this, DevTools shows the CoffeeScript rather than the generated JS:
  // breakpoints land on the line you wrote, and the Scope pane names the
  // sketch's own variables. And because presenting happens on the renderer
  // thread, the canvas keeps painting while you step.
  const inlineMap = (v3) => {
    const map = JSON.parse(v3)
    map.mappings = ';'.repeat(PROLOGUE_LINES) + map.mappings
    return `//# sourceMappingURL=data:application/json;charset=utf-8;base64,${base64(JSON.stringify(map))}`
  }

  const compileSketch = (source, name) =>
    CoffeeScript.compile(source, { bare: true, filename: name, sourceMap: true })

  const keepMapping = (id, compiled, { source, name }) => {
    const entry = {
      map: compiled.sourceMap,
      lines: compiled.js.split('\n'),
      src: source.split('\n'),
      name,
      offset: PROLOGUE_LINES,
    }
    mapped.set(id, entry)
    for (const stale of [...mapped.keys()].slice(0, -RUNS_MAPPED)) mapped.delete(stale)
    return entry
  }

  const mappingOf = (id) => {
    if (mapped.has(id)) return mapped.get(id)
    const sent = runs.get(id)
    return sent && keepMapping(id, compileSketch(sent.source, sent.name), sent)
  }

  // Compiled, wrapped and evaluated into a function here, and only called once
  // it is dispatched (see dispatchRun): a syntax error is reported from here,
  // under the run handler's catch, and never reaches V8 as an uncaught error
  // of the author's.
  const prepareSketch = (source, name) => {
    const id = `beans-run-${++runSeq}.coffee`
    const compiled = compileSketch(source, name)

    // Restoring re-declares: `var a = image.a` followed by the sketch's own
    // `var a` leaves the restored value in place, because a bare `var` does
    // not clear anything.
    const held = Object.keys(image)
    const restore = held.length
      ? `var ${held.map((n) => `${n} = __image[${JSON.stringify(n)}]`).join(', ')};`
      : ';'
    const harvest = declaredNames(compiled.js)
      .map((n) => `__image[${JSON.stringify(n)}] = ${n};`)
      .join('')

    // Every name the run can change: what it inherited and what it declares.
    const live = [...new Set([...held, ...declaredNames(compiled.js)])]
    const publish = live.map((n) => `__image[${JSON.stringify(n)}] = ${n};`).join('')
    const take    = live.map((n) => `${n} = __image[${JSON.stringify(n)}];`).join('')

    // finally, not a plain suffix: a sketch that throws half way should keep
    // whatever it managed to define, the way a REPL does. The frame goes on
    // the same line as the restore so the prologue stays three lines and the
    // source map keeps lining up.
    const wrapped =
      `(function(__image, __frames){\n` +
      `${restore}__frames.push({harvest:function(){${publish}},restore:function(){${take}}});\n` +
      `try{\n${compiled.js}\n}finally{__frames.pop();${harvest}}\n})` +
      `\n//# sourceURL=${id}` +
      `\n${inlineMap(compiled.v3SourceMap)}`

    runs.set(id, { source, name })
    keepMapping(id, compiled, { source, name })
    const sketch = (0, eval)(wrapped)
    return () => sketch(image, frames)
  }

  // A run is the listener of an event the worker dispatches to itself, with no
  // catch anywhere above it, so that V8 predicts a sketch's error as uncaught
  // and the debugger's pauseOnExceptions 'uncaught' stops at the throw with the
  // frame live -- while an error the sketch catches, the prompt's (serveAsk
  // catches) and a syntax error (prepareSketch) still are not stopped on.
  // dispatchEvent reports a listener's exception as the worker's `error` event
  // instead of throwing it to its caller, and fires that event before it
  // returns, so the run still reports synchronously, in the order it always
  // has. docs/research/pause-on-error.md has the measurements.
  //
  // A catch above the dispatch -- around dispatchRun, in the message listener,
  // anywhere on the stack -- would never see the error and still turns the
  // whole feature off without a word: V8's prediction walks straight past the
  // native boundary (measured, the probe's dispatchInCatch). The pauseonerror
  // part's first check is the guard. The debugger knows a run's errors from
  // everything else's by this function's name on the stack (inRun in
  // src/main/debugger.coffee).
  let dispatched = null
  const dispatchRun = (body) => {
    const outcome = (dispatched = { threw: false, error: undefined })
    self.addEventListener('beans-run', body, { once: true })
    self.dispatchEvent(new Event('beans-run'))
    dispatched = null
    return outcome
  }

  // A run's error is the run's to report. Anything else that reaches here was
  // thrown once the run had ended -- a timer, a callback -- and is reported as
  // that, once: left to bubble, the renderer heard it twice, as `worker:` and
  // again as `renderer:` (measured by Claude, 2026-10-05, on main before E1).
  //
  // An Interrupted out here is a Stop reaching code the run left behind -- an
  // async function resumed after the run unwound, at a yield point that still
  // sees the flag up -- and the Stop is already reported as one.
  const LATE = 'after the run'
  self.addEventListener('error', (event) => {
    event.preventDefault()
    if (dispatched) {
      dispatched.threw = true
      dispatched.error = event.error
      return
    }
    if (event.error instanceof Interrupted) return
    fail(LATE, event.error)
  })
  // A rejection nobody handles -- a promise callback that threw, an async
  // function after its first await -- was never reported at all before E1.
  self.addEventListener('unhandledrejection', (event) => {
    event.preventDefault()
    if (event.reason instanceof Interrupted) return
    fail(LATE, event.reason)
  })

  // --- the console prompt ---------------------------------------------------

  // A line typed at the prompt is the same live image the sketch runs in, so
  // it restores and harvests exactly as a run does. The difference is that it
  // has to hand back a value, and a function body has no completion value to
  // give. A *direct* eval does: it sees the restored names, and it returns
  // what the last expression evaluated to. Its `var`s hoist into this
  // function, which is what lets harvest find anything the line defined.
  const evalLine = (source) => {
    // A plain string, not a {js, sourceMap} pair: compile only hands back the
    // pair when a source map was asked for, and a one-liner does not need one.
    const js = CoffeeScript.compile(source, { bare: true, filename: 'console' })
    const held = Object.keys(image)
    const restore = held.length
      ? `var ${held.map((n) => `${n} = __image[${JSON.stringify(n)}]`).join(', ')};`
      : ';'
    const harvest = declaredNames(js)
      .map((n) => `__image[${JSON.stringify(n)}] = ${n};`)
      .join('')
    const wrapped =
      `(function(__image, __source){\n${restore}\ntry{\nreturn eval(__source)\n}` +
      `finally{${harvest}}\n})`
    return (0, eval)(wrapped)(image, js)
  }

  const SHOWN = 4000          // a boid array should not fill the console
  const ITEMS = 24

  const show = (value, depth = 0) => {
    if (value === null) return 'null'
    if (value === undefined) return 'undefined'
    switch (typeof value) {
      case 'string': return JSON.stringify(value)
      case 'function': return `[function ${value.name || 'anonymous'}]`
      case 'number': case 'boolean': case 'bigint': case 'symbol': return String(value)
    }
    if (ArrayBuffer.isView(value)) return `${value.constructor.name}(${value.length})`
    if (depth > 1) return Array.isArray(value) ? '[...]' : '{...}'
    if (Array.isArray(value)) {
      const shown = value.slice(0, ITEMS).map((item) => show(item, depth + 1))
      if (value.length > ITEMS) shown.push(`... ${value.length - ITEMS} more`)
      return `[${shown.join(', ')}]`
    }
    const name = value.constructor && value.constructor.name
    const keys = Object.keys(value)
    const body = keys.slice(0, ITEMS).map((k) => `${k}: ${show(value[k], depth + 1)}`)
    if (keys.length > ITEMS) body.push(`... ${keys.length - ITEMS} more`)
    const braced = `{${body.join(', ')}}`
    return name && name !== 'Object' ? `${name} ${braced}` : braced
  }

  // --- Tab at the prompt ----------------------------------------------------

  // The CoffeeBEANS vocabulary: what attach installs, and the two names a
  // module publishes for sketches. Set at boot, by difference, so a new
  // command is in it without anyone remembering to list it. What the modules
  // hang on globalThis before that (LAYOUT, toColor, ColorBuilder...), and
  // REPL after it, fall outside the difference and are never offered.
  let vocabulary = []
  const PUBLISHED = ['breakpoint', 'COLORS']
  const PLUMBING  = ['Interrupted']

  // The JavaScript a player is likely to reach for, and only that: Robert
  // decided on 2026-10-05 that Tab offers these alongside CoffeeBEANS's own.
  // A list, not globalThis minus a blocklist, so that a browser or Electron
  // upgrade cannot put a new global in front of a player unasked, and the
  // worker's machinery (postMessage, self, fetch, on*, Atomics, WebAssembly,
  // requestAnimationFrame) stays out. To offer another, add its name here; one
  // this worker lacks is dropped. Members are not listed: `Math.hyp` finds
  // `Math.hypot` by the same descriptor walk as any other object's.
  const JAVASCRIPT = [
    'Infinity', 'NaN', 'undefined',
    'isFinite', 'isNaN', 'parseFloat', 'parseInt',
    'JSON', 'Math',
    'Array', 'Boolean', 'Date', 'Error', 'Map', 'Number', 'Object', 'RegExp', 'Set', 'String',
    'Float64Array', 'Int32Array', 'Uint8Array',
  ]
  const javascript = JAVASCRIPT.filter((name) => name in globalThis)

  const descriptorOf = (value, name) => {
    for (let o = Object(value); o !== null; o = Object.getPrototypeOf(o)) {
      const found = Object.getOwnPropertyDescriptor(o, name)
      if (found) return found
    }
    return undefined
  }

  // Where a dotted name ends, found by reading descriptors and never by
  // reading the property: a getter stops the walk instead of being run.
  // buffer.swap draws a frame, keys.poll claims hits, mouse.wheel consumes,
  // and breakpoint would stop the sketch -- Tab must not do any of that.
  // A Proxy is the exception nothing here can refuse: an author's
  // getOwnPropertyDescriptor, getPrototypeOf and ownKeys traps do run.
  const walk = (value, names) => {
    for (const name of names) {
      if (value === null || value === undefined) return undefined
      const found = descriptorOf(value, name)
      if (!found || !('value' in found)) return undefined
      value = found.value
    }
    return value
  }

  // Everything that can follow a dot, up to but not including
  // Object.prototype, whose __defineGetter__ and friends nobody is looking
  // for. An array's or a string's own names are its indices -- a million of
  // them for a big one, and none anybody types after a dot.
  const membersOf = (value) => {
    const object = Object(value)
    const indexed = Array.isArray(object) || ArrayBuffer.isView(object) || object instanceof String
    const names = indexed ? ['length'] : Object.getOwnPropertyNames(object)
    for (let o = Object.getPrototypeOf(object); o !== null && o !== Object.prototype; o = Object.getPrototypeOf(o))
      names.push(...Object.getOwnPropertyNames(o))
    return names
  }

  // `local` says the first name is a variable of the frame the debugger is
  // paused in, and `root` is its value, read there; anything else starts from
  // the image, the vocabulary or JavaScript's list. `frameNames` are that
  // frame's variables.
  //
  // Nearest first, alphabetical within each: the paused frame's names, the
  // image's, CoffeeBEANS's, then JavaScript's (Robert, 2026-10-05). A name in
  // two of them keeps the nearer place, since the nearer one is what it means.
  //
  // Line paused, the first two run together: the run's wrapper puts every
  // top-level sketch name in one function, so V8 reports the image's names
  // the paused function refers to as part of the frame's closure scope, and
  // they arrive here in `frameNames`. Only frame-or-image before CoffeeBEANS
  // before JavaScript holds there. Keeping them apart would need the
  // renderer's pausedNames to keep V8's scope types apart (a Claude fixer
  // agent, 2026-10-06 overnight, track T1).
  const complete = ({ path, word, local }, frameNames = [], root) => {
    let ranks
    if (path.length === 0) {
      ranks = [frameNames, Object.keys(image), vocabulary, javascript]
    } else {
      const [first, ...rest] = path
      const start = local ? root
        : first in image ? image[first]
        : vocabulary.includes(first) || javascript.includes(first) ? walk(globalThis, [first])
        : undefined
      const value = walk(start, rest)
      ranks = [value === null || value === undefined ? [] : membersOf(value)]
    }
    const fits = (name) => name.startsWith(word) && IDENTIFIER.test(name) && !name.startsWith('__')
    return [...new Set(ranks.flatMap((names) => names.filter(fits).sort()))]
  }

  // Set once the layout module is loaded; until then there is nowhere to read
  // a question from, and a message that arrives early has nothing to do.
  let askWords = null
  let askBytes = null
  let serving = false
  let owner = null            // which worker this is; see checkOwner in the runtime

  const encoder = new TextEncoder()
  const decoder = new TextDecoder()

  // Re-entrant by construction: a line that calls buffer.swap reaches a yield
  // point, which would ask us to serve the question we are already serving.
  const serveAsk = () => {
    // A worker that a Run has replaced may still serve 'ask' pokes queued in
    // its inbox while it unwinds; the line waiting now is the new worker's.
    if (!askBytes || serving || Atomics.load(askWords, LAYOUT.HEADER.OWNER) !== owner) return
    // Claimed, not just read: until the worker takes it, the renderer may
    // still withdraw a Tab's question to make way for a line.
    if (Atomics.compareExchange(askWords, LAYOUT.HEADER.ASK_STATE, 1, 4) !== 1) return
    // A Run between that check and the claim means the line just claimed is
    // the new worker's -- start() bumps the owner before it resets the ask --
    // so it is given back at once, or nothing could ever claim it again.
    // Checked here and not after answering: by then the new worker may have
    // claimed a line of its own, and giving that back would run it twice.
    if (Atomics.load(askWords, LAYOUT.HEADER.OWNER) !== owner) {
      Atomics.compareExchange(askWords, LAYOUT.HEADER.ASK_STATE, 4, 1)
      return
    }
    serving = true
    // A sketch that is still running has its names in its own scope, so it
    // lends them to the image for the length of the question and takes back
    // whatever the answer changed. That is what makes `boids[0].vx *= 2` at
    // the prompt reach the boid that is actually flying -- and `boi` and Tab
    // find it.
    const frame = frames[frames.length - 1]
    const completing = Atomics.load(askWords, LAYOUT.HEADER.ASK_KIND) === LAYOUT.ASK_FOR.completion
    let reply, state
    try {
      if (frame) frame.harvest()
      // Copied out of shared memory first: TextDecoder will not read a view
      // onto a SharedArrayBuffer.
      const asked = decoder.decode(new Uint8Array(askBytes.subarray(0, Atomics.load(askWords, LAYOUT.HEADER.ASK_LEN))))
      reply = completing ? JSON.stringify(complete(JSON.parse(asked))) : show(evalLine(asked))
      state = 2
    } catch (error) {
      reply = String((error && error.message) || error)
      state = 3
    } finally {
      try { if (frame) frame.restore() } catch (ignored) {}
      serving = false
    }
    // Cut the string, not the bytes: truncating UTF-8 mid-character would put
    // a replacement character on the end of every long answer. Never a
    // completion's, which is JSON and would no longer parse.
    if (!completing && reply.length > SHOWN) reply = reply.slice(0, SHOWN) + ' ...'
    let bytes = encoder.encode(reply)
    if (bytes.length > LAYOUT.ASK_BYTES) {
      bytes = encoder.encode('too many names to send back')
      state = 3
    }
    // A Run while the line was out has given the memory to a new worker and
    // reset the ask for it. The line most likely unwound with 'stopped', and
    // written back that would show up red in the new run's console. The
    // exchange covers a Run landing between the check and the store.
    if (Atomics.load(askWords, LAYOUT.HEADER.OWNER) !== owner) return
    askBytes.set(bytes)
    Atomics.store(askWords, LAYOUT.HEADER.ASK_LEN, bytes.length)
    Atomics.compareExchange(askWords, LAYOUT.HEADER.ASK_STATE, 4, state)
    Atomics.notify(askWords, LAYOUT.HEADER.ASK_STATE)
  }

  // A stack frame gives a JS line and column; the map turns that back into a
  // CoffeeScript line. Column matters: at column 0 most JS lines have no
  // mapping at all, so a miss walks backwards to the nearest one.
  const coffeeLine = (entry, jsLine, jsColumn) => {
    for (let line = jsLine; line >= 0; line--) {
      const start = line === jsLine ? jsColumn : (entry.lines[line] || '').length
      for (let column = start; column >= 0; column--) {
        const at = entry.map.sourceLocation([line, column])
        if (at) return at[0] + 1
      }
    }
    return undefined
  }

  // Every sketch frame in the stack, innermost first: a real traceback rather
  // than only the line the error surfaced on. Frames inside our own runtime
  // modules are unmapped and left out -- a frame in them is our problem, not
  // the author's -- so what remains is the author's own chain of calls.
  //
  // Only a string is a stack: `throw {stack: 5}` is the author's to make, and
  // a report that throws on it is no report.
  const traceback = (error) => {
    const stack = error && typeof error.stack === 'string' ? error.stack : ''
    const frames = []
    for (const raw of stack.split('\n')) {
      const found = /at (?:(.+?) \()?(beans-run-\d+\.coffee):(\d+):(\d+)\)?/.exec(raw)
      if (!found) continue
      const entry = mappingOf(found[2])
      if (!entry) continue
      const line = coffeeLine(entry, Number(found[3]) - entry.offset - 1, Number(found[4]) - 1)
      // A sketch's top-level code runs inside an indirect eval, which V8 names
      // 'eval'; that reads as top level to the author, so drop it.
      const fn = found[1] && found[1] !== 'eval' && found[1] !== '<anonymous>' ? found[1] : null
      frames.push({
        fn,
        name: entry.name,
        line,
        text: line ? (entry.src[line - 1] || '').trim() : null,
      })
    }
    return frames
  }

  // Anything can be thrown, and not everything converts: String() of an
  // object with no prototype throws, and a report that throws is no report.
  const textOf = (value) => {
    try {
      return String(value)
    } catch (unconvertible) {
      return Object.prototype.toString.call(value)
    }
  }

  // The report, apart from the posting of it, because the debugger asks for
  // the same one at an error pause (REPL.failure), before the run has ended.
  const failure = (stage, error) => {
    // A compile error carries its own CoffeeScript location; a runtime error
    // carries a stack that has to be mapped back through the source map. The
    // renderer answers the two differently -- a syntax error puts the cursor
    // on it, a runtime one offers the stack -- so the kind travels with it.
    const location = error && error.location
    const frames = location ? [] : traceback(error)
    return {
      type: 'error',
      stage,
      kind: location ? 'syntax' : 'runtime',
      message: textOf((error && error.message) || error),
      line: location ? location.first_line + 1 : (frames[0] && frames[0].line),
      column: location ? location.first_column + 1 : undefined,
      frames,
    }
  }

  const fail = (stage, error) => postMessage(failure(stage, error))

  // Not among the message handlers below: they run under a catch, and nothing
  // may catch above a run (see dispatchRun). Preparing it may, and does.
  const run = ({ source, name }) => {
    let body
    try {
      body = prepareSketch(source, name || 'sketch.coffee')
    } catch (error) {
      return fail('run', error)
    }
    const outcome = dispatchRun(body)
    // Every run ends in one of the three, or the renderer waits on it for good
    // and Stop blames a missing yield point. So a report that throws -- on a
    // thrown value whose every read throws, say -- is reported itself. Below
    // the dispatch, so this catch is never above a run.
    try {
      if (!outcome.threw) postMessage({ type: 'done' })
      else if (outcome.error instanceof Interrupted) postMessage({ type: 'stopped' })
      else fail('run', outcome.error)
    } catch (unreported) {
      fail('run', unreported)
    }
  }

  const MODULES = [
    '/src/runtime/breakpoint.coffee',
    '/src/runtime/layout.coffee',
    '/src/runtime/keys.coffee',
    '/src/runtime/colors.coffee',
    '/src/runtime/input.coffee',
    '/src/runtime/surface.coffee',
    '/src/runtime/probe.coffee',
    '/src/runtime/paint.coffee',
    '/src/runtime/fill.coffee',
    '/src/runtime/sound.coffee',
    '/src/runtime/font.coffee',
    '/src/runtime/runtime.coffee',
  ]

  // addEventListener, not self.onmessage: sketches compile bare into this same
  // scope, and `onmessage = anything` would otherwise null out our inbox with
  // no error. Same reasoning for any other on* handler.
  self.addEventListener('message', ({ data }) => {
    const handlers = {
      async boot() {
        for (const path of MODULES) await loadModule(path)
        const before = new Set(Object.getOwnPropertyNames(globalThis))
        owner = data.owner
        attach(data.sab, owner)
        vocabulary = [
          ...Object.getOwnPropertyNames(globalThis).filter((name) => !before.has(name) && !PLUMBING.includes(name)),
          ...PUBLISHED,
        ]
        askWords = new Int32Array(data.sab, 0, LAYOUT.HEADER_WORDS)
        askBytes = new Uint8Array(data.sab, LAYOUT.askOffset, LAYOUT.ASK_BYTES)
        // How the runtime reaches us from a yield point. A property on
        // globalThis rather than a name at this scope, which is the rule the
        // whole file is built around.
        // `show` is for the debugger, which answers the prompt against a
        // paused frame and wants the answer to read like any other;
        // `complete` is how Tab asks that frame, in the same JSON the
        // shared-memory answer comes back in; `failure` is how an error
        // pause gets the report the run would have made; and `owner` tells a
        // pause of this worker from one of the worker a Run replaced.
        globalThis.REPL = {
          owner,
          serve: serveAsk,
          show,
          complete: (question, frameNames, root) => JSON.stringify(complete(question, frameNames, root)),
          failure: (error) => failure('run', error),
        }
        postMessage({ type: 'ready' })
      },
      // An idle worker is sitting in this queue and will never look at shared
      // memory on its own, so the renderer pokes it. A busy one cannot receive
      // this at all and answers at its next yield point instead -- by the time
      // the message does arrive there is nothing left to do.
      ask() {
        serveAsk()
      },
    }
    // The run outside the catch the others share. And a plain listener: the
    // shape measured to stop on errors (research/pause-on-error, c5c788d) had
    // no async function under the run, and one with it was never tried.
    if (data.type === 'run') return run(data)
    ;(async () => {
      try {
        await handlers[data.type]()
      } catch (error) {
        fail(data.type, error)
      }
    })()
  })
})()
