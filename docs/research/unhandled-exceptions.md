# Unhandled exceptions and rejections -- audit

*Written by Claude (Opus 5.5) on the night of 2026-10-05/06, chunk A2 of
`docs/overnight/2026-10-06.md`, branch `fix/startup-failures`, at Robert's
request of 2026-10-05: "We should probably audit for any other unhandled
exceptions." Read against `main` at `9c76fe0` (A1's startup box, T1, V1
and F1 merged); every file:line below is at that commit. Measured on
Robert's Linux machine in Electron 44 under the suite lock, 2026-10-06,
either with a throwaway Electron probe (a bare app: a rejection in main, a
throwing `ipcMain.handle`, a worker that throws and rejects, two loads that
overtake each other) or with a throwaway test part driving the real app;
neither is committed. Anything not measured is marked **inferred**, and
**read** means established by reading the code alone.*

## What each process does with a failure nobody catches, today

| Where | What happens | Seen by a player? | |
|---|---|---|---|
| main, unhandled rejection | Node prints `UnhandledPromiseRejectionWarning` on stderr and carries on (Electron leaves Node in warn mode) | no | measured |
| main, uncaught exception | Electron's own "A JavaScript error occurred in the main process" box, unless something listens for `uncaughtException` | yes, as a modal box -- also in a test run, on the desktop (AGENTS.md: the EPIPE box) | **inferred** from Electron's docs and AGENTS.md; not raised on purpose, to keep a box off Robert's screen |
| main, `ipcMain.handle` that throws | stderr gets `Error occurred in handler for 'x': ...`; the renderer's promise rejects with `Error invoking remote method 'x': Error: ...` | only if the renderer says so | measured |
| renderer, after `renderer.coffee` has run | `window` `error` and `unhandledrejection` listeners (`renderer.coffee:1611-1614`) say `renderer: <message>` in the console, and do not `preventDefault`, so DevTools and main's terminal (`[renderer] Uncaught ...`) get it too | yes, without a stack | measured |
| renderer, before `renderer.coffee` has run | the loader in `index.html:161-172` is an async function with no catch; nothing is listening yet | no: a dark window, an empty console | measured (see R1) |
| worker, uncaught error outside a run | the `Worker` object's `error` event: `worker.onerror` (`renderer.coffee:1414`) says `worker: Uncaught Error: ...` and sets status `error`; the event is not cancelled, so the window listener says it again | yes, twice | measured |
| worker, unhandled rejection | not passed to `Worker.onerror` at all; DevTools and the terminal only | no | measured |

## The list

Each entry: where, how to trigger it, what the player sees today, and who
owns the file tonight. **Fixed** marks what chunk A2 changed (below).

### Main process

- **M1. Any unhandled rejection in main.** No `process.on
  'unhandledRejection'`. Trigger: none known in shipped code; every chain
  read has a catch or is awaited by a handler. A test part's stray
  `Promise.reject` is the measured case. Today: a stderr warning, nothing in
  the window (measured: console `""`). **Fixed** (A).

- **M2. `main.coffee:692-700`, the `whenReady` callback.** A1's loop catches
  everything `reachWindow` throws and shows the box. What is left outside
  the `try`: `tryAgain`/`startupBox`/`ask` throwing (a
  `dialog.showMessageBoxSync` that throws), which would reject the callback
  and leave the app with no window and only a stderr warning. **Inferred**,
  and no trigger known; not changed.

- **M3. `main.coffee:700`, `activate` calls `createWindow` bare.** A throw in
  it is an uncaught exception in an event handler: Electron's box. Also,
  `window-all-closed` quits on every platform (`:702`), so `activate` with
  no window is close to unreachable even on macOS. **Inferred**; not changed.

- **M4. `main.coffee:487` and `:498`, `win.loadURL` not awaited or caught.**
  Measured in the bare probe: it rejects with `ERR_FILE_NOT_FOUND` for a
  missing file and with `ERR_ABORTED` when another load overtakes it (View
  > Reload pressed while the window is still coming up; a second crash
  during the crash reload). Measured in the app: an `index.html` that
  `serve` answers 404 does *not* reject -- the load resolves and the window
  shows `not found: /src/renderer/index.html`, which is visible. Today: a
  stderr warning for the two rejections. With M1 fixed, an `ERR_ABORTED`
  would have become a `main: ERR_ABORTED ...` line in the page that
  replaced it -- true, but alarming, for a reload. **Fixed** (A): an
  overtaken load says nothing, any other failed load is said. Electron
  does not report an aborted load to `did-fail-load` (measured), so the
  check hands `loadPage` loads that fail in the shape the probe measured
  (`code: 'ERR_ABORTED'`, `errno: -3`).

- **M5. `main.coffee:565`, File > Open Data Folder.** `shell.openPath`
  answers an error string rather than rejecting; it was logged to stdout.
  Trigger: no file manager or `xdg-open` that works. Today: nothing
  happens, and nothing says why. **Inferred** (not triggered: it would open
  a file manager on Robert's desktop). **Fixed** (A), unchecked -- see below.
  It also meant a test run that clicked the item would open a real file
  manager; it now goes through `openFolder`, which a test run only prints.

- **M6. `main.coffee:586-589` and `:598-600`, Vim Keys and Warn About Name
  Case.** `saveSettings` -> `settings.coffee` `save` catches every error and
  `console.log`s it. Trigger: a data folder that is read-only, full, or (as
  the check does it) a folder where the staging file goes. Today: the tick
  takes effect, nothing is said, and the next launch has the old choice
  back (measured: console `""`). **Fixed** (A).

- **M7. `main.coffee:687`, `Settings.read` at launch.** A file that will not
  parse, is not an object, or cannot be read (`EACCES`, `EISDIR`) is logged
  to stdout and read as every default. Today: the player's choices are
  silently forgotten. **Read**. **Fixed** (A).

- **M8. `ipcMain.handle` handlers.** Every one, with what its renderer
  callers do with the rejection:
  - `sketch:find` (`:185`) throws for a name outside sketches/ (`sketchFile`)
    and for `statSync` errors other than ENOENT -- e.g. `:e foo/bar` where
    `sketches/foo` is a file, ENOTDIR (**inferred**). Callers: the boot
    (`renderer.coffee:1641`, caught and said properly), `openSketch`
    (`:1540`, via `:e`/`/e`, not caught). Measured: `/e ../outside-probe`
    says `renderer: Error invoking remote method 'sketch:find': Error:
    sketch outside sketches/: ../outside-probe` and leaves the editor where
    it was. Visible, but in the words of an internal error. Owner: F
    (`openSketch`).
  - `sketch:create` (`:192`): mkdir/writeFile errors -> `openSketch`, as
    above. **Inferred**. Owner: F.
  - `sketch:read` (`:202`): ENOENT, outside names. Callers via
    `Editor.load`/`selectSketch`: the boot (caught: `startup: ...`),
    `visitFrame` (caught: `cannot open ...`), `openSketch` and `pickSketch`
    (not caught: the window listener's `renderer: Error invoking remote
    method ...`). **Read**.
  - `sketch:write` (`:266`): caught by `Editor.save`, said as `could not
    save <name>: ...`. Measured in every suite log (the EPERM check).
    Nothing to do.
  - `image:load` (`:300`): caught by `answerLoad` and handed to the sketch
    as its `load` error. Measured (the missing-asset check). Nothing to do.
  - `sketch:list` (`:308`): only the boot asks, inside its `try`. **Read**.
  - `sketch:pick` (`:316`): `realpath` of sketches/ or of the picked file
    fails (sketches/ gone, a dangling link picked) -> `pickSketch` (not
    caught) -> `renderer: Error invoking remote method 'sketch:pick' ...`.
    **Inferred**. Owner: F (`pickSketch` sits with `openSketch`).
  - `app:about` (`:37`): `VERSION` never rejects -- `version.coffee`'s
    `derive` turns every failure into a bare version with a note. **Read**.
  - `clipboard:write`, `settings:vim`, `settings:warnCase`: cannot throw.
  - `beans:paths` (`:307`): nothing in the renderer calls it any more.
    **Read**. Dead; not removed (not A's, and harmless).
  - `debug:*` (`debugger.coffee:172-180`): `pause`, `step` and `resume`
    reject when a CDP command fails. Callers `linePause`
    (`renderer.coffee:895-899`), `stepLine` (`:913`), `continueAll`
    (`:921`) do not catch -> the window listener. `stop` (`:1446`) awaits
    `beans.debug.resume yes` with no catch: a rejection there ends Stop
    before its deadline is set, so the sketch keeps running and the status
    stays `running`, with only the listener's line. **Inferred**, no
    trigger found. Owner: E.

- **M9. `main.coffee:342-425`, the sketch watcher.** A failed read
  (`:381`), a folder that cannot be watched (`:397`), a watch that stops
  (`:403`) and a failed stat (`:415`) all go to stdout only. The one that
  matters is `watch stopped`: from then on an outside edit (vim) to that
  folder is never picked up, and nothing in the window says so.
  **Inferred** (the code's own comment says deleting a watched folder
  raised the error). Owner: F (the watcher). With A2's `sayProblem` in
  place, each is a one-word change.

- **M10. Startup `fs` and `child_process`.** `data.prepare` (async: every
  failure reaches A1's box, measured by A1's checks); `probeFolding`
  (sync, inside `reachWindow`'s `try`: the box); `Settings.read` (M7);
  `capture`'s `mkdirSync` (only under `BEANS_CAPTURE`); `version.coffee`'s
  `git` calls (every failure becomes a note in About, checked by the `about`
  part). Nothing else runs a child process. **Read**.

### Renderer

- **R1. `index.html:161-172`, the loader.** Fetches five CoffeeScript files
  and evals each, in an async function with no catch, before any listener
  exists. A 404 was not noticed: its body (`not found: <path>`) was compiled
  as CoffeeScript. Trigger: a broken install, or a syntax error in one of
  the five files (an everyday event for whoever is editing them). Measured:
  with `help.coffee` answered 404, a fresh page's console stayed empty for
  the full 5s the check waits. **Fixed** (A).

- **R2. `renderer.coffee:1611-1614`, the window listeners.** What they do
  with what they catch: one console line, `renderer: <message>`, no stack,
  no file or line; they do not cancel the event, so DevTools and the
  terminal also get it. Every uncaught renderer rejection below lands here.
  For an IPC rejection the message is Electron's wrapper (`Error invoking
  remote method 'x': Error: ...`). Visible, and enough to know something
  broke; not enough to know where. Not changed; see Questions.

- **R3. Renderer calls with no catch** that therefore end at R2:
  `openSketch` (`:1540`), `pickSketch` (`:1546`), `showAbout` (`:795`),
  `aboutCopy.onclick` (`:801`), the boot's `beans.about().then` (`:1628`),
  `linePause`/`stepLine`/`continueAll`/`stop` (M8, `debug:*`), the URL's
  `run` and `stopAt` timers (`:1658-1661`). **Read**. Owners: F
  (`openSketch`, `pickSketch`), V (About), E (stepping and Stop).

- **R4. `renderer.coffee:1414`, `worker.onerror`.** Does not cancel the
  event, so a worker's uncaught error is said twice. Measured: a sketch
  `setTimeout (-> throw new Error 'timer threw'), 20` printed `worker:
  Uncaught Error: timer threw` and then `renderer: Uncaught Error: timer
  threw`, status `error`. It sets status `error` whether or not a sketch
  is still running (**inferred**). Owner: E (`start()`'s error handling;
  E1 is redoing errors outside a run).

- **R5. `renderer.coffee:1274-1287`, `startSound`.** Its setup is caught
  and said (`sound: ...`). But the `AudioWorkletNode` has no
  `processorerror` listener: if the worklet's `process` throws, the
  Web Audio spec has the node output silence from then on, and nothing is
  said. **Inferred**; no trigger found (the worker validates every value
  it queues). Owner: nobody tonight (the sound section).

- **R6. `renderer.coffee:1216-1248`, the present loop.** `tick` re-arms
  `requestAnimationFrame` before doing anything, so a throw in it repeats
  every frame and fills the console to its cap through R2. **Inferred**;
  `screen` validates the sizes that once made `createImageData` throw.
  Not changed: re-arming first is what keeps the window alive.

- **R7. `renderer.coffee:252-264`, `drainAsk`.** Clears the ask state before
  decoding, on purpose, so a bad answer throws once rather than every 16ms.
  `completed` -> `offer` parses a completion as JSON; a reply that is not
  JSON would throw once into R2. **Read**. Owner: T.

### Worker

- **W1. A sketch's unhandled rejection** -- `Promise.reject`, an `async`
  callback that throws, anything after an `await`. Measured: the app's
  console showed only the sketch's own `ran`, status `ready`; the terminal
  had `[renderer] Uncaught (in promise) Error: later rejection`. The bare
  probe confirms `Worker.onerror` never fires for a worker's rejection.
  Owner: E (E1 adds the worker's `unhandledrejection` listener).

- **W2. A sketch's uncaught error outside a run** (a timer): said, twice --
  R4. Owner: E.

- **W3. `worker-boot.js:31-36`, `loadModule`.** Does not check
  `response.ok`, so a missing runtime module's 404 body is compiled and the
  boot fails as a CoffeeScript syntax error (`boot: ...`) rather than
  saying the file is missing. **Inferred** from the code and from R1, where
  the same thing happened. Owner: E (worker-boot.js).

- **W4. `worker-boot.js:356`, `serveAsk`.** `try { if (frame)
  frame.restore() } catch (ignored) {}` swallows whatever `restore` throws,
  silently -- against the house rule. When `restore` can throw is not
  known: it only assigns the image's values back to the sketch's own
  `var`s. **Read**. Owner: E/T (worker-boot.js); reported, not changed.

- **W5. `debugger.coffee:282, 297, 433, 473`.** Four CDP sends end in
  `.catch ->`. Three are harmless if they fail (`Debugger.disable`,
  `setSkipAllPauses` either way). The fourth, `Runtime.runIfWaitingForDebugger`
  (`:297`), is the one its own comment says the worker waits on forever:
  if it is refused, the app sits on `booting` and nothing says why.
  **Inferred**. Owner: E.

## What A2 changed

All in track A's files. Each has a check in the new `problems` part,
except where said below, and each check fails against the code before it:
each fix was taken out alone, and its check failed (Claude, 2026-10-06).

- **`sayProblem` in `main.coffee`**, the one way main says a failure
  nobody is waiting on: stderr as before, and a console line in every page
  that has asked to hear them (`app:problems`, through `beans.onProblem` in
  the preload). Until a page has asked, they are held, so one from before
  the window or during a reload is said once a page is up, once. Fixes M1
  through a `process.on 'unhandledRejection'` that calls it (the window
  gets `main: <message>`, stderr `unhandled rejection: <stack>` -- the
  word kept because listening silences Node's own warning, and A1's
  launch check looks for it), and is what M4-M7 call.
  `uncaughtException` is left to Electron's box (M2-M3).
- **`settings.coffee`**: `read` and `save` hand their failure to a `warn`
  function; a launch passes `sayProblem`. (M6, M7; for M7 the check is
  that `read` hands its failure over -- that the launch passes
  `sayProblem` is one argument, read rather than checked, since the suite
  runs inside a launch already past it.)
- **File > Open Data Folder** goes through `openFolder`, which says a
  failure with `sayProblem`. (M5; no check -- making `openPath` fail for
  real means opening a file manager on Robert's desktop.)
- **`index.html`'s loader** says which file stopped the app, and why, in
  the console, and loads nothing after it; a 404 is reported as one. (R1)
- **`loadPage` in `main.coffee`**, the window's two loads: an overtaken
  load is not a failure; any other is said. (M4)
- **`serve` and the suite**: `unserved`, a set of paths `serve` answers 404
  for, handed only to the suite (like `faults`), so R1 can be checked
  without breaking the checkout.

Not checked: that a page which starts reloading stops being sent problems
until it asks again (`did-start-loading`) -- the only way to exercise it is
to reload a window mid-run, which on Linux stops a minimised window's
animation frames (`test/toolkit.coffee`, `freshPage`); and Open Data
Folder's failure (M5).

## Not fixed, by owner

- **E:** W1, W2/R4 (double report; status `error` with a sketch running),
  W3, W4, W5, `stop`'s unguarded `await` (M8 `debug:*`).
- **F:** M8's `openSketch`/`pickSketch` saying IPC wrappers (`:e ../x`),
  `sketch:find`'s ENOTDIR, M9 (the watcher, stdout only).
- **V:** `showAbout`/`aboutCopy` rejections (R3) -- harmless today.
- **T:** R7 (one-off, at worst).
- **Nobody tonight:** R5 (the audio worklet's `processorerror`).
