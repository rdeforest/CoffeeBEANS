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

    // finally, not a plain suffix: a sketch that throws half way should keep
    // whatever it managed to define, the way a REPL does.
    const wrapped =
      `(function(__image){\n${restore}\ntry{\n${compiled.js}\n}finally{${harvest}}\n})` +
      `\n//# sourceURL=${id}`

    runs.set(id, {
      map: compiled.sourceMap,
      lines: compiled.js.split('\n'),
      src: source.split('\n'),
      name,
      offset: PROLOGUE_LINES,
    })
    for (const stale of [...runs.keys()].slice(0, -RUNS_KEPT)) runs.delete(stale)
    ;(0, eval)(wrapped)(image)
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
        postMessage({ type: 'ready' })
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
