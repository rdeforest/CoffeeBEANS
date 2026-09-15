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

  const runSketch = (source, name) => {
    const id = `beans-run-${++runSeq}.coffee`
    const compiled = CoffeeScript.compile(source, { bare: true, filename: name, sourceMap: true })
    runs.set(id, { map: compiled.sourceMap, lines: compiled.js.split('\n'), name })
    for (const stale of [...runs.keys()].slice(0, -RUNS_KEPT)) runs.delete(stale)
    ;(0, eval)(`${compiled.js}\n//# sourceURL=${id}`)
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

  const locate = (error) => {
    const stack = (error && error.stack) || ''
    for (const [id, entry] of runs) {
      const found = new RegExp(`${id.replace(/\./g, '\\.')}:(\\d+):(\\d+)`).exec(stack)
      if (!found) continue
      return coffeeLine(entry, Number(found[1]) - 1, Number(found[2]) - 1)
    }
    return undefined
  }

  const fail = (stage, error) => {
    // A compile error carries its own CoffeeScript location; a runtime error
    // carries a stack that has to be mapped back through the source map.
    const location = error && error.location
    postMessage({
      type: 'error',
      stage,
      message: String((error && error.message) || error),
      line: location ? location.first_line + 1 : locate(error),
    })
  }

  const MODULES = [
    '/src/runtime/layout.coffee',
    '/src/runtime/keys.coffee',
    '/src/runtime/colors.coffee',
    '/src/runtime/input.coffee',
    '/src/runtime/surface.coffee',
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
        // Batched prints have to land before the line that ends the run.
        const flush = () => globalThis.RUNTIME && globalThis.RUNTIME.flushPrint()
        try {
          runSketch(data.source, data.name || 'sketch.coffee')
          flush()
          postMessage({ type: 'done' })
        } catch (error) {
          flush()
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
