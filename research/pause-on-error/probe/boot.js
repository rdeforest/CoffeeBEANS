// Stands in for worker-boot.js, in the three shapes the note compares. Loaded
// under a URL matching the app's '/src/renderer/' ignore pattern.
;(() => {
  let seq = 0

  // As runSketch does: the sketch inside a function, inside try/finally.
  const runSketch = (source, id) => {
    const wrapped = `(function(){\ntry{\n${source}\n}finally{}\n})\n//# sourceURL=${id}`
    // A function body has no completion value; the cost loops leave theirs here.
    globalThis.RESULT = undefined
    ;(0, eval)(wrapped)()
    return globalThis.RESULT
  }

  const report = (error) => ({
    type:    error instanceof Interrupted ? 'stopped' : 'error',
    message: String(error && error.message),
    mapped:  /beans-run-\d+\.coffee:\d+/.test((error && error.stack) || ''),
  })

  // What the error event saw, for the two shapes that let the error escape.
  let escaped = null
  self.addEventListener('error', (event) => {
    event.preventDefault()
    escaped = event.error
  })

  const styles = {
    // Today's shape: run() catches, inside an async listener that catches too.
    catch: (data) => {
      try {
        const result = runSketch(data.source, data.id)
        postMessage({type: 'done', result})
      } catch (error) {
        postMessage(report(error))
      }
    },

    // Way (b): nothing catches; the error leaves the listener and comes back
    // as an error event, which the next message (or a timer) reports.
    escape: (data) => {
      escaped = null
      setTimeout(() => postMessage(escaped ? report(escaped) : {type: 'done', result}), 0)
      const result = runSketch(data.source, data.id)
    },

    // Way (c): still synchronous. dispatchEvent reports a listener's error
    // instead of throwing it to the caller, so nothing on the stack catches it.
    dispatch: (data) => {
      escaped = null
      let result
      const runner = () => { result = runSketch(data.source, data.id) }
      self.addEventListener('beans-run', runner)
      self.dispatchEvent(new Event('beans-run'))
      self.removeEventListener('beans-run', runner)
      postMessage(escaped ? report(escaped) : {type: 'done', result, sync: true})
    },
  }

  // Today's listener is async and catches around the handler; the catch style
  // keeps that. The other two need a plain listener: an async one would turn
  // the escaping error into a rejected promise rather than an error event.
  const today = async (data) => {
    try {
      await styles.catch(data)
    } catch (error) {
      postMessage(report(error))
    }
  }

  // The app's real listener keeps its async try/catch around every handler.
  // Does a catch *above* dispatchEvent bring the prediction back to caught?
  const todayAround = async (data) => {
    try {
      await styles.dispatch(data)
    } catch (error) {
      postMessage(report(error))
    }
  }

  self.addEventListener('message', ({data}) => {
    if (data.type !== 'run') return
    if (data.style === 'catch') return today(data)
    if (data.style === 'dispatchInCatch') return todayAround(data)
    styles[data.style](data)
  })
})()
