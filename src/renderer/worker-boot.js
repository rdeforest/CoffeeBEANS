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
  const compile = (source, filename, bare) =>
    CoffeeScript.compile(source, { bare, filename, inlineMap: true })

  const evaluate = (source, filename, bare) => (0, eval)(compile(source, filename, bare))

  const loadModule = async (path) => {
    const response = await fetch(path)
    evaluate(await response.text(), path, false)
  }

  const fail = (stage, error) => {
    // CoffeeScript compile errors carry a location; runtime errors carry a stack.
    const location = error && error.location
    const fromStack = () => {
      const match = /<anonymous>:(\d+):/.exec((error && error.stack) || '')
      return match ? Number(match[1]) : undefined
    }
    postMessage({
      type: 'error',
      stage,
      message: String((error && error.message) || error),
      line: location ? location.first_line + 1 : fromStack(),
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
          evaluate(data.source, data.name || 'sketch.coffee', true)
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
