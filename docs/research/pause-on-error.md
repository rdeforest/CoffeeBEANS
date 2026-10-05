# Pausing on uncaught errors -- research

*Written by Claude (Opus 5.5) on the night of 2026-10-04/05, track X1 of
`docs/overnight/2026-10-05.md`, branch `research/pause-on-error`. Every
number here was measured that night on Robert's Linux machine (the one
described in AGENTS.md, Platform facts), in Electron 44.3.0 / Chrome
152.0.7977.78 / V8 15.2.124.19, one Electron at a time under the suite
lock. Anything not measured is marked **inferred**.*

## The question

AGENTS.md, Decisions: pausing on uncaught errors is wanted -- landing in
the debugger with `ball` live beats four lines of traceback -- and blocked,
because `worker-boot.js` catches every sketch error, so V8 predicts every
one as caught and `pauseOnExceptions: 'uncaught'` never fires. Two ways out
were named: (a) pause on all exceptions and resume automatically outside
the author's own code, or (b) change how sketch errors propagate. This note
measures both and a third.

## The answer, short

**(b) works, and works exactly.** With no `catch` anywhere on the stack
above the sketch, V8's own catch prediction does the deciding: the
sketch's uncaught errors pause at the throw with the frame live, and an
error the sketch catches, the prompt's own errors, and everything else do
not. The prototype keeps run reporting synchronous by running the sketch
as the listener of an event the worker dispatches to itself
(`dispatchEvent` reports a listener's error instead of throwing it to the
caller). Eleven checks against the real app pass with it. The price is that
the Debugger domain has to be on for every run, not only when the buffer
says `breakpoint` -- that is the decision Robert has to make -- and that
the existing checks which make a sketch fail on purpose now stop at the
failure (armed, the full suite fails 28 checks, almost all of them the
knock-on of a few such pauses).

**(a) is a dead end:** every throw, caught or not, costs a round trip to
the main process -- a sketch that throws and catches in a loop runs about
300 times slower -- and V8's `uncaught` flag is useless to it (false for
everything, because of the catch it is working around), so the debugger
would have to re-implement catch prediction from the CoffeeScript AST.

## What V8 does -- measured with the standalone probe

`research/pause-on-error/probe/` is a page, a worker and a main process
speaking the same CDP as `src/main/debugger.coffee`, with the same
ignore-list patterns (`^beans-runtime/`, `/src/renderer/`), a stand-in
runtime under `beans-runtime/lib.js` and a stand-in bootstrap under a
`/src/renderer/` URL. Each sketch runs in a fresh worker, attached once.
Raw results: `tmp/probe-x-sem2.log` (not committed; the probe regenerates
it). Run with

    flock .../CoffeeBEANS/tmp/suite.lock \
      node_modules/.bin/electron research/pause-on-error/probe > out 2>&1

Four shapes of bootstrap:

- **catch** -- today's: `run()` catches, inside an async listener that
  catches too.
- **escape** -- way (b) at its plainest: nothing catches, the error leaves
  a plain (non-async) message listener and comes back as the worker's
  `error` event; the result is posted from a `setTimeout`.
- **dispatch** -- way (c): the sketch runs as the listener of a
  `beans-run` event the worker dispatches to itself, synchronously.
- **dispatchInCatch** -- dispatch, but with today's async try/catch still
  wrapped around the handler, above the `dispatchEvent`.

Five sketches: the author's own `ball.x` on a null `ball` two calls deep
(`own`); bad input to the runtime, so the throw is in ignore-listed code
(`lib`); each of those caught by the sketch (`ownCaught`, `libCaught`); and
the `Interrupted` a Stop throws from a yield point (`interrupted`).

Pauses with `setPauseOnExceptions 'uncaught'`, ignore-list on:

| sketch      | catch | escape | dispatch | dispatchInCatch |
|-------------|-------|--------|----------|-----------------|
| own         | none  | **pauses in `addAngle`** | **pauses in `addAngle`** | none |
| lib         | none  | **pauses**, top frame in the runtime, the author's frame next | same | none |
| ownCaught   | none  | none   | none     | none            |
| libCaught   | none  | none   | none     | none            |
| interrupted | none  | pauses | pauses   | none            |

What that established, each measured:

1. **Today's shape never pauses on `uncaught`, and ignore-listing the
   catcher does not change that.** Run again with the ignore-list empty:
   identical. (Recorded because newer DevTools treats exceptions caught by
   ignore-listed code specially in places; V8 15.2's prediction does not.)
2. **Remove every catch above the sketch and `uncaught` is exact.** It
   pauses on the author's mistakes and nothing else, with `data.uncaught:
   true`. At the pause the author's frame is live: locals `a=41 b=1
   sum=42`, and `Debugger.evaluateOnCallFrame` reads `sum` (42).
3. **A catch above the `dispatchEvent` still counts.** `dispatchInCatch`
   never pauses, although that catch can never see the error
   (`dispatchEvent` swallows it). V8's prediction walks straight past the
   native boundary. So the listener that calls a run must have no `catch`
   at all -- the trap the first app prototype fell into (below).
4. **The error event fires inside `dispatchEvent`.** The dispatch shape
   posts its result right after `dispatchEvent` returns, and that result
   was `error` whenever the sketch threw: the run can report synchronously,
   in the same order it does today.
5. **A Stop's `Interrupted` pauses too** (it is uncaught by design). The
   paused event's `data.className` is `"Interrupted"`, so the debugger can
   resume it without telling anyone.
6. **The stack is still mapped** after the error escapes: `error.stack`
   names `beans-run-N.coffee:line`, so `traceback()` keeps working.
7. **An expression that throws, evaluated at an exception pause, comes back
   as an exception** -- no nested pause, no hang (`ball.y` at the `own`
   pause, `timeout` 2000, answered at once).
8. **`'all'` pauses on every throw, caught or not, in every shape,** and
   `data.uncaught` is V8's prediction -- false for all of them under
   today's catch. It pauses on a throw inside ignore-listed code that the
   sketch catches (`libCaught`) as well, so the ignore-list does not thin
   it out.
9. **`'caught'` exists** in this V8 (it is missing from the 2022 protocol
   JSON) and pauses on exactly the predicted-caught set. Not useful here.

## Way (a): pause on all, decide in the debugger

Not prototyped in the app, for the two reasons below; the probe measured
the floor of its cost, and `research/pause-on-error/probe/caught.coffee`
prototypes the deciding it would need.

**Cost, measured** (probe, iterations a second of a loop that throws and
catches, median of 3; the loop checks the clock every 1000 iterations, so
counts are in thousands):

| loop        | not attached | armed `none` | armed `uncaught` (today's shape) | armed `uncaught` (dispatch) | armed `all` (today's shape), every pause resumed at once |
|-------------|-------------:|-------------:|------------:|------------:|---------:|
| `throw new Error` caught | 1,695,000 | 1,307,000 | 1,078,000 | 1,011,000 | **4,000** |
| `null.x` caught          |   333,000 |   317,000 |   301,000 |   296,000 | **4,000** |
| runtime throw caught     | 1,455,000 | 1,126,000 |   894,000 |   854,000 | **4,000** |
| no throw                 | 2.15e9    | 2.15e9    | 2.15e9    | 2.15e9    | 2.15e9   |

The no-throw loop is `Math.sqrt n` and V8 very likely optimises it away;
it shows only that nothing slows down code that does not throw. Under
`all` the escape and dispatch shapes gave the same 4,000-5,000 (one
dispatch case was cut off by the run's time limit). Under `all` each throw
is a pause, a CDP message to the main process, and a
resume: about 0.25ms each, so 4,000-5,000 a second whatever the sketch does.
That is the floor -- the resume was sent with no thinking at all.

**Deciding, inferred and prototyped offline.** Because `data.uncaught` is
false for everything under today's catch, the debugger would have to work
out itself whether the sketch will catch: walk the paused stack and ask, of
each frame the author wrote, whether its position sits inside the `try`
body of a try/catch in the source. The source is available (the run's
source map carries `sourcesContent`) and CoffeeScript's `nodes()` gives
column-exact `Try` ranges; `caught.coffee` does it in 30 lines and passes
its five cases (a throw in a try, in a function called from a try, in a
catch clause, with no try, and under a runtime frame). It would still have
to special-case the prompt (whose errors `serveAsk` catches), the
CoffeeScript compiler (which throws and catches inside itself on a bad
line) and a `catch` that rethrows, and `debugger.coffee`'s source-map
decoder would have to keep the source column it now throws away. It
re-implements, imperfectly, what V8 does for free once the catch is gone.

## Way (b), done as (c): the error escapes, synchronously

The prototype in the app is one commit on this branch, marked
`PROTOTYPE` everywhere it touches, behind `BEANS_PAUSE_ON_ERROR=1`:

- `src/renderer/worker-boot.js`: `run()` calls `runSketch` through
  `uncaught(body)`, which adds `body` as a once-only `beans-run` listener,
  dispatches the event, and hands back what the worker's `error` listener
  saw (`preventDefault`ed, so it never reaches the page). The message
  listener is no longer `async`, and `run` is called outside the try/catch
  the other handlers keep -- the first version of the prototype left that
  catch above the `dispatchEvent` and nothing paused, exactly as the
  probe's `dispatchInCatch` predicted.
- `src/main/debugger.coffee`: with the flag, `arm` is always wanted, and
  `enable` adds `setPauseOnExceptions 'uncaught'`. `onPaused` hands
  `reason: 'exception'` to `onException`, which resumes an `Interrupted`,
  resumes when no frame on the stack is the author's, and otherwise reports
  the pause at the first frame the author wrote (`at`) with the error's
  first line. `evaluate` uses that frame; `step` from an error pause is a
  resume.
- `src/renderer/renderer.coffee`: a pause carrying an error says so in the
  console, marks the line red as a failed run does, and focuses the prompt.
  `start()` silences the old worker's `onerror` before terminating it
  (below).

### 1. Does it stop on the author's line, frame live? Measured: yes

`test/parts/pauseonerror.coffee`, run with the flag, all eleven pass
(`tmp/suite-x-on.log` for 1-10, `tmp/suite-x-fix-on.log` for all eleven):

1. `ball.x + sum` on a null `ball`, inside `addAngle`: status `line
   paused`, the highlight on `ball.x + sum`, console `error (line 5):
   TypeError: Cannot read properties of null (reading 'x')`.
2. The pane holds `a 41`, `b 1`, `sum 42` -- the frame that threw.
3. The prompt answers `sum * 2` with 84, in that frame.
4. Continue ends the run as the error it was: status `error`, the usual
   `run (line 5): ...` and traceback, `print 'after'` never ran.
5. `COLORS.byName 'mauvish'` (thrown inside the runtime) stops on the
   author's line that called it, `hue` in the pane.
6. A sketch that catches both kinds runs to the end, never paused.
7. `null.x` at the idle prompt is only an answer.
8. `null.x` at a running sketch's prompt is only an answer; the sketch runs
   on (`serveAsk`'s catch is on that stack, so V8 predicts caught).
9. Stop on a running `loop` reads `*** stopped ***`, never a pause.
10. Stop while stopped at an error lets the run end (`error`).
11. A syntax error is reported as before (`run (line N)`, status `error`)
    and never pauses, although the compiler now runs with no catch above
    it.

Checks 1-3 failed against the first, catch-above-dispatch version of the
prototype -- the same app, armed, but with V8 predicting caught -- which
is the evidence they test the behaviour and not the plumbing.

### 2. What it costs -- measured, in the app

`BEANS_TESTS=pauseonerror`, three runs each, the same part file in three
trees: `main` (4024402 with only the part added), the prototype with the
flag off, and with it on (`tmp/suite-x-main.log`, `-off.log`, `-on.log`).

| iterations a second    | main            | prototype, flag off | prototype, armed |
|------------------------|----------------:|----------------:|----------------:|
| `throw new Error` caught | 1,518,000-1,539,000 | 1,115,000-1,259,000 | 799,000-829,000 |
| `null.x` caught          | 129,000         | 125,000-129,000 | 91,000-92,000   |
| runtime throw caught     | 1,313,000-1,318,000 | 1,112,000-1,165,000 | 716,000-735,000 |
| no throw                 | 803M-810M       | 796M-802M       | 801M-809M       |

Frame rate, frames a second over 2s, three runs in each of two rounds
alternating `main` and armed (`tmp/frames-x-*.log`):

| sketch, per frame | main | armed |
|---|---|---|
| one `circle` (frame clock bound) | 144.0-145.0 | 144.0-144.5 |
| 150 `circleFill` r=90 | 144.0-144.5 | 144.0-144.5 |
| a million `Math.sin` (CPU bound) | 35.5-36.5 | 35.5-36.0 |

| Run to ready (ms, 5 runs) | main 177-179 | flag off 153-179 | armed 180-206 |
|---|---|---|---|

Reading it:

- **Code that does not throw costs nothing.** Plain loops and frame rates
  do not move.
- **A throw costs more, up to about half its speed**, from two sources.
  The Debugger domain being on at all (probe: about 23% on a throw, 5% on
  `null.x`; `uncaught` adds a little more, V8's prediction walking the
  stack on every throw), and the dispatch shape itself: with the flag *off*, nothing
  attached, a caught throw is about 19% slower than on `main`. Why the
  shape costs anything is **not known** -- the likeliest reading (inferred)
  is that V8 builds a message object for every throw when the nearest
  handler outside JS is the verbose one Blink puts round an event listener.
  At 800,000 caught throws a second a sketch would have to throw more than
  13,000 times a frame at 60fps before this showed; no example sketch
  throws at all.
- **A Run takes about 25ms longer** armed: `Debugger.enable`, the
  ignore-list and `setPauseOnExceptions` on each new worker, before it is
  released to boot.
- The earlier frame-rate measurement of `Debugger.enable` (AGENTS.md, "the
  facts the spikes established") was inconclusive; this one, run under
  the lock with the two alternated, finds no difference on a CPU-bound
  frame (35.5-36.5 against 35.5-36.0).

### 3. How it reads to a beginner -- measured text, judged by Claude

At the pause the console says, in the error colour,

    error (line 5): TypeError: Cannot read properties of null (reading 'x')
        stopped where it happened -- ask the prompt, then Continue (F8) to end the run

the line is highlighted as a pause and marked red as a failed run is, the
variables pane shows the frame, and the prompt has the keyboard. The
status line says `line paused`. That is an error, not a freeze -- but the
status word is the weak spot: it is the same word a `breakpoint` produces.
Whether an error pause gets its own status (`error paused`?) is Robert's
call; it touches `PAUSED`, the buttons and every check that waits on a
status. After Continue the error is printed a second time with its
traceback, as today. That double report is deliberate in the prototype (the
second carries the stack) but may read as two errors; again Robert's call.

### 4. Interaction with the established facts

- **Never re-attach to a worker** -- untouched. The page is attached once
  and each worker's session is set up once, as now; arming for every run
  only means every worker's setup takes the `enable` branch the
  `breakpoint` case already takes.
- **Nothing reaches V8 while a prompt evaluation is out** -- untouched.
  The only new sends are the resumes for `Interrupted` and for errors with
  no author frame, and both happen inside a pause the debugger has just
  received, when no evaluation can be out (evaluation is only offered
  while `stopped`, and these pauses never set `stopped`). Measured
  indirectly: the `debugging` part's endless-evaluation checks pass with
  the flag on up to the point a region test's deliberate error leaves a
  pause behind (below).
- **Armed only when the buffer says `breakpoint`** -- this is what changes.
  Pause-on-error needs the Debugger domain on before the sketch throws,
  i.e. for every run. Measured consequences: a Run is ~25ms slower, a
  caught throw up to ~45% slower, nothing else moves. With the domain
  always on, `breakpoint` is no longer free when nothing is watching
  (`stepping` check 7 says so and fails, by design), and the whole
  arm-from-the-buffer machinery (`watchBuffer`, `syncDebug`, the `arming`
  status, `wanted`/`forced`) could shrink to "always" -- inferred, not
  attempted.
- **DevTools** still detaches us, so with DevTools open there is no
  pause-on-error from the app. Inferred, not measured: DevTools' own "pause
  on uncaught exceptions" would now work on sketches, since the catch that
  hid them is gone.
- **Stop.** Today Stop sets pauses aside (`setSkipAllPauses`) only when
  armed; armed always, it always would. `Interrupted` is filtered by class
  name as a backstop for the race between raising the flag and the skip
  arriving. Check 9 passed; whether the skip or the filter is what let it
  through was not recorded.

### The whole suite, armed -- measured

Flag off, the full suite passes with the prototype in: 171 checks green,
175s including this part's measurements (`tmp/suite-x.log`).

Flag on (`tmp/suite-x-full-on.log`), 28 of 177 fail. Read by Claude, each
falls into one of three groups:

- **Checks that make a sketch fail on purpose, now stopped at the
  failure** (image 49, the lifecycle error checks, focus's stack check, a
  region error in `debugging`, the bad-note checks in `sound`), and every
  check after each in the same part, which finds the sketch still paused
  and is told `*** already running ***`. Expected: a real change would have
  those checks continue past the pause, or run the suite with
  pause-on-error off and test it in its own part. Inferred for the later
  `sound` failures (`busy=0` and the like), which were not read one by
  one.
- **`breakpoint is free when no debugger is attached`** -- false by
  construction once armed always.
- **A real bug, fixed in the prototype:** Run while stopped at an error
  terminates a worker that is paused mid-throw; the error reaches the old
  Worker object on the way out, its `onerror` printed `worker: Uncaught
  Error: halt` and set the *new* worker's status to `error`, and the
  unhandled event reached the window as `renderer: Uncaught Error: halt`.
  `start()` now replaces the old worker's `onerror` with a
  `preventDefault` before terminating it. Rerun armed
  (`BEANS_TESTS=image,repl,pauseonerror`, `tmp/suite-x-fix-on.log`): the
  `repl` part, all six of whose failures came after it, now passes whole,
  and neither message appears; only image 49 itself fails, as it should.
  This bug is latent today too in principle, but nothing pauses mid-throw
  today.

## Not done

- Way (a) in the app. Its cost floor (300x on a throwing loop) and the
  catch prediction it would need were judged enough to rule it out; the
  probe and `caught.coffee` are the evidence.
- Stepping on from an error pause: the prototype makes Step a Continue.
  What V8 does on `stepInto` from an exception pause was not measured.
- `throw 'a string'` (a non-Error): the prototype would say `error: error`
  -- `data.description` is absent for a primitive; the real change should
  use `data.value`. Not measured.
- A syntax error now leaves the listener uncaught too. Check 11 shows it
  reports as before and never reaches the author as a pause; whether V8
  paused at all (and `onException` resumed it, every frame being ours) was
  not recorded. The real change should compile before dispatching, so the
  compiler never runs on that path.
- `scripts` in `debugger.coffee` grows by one entry per run and per prompt
  line for the life of a worker once the domain is always on. Inferred
  small; not measured.
- macOS and Windows: nothing here was run there. Nothing in it is
  platform-specific that Claude knows of (the CDP and V8 behaviour are the
  same code); play-test it.

## Recommendation for Robert

**Take way (c): run the sketch as a dispatched event with no catch above
it, and arm the debugger for every run with `pauseOnExceptions
'uncaught'`.** V8 then decides what is uncaught, exactly, for free -- the
sketch's own try/catch, the prompt, Stop and the runtime all come out
right without the debugger knowing anything about them.

**Size of the real change, estimated:** about 40 lines in `worker-boot.js`
(the `uncaught` helper, the listener split, compile before dispatch),
40-60 in `debugger.coffee` (`onException`, the frame to show, step and
evaluate against it, `data.value` for primitives), 10-20 in the renderer
(the message, the old worker's `onerror`, perhaps a status), and the
suite: a new part like the prototype's eleven checks, and the ~10 existing
checks that fail on purpose taught to continue past the pause. If arming
becomes permanent, the arm-from-the-buffer code (`watchBuffer`,
`syncDebug`, `armFirst`'s `arming` status, `wanted`/`forced`) can mostly
go, which would make the change smaller than it adds -- but that is a
second change, and AGENTS.md's "Arm from the buffer" decision would need
rewriting. A night's track either way.

**Risks:**

- Caught throws get up to ~45% slower (measured), and a Run ~25ms slower.
  Code that does not throw is unaffected (measured).
- The dispatch shape costs ~19% on a caught throw even with no debugger,
  for a reason not established.
- The prediction trap: any future `catch` added above the run -- in the
  message listener, around `run()` -- silently turns pause-on-error off.
  A check like the prototype's first one guards it.
- Every intentional-error test becomes a pause unless the suite opts out.

**What needs Robert's decision:**

1. **Arm the debugger for every run?** It is the price of the feature. The
   alternative -- arm only when the buffer says `breakpoint` -- would make
   pause-on-error a thing that only works for people already debugging,
   which defeats the beginner it is for.
2. **Is `breakpoint` still free?** Armed always, a `breakpoint` left in a
   sketch always stops. That seems to be what a beginner would expect, but
   it reverses a stated property (stepping check 7).
3. **Status word and double report:** `line paused` or a new `error
   paused`; print the error at the pause, at the end, or both.
4. **A switch?** A preference to turn pause-on-error off (for a sketch that
   wants its error to just end the run, or for speed) -- or none.
5. **The suite:** errors pause in every part (and the deliberate-error
   checks continue past them), or pause-on-error is off in the suite except
   in its own part.

## Measured or inferred, in one place

Measured, 2026-10-05, by Claude: everything in the probe tables; the
eleven app checks; the app cost table and Run timing; the full-suite results both
ways; the dead-worker `onerror` leak. Inferred: why the dispatch shape
costs anything; that the later `sound` failures armed are cascade; that
DevTools' own pause-on-uncaught now works; the size estimate; that
`scripts` growth is small; that nothing differs on macOS or Windows.

## Files

- `research/pause-on-error/probe/` -- the standalone probe (`main.coffee`,
  `boot.js`, `lib.js`, `page.html`, `index.js`) and `caught.coffee`, way
  (a)'s catch prediction.
- The `PROTOTYPE` commit on `research/pause-on-error` --
  `src/renderer/worker-boot.js`, `src/main/debugger.coffee`,
  `src/renderer/renderer.coffee`, `test/parts/pauseonerror.coffee`, and the
  part's name in `test/suite.coffee`. Not for merging as it stands.
