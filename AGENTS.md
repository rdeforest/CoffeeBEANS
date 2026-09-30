# Notes for whoever picks this up next

README says what CoffeeBEANS is and how to use it. NOTES.md is the design
diary. This file is the working state: what is half-built, what was decided
and why, and the facts that cost something to learn.

## Running and testing

    npm start                                the app
    npm test                                 all 133 checks, ~120s
    BEANS_TESTS=stepping npm test            one part, ~10s

Parts: `editor image repl buffers stepping debugging lifecycle drawing color
loading shell input sound perf`. Each starts from a reset app, so running one alone means
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

## Priorities

Robert's order, set 2026-09-28:

1. **Debugging** -- done 2026-09-29: line stepping and the variables pane,
   below.
2. **Sound.** First pass done 2026-09-29; the design and what is parked are
   in NOTES.md under Sound. Robert wants a modular synth and effects later.
3. **Tab completion at the console** -- designed and parked, at the bottom of
   this file. Do not start it ahead of the other two.

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

- **Line stepping** (`src/main/debugger.coffee`, the `line stepping` and
  `variables pane` sections of `renderer.coffee`, test part `debugging`).
  The buffer arms it; `breakpoint`, Cmd/Ctrl-\ / F8, F10 / `:line`, the ↧
  button; the pane beside the console; the prompt against the paused frame.
  Both must-fixes are in: Stop lets a line-paused sketch go with pauses
  skipped and only then starts its deadline, and the prompt goes through
  `Debugger.evaluateOnCallFrame` while line paused.
- **Region line numbers are buffer line numbers.** A region is padded with
  blank lines down to where it sits, so errors, tracebacks and pauses all
  name the line in the file.

Not done, each waiting on a reason:

- **Click-to-run for a getter in the pane.** It shows `(getter, not run)`;
  the prompt can run it (`o.boom`), which is the escape hatch for now.
- **Pausing on uncaught errors** -- still blocked, see Decisions.

## Facts line stepping established

Verified in Electron 44 while building it; do not re-derive.

- **Never re-attach to a worker you have detached from.** `Debugger.enable`
  on the new session hangs forever -- even with `Debugger.disable` and
  `Target.detachFromTarget` first. So the page stays attached once armed,
  and arm/disarm is `Debugger.enable`/`disable` on the live session, which
  re-enables fine. DevTools forces a detach, so after it closes breakpoints
  work from the next Run (a fresh worker), and the app says so.
- **`Debugger.pause` stops inside ignore-listed code** -- `doSwap`, for a
  sketch parked on a frame -- and a `stepInto` from there never stops on the
  way back to the sketch; V8 only stops a step-in at a call. `stepOut`
  carries past every ignored frame to the author's line. The same goes for
  the wrapper's `harvest`/`restore` and the prompt's compiled line.
- **A local scope object is a snapshot.** After the prompt assigns to a
  local, `Runtime.getProperties` on the old scope still shows the old value;
  re-read each local with `evaluateOnCallFrame` (`throwOnSideEffect: true`).
  Closure scopes are live.
- **CoffeeScript's `modulo` and `boundMethodCheck` helpers** live in the
  sketch's own script and map to its first line; they are stepped out of,
  recognised by name and by their body sitting on their header's line. The
  other helpers (`slice`, `indexOf`, `hasProp`, `splice`) are natives.
- **A `breakpoint` pause shows the line after it** -- the line about to run,
  which is what the highlight means everywhere. That comes from the one
  `stepOut` needed to leave `beans-breakpoint.js`.
- **`Target.setAutoAttach` answers after attaching the existing worker**, so
  the session is known when it resolves; no polling.
- **`t.settle()` counts both pauses as settled.** A check that waits for a
  Stop to finish has to wait for `ready` itself.

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
- **Cmd/Ctrl-\ (and F8) is the line pause** -- suspend *now*. Ctrl-Z was the
  first choice and was dropped 2026-09-29: it is undo on Windows, and Steam
  means Windows. `\` and F8 are DevTools' own pause/resume keys, and Ctrl-\
  is the shell's other stop key. The ❚❚ button is the frame pause (stop at a
  boundary). The means of pausing picks the kind.
  Clicking outside the canvas was considered and rejected — that is how you get
  to the editor.
- **Arm from the buffer**: armed while the buffer (or the source being run)
  contains `breakpoint`, disarmed when it does not, debounced off the
  keystroke stream the line counter already uses; a run checks for itself
  first. Zero ceremony, and it cannot be armed-when-you-forgot. Armed means
  the Debugger domain is on, not attached -- see the re-attach fact above.
- **A line step is a step *into*:** the next line that runs, wherever it is.
  The runtime is ignore-listed, so `print` and `buffer.swap` are one step.
  There is no separate step-over; the scope wall has room for four verbs.
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

## Sound, the facts worth keeping

- `sound-worklet.coffee` is compiled in the renderer and loaded as a blob
  with `layout.coffee` ahead of it; a worklet takes one module and has no
  CoffeeScript. Anything both sides need goes in LAYOUT (`CONTROL_RATE`).
- Stop and a new worker bump `SOUND_EPOCH`, and the worklet drops everything
  queued when it changes. Not the interrupt flag: that stayed raised after a
  Stop, and would have swallowed a note typed at the prompt.
- The interrupt flag is now lowered when the worker reports `done`,
  `stopped` or `error`. Before, every yield point reached from the prompt
  after a Stop -- `buffer.swap` too, not just `sound` -- threw 'stopped'.
- `SOUND_HOLD` follows the status line: either pause freezes the audio clock.
- `main.coffee` sets `autoplayPolicy: 'no-user-gesture-required'`; without it
  the AudioContext starts suspended and the first sketch is silent.
- A test run is not listened to. The worklet reports notes begun, a peak per
  render quantum and a busy bit per voice (`Sound.*` in the renderer), and
  the `sound` part checks those. None of it says the result sounds good --
  that takes an ear.

## Open for discussion

- **What the canvas does on zoom.** Cmd-minus / Cmd-equals (View menu
  roles) rescale the whole window, canvas included. Should the canvas follow
  the UI zoom, scale itself up to fill the stage on its own, or have an
  option? Raised 2026-09-29; nothing decided.

## Tab completion (parked, lowest priority)

Estimated at ~150 lines plus ~5 checks in `repl`. Decided:

- **Bash style.** Tab completes as far as every candidate agrees, and beeps
  when that is ambiguous; a second Tab lists the candidates in the console.
  No popup -- it would fight the prompt history for Up/Down.
- **Only the CoffeeBEANS vocabulary.** Candidates are the image, the running
  sketch's harvested locals, and the runtime API. Worker globals (`Atomics`,
  `postMessage`, `WebAssembly`...) are left out: anyone who wants those is not
  using them from the console.
- **The worker answers, over the ask channel.** Only the worker knows the
  names worth completing. A new header word marks a completion question;
  `drainAsk` routes the answer to the completer instead of printing it, and
  drops an answer that arrives after the line has changed. A sketch with no
  yield point cannot answer, same as the prompt: Tab does nothing.
- **Never invoke an accessor to find members.** Resolve `a.b.` by walking
  property descriptors and refuse to pass through a getter -- `buffer.swap`
  draws a frame, `keys.poll` claims hits, `mouse.wheel` consumes. Same rule as
  the variables pane.
- **Share one "ask the worker" path with the prompt**, so the line-stepping
  fix that routes the prompt to `Debugger.evaluateOnCallFrame` while paused
  covers completion too, rather than completion wedging on its own.
