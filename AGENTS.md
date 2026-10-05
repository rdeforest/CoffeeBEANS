# Notes for whoever picks this up next

README says what CoffeeBEANS is and how to use it. NOTES.md is the design
diary. This file is the working state: what is half-built, what was decided
and why, and the facts that cost something to learn.

## Before starting work

**Check upstream first**, every session, before touching anything:

    git fetch && git status
    git log --oneline HEAD..origin/main      # what arrived
    git log --oneline origin/main..HEAD      # what is local only

Robert works on this repo from two machines and from several kinds of Claude
session (CLI, desktop, cowork), so a local copy is often behind. Read what
arrived before building on top of it, and say if any of it contradicts what
you were about to do.

**And never rewrite a commit without checking it is unpushed** --
`git branch -r --contains <commit>` prints nothing for a local-only one. On
2026-10-04 a Claude session amended a commit Robert had already pushed, and
his next pull conflicted with itself. Once pushed, a correction is a new
commit, not an amend.

## How code changes get made

From 2026-10-04 CoffeeBEANS is worked the way voxel-mvp was on the nights of
2026-09-26 and 09-27 (its `docs/overnight-2026-09-27.md` is the worked
example), at Robert's request.

**The day** is Robert's: review what landed overnight, answer the agents'
questions, talk about the big picture, test by hand, and queue the next
night's work before bed. **The night** is the agents', working the queue
while he sleeps.

**The queue** is one plan per night, `docs/overnight/YYYY-MM-DD.md` (named
for the morning it lands, as voxel-mvp's were), drafted by Claude and
approved by Robert. It holds a progress checklist; the tracks,
each with its branch, worktree and the files it owns (a chunk that needs
another track's file stops and says so); the session facts a restarted
session needs, the suite's check count first; and, by morning, the brief.
Closed out, it moves to `docs/overnight/done/`.

**Every code change goes through the loop:**

- an **author** writes the chunk;
- two **reviewers**, in parallel and adversarial, see only the diff and the
  files it names -- one hunting for wrong behaviour, one for what is missing
  (the part of the ask not done, the check that would pass against the old
  code too);
- a **tiebreak** when the author disputes a blocking finding;
- a **fixer** applies what survives and commits only on a green suite,
  explaining any change in the check count.

voxel-mvp ran Opus 5.5 as author, correctness reviewer and fixer, Sonnet 5
as completeness reviewer and Fable 5.1 as tiebreak. Each night's plan names
its own. After the tracks merge, one more review reads the combined result:
in voxel-mvp that is the step that caught the cross-track bugs.

**Standing rules for a night:**

- A question that needs Robert's judgement goes in the brief with its
  evidence, and work moves on. Do not guess his intent and build on the guess.
- Anything decided without him goes in the brief, so he can overrule it.
- Do not shrink a chunk to close it. If the hard part was cut, say so.
- Commit the smallest chunks that pass; push after each merge, checking
  upstream first (above).
- Whether two suites can run at once without the frame-timing checks failing
  is not known yet. Run them one at a time until it is measured.

**The morning brief**, at the bottom of the plan: what needs Robert first;
what landed; what was decided without him; what was not done and why; and a
list of things to try by hand.

## Running and testing

    npm start                                the app
    npm test                                 all 171 checks
    BEANS_TESTS=stepping npm test            one part, ~10s

Parts: `editor image repl buffers stepping debugging focus lifecycle drawing
color loading shell input sound perf`. Each starts from a reset app, so running one alone means
the same thing as running it in the middle of everything else.

Other switches: `BEANS_SHOW=1` shows the test window (hidden by default, so a
run never steals focus; on Linux a hidden run is shown inactive and then
minimised, see Platform facts),
`BEANS_MINIMIZE=1` minimises it (on macOS the only way to exercise
`backgroundThrottling`), `BEANS_DEVTOOLS=1` opens DevTools detached,
`BEANS_CAPTURE=2500` screenshots to `tmp/` then quits, `BEANS_QUERY='?sketch=
bounce&run=1'` drives the app from the URL, `BEANS_DATA_HOME=test_tmp` keeps a
run away from the real data folder.

**Do not pipe `npm test` into `head`.** Closing stdout mid-run throws EPIPE out
of the main process and Electron shows a modal dialog. Redirect to a file.

**`npm test` exits nonzero when a check fails** -- since 2026-10-04. Before
that it always exited 0 (Electron's quit path ignores `process.exitCode`; the
suite now uses `app.exit`), which is how the Linux suite stayed red for weeks
with nobody hearing. Trust the exit status now, and run the suite on Linux as
well as the Mac before calling something done.

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

It cuts both ways, and order matters. CoffeeScript resolves scope in file
order, so a file-scope variable assigned *below* a function that also assigns
it becomes that function's local instead: `inFlight` in the renderer did this
on 2026-10-04 and `send` recorded nothing anybody read. Declare file-scope
state above every function that touches it, and when in doubt, read the
compiled output -- an inner `var name` or a `typeof name` guard is the tell.

**Comments say why, not what.** Match the density around you.

**`screen` resets every drawing mode** — buffering, fps cap, draw target,
brush, text cursor. Each of those, left set, makes the next sketch draw
nothing with no error.

## Priorities

**The direction changed on 2026-10-04:** CoffeeBEANS becomes a game for
Steam, done by 2027-07-30, aimed at Next Fest in October 2027. The schedule
and every decision behind it are in `docs/ROADMAP.md`; read it before
choosing what to work on.

Now: Phase 0 there -- the licence, builds and tests for all three platforms
in CI, seeded `rnd` (NOTES.md, Seeded randomness), feature gating, and the
sandbox mode.

From Robert's playtesting, 2026-10-04:

- **The editor defaults to ordinary keys; vim is an option.** Most people on
  Steam will not want vim. Emacs keys if anyone asks (after some mockery);
  WordStar users get pointed at Turbo Pascal.
- **The prompt behaves like the node and coffee REPLs** -- readline's emacs
  keys and Tab completion. Tab completion is no longer parked (its design is
  at the bottom of this file).
- **Commands at the prompt**, as `/run` or `:run`: a line starting with
  either is always a command, and CoffeeScript that starts with a regex goes
  in parens. Vim's ex commands and the prompt share one table. The vim
  switch is a remembered checkbox in the Edit menu.

Earlier priorities, by Robert on 2026-09-28: debugging (done 2026-09-29);
sound (first pass done 2026-09-29; the modular synth and effects wait on the
roadmap).

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
- **Nothing may reach V8 while the prompt is evaluating in a paused frame.**
  A `stepInto` sent into a still-running `evaluateOnCallFrame` segfaults the
  renderer (null deref in v8_inspector on the DedicatedWorker thread; found
  2026-10-01, reproduced 2026-10-03). Step and continue are refused while one
  is out; Stop waits it out. `timeout` on `evaluateOnCallFrame` bounds it
  (`EVAL_LIMIT`): V8 terminates the expression, the call rejects with
  "Execution was terminated", and the paused frame stays usable.
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
expressions (the prompt is one, and better), editing values in the pane,
stepping into the runtime.

A clickable call stack was on that list. Robert moved it in on 2026-10-04,
for runtime errors: the stack shows in the variables pane, innermost first,
the innermost line marked, the prompt focused, and a click takes the editor
to a frame's line (`showStack`/`visitFrame` in the renderer, test part
`focus`). It is post-mortem -- the frames are gone, only their lines are
known -- so it is not "pausing on uncaught errors", which is still blocked
(see Decisions). A live stack while line paused is still out, but now that
the pane can draw one, it would be cheap if a reason turns up.

## Platform facts

Each of these passed on the Mac and failed on Linux, so check both.

- **Watch folders, never files.** On Linux Node implements
  `fs.watch(dir, {recursive: true})` itself by watching every file's inode,
  and a file replaced by rename -- vim's save, and our own atomic save --
  leaves its watch on the dead inode: the first save is seen, none after.
  `watchSketches` watches each folder non-recursively and adopts folders
  that appear. Node fixed this upstream in v26.9.0 (nodejs/node#65486,
  2026-08-31); Electron 44 ships Node 24.20, which does not have it, and
  the PR carries no v24 backport label. Measured by Claude, 2026-10-04,
  on 24.20, 26.8 (broken) and 26.10 (fixed). To check a newer Electron:
  under `fs.watch(dir, {recursive: true})`, save a file twice by renaming a
  new one over it; if the second save reports, the fix has arrived and the
  hand walk could go back to `recursive`.
- **A never-shown window that draws gets about one animation frame a second
  on Linux**, `backgroundThrottling: no` or not. Both halves matter: the same
  never-shown window drawing nothing gets the full 144/s, and a window that
  was shown first keeps full rate even minimised afterwards -- so this is a
  test-run problem, not one a user meets. Timers are never affected (about
  245 `setTimeout(0)` wake-ups a second throughout). CoffeeBEANS draws every
  tick, so a hidden test run's present loop ticked once or twice a second
  and the frame-timing checks in `repl`, `buffers`, `stepping` and
  `debugging` failed. Measured by Claude, 2026-10-04: a 40-line probe
  drawing one `putImageData` a frame, and in the app a sketch counting
  `frames` (bumped every tick) against its own swaps -- one for one, so the
  swap handshake is innocent.

  **The fix** (`createWindow`): a hidden Linux run shows the window inactive,
  then minimises it 300ms after `show`. Results for those four parts,
  hidden: never shown 0 of 2 runs passed; minimised without being shown, a
  coin toss; shown then minimised straight from `show`, 2 of 3; with the
  300ms beat, 8 of 8, and the full suite green. The likeliest reading is
  that `show` fires when the map is requested, and an iconify that overtakes
  the map leaves a window that was never mapped. Not proven. If the timing
  parts start failing hidden again, look there first. The cost: the test
  window appears for 300ms, without taking focus (checked with
  `_NET_ACTIVE_WINDOW` sampled through whole runs), and sits minimised in
  the panel while the suite runs.

  **The machine these numbers came from**, in case they do not reproduce: a
  Linux X11 session under Marco, three 2560x1440 monitors across two GPUs --
  the middle one (DP-4, primary, 144Hz) on an RTX 5090, the outer two (left
  HDMI-1-1 at 60Hz, right HDMI-1-0 at 144Hz) on an RTX 4070. Chromium ran
  one 144Hz frame clock for every window, including one placed on the 60Hz
  monitor, so a frame rate measured here is that clock, not the monitor's
  -- and on the left screen the fps meter reads 144 while the screen shows
  60. Untested on a single-GPU Linux machine.
- **Vim's command line focuses the editor as it closes**, after running the
  command and inside the same keydown. Anything an ex command wants focused
  has to be focused a tick later (`toCanvas`), and a run that fails inside
  that tick cancels it. The `focus` part types `:run` through the real panel
  for exactly this; calling the ex handler directly would never catch it.

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
- Stop with nothing running only bumps the epoch. It used to raise the
  interrupt flag too, and with no busy worker to report idle, nothing would
  ever lower it -- the prompt bug above, reached by the obvious way to hush
  a held note that outlived its sketch.
- Voices: the worker names them, the worklet only sees small numbers from
  `voiceOf`, and drops a voice the moment it is idle. `SOUND_BUSY` is a
  count of voices sounding, not a bitmask.
- A test run is muted (`setAudioMuted`) unless `BEANS_SHOW` is set. Muting
  does not stop the worklet, so the sound checks still see everything.
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

## Tab completion (designed; wanted since 2026-10-04)

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
