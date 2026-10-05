// Stands in for the runtime: an ignore-listed script (beans-runtime/) that
// throws on bad input, and the Interrupted a Stop throws from a yield point.
class Interrupted extends Error { constructor() { super('stopped') } }
globalThis.Interrupted = Interrupted
globalThis.colour = (name) => { throw new Error(`no colour named "${name}"`) }
globalThis.yieldPoint = () => { throw new Interrupted() }
