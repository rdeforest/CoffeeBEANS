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
  const loadModule = async (path) => {
    const response = await fetch(path)
    const source = await response.text()
    ;(0, eval)(CoffeeScript.compile(source, { bare: false, filename: path }))
  }

  // Sketches get a real source map and a script id that is safe to put in a
  // regex, because the error path has to find their frames in a stack. The
  // id is not the sketch name: names carry spaces and parentheses.
  const RUNS_KEPT = 32
  const runs = new Map()
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
  // Block comments can precede it; nothing else can.
  const declaredNames = (js) => {
    let head = js
    for (;;) {
      head = head.replace(/^\s+/, '')
      if (!head.startsWith('/*')) break
      const closed = head.indexOf('*/')
      if (closed < 0) return []
      head = head.slice(closed + 2)
    }
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

  const runSketch = (source, name) => {
    const id = `beans-run-${++runSeq}.coffee`
    const compiled = CoffeeScript.compile(source, { bare: true, filename: name, sourceMap: true })

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

    runs.set(id, {
      map: compiled.sourceMap,
      lines: compiled.js.split('\n'),
      src: source.split('\n'),
      name,
      offset: PROLOGUE_LINES,
    })
    for (const stale of [...runs.keys()].slice(0, -RUNS_KEPT)) runs.delete(stale)
    ;(0, eval)(wrapped)(image, frames)
  }

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

  // Set once the layout module is loaded; until then there is nowhere to read
  // a question from, and a message that arrives early has nothing to do.
  let askWords = null
  let askBytes = null
  let serving = false

  const encoder = new TextEncoder()
  const decoder = new TextDecoder()

  // Re-entrant by construction: a line that calls buffer.swap reaches a yield
  // point, which would ask us to serve the question we are already serving.
  const serveAsk = () => {
    if (!askBytes || serving) return
    if (Atomics.load(askWords, LAYOUT.HEADER.ASK_STATE) !== 1) return
    serving = true
    // A sketch that is still running has its names in its own scope, so it
    // lends them to the image for the length of the question and takes back
    // whatever the answer changed. That is what makes `boids[0].vx *= 2` at
    // the prompt reach the boid that is actually flying.
    const frame = frames[frames.length - 1]
    let reply, state
    try {
      if (frame) frame.harvest()
      // Copied out of shared memory first: TextDecoder will not read a view
      // onto a SharedArrayBuffer.
      const asked = new Uint8Array(askBytes.subarray(0, Atomics.load(askWords, LAYOUT.HEADER.ASK_LEN)))
      reply = show(evalLine(decoder.decode(asked)))
      state = 2
    } catch (error) {
      reply = String((error && error.message) || error)
      state = 3
    } finally {
      try { if (frame) frame.restore() } catch (ignored) {}
      serving = false
    }
    // Cut the string, not the bytes: truncating UTF-8 mid-character would put
    // a replacement character on the end of every long answer.
    const bytes = encoder.encode(reply.length > SHOWN ? reply.slice(0, SHOWN) + ' ...' : reply)
    askBytes.set(bytes.subarray(0, LAYOUT.ASK_BYTES))
    Atomics.store(askWords, LAYOUT.HEADER.ASK_LEN, Math.min(bytes.length, LAYOUT.ASK_BYTES))
    Atomics.store(askWords, LAYOUT.HEADER.ASK_STATE, state)
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
  const traceback = (error) => {
    const stack = (error && error.stack) || ''
    const frames = []
    for (const raw of stack.split('\n')) {
      const found = /at (?:(.+?) \()?(beans-run-\d+\.coffee):(\d+):(\d+)\)?/.exec(raw)
      if (!found) continue
      const entry = runs.get(found[2])
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

  const fail = (stage, error) => {
    // A compile error carries its own CoffeeScript location; a runtime error
    // carries a stack that has to be mapped back through the source map.
    const location = error && error.location
    const frames = location ? [] : traceback(error)
    postMessage({
      type: 'error',
      stage,
      message: String((error && error.message) || error),
      line: location ? location.first_line + 1 : (frames[0] && frames[0].line),
      frames,
    })
  }

  const MODULES = [
    '/src/runtime/layout.coffee',
    '/src/runtime/keys.coffee',
    '/src/runtime/colors.coffee',
    '/src/runtime/input.coffee',
    '/src/runtime/surface.coffee',
    '/src/runtime/probe.coffee',
    '/src/runtime/paint.coffee',
    '/src/runtime/fill.coffee',
    '/src/runtime/font.coffee',
    '/src/runtime/runtime.coffee',
  ]

  // addEventListener, not self.onmessage: sketches compile bare into this same
  // scope, and `onmessage = anything` would otherwise null out our inbox with
  // no error. Same reasoning for any other on* handler.
  self.addEventListener('message', async ({ data }) => {
    const handlers = {
      async boot() {
        for (const path of MODULES) await loadModule(path)
        attach(data.sab)
        askWords = new Int32Array(data.sab, 0, LAYOUT.HEADER_WORDS)
        askBytes = new Uint8Array(data.sab, LAYOUT.askOffset, LAYOUT.ASK_BYTES)
        // How the runtime reaches us from a yield point. A property on
        // globalThis rather than a name at this scope, which is the rule the
        // whole file is built around.
        globalThis.REPL = { serve: serveAsk }
        postMessage({ type: 'ready' })
      },
      // An idle worker is sitting in this queue and will never look at shared
      // memory on its own, so the renderer pokes it. A busy one cannot receive
      // this at all and answers at its next yield point instead -- by the time
      // the message does arrive there is nothing left to do.
      ask() {
        serveAsk()
      },
      run() {
        try {
          runSketch(data.source, data.name || 'sketch.coffee')
          postMessage({ type: 'done' })
        } catch (error) {
          if (error instanceof Interrupted) postMessage({ type: 'stopped' })
          else fail('run', error)
        }
      },
    }
    try {
      await handlers[data.type]()
    } catch (error) {
      fail(data.type, error)
    }
  })
})()
