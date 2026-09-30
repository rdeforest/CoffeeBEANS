# Advanced features: physics, and the question behind it

An open question, written down on 2026-09-29 so it stays open on purpose
rather than getting settled by whoever touches it next. Nothing here is
decided and nothing here is scheduled. The priorities in AGENTS.md stand.

## How the question came up

`sketches/particles.coffee` started as balls bouncing around the screen.
Then walls seemed like a nice addition. Then came the thought: do I really
want to reinvent this wheel? matter-js was the first physics library that
turned up, and trying it hit a wall at once: sketches have no `require`.

That quickly turned into a bigger question than "how do I get matter into
a sketch". Adding a physics library means adding a way to extend
CoffeeBEANS. That was the itch to widen the project's scope, and following
it too far would turn CoffeeBEANS into something it was never meant to be.

CoffeeBEANS exists so that this works, and it has worked:

```coffee
screen width = 320, height = 200

[midX, midY] = [width/2, height/2]

for x in [0..width] by 5
  line x,          0, midX, midY
  line x, height - 1, midX, midY
for y in [0..height] by 5
  line 0,          y, midX, midY
  line width - 1,  y, midX, midY
```

Any advanced feature should be measured against that sketch. If a feature
makes it longer, or leaves a beginner reading it wondering what else they
are supposed to know, it costs more than it looks.

## What is settled

- **CoffeeBEANS is not open for extension.** If anything, things outside
  the original spec should be closed off, not added.
- **Sketches should be easy to share.** A sketch that only runs because of
  something installed on its author's machine does not meet that.
- **No plugin system before 1.x.** If libraries are added before then, add
  them in a way that could later become a plugin system.

## A hole in the wall we already have

The sandbox is easy to reason about because sketches cannot reach
`node:fs` and its relatives: `nodeIntegration` is off and sketches run in a
worker. But there is no Content-Security-Policy anywhere, and sketches run
through `eval` in a worker that has `fetch` and `importScripts`. The only
gate is COEP `require-corp`, and CDNs such as jsDelivr send
`Cross-Origin-Resource-Policy: cross-origin` to get past it. So a sketch can
probably `importScripts` a library off the internet today. This has not
been tried.

That matters for support as much as for security: "I imported BLAH and it
doesn't work, please fix." There are two ways to close it:

- **Remove the functions after boot.** Harder than it looks: `importScripts`
  and `fetch` live on `WorkerGlobalScope.prototype`, not on `self`, so
  `delete self.importScripts` does nothing and `self.constructor.prototype`
  still reaches them. Our own bootstrap also needs both (`coffeescript.js`,
  `loadModule`), so removal has to come after loading. Good enough to stop
  the support requests, but not a real barrier.
- **Add a CSP** to the responses in `serve`. This is the actual barrier.

Either is cheap, and neither depends on how the physics question comes out.
There are probably other worker-only APIs worth auditing in the same pass.

## The options

### 1. `require` in sketches

A CommonJS shim that resolves `node_modules` over `app://`.

- For: any library, and the syntax the tutorials use.
- Against: every npm package becomes part of the surface you have to audit.
  Many packages assume Node or the DOM and fail in confusing ways. A sketch
  depends on what happens to be installed, which breaks sharing. The module
  cache and the live image have different lifetimes, so after a restart the
  image is clean but the modules are not. And it is exactly the door to
  things that are better played with in VS Code.

### 2. Load from a URL

Fetched from a CDN and cached the way `load` caches images (`cachedBytes`).

- For: nothing to install, the sketch names its own dependency, and the
  offline cache already exists.
- Against: a supply-chain hole in exactly the place meant to be easy to
  analyse. It only works because of the gap above. The first run needs a
  network connection.

### 3. A curated library that ships with the app

Vendor the library and load it in the worker the way `MODULES` are loaded.
There are two ways to expose it:

- **3a. Always present**, as a global such as `Matter`. Trivial to build,
  but it adds a name to shared scope and costs boot time for every sketch.
- **3b. Opt-in and blocking**, like `load`: `physics = library 'matter'`.
  The sketch chooses its own name, so nothing new appears at file scope. It
  loads on first use and then stays loaded. A manifest entry (name, file,
  what is exported, help text, which debugger family it belongs to) is the
  shape a 1.x plugin system would grow from.

- For both: you check each library once, you decide what is exposed, and it
  works offline. It uses a solved wheel instead of reinventing one.
- Against both: you now have to track upstream security updates for every
  library you ship.

### 4. A CoffeeBEANS-flavoured wrapper

A BASIC-shaped API over some engine (not necessarily matter):

```coffee
b = ball x, y, r
wall x1, y1, x2, y2
gravity 0, 1
step
```

- For: sketches stay minimal, the surface we promise to support stays small,
  and it reads well to a beginner. Switching engines underneath becomes
  possible.
- Against: a second API to design and keep in sync. The underlying engine's
  docs and tutorials stop applying. Easy to spend a week on. Most naturally
  built on top of 3b, once the raw API has been shown to fight the style.

### 5. Our own physics in `src/runtime/`

Verlet or impulse-based; circles, boxes and walls.

- For: readable source people can learn from, and fully steppable in the
  debugger. We can make choices that suit our execution model (a fixed step
  per frame, the live image, restart meaning a clean slate) and our taste.
  No third-party code and no upstream to track.
- Against: getting stacking, rotation, friction and constraints right is real
  work, and matter has already done it. We then have to maintain it. It also
  overlaps with `particles.coffee`, which is play and should stay play.

### 6. A different engine

- **planck.js** (JS port of Box2D): works in a worker, and stacking and
  joints are more accurate than matter's. The API is heavier and uses metres
  rather than pixels.
- **Rapier** (WASM): fast and deterministic. Opaque to the debugger, needs
  async init, and is large.
- **p2.js** is unmaintained. **verlet-js** is small but toy-grade.
- matter is the friendliest of these for pixel-scale 2D and for beginners.

### Shortlist

Still under consideration: **3b**, **4** and **5**.

## Trade-offs, as weighed so far

- Shipping third-party libraries means tracking upstream security updates.
- Building our own means maintaining the code.
- Our own wrapper keeps sketches minimal and keeps the interface we support
  small.
- A third-party library saves reinventing the wheel.
- Building our own lets us make choices that suit our execution model and
  our aesthetic better.

## Worker interactions any option must handle

Written against matter, but most of these apply to any engine.

- **Debugger.** The library needs a named `sourceURL` in a family the
  debugger ignores (for example `beans-lib/matter.js`), or stepping out of
  `Engine.update` lands in collision code. This follows from the "only pause
  in user code" decision in AGENTS.md.
- **DOM-dependent parts.** matter's `Render`, `Runner` and `Mouse` need
  `document` or `window`, so leave them out of what is exposed. The sketch
  calls `Engine.update engine, 1000/60` in its own loop and draws with our
  primitives, which fits CoffeeBEANS better anyway. `Common.now` falls back
  to `Date` when there is no `window`. Concave bodies need `window.decomp`
  and stay unavailable.
- **Restart.** matter keeps global state (`Common._nextId`, its random seed,
  the `Matter.use` plugin registry). Either evaluate the library again on
  restart or accept ids that carry over between runs. Evaluating it again
  keeps "restart means a clean slate" true.
- **Watchdog.** `Engine.update` with thousands of bodies has no yield point.
  Stop still works, but the error it gives may blame the wrong cause, as
  the existing "no yield point" message already does.
- **`:help` and tab completion.** Library names need help entries. Walking
  the property descriptors on matter's namespace is safe: it has no getters
  with side effects.

## Deliberately left open

- **Always-on or opt-in?** Startup time is not the worry: anything under
  the five seconds it takes to say "I wonder how long this program will take
  to start" is fine. The real tension is between not having to call a
  function to bring a library in, and swamping a beginner with too many
  things they can do at once.
- **Build, wrap, or ship?** Choosing between 3b, 4 and 5, or a combination
  such as 4 built on 3b or 4 built on 5.
- **Is this CoffeeBEANS at all?** Physics, 3D and similar features might
  belong in a separate "pro" edition some day rather than in the base. Or
  the better use of the effort might be making Godot friendlier, and leaving
  CoffeeBEANS as a small BASIC-shaped toy.

Until one of these is answered, `particles.coffee` does its own physics,
and that is fine.
