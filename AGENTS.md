# Notes for whoever picks this up next

README says what CoffeeBEANS is and how to use it. NOTES.md is the design
diary. This file is the working state: what is half-built, what was decided
and why, and the facts that cost something to learn.

## Running and testing

    npm start                                the app
    npm test                                 all 93 checks, ~95s
    BEANS_TESTS=stepping npm test            one part, ~10s

Parts: `editor image repl buffers stepping lifecycle drawing color loading
shell input perf`. Each starts from a reset app, so running one alone means
the same thing as running it in the middle of everything else.

Other switches: `BEANS_SHOW=1` shows the test window (hidden by default, so a
run never steals focus), `BEANS_MINIMIZE=1` minimises it (the only way to
exercise `backgroundThrottling`), `BEANS_DEVTOOLS=1` opens DevTools detached,
`BEANS_CAPTURE=2500` screenshots to `tmp/` then quits, `BEANS_QUERY='?sketch=
bounce&run=1'` drives the app from the URL, `BEANS_DATA_HOME=test_tmp` keeps a
run away from the real data folder.

**Do not pipe `npm test` into `head`.** Closing stdout mid-run throws EPIPE out
of the main process and Electron shows a modal dialog. Redirect to a file.

The suite waits on the app, never on the clock: `t.settle()` polls the status
line, `t.quiet()` polls `Printing.pending()` (bytes still in the print ring or
lines still queued). Fixed sleeps were tried twice and both times produced a
suite that *lied* — on a busy machine every check read the previous test's
console. If you add a check, use the helpers.

## House rules worth knowing

**Shared scope is the hazard.** The renderer, the worker bootstrap and the
runtime each compile into one scope. NOTES.md lists three bugs from a name
that looked free (`history`, `onmessage`, `load`); a fourth (`frame`, the
present loop, clobbered by `for frame in frames`) killed rendering entirely
and took forty tests with it. Before naming anything at file scope, check it.

**Comments say why, not what.** Match the density around you.

**`screen` resets every drawing mode** — buffering, fps cap, draw target,
brush, text cursor. Each of those, left set, makes the next sketch draw
nothing with no error.

## Where the debugger work stands

Committed: `dd834d2` (frame stepping + source maps), `e1260d0` (`breakpoint`
and named runtime modules). The plan file that got us here is
`~/.claude/plans/all-excellent-news-i-floofy-shell.md`; this section supersedes
its Stage 3 and 4.

Done:

- **Frame stepping.** Pausing is declining to clear `H.SWAP`. The worker parks
  in `doSwap`'s `Atomics.wait`, which wakes every 100ms, so a frame-paused
  sketch still answers the `>` prompt. `Stepping.pause/step/go` in the
  renderer; `:pause`, `:step`, `:continue`.
- **Source maps.** `runSketch` emits an inline `sourceMappingURL` beside the
  existing `sourceURL`, shifted past the 3-line prologue by prefixing three
  `;` to `mappings`. DevTools shows CoffeeScript today.
- **`breakpoint`.** A getter compiling to `debugger`, in its own module. Works
  in DevTools now.
- **Named runtime modules.** `beans-runtime/<name>.js`, so a debugger can be
  told to ignore the family in one pattern.

Next, in order:

1. `src/main/debugger.coffee` — attach, a session per worker, arm/disarm, a
   whitelisted IPC surface. Nothing user-visible.
2. Line-paused state, the four verbs, and the two fixes below.
3. The variables pane.

## Must fix as part of line stepping

- **The Stop watchdog will shoot a V8-paused worker.** `stop()` terminates
  after 250ms if status is still running; a paused worker can never reach
  `checkInterrupt`, so it *always* misses, destroys the live image, and blames
  it on "no yield point", which is a lie. Freeze the deadline while paused.
- **`Prompt.ask` wedges against a V8-paused worker.** It sets `ASK_STATE = 1`
  and nothing serves it, so every later line says "still waiting on the last
  one". Route the prompt to `Debugger.evaluateOnCallFrame` while paused —
  better anyway, since you get the paused frame rather than the image.

## Facts the spikes established

Verified against a real CDP session in Electron 44; do not re-derive.

- `Target.setAutoAttach {autoAttach, waitForDebuggerOnStart, flatten: true}`
  on the page session yields `Target.attachedToTarget` with
  `targetInfo.type === 'worker'` for the sketch worker. Electron's
  `sendCommand(method, params, sessionId)` and the 4-arg `message` event carry
  the session both ways.
- `//# sourceURL=` makes an eval'd sketch an addressable script.
  `setBreakpointByUrl` with `urlRegex: '^beans-run-\\d+\\.coffee$'` binds
  pending and fires `breakpointResolved` when the script parses, then hits.
  V8 snaps the line to the nearest breakable location.
- The local scope at a sketch pause is exactly the sketch's own variables plus
  `__image` and `__frames` — filter names starting `__`, drop the `global`
  scope, keep `local`/`closure`/`block`/`catch`.
- **`callFrame.url` comes back empty.** Keep a `scriptId → url` map from
  `Debugger.scriptParsed`; do not read the url off a pause.
- A `breakpoint` hit leaves the top frame inside `beans-breakpoint.js`, which
  cannot be ignore-listed (see below), so V8 will not step out of it. One
  `Debugger.stepOut` lands on the author's line.
- `Debugger.pause` latency is ~4ms, not the ~100ms predicted — the 100ms
  timeout in `doSwap`'s wait loop bounds it.
- `waitForDebuggerOnStart: true` needs `Runtime.runIfWaitingForDebugger` in a
  `finally` **and** a hard timeout, or a broken handler leaves the app on
  `booting` with no error.
- DevTools and `webContents.debugger` are mutually exclusive: attaching while
  DevTools is open throws, and opening DevTools force-detaches the session.
  Handle `devtools-opened`/`devtools-closed` and say so in the UI.
- `Debugger.enable`'s frame-rate cost was measured and is **inconclusive** —
  ratios 0.79/0.96/1.18/0.78, one pair faster armed, noise larger than the
  effect. Do not re-measure on a loaded machine; the decision below does not
  depend on it.

## Decisions, so they do not get relitigated

- **`breakpoint` in the source, not clickable gutter breakpoints.** The marker
  moves with the text, survives a region eval and a vim write, needs no
  bookkeeping, and is a no-op when nothing is attached. Gutter breakpoints
  remain possible later and would be purely additive.
- **`breakpoint.coffee` must never be ignore-listed.** A debugger skips
  `debugger` statements inside an ignored script, so the command would quietly
  stop working. That is why it sits outside `beans-runtime/`.
- **Only pause in user code.** Blackbox `beans-runtime/` and `worker-boot.js`.
  If runtime debugging is ever wanted, gate it behind an env var.
- **Two kinds of pause, named apart:** `frame paused` and `line paused`.
  `held`/`paused` was rejected — you cannot remember which is which.
- **No mode toggle.** Both step buttons mean something in both states: from a
  frame pause, step-line resumes and breaks on the next sketch line; from a
  line pause, step-frame runs to the next frame boundary.
- **Ctrl-Z is the line pause** (suspend *now*, like the shell). The ❚❚ button
  is the frame pause (stop at a boundary). The means of pausing picks the kind.
  Clicking outside the canvas was considered and rejected — that is how you get
  to the editor.
- **Arm from the buffer**: attach when the buffer contains `breakpoint`,
  detach when it does not, debounced off the keystroke stream the line counter
  already uses. Zero ceremony, and it cannot be armed-when-you-forgot.
- **Variables get their own pane**, not printed into the console, so a value
  can be watched changing as you step.
- **Never auto-invoke accessors in the pane.** `buffer.swap` is a getter that
  blocks and draws a frame — expanding an object must not advance the program.
  `throwOnSideEffect: true` for the pane, `false` for the prompt, and offer
  click-to-run when V8 refuses.
- **Pausing on uncaught errors is wanted** — landing in the debugger with
  `ball` live beats four lines of traceback, especially for a beginner hitting
  `Cannot read properties of undefined`. Blocked for now: `worker-boot.js`
  wraps `runSketch` in a `try/catch`, so V8 predicts every sketch error as
  caught and `pauseOnExceptions: 'uncaught'` never fires. Needs either
  pause-on-all plus auto-resume outside user code, or restructuring how sketch
  errors propagate. Must read as *an error*, not a silent freeze.

## The scope wall

Robert raised scope creep himself and set the test: **could you have done it in
AmigaBASIC with `STOP`?** The motivating case is small and concrete — put a
breakpoint in `addAngle`, look at its parameters, notice you are passing a
vector where you meant a scalar, get back to playing.

In: `breakpoint`; the line highlighted; the locals of that frame; the `>`
prompt against the paused frame; four verbs (step line, step frame, continue,
stop).

Out, each needing a fresh reason: clickable gutter breakpoints, conditional
breakpoints (`breakpoint if angle > pi` is already just code), watch
expressions (the prompt is one, and better), a clickable call stack (a one-line
breadcrumb, maybe), editing values in the pane, stepping into the runtime.
