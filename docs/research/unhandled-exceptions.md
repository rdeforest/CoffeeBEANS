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

*Updated by the A2 fixer (Claude, Opus 5.5), 2026-10-06, after merging
`main` at `354f57d` (U1, T2, K7 and E1 merged since `9c76fe0`). The entries
above "Since 9c76fe0" keep their `9c76fe0` line numbers; where main's new
code changes what an entry says, a **Since the merge** note follows it.
Entries added at the merge cite names, and lines at the fixer's commit.*

*Updated again by the second A2 fixer (Claude, Opus 5.5), 2026-10-06, after
the second review: a test run's `uncaughtException` handler, the watcher's
read failures said once, `setWindowOpenHandler`, and the merge of `main` at
`22a0c08` (E1, T3, U2, D2, K5). Those notes are marked **second fixer**.*

## What each process does with a failure nobody catches, today

| Where | What happens | Seen by a player? | |
|---|---|---|---|
| main, unhandled rejection | Node prints `UnhandledPromiseRejectionWarning` on stderr and carries on (Electron leaves Node in warn mode) | no | measured |
| main, uncaught exception | Electron's own "A JavaScript error occurred in the main process" box, unless something listens for `uncaughtException`; a test run now does (**second fixer**): it prints `uncaught exception: <stack>` and exits 1. Since 2026-10-08 a player's app does too: `mainFailed` says it through `sayProblem`, offering `/reload`, and carries on (see "Since 2026-10-08") | yes, in the console; a test run puts nothing on the screen | the box: **measured** -- two of the first A2 fixer's runs hung on it (below). The test run's exit and the player's way: checked, `startup` part |
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
  For a test run, every uncaught exception in main now ends the run instead
  of raising the box (**second fixer**; "What A2 changed"). For a player it
  is said in the console since 2026-10-08 (below).

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
  - `debug:members` and `debug:getter` (**since the merge**,
    `debugger.coffee` `members`, ~line 670, and `getter`/`runGetter`, ~line
    692): reject when `Runtime.getProperties` or `Runtime.callFunctionOn`
    fails, or `members` gives up after `EVAL_LIMIT`. Their renderer
    callers -- a row's `open` in `varRow` and `runGetter` -- catch the
    rejection and say it in the console. **Read**. Nothing to do.
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
  (`:403`) and a failed stat (`:415`) all went to stdout only. The one that
  matters is `watch stopped`: from then on an outside edit (vim) to that
  folder is never picked up, and nothing in the window said so.
  **Inferred** (the code's own comment says deleting a watched folder
  raised the error). Owner: F (the watcher). **Fixed by the A2 fixer**,
  at the orchestrator's request: each goes through `unseen` in
  `watchSketches`, which says `changes made outside CoffeeBEANS to <where>
  will not be seen: <why>` through `sayProblem` -- except an `ENOENT`, and a
  `watch stopped` whose folder is no longer there, which lose nothing (a
  sketch or a folder deleted outside the app) and stay on stdout. It was not
  the one-word change the audit first said: routed blindly, deleting a
  sketch outside the app would have printed an error. Checked for a folder
  that cannot be watched (made with mode 0, so not on Windows or as root:
  measured EACCES on Linux). Not checked: `watch stopped` itself, which
  needs a watch to fail after it started; whether Windows raises it with
  the folder still there while its deletion is pending is **inferred**
  not, and would be said if so.

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
  **Since the merge:** E1 gives `worker-boot.js` its own `error` and
  `unhandledrejection` listeners, which `preventDefault` and report through
  the run (`after the run`), so an error from a running worker no longer
  reaches `worker.onerror` (**read**, not re-measured). The standing
  `worker.onerror` in `start()` (`renderer.coffee`, ~line 1647) still does
  not call `event.preventDefault()`, so an error raised before
  `worker-boot.js` has registered those listeners -- `importScripts` of
  `coffeescript.js` throwing, a syntax error in the boot itself -- is still
  said twice: `worker: ...` and then `renderer: ...` from the window
  listener. **Read**. Owner: E, a one-line follow-up; not fixed here.

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
  Owner: E. **Since the merge:** E1 added the worker's
  `unhandledrejection` listener, which reports it (**read**).

- **W2. A sketch's uncaught error outside a run** (a timer): said, twice --
  R4. Owner: E. **Since the merge:** said once, by E1's listener, as
  `after the run` (**read**); see R4 for what is still said twice.

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

## Since 9c76fe0

Added by the A2 fixer (Claude, 2026-10-06) after merging `main` at
`354f57d`. Lines are at the fixer's commit.

- **M11. A navigation the page starts** -- a file dropped on the window
  anywhere CodeMirror does not take it (the canvas, the console), or a
  link, if one is ever added. Chromium's default for a dropped file is to
  navigate to it, which replaced the app with the file's contents, and
  only View > Reload came back. The drop is **inferred** (Chromium's
  default; dragging on Robert's desktop is off limits). Measured in a bare
  Electron 44 probe: a page-initiated `location.href` emits
  `will-navigate`, `preventDefault` there keeps the page, and the
  window's own `loadURL`, reload and hash changes do not emit it.
  **Fixed** (A): `createWindow` refuses every `will-navigate` through
  `refuseNavigation`. Checked by handing that function to a second window
  of the app and having it navigate itself -- not the test window, so that
  a regression costs one check rather than the run; that `createWindow`
  calls it is one line, read, as with `loadPage`.
  The same probe found that a refused navigation still emits
  `did-start-loading` and then `did-stop-loading`, with no `did-navigate`
  -- and so did a hash change -- which would have taken the window off
  `sayProblem`'s list for good under A2's first version; see "What A2
  changed". `window.open` / `target=_blank` would open a new window
  (`setWindowOpenHandler` unset); nothing in the app can do either today
  (**read**). **Fixed by the second fixer**: `refuseNavigation` also
  denies every new window (`setWindowOpenHandler -> action: 'deny'`), item
  14 of Electron's security checklist. Not checked: a check that failed
  against the old code would have a window opened on the desktop of
  whoever runs the suite. That `refuseNavigation` sets it is one line,
  read.
- **M12. U1's `sketch:flush` (`main.coffee:381`) and `will-quit`
  (`:870`).** The flush's save failing, or still going after
  `SAVE_LIMIT`, went to stderr only: the page that sent it is going away.
  **Fixed** (A, fixer): both go through `sayProblem`, so on View > Reload
  the page that comes up says `could not save <name>: ...`, or that the
  save is still going and the editor shows the old text until it lands.
  The failure is checked (the `problems` part, a refused rename); the
  slow case is not (it costs `SAVE_LIMIT`, and the `lifecycle` part
  already waits it out once). `will-quit`'s "still saving" line is left on
  stderr: by then every window has closed and no page can see it, and a
  save that fails at quit rejects into a `sketch:write` whose page is gone,
  which Electron logs (`Error occurred in handler for 'sketch:write'`).
  **Read**.
- **M13. K7's `edit:native` (`main.coffee:109`).** `NATIVE_HISTORY[verb]`
  throws for a verb that is not `undo` or `redo`, and `fromMenu`
  (`editor.coffee:459`) does not catch it. The verb only ever comes from
  main's own menu items. **Read**. Nothing to do.
- **M14. `writeSketch` (`main.coffee:285`) leaves its staging file**
  (`.<name>.coffee.saving`) in the sketch's folder when the rename fails
  for good, as the `problems` part's refused flush showed: the `editor`
  part's "atomic save leaves nothing behind" failed on it until the part
  cleaned up after itself. **Measured**. Harmless to the sketch, but a
  stray hidden file per failed save. Owner: whoever owns the save queue
  (S1/U); not changed.
  **Since U2** (merged by the second fixer, `main` at `22a0c08`): a save
  now first reads the sketch for its line endings (`endingOf`), and that
  read, like the rename, is retried on Windows' transient codes
  (`retried`, `TRANSIENT_WAITS`); a read that still fails is logged and
  the save goes on with the platform's endings. Nothing changed after the
  staging write: a rename that fails for good still leaves
  `.<name>.coffee.saving` behind (**read**). A failed read leaves nothing,
  since the staging file is written after it.
- **M15. A reload that fails rejoins `listening` as an error page**
  (second review, 2026-10-06). A page that started loading and stopped
  without a `did-navigate` rejoins at `did-stop-loading` (M11's refused
  navigation). A reload whose load failed outright would stop the same
  way, and the error page -- which has no preload and never asks for
  problems -- would be sent them, and they would be lost. It cannot happen
  today: `serve` answers every failure with a 404, which is a page that
  loads (M4). **Read**; recorded, not changed. If `serve` ever rejects, or
  a load can fail before `serve` answers, check `did-fail-load` there.
- **U2's mixed-endings note from `sketch:flush`** (`main.coffee`, the
  flush) went to stdout only: the page that would have shown it is going
  away. **Fixed by the second fixer** at the merge: it goes through
  `sayProblem`, so the page that comes up says it. Not checked (**read**):
  the `lifecycle` part checks the note through `sketch:write`, and the
  flush path is the same `queueSave`.
- **R8. T2's completion list.** No new promise chain without a catch;
  `completed` and `completePaused` still `JSON.parse` an answer, as R7
  says. **Read**. Owner: T.
- **U1's `pagehide` flush (`editor.coffee:502`)** blocks in `sendSync`
  until main answers, which main bounds by `SAVE_LIMIT`. Nothing thrown
  there can reach anybody: the page is going. **Read**.

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
  `uncaughtException` was left to Electron's box (M2-M3) until 2026-10-08
  (below).
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
- **A test run exits on an uncaught exception in main** (second fixer):
  `process.on 'uncaughtException'`, registered at the top of `main.coffee`
  only under `BEANS_TEST`, prints `uncaught exception: <stack>` and calls
  `app.exit 1`. Before, Electron's modal box blocked main until clicked,
  and a hidden run sat on it, on Robert's desktop, until killed (twice on
  2026-10-06, below). Nothing in the suite depended on the box: the
  `startup` part's children answer their own box through `ask` and raise
  no exception (**read**). Checked by a `startup` child that a
  `NODE_OPTIONS` preload (`test/fixtures/throw-in-main.js`) makes throw in
  main once the app is ready: it must exit 1 and print the line. Against
  the old code it prints no such line, so the check fails -- established
  by reading, and by running the child with no display at all (no
  `DISPLAY`, `--ozone-platform=headless`), where it died at once (exit
  133, SIGTRAP) without printing it -- on Electron's box, **inferred**. Its effect on a regression:
  that child would put Electron's box on the screen for the check's 15s,
  then be killed.

Not checked: Open Data Folder's failure (M5).

The second fixer's, beside the handler (Claude, 2026-10-06):

- **The watcher's read failures** -- a sketch that would not read, an
  entry it could not stat -- now say `could not read <where>: <why>`, once
  for each path until a read of it succeeds; the repeats go to stdout.
  Before, each said that changes to it "will not be seen", which a failure
  that may pass (Windows' `EBUSY`/`EPERM`, `ENOTDIR`) did not mean, and
  said it at every event. A folder that cannot be watched, or whose watch
  stops, still says "will not be seen". Checked (the `problems` part, a
  sketch made mode 0: said once, a second failing event only on stdout,
  said again after a read has succeeded; not on Windows or as root).
- **The `problems` part's own windows**: `openPage` destroys its window
  when the load rejects; before, the window leaked, its caller's
  `finally` having nothing to destroy yet.

The fixer's changes, from the two reviews and the merge (Claude,
2026-10-06), each with a check that fails without it except where said:

- **Who hears `sayProblem`.** A page leaves the list when it starts
  loading another, as before, and also when its renderer dies or it is
  destroyed -- before, a crashed page stayed on the list and problems
  sent to it were lost rather than held, and a destroyed one was only
  pruned the next time something was said. These hooks are registered
  once per page in `app.on 'web-contents-created'`, not per request. A
  page that started loading and stopped without another arriving (a
  refused navigation, M11; a hash change) rejoins at `did-stop-loading`
  and is sent what was held meanwhile -- under the first version it
  stayed off the list for good. The reload path is now checked in a
  second, never-shown window that the check reloads (never the test
  window: AGENTS.md). The crash is checked in a window of its own session
  (`partition`), on a `data:` page that asks through the preload: a second
  window of the app shared the test window's renderer process (measured,
  Electron 44, Linux), and crashing it would have crashed the suite.
- **At most `HELD` (50) problems are held**, the first kept, the rest
  counted and said as `main: <n> more problems, on the terminal only`.
  A page whose loader failed (R1) never asks, and would otherwise have
  held every problem for the life of the app.
- **M9, M11, M12**, above.

One hazard the fixer met and did not change: `sayProblem` throws if the
list holds a destroyed page (`Object has been destroyed` from `send`), and
called from the `unhandledRejection` listener that throw becomes an
uncaught exception -- Electron's modal box, which blocks the main process.
The hooks above keep destroyed pages off the list; the suite's own `aside`
helper once put one back, and two runs hung on the box until killed
(Claude, 2026-10-06). The helper is fixed; the hazard stands for any future
code that adds to `listening` by hand. **Measured**.

The first version's check that a held problem was not shown early could
not fail: the test window had been taken off the list by hand, so nothing
was sent to it either way. It is replaced by the reload check, which fails
if a reloading page is still sent problems.

## Since 2026-10-08: a player's uncaught exception in main

*Claude (Opus 5.5), branch `fixes/uncaught`, at Robert's decision of
2026-10-08.*

- **Said, not boxed.** `process.on 'uncaughtException'` at the top of
  `main.coffee` now listens in every run. A test run still prints
  `uncaught exception: <stack>` and exits 1. A player's app calls
  `mainFailed`: the terminal gets the same line, and the window's console
  `main: <message> -- CoffeeBEANS hit an error of its own and may not work
  properly from here. /reload reloads the window (the sketch's text is
  kept, what it built is not); if that does not help, quit and start it
  again`. Whether main is sound after a throw cannot be known, so the line
  says it may not be rather than guessing. A failure inside `mainFailed`
  goes to the terminal: a throw inside the listener would end the process.
- **Before any window.** Through `sayProblem`, so held and said once the
  page asks -- no dialog, so A1's never-settling async box does not arise.
- **No spam, no reload loop.** Once for each place thrown from (the stack
  below the message), at most five places, then one line saying the rest
  go to the terminal; repeats are counted on the terminal at the 2nd,
  10th, 100th... time; at most 100 places are remembered. The count starts
  again when a listening page navigates (a reload), so something still
  throwing is said again in the new page. Nothing reloads on its own.
- **`/reload`** (and `:reload`), a new command in the shared table, never
  shortened, does what View > Reload does: main reloads the page that
  asked. A page's own `location.reload()` reaches `will-navigate` and is
  refused there (M11), so it did nothing (measured, Electron 44, macOS).
- **Checked** by a second Electron from the `startup` part, with
  `BEANS_UNCAUGHT=player` (a test run taking the player's way) and the
  `throw-in-main.js` preload, running the by-name part `uncaught`, which
  throws real exceptions from main's timers and reports the console at
  each step: the child exits 0, the held line and the offer show once, a
  repeat is said once, the cap, the terminal counts, `/rel` not reloading,
  and the reloaded page hearing the next throw afresh. Against the old
  code the child exits 1 on the first throw.
- **Not checked:** that Electron's box no longer appears in a player's app
  (it shows only when nothing listens, which the test run's exit already
  relies on); a real throw in shipped code (none is known).

## Questions

For Robert; the code does not decide them.

- ~~**What a player's app does with an uncaught exception in main.**~~
  Answered by Robert, 2026-10-08: say it with `sayProblem`, offering to
  reload the window. Built the same day; see "Since 2026-10-08".
- **R2: should the renderer's error line say where?** It says
  `renderer: <message>`, with no stack, file or line.

## Not fixed, by owner

- **E:** R4's standing `worker.onerror` without `preventDefault` (an error
  before `worker-boot.js`'s listeners exist is said twice; W1 and W2
  otherwise answered by E1), W3, W4, W5, `stop`'s unguarded `await` (M8
  `debug:*`).
- **F:** M8's `openSketch`/`pickSketch` saying IPC wrappers (`:e ../x`),
  `sketch:find`'s ENOTDIR. (M9 was routed by the A2 fixer; the watcher is
  still F's.)
- **V:** `showAbout`/`aboutCopy` rejections (R3) -- harmless today.
- **T:** R7 (one-off, at worst).
- **Nobody tonight:** R5 (the audio worklet's `processorerror`).
