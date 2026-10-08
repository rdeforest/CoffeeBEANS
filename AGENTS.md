# Notes for whoever picks this up next

README says what CoffeeBEANS is and how to use it. NOTES.md is the design
diary. This file is the working state: what is half-built, what was decided
and why, and the facts that cost something to learn.

## Status: on hold, recreation only (since 2026-10-07)

Robert put CoffeeBEANS on hold on 2026-10-07 for a new venture that takes
his working energy. The Steam / Next Fest October 2027 target is dropped;
`docs/ROADMAP.md` stays as the record of that plan, not a schedule. He may
still open sessions because he enjoys it: no deadlines, no phases, no
overnight queues. Keep sessions short and small.

Where it stands: main is green at 663 checks on Linux (Windows CI green
apart from one runner-side `sound` flake). The last overnight,
`docs/overnight/2026-10-06.md`, is closed out; its morning brief holds the
open questions for Robert (retire arming from the buffer, main's uncaught
exceptions in a player's app, seeded examples' line endings on Windows,
redaction of names, Eval after DevTools, literal-first sketches, splitting
`main.coffee` and `renderer.coffee`) and a by-hand play-test list. The plan
moves to `docs/overnight/done/` once he has read it.

Next small step: the editor colours `a / f(b / 2)` as a regex (the legacy
CoffeeScript mode starts a regex at any `/` with another `/` later on the
line). Check upstream `@codemirror/legacy-modes` first, then patch the mode
and add a check.

Known bugs and gaps: the brief's "Not done" list, and the "Still open" notes
throughout this file.

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
- **Never `git stash`** in a night with worktrees: `refs/stash` is shared by
  every worktree of the repo. On 2026-10-05 two agents stashed at the same
  moment and each popped the other's chunk into the wrong worktree. Set a
  change aside as a patch file (`git diff HEAD > tmp/mine.patch`) instead.
- **Never touch Robert's desktop.** On 2026-10-06 an author looking for the
  test window ran `xdotool search --name CoffeeBEANS`, matched his Firefox (a
  GitHub tab named for the repo), sent it Escape, and moved the real pointer.
  Find a window by the PID you started, never by title; never move the
  pointer or focus a window you did not create.
- **Reviewers mutate a copy, never the worktree under review**: `git archive
  HEAD | tar -x` into `tmp/`, then `git diff --cached | patch -p1` (`git
  apply` silently does nothing there), and symlink `node_modules`. Twice on
  2026-10-06 a reviewer reverted code in the real worktree mid-run and
  invalidated the other reviewer's results.
- **A fixer's commit that adds mechanism gets its own correctness review**
  before merge. On 2026-10-06 nearly every such review found something, and
  several were blocking.

**The morning brief**, at the bottom of the plan: what needs Robert first;
what landed; what was decided without him; what was not done and why; and a
list of things to try by hand.

## Running and testing

    npm start                                the app
    npm test                                 all 663 checks
    BEANS_TESTS=stepping npm test            one part, ~10s

`npm test` runs `test/run.coffee`, which works from cmd.exe and PowerShell
too; set a switch there with `set BEANS_TESTS=stepping` (cmd) or
`$env:BEANS_TESTS='stepping'` (PowerShell) before `npm test`. After a green
full run the runner, not the app, removes `test_tmp`: on Windows Electron
still holds its own files in there until it has exited.

**CI** (`.github/workflows/test.yml`, since 2026-10-05): the suite on
ubuntu-24.04 (under xvfb) and windows-latest on every push, macOS on a `v*`
tag or by hand (`gh workflow run test.yml`). The repo is private, so runs
cost minutes: push merges, not every commit.

Parts: `startup problems editor image repl buffers stepping debugging focus
lifecycle drawing color loading shell about report input random names sound
perf pauseonerror stopbutton`. Each starts from a reset app, so running one alone means
the same thing as running it in the middle of everything else. `quit` runs
only when named (`BY_NAME` in `test/suite.coffee`): it ends the app it runs
in, so `lifecycle` starts a second Electron to run it, and `startup` starts
children of its own. Error stops are off in every part except `pauseonerror`
(Robert, 2026-10-05), through the same switch the preference uses.

Other switches: `BEANS_SHOW=1` shows the test window (hidden by default, so a
run never steals focus; on Linux a hidden run is shown inactive and then
minimised, see Platform facts),
`BEANS_MINIMIZE=1` minimises it (on macOS the only way to exercise
`backgroundThrottling`), `BEANS_DEVTOOLS=1` opens DevTools detached,
`BEANS_CAPTURE=2500` screenshots to `tmp/` then quits, `BEANS_QUERY='?sketch=
bounce&run=1'` drives the app from the URL, `BEANS_DATA_HOME=test_tmp` keeps a
run away from the real data folder, `BEANS_STARTUP_ANSWERS` answers the
startup problem box in a child run (`startup` part).

**Nothing a test runs may open anything on the desktop.** Every call that
would -- the startup box, Open Folder, the report's Show in Folder and
issues page, the sketch picker -- goes through `onDesktop` in
`main.coffee`, which under `BEANS_TEST` prints what it would have done and
records it in `opened` for the suite instead (I1, 2026-10-06). Add any new
one there.

Under `BEANS_TEST` an uncaught exception in main prints its stack and exits
1 (since 2026-10-06, A2). Without that, Electron puts a modal "JavaScript
error in the main process" box on screen and a hidden run hangs under the
suite lock until someone kills it -- which happened twice that night.

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

**The image keeps what the compiled `var` names.** CoffeeScript puts every
top-level name into one leading `var`, and `declaredNames` in
`worker-boot.js` reads it. Until 2026-10-06 (D2) it skipped only `/* */`
ahead of it, so a sketch whose first line was a `#` comment (compiled to
`//`) kept none of its names. Comments of either kind are skipped now. A
sketch that opens with a literal -- a docstring, a number, backtick
JavaScript that is more than a comment -- still keeps nothing: skipping
those safely needs a lexer, because a heredoc can hold a line starting
`var`. A `###` block followed by a `#` line compiles the `//` *after* the
`var`, so a check written in that order passes against the old code.

## Priorities

**On hold since 2026-10-07** (see Status, at the top). What follows is the
record of the priorities before that.

**The direction changed on 2026-10-04:** CoffeeBEANS becomes a game for
Steam, done by 2027-07-30, aimed at Next Fest in October 2027. The schedule
and every decision behind it are in `docs/ROADMAP.md`. Dropped 2026-10-07.

Was next: Phase 0 there -- the licence, builds and tests for all three
platforms in CI, seeded `rnd` (NOTES.md, Seeded randomness), feature gating,
and the sandbox mode.

From Robert's playtesting, 2026-10-04:

- **The editor defaults to ordinary keys; vim is an option.** Most people on
  Steam will not want vim. Emacs keys if anyone asks (after some mockery);
  WordStar users get pointed at Turbo Pascal. Done 2026-10-05 (Edit > Vim
  Keys).
- **The prompt behaves like the node and coffee REPLs** -- readline's emacs
  keys and Tab completion. Both done 2026-10-05 (Tab completion is at the
  bottom of this file).
- **Commands at the prompt**, as `/run` or `:run`: a line starting with
  either is always a command, and CoffeeScript that starts with a regex goes
  in parens. Vim's ex commands and the prompt share one table. The vim
  switch is a remembered checkbox in the Edit menu. Done 2026-10-05.

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
- **Click-to-run for a getter in the pane** (2026-10-05, `cdc09cb`). A
  member getter shows `(getter, not run)`; a click runs it once through
  `evaluateOnCallFrame` (`throwOnSideEffect: false`, bounded by
  `EVAL_LIMIT`), its owner parked on a worker global because
  `callFunctionOn` takes no timeout. It takes the same turn as the prompt:
  refused while an evaluation is out, and nothing else -- expanding a row
  included -- reaches V8 while it runs. One result shows at a time, and any
  other redraw puts it back to `(getter, not run)`. Scope-level and
  symbol-keyed getters are not offered. The runtime's own accessors
  (`buffer.swap`, `keys.poll`, `mouse.wheel`) are a click away too, as they
  always were at the prompt.

- **Pausing on uncaught errors** (E1, 2026-10-06, then six rounds of review
  and fixes the same night; test part `pauseonerror`). The sketch runs as
  the listener of an event the worker dispatches to itself (`dispatchRun`),
  with no `catch` above it, and the debugger is armed for every run with
  `pauseOnExceptions 'uncaught'`. An uncaught error in the run stops on the
  author's line as `error paused`: pane, prompt and stack work against the
  live frame; Continue ends the run as the error without saying it twice;
  Step is refused (decided by Claude -- nothing catches the error, so a step
  could only end the run). An error the sketch catches, the prompt's own,
  Stop and a syntax error never stop. Errors after the run has ended
  (timers, promise callbacks, after an `await`) are reported once, "after
  the run", never stopped on; unhandled rejections are now reported at all
  (before E1 they vanished). A check guards the prediction trap: any `catch`
  above the run turns the feature off silently.

Not done, each waiting on a reason:

- **Retiring arming from the buffer.** With the debugger armed for every
  run, `watchBuffer`/`wantsDebug`/`armedFor` in the renderer and `wanted`/
  `forced`/`disable` in main decide nothing. They are kept until Robert
  rules on the Decision below; `armFirst` is still load-bearing (the first
  attach, and clearing a Stop's skip).

## Facts line stepping established

Verified in Electron 44 while building it; do not re-derive.

- **Never re-attach to a worker you have detached from.** `Debugger.enable`
  on the new session hangs forever -- even with `Debugger.disable` and
  `Target.detachFromTarget` first. So the page stays attached once armed,
  and arm/disarm is `Debugger.enable`/`disable` on the live session, which
  re-enables fine. DevTools forces a detach, so after it closes breakpoints
  work from the next Run (a fresh worker), and the app says so.
  Narrowed by a Claude reviewer of I1, 2026-10-06 (Electron 44, Linux,
  DevTools simulated by emitting its events, so the detach was a real
  `cdp.detach()`): re-enabling the old worker answered in 3ms when it was
  idle (1 of 1), and hung to the 2s `SETUP_LIMIT` when it was busy in a
  sketch loop (2 of 2). Auto-attach re-attaches it with the next attach
  anyway, so main remembers its `targetId` and never enables it again
  (`stale` in `src/main/debugger.coffee`); Ctrl-\ at it says pausing works
  from the next Run. A worker born while DevTools was open is enabled as
  any other: with the events simulated nobody had attached it, but a real
  DevTools does, and whether enabling it then hangs is untested -- as is a
  real DevTools session for all of the above.
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
- **`t.settle()` counts all three pauses as settled.** A check that waits
  for a Stop to finish has to wait for `ready` itself.

Facts pausing on errors established (2026-10-06, Electron 44):

- **Every debugger turn speaks only to its own session.** A Run replaces the
  worker while an old evaluation may still be finishing, and the old turn's
  next command once went to the new worker's session mid-evaluation. Now:
  `asking` is the one evaluation out in a paused worker; `takeTurn` races it
  against `left`, a promise that settles when the session goes
  (`sessionGone`, in `setUp` and `resetSession`); `speaker()` gives a
  multi-step job a `talk` bound to the session it started in, which refuses
  once that session is gone; `whenFree` waits for the turn and sends in the
  same tick. `halted` is V8's real pause and `current` checks it between
  awaits in a pause's setup; `stopped` is the pause the renderer was told
  of.
- **The suite checks the binding rule itself.** Under `BEANS_TEST` every CDP
  command goes through `watched`, which records any command sent to a
  session while an `evaluateOnCallFrame` or `callFunctionOn` is out there,
  and every part ends with a check that nothing was recorded. A new path
  that breaks the rule fails the suite instead of waiting for a reviewer.
- **`callFunctionOn` has no timeout.** Anything that runs author code (a
  getter on a thrown object, `REPL.show` of a Proxy) goes through
  `onParked`: the value is parked on the worker global under
  `__beansParked` (by `callFunctionOn` with `this` the global, so no name
  is looked up), then read by an `evaluateOnCallFrame` with `timeout:
  EVAL_LIMIT`. Frame expressions name nothing but `__beansParked`: a sketch
  variable called `globalThis` once turned every pause off.
- **Source maps are fetched when a pause needs them**
  (`Debugger.getScriptSource`), the newest 32 cached; the worker keeps each
  run's source to recompile an old map for a traceback, so its memory grows
  with runs for the worker's life (not measured; not bounded).
- **A pause names its worker** (`REPL.owner`), and the renderer drops one
  from a worker it has replaced. A sketch that clobbers `REPL` makes the
  pause fail loudly ("could not pause") rather than vanish.
- **A Stop's skip-all-pauses is reported** to the renderer (`'skipping'`), so
  the next run re-arms; guessed from the renderer's own request, it once
  left the next run's breakpoint and error stops silently skipped.
- **Test hooks** for these races live in `hooks` (`pausing`, `stopping`,
  `arming`), null outside the suite.

- **`Worker.terminate()` gives a busy worker two seconds.** Chromium queues
  the shutdown behind whatever the worker is running and only forces
  `TerminateExecution` after `kForcibleTerminationDelay` = 2s
  (`worker_thread.cc`). So every Run over a running sketch -- not only one
  from a line pause -- left the old worker printing into the new console,
  taking the new sketch's frames and able to claim its prompt line, for 2.0s
  (measured by Claude, 2026-10-05, Electron 44). Fixed (H2): header word
  `OWNER`, bumped by `start()` before `terminate()`; the runtime's
  `checkOwner` (yield points, `print`, `sound`, `screen`, the buffer modes,
  `load`) repoints every shared view at a private buffer on the first
  mismatch and throws `Interrupted`, and `serveAsk` checks the owner before
  claiming a line. Still open: a sketch with no yield point writes shared
  pixels for the full 2s, and one that kept its own `display.pixels` keeps
  the shared array. Messages a terminated worker posts are dropped by
  Chromium (error events excepted).

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
- **Three kinds of pause, named apart:** `frame paused`, `line paused` and
  (since E1) `error paused`. `held`/`paused` was rejected — you cannot
  remember which is which.
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
  **Moot since 2026-10-06:** Robert's choice for pausing on errors arms the
  debugger for every run. The code is kept until he decides whether to
  remove it (see "Not done" above).
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
  errors propagate. Must read as *an error*, not a silent freeze. (Built
  2026-10-06, E1: see Done above.)
  Researched 2026-10-05: `docs/research/pause-on-error.md`. **Decided by
  Robert, 2026-10-05:** build it the note's way -- the sketch runs as an
  event listener with no catch above it, and the debugger is armed for
  every run (about 0-50ms per Run; a sketch that throws and catches in a
  loop pays more, and that is accepted). The status word is `error paused`.
  The error is reported once, when it stops. A preference turns error
  stops off. Errors after the run has ended (timers, promise callbacks,
  after an `await`) are only reported, never stopped on. The suite stops
  on errors only in the part that tests pausing on them.
- **Preferences live in main's data folder**, `settings.json` beside
  `sketches/` (`src/main/settings.coffee`), not the renderer's localStorage:
  the Edit menu shows Vim Keys and is built before any page loads, so main
  has to own it. JSON because YAML would be a new dependency. A file that
  will not parse, or is not an object, is logged and the defaults used.
  Decided by Claude, 2026-10-05 (K2); Robert may overrule. Since 2026-10-06
  (E2) the remembered checkboxes -- Vim Keys, Stop on Errors, Warn About
  Name Case -- come from one table, `PREFERENCES` in `main.coffee`: a label,
  a default (a value that is not a boolean reads as the default), and a
  `changed` that brings whatever follows the preference into line, run at
  every launch and Try Again as well as on a click. Pages read them through
  one `settings:get` channel.
- **Stop on Errors is one switch with two writers** (E2, decided by
  Claude): `errorStops` in `debugger.coffee`, written by the preference
  and, in the suite only, by `t.stopOnErrors`; the last write wins, and
  `t.reset` sets it before every part. Changed during an error pause, it
  applies from the next error. Off means the run ends as it did before E1:
  the same report, stack and marked line, byte for byte.

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
known -- so it is not "pausing on uncaught errors", which is a live pause
(built 2026-10-06, see Done). A live stack while line paused is still out, but now that
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
- **A page reloaded inside a minimised window gets no animation frames at
  all on Linux**, `backgroundThrottling: no` or not: a shown window kept
  144.5 rAF/s across two reloads, a shown-then-minimised one went from 144 to
  0 and its sketch sat at `running`. So the hidden test window (shown, then
  minimised) is never reloaded; `t.freshPage` opens a second window instead.
  Measured by a Claude reviewer, 2026-10-05. Untested, inferred: the
  `render-process-gone` recovery reloads too, so a crash while minimised may
  come back drawing nothing until the window is restored.

Found by CI on GitHub's runners, 2026-10-05 (C1 and C2 of that night's plan):

- **Electron's sandbox dies on ubuntu-24.04** (`The SUID sandbox helper
  binary was found, but is not configured correctly`) unless the workflow
  sets `kernel.apparmor_restrict_unprivileged_userns=0`. Fixed there, not by
  `--no-sandbox`.
- **On the Windows runner a never-shown or minimised window draws at about
  1fps**, like Linux's never-shown one; shown and left alone it runs full
  rate. So a hidden Windows test run shows its window inactive and leaves it
  up (`createWindow`). A Windows contributor sees it, unfocused.
- **CRLF**: Git for Windows' default checkout turned sketches CRLF and the
  suite rewrote them LF. `.gitattributes` pins LF now. The editor bug behind
  it -- `Editor.load` kept the raw CRLF text as `lastWritten` while CodeMirror
  holds `\n`, so a CRLF sketch read dirty forever, refused `/e`, and was
  rewritten LF on the next switch -- was fixed the same night (K4,
  `a9a427a`): disk text goes through CodeMirror's own line splitting
  (`asHeld`) at load and on an outside change. Line endings follow the
  platform since 2026-10-06 (U2, Robert reversing K4's always-LF): every save
  reads the file's current endings and keeps the majority, saying once in the
  console when they were mixed; a file with none yet (new, emptied, one line
  with no newline) takes the platform's, CRLF on Windows. Nothing is
  remembered between saves -- the disk is the record. A raw CR inside a
  string was already lost before U2: CodeMirror splits on `\r` at load.
  Examples seeded by `data.coffee` are copied as they are in git, so they
  land LF on Windows; whether they should take the platform's is Robert's
  call (open).
- **Saves failed on Windows, and a stale read reverted the editor** (fixed
  the same night, S1). Overlapping `sketch:write` calls shared one staging
  name, `.<name>.saving`, so one save's rename carried off another's file
  (ENOENT; 11 of 12 overlapping saves reproduced on Linux). Saves of one
  file now queue in main, and on Windows a rename refused with
  EPERM/EACCES/EBUSY is retried for about 1.3s, logged. Worse, and the cause
  of every Windows CI failure that night: the watcher read the file 60ms
  after an event with no idea a save was in flight, and `applyExternal` took
  the old text for an outside edit -- the next eval ran the previous
  buffer. The watcher now waits for that file's save chain. Still open: a
  read sent while the renderer's write is crossing IPC can revert the editor
  until the echo; the fix not taken is a write number echoed in
  `sketch:changed`. And with no conflict detection, an outside edit made
  during one of our saves is lost silently. Main hands the suite a `faults`
  hook (slow, refused renames) to test this; it does nothing otherwise.
- **macOS missed the first save in a folder created outside the app** once
  (`a folder created outside the app is watched, every save`), in the one
  by-hand run. Not investigated.

Found on the night of 2026-10-06, Electron 44, measured unless marked:

- **On GitHub's Xvfb runner a page gets no animation frames until its window
  is shown** (K6), and the suite starts at `did-finish-load`, before `show`
  -- which came about 2.7s into the first part. CodeMirror measures only on
  a frame, so the editor part's first checks failed on time. The suite now
  waits for one frame (`t.drawing()`, `test/suite.coffee`) before any part.
  On Robert's machine a never-shown window gets about 3 frames a second, not
  none. Why `show` is late on CI is not known.
- **Before any window exists, async `dialog.showMessageBox` never resolves
  and `shell.openPath` never settles** (Linux; A1). The startup problem box
  (a `sketches/` link that leads nowhere: Try Again / Open Folder / Quit)
  uses the sync box for that reason.
- **Electron's main process runs Node's `warn` mode** (A2): an unhandled
  rejection is a line on stderr and nothing else. Listening for
  `unhandledRejection` silences even that, so the handler says "unhandled"
  itself. Problems in main go through `sayProblem` to the window's console,
  held (at most 50, the rest counted) until a page listens. A throwing
  `ipcMain.handle` reaches the renderer as "Error invoking remote method
  '…': Error: …", which tells a player nothing -- each call site should say
  its own failure. `Worker.onerror` never fires for a worker's unhandled
  rejection. A `loadURL` overtaken by another load rejects with
  `ERR_ABORTED` and is not reported to `did-fail-load`; a 404 from our own
  `serve` resolves and shows the 404 text. `shell.openPath` resolves to an
  error string rather than rejecting. A refused navigation or a hash change
  fires `did-start-loading` and `did-stop-loading` with no `did-navigate`.
  `win.destroy()` is deferred, and `destroyed` fires before `closed`. Every
  `will-navigate` is refused and `window.open` denied. The whole audit, with
  what is still open, is `docs/research/unhandled-exceptions.md`.
- **Leaving a page** (U1): async IPC sent from `pagehide` does reach main; a
  reload waits indefinitely for a `sendSync` answer; a closing window waits
  about 500ms from `pagehide`; quit loses a slow save unless `will-quit` is
  held. The unload flush and the quit hold are both bounded by `SAVE_LIMIT`
  (5s). SIGTERM only *starts* a quit, so the quit check falls back to
  SIGKILL.
- **The system clipboard is never touched by the suite** (V1): on X11 the
  owner's clipboard empties when it exits, so a run that wrote and restored
  it cost Robert what he had last copied. The About check spies on
  `clipboard.writeText` instead.
- **The version comes from git** (`src/main/version.coffee`, V1): release,
  commit count, short id, `-dirty`. `version-stamp.txt` is read only where
  there is no `.git`. Every `GIT_*` variable is scrubbed -- a git hook in a
  linked worktree exports `GIT_DIR`, which sent the About check's own
  commits into the outer repository -- and `GIT_CEILING_DIRECTORIES` stops
  an empty `.git` from answering for the checkout around it. Git for Windows
  cannot open `\\.\nul` (`os.devNull`) as `GIT_CONFIG_GLOBAL`; use an empty
  file.
- **Chromium keeps one native undo stack per page** (K7). `{role: 'undo'}`
  with the editor focused did nothing, undid the wrong field, or killed
  redo. So Edit > Undo and Redo are our own items: CodeMirror's history when
  the editor has focus, `webContents.undo`/`redo` (`edit:native`) for a text
  field -- never `execCommand`, which reached into the editor's DOM behind
  CodeMirror's back. Their accelerators are registered on macOS only, where
  the menu is the only way a key reaches them; `Mod-Shift-z` redo was added
  for Windows.
- **Whether names fold case is asked of the disk, not `process.platform`**
  (F1): the realpath of a case-swapped name, falling back to the platform.
  The fold is `toLowerCase`, which is not exact for a few characters (the
  Kelvin sign) and does no Unicode normalisation. The "Warn About Name Case"
  setting says when the name asked for and the name on disk differ.

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

## Stop, and what it means in each state (E3, 2026-10-06)

Stop is disabled (really, with a title saying why) when there is nothing to
stop, and Ctrl-. calls `stop()` directly, so it works either way.
`stoppable()` in the renderer: live while arming, running or in any of the
three pauses; while booting with a run waiting on the boot; while a prompt
line is out (`ASK_STATE` 1 or 4); and while any voice sounds (`SOUND_BUSY`)
-- Stop with nothing running is how a held note is hushed. The 16ms console
timer re-checks it, because the worker and the worklet change those words
without telling anyone. Each term, mutated out in review, broke exactly its
own check.

What three rounds of review established about `stop()`:

- **Stop at an idle worker** (`IDLE`: ready, error, booting) bumps the sound
  epoch, raises the interrupt only for a prompt line the worker has claimed
  (state 4), and takes back one not yet claimed (state 1 -> 0, "*** stopped
  ***"). Raised at any other time, the interrupt stayed up and the next
  prompt line answered "stopped".
- **A run being armed is cancelled** by Stop: the `stops` counter is checked
  after `armFirst`'s await, and `armedOver` puts back the status the run was
  asked from. `underneath()` is the status beneath an `arming`, and `send`
  tests it, so a second run cannot be posted to a busy worker.
- **A hold ends with its run** -- decided by Claude, Robert may overrule.
  `finished` clears it; a hold pressed during a boot still carries into that
  run. Before, a hold outlived its run and froze the next `/eval` at its
  first frame under a status reading `running`.
- **Stop of a held, busy sketch counts as stopping a running one**
  (`resumeTo = 'running'`), so the 250ms deadline still applies.
- Still open: a prompt line with no yield point at an idle worker cannot be
  stopped; an `/eval` sent before a stopped line answers lowers the flag.

## Vim emulation (codemirror-vim), the facts worth keeping

- **Autoindent is taken back the way Vim does it** (K5, 2026-10-06): `o`,
  `O`, `cc`, `S` then Esc leave the line blank, not holding the indent. The
  measured table of what real Vim 9.1 does (`vim -u NONE -N -i NONE -n -c
  'set ai bs=indent,eol,start'`) is the comment above `indentField` in
  `src/renderer/editor.coffee`; rows marked "ours" are where we differ, and
  every one keeps an indent Vim would take back, never the reverse.
- **It leans on codemirror-vim's internals**, so check it after any upgrade
  of the plugin: `lastEditInputState`, `curOp.isVimOp`, the
  `input.type.compose` label, and `Vim.getVimGlobalState_()` -- labelled a
  testing hook -- for `macroModeState.isPlaying`.
- **`.` sets `isPlaying` and then clears it**, without restoring what it was,
  so a `.` inside a macro ends the macro's "playing" for everything after
  it. Playback is therefore decided once per vim command (`playedBack`
  latches it on `cm.curOp`). `3o`'s repeated insert runs outside any vim
  command.
- **A macro that calls itself overflows the stack** and leaves `isPlaying`
  raised until a reload; after that `.` does nothing in the plugin itself.
- **`Vc` on an indented line deletes the line and its newline** in
  codemirror-vim, where Vim (and `cc`/`S`) leave a blank line. A plugin bug,
  not reported upstream; K5's checks use `S` and `cj` for that path.
- **Undo after clicking off a fresh indent takes two steps**: CodeMirror's
  pointer tracking reads only the first transaction's label, so the strip
  has to be a second one.

## Bug reports (V2, 2026-10-06)

The 📣🐞 button between the title and the folder opens a three-step dialog:
what happened, the report as it will be saved (editable), then the file and
how to open an issue at thatsnice/CoffeeBEANS. Robert's rule for what a
report may hold: **safe to post on a large billboard in a big city.** So
`src/main/redact.coffee` leans towards taking too much:

- This player's home, data and app folders become `~`, `<data>` and
  `<app>`; anyone's home folder under any root (`/home`, `/Users`, `/var/
  home`, `/media`, `/run/media`, Git Bash's `/c/Users`, WSL's `/mnt/c/
  Users`, `/Volumes/…/Users`) loses its owner's name. A relative
  `sketches/media/boom.wav` or `y = x/media/2` is over-redacted to keep
  that; chosen.
- The player's user and host names go wherever they stand as a whole word;
  names under three letters only inside paths. Their full name (git
  `user.name`, the macOS long name) is not looked up.
- All IP addresses, loopback included; MAC addresses; e-mail addresses,
  `%40` forms too; `.local` names with a hyphen; network shares.
- Secrets: values after secret-looking names (`password`, `PGPASSWORD`,
  `token`…), on the same line or a quoted value on the next; bearer tokens;
  cookies; known key prefixes (`sk_live_`, `hf_`, `ghp_`…); private key
  blocks; long random-looking runs (mixed case, and digits or a balanced
  share of capitals, and not path-shaped -- measured on 200,000 keys).
- Web addresses keep their paths (a sketch's load failure needs them), not
  their query strings.
- Every rule is linear: a check redacts lines of 100k-400KB in under a
  second each (about 40ms in practice). Three earlier versions were
  quadratic and froze main for up to 36s.
- Known limits, accepted for now: `/Users/Mike Smith` at the very end of a
  line leaves the surname; an unquoted secret value on the next line stays.
  The player sees the report and can edit it before it is saved. A small
  local model to review it was deferred by Robert (ROADMAP).

## Open for discussion

- **What the canvas does on zoom.** Cmd-minus / Cmd-equals (View menu
  roles) rescale the whole window, canvas included. Should the canvas follow
  the UI zoom, scale itself up to fill the stage on its own, or have an
  option? Raised 2026-09-29; nothing decided.

## Tab completion (built 2026-10-05)

Built as designed below (P2, `99270f4`; 23 checks in `repl`). What the
building added:

- **`ASK_KIND`** (header word 58) says whether the ask buffer holds a line or
  a completion question, and **`ASK_STATE` 4** means "being answered": the
  worker claims every question with `compareExchange` 1 -> 4. So a line typed
  while a Tab is still unclaimed withdraws the Tab (1 -> 0) and goes through;
  only a Tab the worker is already answering refuses it, as "still answering
  Tab". Before this a pending Tab blocked every later line. Withdrawal goes by
  `ASK_KIND`, never by whether a Tab is out: a paused-frame Tab sets
  `completing` too, and once took back a waiting *line* (H1, `3c9d555`).
- **Every evaluation in a line-paused frame** -- a line, a Tab, a getter
  click -- goes through `evaluatePaused`, one counter (`debugAsking`), and
  waits for member listings still out; a listing is bounded by `EVAL_LIMIT`
  in main so it always settles.
- **An answer is dropped unless the prompt still has focus**, as well as
  unless the line and caret are unchanged: the answer is written with
  `execCommand`, which types into whatever is focused, and a late answer once
  typed itself into the editor and was autosaved.
- **The vocabulary is computed by difference** around `attach()`, plus
  `breakpoint` and `COLORS`, minus `Interrupted`; a new runtime command is
  included without a list to keep. `Math.`/`Atomics.` roots do not complete;
  names after an index or a call (`a[0].`, `f().`) do not either, since that
  would mean evaluating.
- **An author's Proxy runs its traps** during a member walk. JavaScript gives
  the worker no way to tell a Proxy apart; the runtime has none.
- **The beep is the renderer's own oscillator**, not a note through the
  worklet: the worker is the only writer of the sound ring, and a beep must
  sound when no sketch is running. The suite counts beeps with
  `Prompt.beeps()`; whether it sounds right takes an ear.
- `/` and `:` command names complete from `Editor.commands()`, no worker
  needed. Tab inside a reverse search takes the match and then completes.

Changed by Robert on 2026-10-05, built on 2026-10-06 (T1, T2, T3):

- **A list, not a console dump** (T2). The second Tab opens a list over the
  stage, just above the prompt, that narrows as the word grows and asks
  again when the word is deleted back past where it was asked or a `.` is
  typed. While it is open, Up/Down/Ctrl-P/Ctrl-N/Tab/Enter/Esc belong to the
  list (`CHOICE_KEYS`, ahead of `PROMPT_KEYS`), which is how it no longer
  fights the history. It closes on one candidate or none, Esc, a caret move,
  blur, submit, a recall and Ctrl-R. The first Tab that opens it does not
  beep.
- **Some JavaScript is offered, ranked last** (T1). Sketch names first, then
  the runtime's, then an allowlist of the JavaScript a player would use
  (`Math`, `JSON`, `Array`, `Object`, `Number`, `String`, `Date`, `Map`,
  `Set`, `parseInt` and the like; `src/renderer/worker-boot.js`). Plumbing
  is left out: `on*`, `postMessage`, `console` (it prints to DevTools),
  `Promise`, `setTimeout`, `Proxy`, `Reflect`, `globalThis`, `crypto`.
  `structuredClone` was taken out again because `st` became ambiguous with
  `step`. Ranking only orders the list; how far Tab completes is unchanged.
  While line paused, the frame's names and the image's rank alike: a
  closure captures the image's names, so V8 cannot tell them apart.
- **Up and Down search history by what is typed, as node does** (T3, ported
  from Node 24.20's readline and `ReplHistory`, checked against Node 26.10's
  internals). The prefix is the text before the caret at the first Up; any
  key but Up/Down ends the walk; repeats are skipped. Ctrl-P/Ctrl-N walk
  every line, as node's do. Two deliberate differences: Up past the oldest
  match stays on it, and Down past the newest gives back the whole line as
  typed, caret and all, edits to a recalled line included.

The design as decided 2026-10-04, its first two points replaced by the
above:

- **Bash style.** Tab completes as far as every candidate agrees, and beeps
  when that is ambiguous; a second Tab lists the candidates. (Was: in the
  console, no popup.)
- **The vocabulary.** Candidates are the image, the running sketch's
  harvested locals, the runtime API, and (since T1) the allowlist above.
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
