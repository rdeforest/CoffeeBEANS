// Preloaded into a second CoffeeBEANS through NODE_OPTIONS by the startup
// part: an exception nobody catches, thrown in main as soon as the app is
// ready, ahead of its window. A preload runs before Electron's own modules
// can be required, hence the first timer.
//
// With BEANS_THROW_LOADING it is thrown instead while main.coffee is still
// loading, out of one of its own requires: `early` before mainFailed is
// defined (./debugger), `late` after it but before the window is asked for
// (./settings).
const Module = require('module')
const at = { early: './debugger', late: './settings' }[process.env.BEANS_THROW_LOADING]

if (at) {
  const load = Module._load
  Module._load = function (request, parent, ...rest) {
    if (request === at && parent && /main\.coffee$/.test(parent.filename))
      throw new Error(`startup: thrown while loading, at ${at}`)
    return load.call(this, request, parent, ...rest)
  }
} else {
  setTimeout(() => require('electron').app.whenReady().then(() =>
    setTimeout(() => { throw new Error('startup: thrown in main') }, 0)), 0)
}
