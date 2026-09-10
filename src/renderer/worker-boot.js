// Plain JS because importScripts needs it. Everything past this point is
// CoffeeScript compiled at runtime, which is also how sketches are run.
importScripts('/src/renderer/vendor/coffeescript.js')

// Our own modules compile wrapped, so their top-level names cannot collide
// with globals like `name` or `location`. Sketches compile bare on purpose:
// their definitions have to survive into the worker scope so a later
// eval-region can call them. That is the live image.
const compile = (source, filename, bare) =>
  CoffeeScript.compile(source, { bare, filename, inlineMap: true })

const evaluate = (source, filename, bare) => (0, eval)(compile(source, filename, bare))

const load = async (path) => {
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

// addEventListener, not self.onmessage: sketches compile bare into this same
// scope, and `onmessage = anything` would otherwise null out our inbox with
// no error. Same reasoning for any other on* handler.
self.addEventListener('message', async ({ data }) => {
  const handlers = {
    async boot() {
      for (const path of ['/src/runtime/layout.coffee', '/src/runtime/keys.coffee', '/src/runtime/colors.coffee',
           '/src/runtime/input.coffee', '/src/runtime/runtime.coffee'])
        await load(path)
      attach(data.sab)
      postMessage({ type: 'ready' })
    },
    run() {
      try {
        evaluate(data.source, data.name || 'sketch.coffee', true)
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
