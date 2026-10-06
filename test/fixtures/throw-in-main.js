// Preloaded into a second CoffeeBEANS through NODE_OPTIONS by the startup
// part: an exception nobody catches, thrown in main as soon as the app is
// ready, ahead of its window. A preload runs before Electron's own modules
// can be required, hence the first timer.
setTimeout(() => require('electron').app.whenReady().then(() =>
  setTimeout(() => { throw new Error('startup: thrown in main') }, 0)), 0)
