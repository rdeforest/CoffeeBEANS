# CoffeeBEANS

A BASIC-shaped drawing toy. CoffeeScript in, pixels out, no build step.

CoffeeBEANS is on its way to being a game on Steam: a story about
programming in the late '80s and early '90s, told through challenges that
unlock the language as you solve them, with a sandbox that has everything
open. The plan and the schedule are in [docs/ROADMAP.md](docs/ROADMAP.md).
The code stays free and open; the game adds a story, art and music of its
own.

    npm install
    npm start

## How it works

Sketches run in a Web Worker. Framebuffers live in a `SharedArrayBuffer` the
renderer also sees, so the main thread can present frames while a sketch is
still mid-loop, and `buffer.swap` can genuinely block until a frame is on
screen. That is what makes a plain `loop` work as an animation loop.

    screen 320, 200
    buffer.on
    loop
      cls()
      point 160 + 50 * cos(t), 100 + 50 * sin(t), COLORS.coffee
      buffer.swap

`wait n` also blocks until frames reach the screen, but it is a sleep, not a
swap: it never flips, so a loop can wait between draws without showing its
back buffer.

Stop sets an interrupt flag. A sketch that reaches `buffer.swap` unwinds
cleanly and keeps its definitions; one with no yield point gets terminated.

## Drawing

    point x, y                    line x1, y1, x2, y2
    rect x1, y1, x2, y2           rectFill x1, y1, x2, y2
    circle cx, cy, r              circleFill cx, cy, r
    ellipse cx, cy, rx, ry        ellipseFill cx, cy, rx, ry

Every one takes an optional colour as its last argument, and every one is a
primitive writing the buffer directly rather than a loop over `point`.
Rectangles take two corners, like `line`, rather than a position and a size,
so the arguments do not change meaning between neighbouring commands.

Lines are clipped before they are drawn, so `line -1e9, -1e9, 1e9, 1e9`
costs the same as any other line. Ellipses are scanline-filled and bounded
by the screen for the same reason.

## Text

    locate 1, 1
    color COLORS.coffee
    text "SCORE #{score}"

An 8x8 bitmap font, drawn through the same plot the shapes use -- so it
obeys `drawTo` and lands on a surface as readily as on the screen. `textAt`
takes pixel coordinates when a score needs to sit somewhere exact, and
`textScale` makes it chunkier. The glyphs live in `src/runtime/font.coffee`
as readable hex, one line each, so you can edit one.

## Loading images

    cat = load "https://example.com/cat.png"
    put cat, 100, 80

`load` blocks, the way `buffer.swap` does and for the same reason: a worker
parked in `Atomics.wait` cannot receive a message, but it can send one before
it parks. No promises, no await. Downloads are cached under `assets/` in your
data folder on first fetch, so a sketch you demo on a stage with bad wifi
still runs, and so does one whose URL rotted six months ago.

## Paints

Anywhere a colour goes, a paint goes too -- `cls`, `point`, `line`, the rect
and ellipse families, `text` and `fill`:

    cls gradient COLORS.blue, COLORS.black, angle: pi / 2, length: 200
    rectFill 0, 150, 319, 199, tile myPattern
    color maker (p) -> COLORS.fromHSV p.x, 1, 1

A paint is a function of position, which is all a pattern or a gradient
really is, and it takes **the same probe a fill rule takes**. So there is one
idea here rather than two:

    fill 10, 10, where (p) -> p.value < 0.5     # which pixels
    color        maker (p) -> ...                # what colour each becomes

A maker can read the pixel it is replacing through `p.color`, which is how
you darken or tint what is already there rather than painting over it.

A solid colour stays a plain number the whole way down, so a run is still
filled in one call and nothing pays for machinery it is not using. Only a
maker costs a call per pixel.

## Filling

    fill x, y                              # flood what matches the seed pixel
    fill x, y, COLORS.red, border COLORS.white
    fill x, y, COLORS.red, where (p) -> p.value < 0.5

One walk, one question: may the fill continue into this pixel. "Stop at
anything unlike where I started" and "stop at white" are not two features,
they are two answers. `border` is BASIC's `PAINT`: it crosses anything that
is not the border colour, where the default crosses nothing unlike the seed.

A rule is a rule and a colour is not, so they tell themselves apart and
`fill x, y, border black` needs no placeholder to mean "the colour I already
set". Scanline spans, four-way, and it obeys `drawTo`.

The probe a `where` predicate receives carries position (`p.x`, `p.y`), the
colour there and at the seed, channels as `p.red`/`p.green`/`p.blue`/
`p.alpha` and `p.hue`/`p.saturation`/`p.value`, and the four neighbours,
which are `null` past the edge. It is one reused object, valid during the
call and not after -- a fill tests tens of thousands of pixels and building
one each would cost more than the walk.

## Surfaces

An off-screen surface is shaped exactly like the screen, so every drawing
command works on one without knowing the difference:

    canvas = surface 64, 64
    drawTo canvas, ->
      cls 0x00000000
      circleFill 32, 32, 20, COLORS.coffee
    put canvas, 100, 80

`get` captures a region, `put` blits one back, `stamp` blits one scaled and
rotated, and `overlaps` answers collision by actual pixels rather than
bounding boxes. `drawTo` takes a block, which restores the previous target
even if the block throws; called bare it is a mode, like the current colour.

The same type is meant to serve sprites, loaded images and font glyphs when
those arrive. `examples/tree.coffee` uses it for recursive feedback.

## Where your work lives

Sketches live in your data directory, not in this repo, so running the app
never collides with working on it:

    ~/.local/share/coffeebeans/sketches/       ($XDG_DATA_HOME is honoured)

**File -> Open Data Folder** (Ctrl+Shift+D) opens it in your file manager.
The directory is seeded from `examples/` the first time it is created, and
never again -- an existing data directory belongs to you, including an empty
one. `BEANS_DATA_HOME` overrides the location; that is how `npm test` gets
its own throwaway copy.

`sketches/` (or any folder above it) can be a link to somewhere else,
another drive say. If the link points at nothing -- the drive is not
mounted -- CoffeeBEANS says so at launch, naming both ends, and offers Try
Again (once the drive is back), Open Folder (the folder the link is in) and
Quit. It never creates the missing folder itself, which would quietly
collect new sketches somewhere other than the drive.

Each example is offered exactly once, recorded in `.seeded`, so a new
example added in an update arrives on your next launch while an example you
edited keeps your edit and one you deleted stays deleted.

The directory is a directory rather than a bare pile of sketches so it has
somewhere to grow. Beside `sketches/` sit `assets/`, where `load` caches
what it downloads, and `settings.json`, what the app remembers about how you
like to work -- for now, whether Vim Keys and Warn About Name Case are
ticked.

A sketch's name is its path under `sketches/` without the `.coffee`. Where
the disk ignores case, as macOS's and Windows's do unless set up otherwise,
`Foo` and `foo` are one sketch: `/e Foo` opens `foo.coffee`, and the console
says so unless **Edit > Warn About Name Case** is unticked. The app asks the
disk which kind it is rather than going by the platform.

## Editing

The editor pane is CodeMirror with the keys any text editor has -- Ctrl-Z
to undo, Ctrl-F to find, and the rest -- and the file on disk is the only
source of truth: edits autosave, and a save from another editor (vim in
another window, say) reloads the pane. On a Mac those editor keys are Cmd-Z
and Cmd-F, as copy (Cmd-C) and redo (Cmd-Shift-Z) are at the prompt; the
app's own keys below -- Ctrl-Enter, Ctrl-S, Ctrl-. -- stay Ctrl. With
ordinary keys Ctrl-r does nothing in the editor, so it cannot reload the page
under an unsaved edit; reloading is View > Reload. Running is an operation on a region:

    Ctrl-Enter          eval the selection, or the paragraph under the cursor
    Ctrl-Shift-Enter    run -- fresh worker, then the whole buffer
    Ctrl-.              stop
    Ctrl-S              save now (edits autosave anyway)
    > at the console    one line, evaluated in the live worker

Commands are typed at that `>` prompt, starting with `/`:

    /run                fresh worker, then the whole buffer
    /eval               the whole buffer, into the live worker
    /e name             open a sketch, creating it if new; /e! drops edits
    /w                  save now
    /target 30          flag the first source line past 30; /target 0 clears
    /help [word]        quick reference in the console pane: a section,
                        an object (keys, mouse, buffer), or a search

`:run` means what `/run` does, for hands that learned vim. A prompt line
starting with `/` or `:` is always a command, so CoffeeScript that opens
with a regex goes in parens: `(/x/).test s`. A name can be cut short the way
vim cuts them -- `/e` is edit, `/ev` is eval -- and a name that is not a
command gets the list of the ones that are.

**Eval** puts code into the worker you already have, so everything it knows
stays. **Run** throws that worker away and starts a new one. They are
different in kind rather than in scope, which is why they do not share a
verb: there is no "eval all" button, because eval-the-whole-buffer is the
same operation as eval-this-region with everything selected, and `/eval` is
there when you want it without reaching for the mouse.

An eval pressed while a sketch is still running is refused, not queued: the
Eval button greys out and the keyboard binding says so in the console. Stop
it first, or Run, which replaces the worker and never has to ask. Otherwise
the second eval would fire the instant the first ended and look exactly like
the sketch starting itself again.

**Where the keyboard goes.** Run and `/eval` hand it to the canvas, because
a sketch you just ran is almost always one you are about to play with.
Region eval leaves it in the editor: that is the loop of redefining something
and carrying on typing, and the next keystroke belongs to the editor. If the run
fails, a syntax error puts the cursor on the offending character and marks
its line. A runtime error lists its stack beside the console, innermost
first, with that line marked in the editor, and gives the `>` prompt the
keyboard -- the frames are gone, but the image still holds every top-level
name worth asking about. Click a frame to go to its line; a frame from a
region of another sketch opens that sketch.

Modes persist in the live worker too: the current colour, the draw target,
double buffering, any frame cap. `screen` resets buffering and the cap, like
BASIC's SCREEN reset pages, so a sketch starts in the mode it asks for
rather than the one the last sketch left behind. Put `buffer.on` and
`buffer.fps` after `screen`.

Ctrl-Enter and `/eval` evaluate into the *live* worker, so definitions persist
between evals -- define a function in one region, call it from another. That is
BASIC's immediate mode. `/run` is `RUN`: a clean scope.

The `>` prompt under the console is the same live worker again, one line at a
time. It goes through shared memory rather than `postMessage`, for the reason
printing does: a worker busy in a loop, or asleep in `Atomics.wait`, receives
no messages, but it can still read memory at a yield point. So the prompt
answers *between frames of a running sketch* -- you can ask a flying flock how
many boids it has, and set `step = 100` without stopping it. A sketch's names
live in its own scope and only reach the image when the run ends, which for a
`loop` is never, so the running frame lends them for the length of the
question and takes back whatever the answer changed.

A sketch that never reaches a yield point never answers, the same way it never
stops.

The prompt has the node REPL's keys. Up and Down walk earlier lines, and
Ctrl-R and Ctrl-S search back and forward through them. Ctrl-A and Ctrl-E go
to the start and end of the line, Alt-B and Alt-F a word at a time. Ctrl-K
and Ctrl-U cut, and Ctrl-Y puts the cut back -- so redo there is
Ctrl-Shift-Z, not Ctrl-Y; Ctrl-W and Alt-D delete a word. Ctrl-C copies a selection or else clears the line,
and Ctrl-L clears the console. While the prompt has the keyboard these beat
the app's own shortcuts: Ctrl-E there is end of line, not hide the editor.
On a Mac, Option types characters, so the Alt keys are not bound there. Tab
completes a name, as far as every candidate agrees; a second Tab lists them.

A sketch runs in its own scope, so its names cannot collide with the drawing
commands or with anything the app owns. You can still shadow a command --
`line = 5` hides `line` for as long as the session lives -- but the command
itself is never damaged, and `/run` gives it back.

### Vim keys

**Edit > Vim Keys** puts vim in the editor. It switches live, keeping the
buffer, the cursor and the undo history, and the app remembers it. With it
ticked:

- Every `/` command works from vim's command line as well: `:run`, `:e name`,
  `:e!`, `:w`, `:help keys`. One table serves the prompt and vim, so the two
  cannot drift apart.
- Ctrl-r in visual mode evals the selection. Normal mode keeps it for redo,
  where vim wants it; visual mode leaves it free.
- Ctrl-Enter, Ctrl-Shift-Enter, Ctrl-S and Ctrl-. work as they do without vim.
- Ctrl-e scrolls in normal mode, as vim's does; it shows or hides the editor
  from insert mode or the canvas.

## Input

Polled, not evented -- a worker parked in `Atomics.wait` cannot receive a
message, so the main thread writes shared memory and the sketch reads it.
That is also how BASIC felt.

    if keys.down 'left' then x -= 2
    print 'jump' if keys.hit 'space'
    point mouse.x, mouse.y if mouse.left

`down` is held right now; `hit` went down since the last frame and is sticky
in shared memory until claimed, so a tap that starts and ends between two
frames is still caught. `up` is the other edge, sticky the same way.
`buffer.swap` claims them; `keys.poll` does it by hand for code that never
swaps.

With no name, each lists the keys it would say yes to -- so to find out what
a key is called, hold it and ask: `keys.down()` at the prompt. Punctuation
answers to its character or a word (`';'` or `'semicolon'`), and a name
nobody knows is an error rather than a quiet `false`.

**Click the screen to send it keys.** Otherwise the editor keeps them, which
is what you want while you are typing. The canvas gets a coffee-coloured
outline when it holds the keyboard.

## Sound

Like paints: a plain value is the simple case, and a function in the same
slot is the unlimited one.

    sound 440, 0.5                                  # Hz, seconds
    sound 'C4', 0.5                                 # or a note name
    sound 'E4', 1, voice: 1, wave: 'square', volume: 0.3
    sound ((t) -> 440 + 20 * sin(t * 30)), 2         # vibrato, t in seconds
    sound 'A3', 1, volume: (t, u) -> 1 - u           # a fade, u from 0 to 1
    sound 110, 1, wave: (phase) -> if phase < 0.25 then 1 else -1

`sound` queues and returns at once. A voice is any number or name, made the
first time you use it, and each plays its notes in order, so one voice is a
tune and several are harmony. There is no limit on voices; past a few at
full volume they start to distort, so turn each down as on a mixing desk.

Leave out the length and a note plays until it is stopped. Every `sound`
hands back its note, to change or stop while it plays -- which is how a key
held down becomes a note held down:

    playing = {}
    loop
      for key, note of {a: 'C4', s: 'D4', d: 'E4'}
        playing[key] ?= sound note, voice: key if keys.hit key
        if playing[key] and not keys.down key
          playing[key].stop 0.1                   # a 0.1s fade
          delete playing[key]
      buffer.swap

`held.frequency = 'D4'` and `held.volume = 0.5` change a note as it plays;
`sound.stop 'bass'` silences a voice and its queue, `sound.stop()` all of
them. Functions run in
your sketch when the note is queued -- a curve is sampled every 2ms, a wave
as one period -- so they can use anything the sketch can see. The sound
itself is made on the audio thread, which keeps time whatever the sketch is
doing. Stop and Run silence everything; a pause holds the sound with the
picture.

## Stopping to look

Put `breakpoint` in a sketch -- BASIC's `STOP` -- and running it stops
there. The line about to run lights up in the editor, and the names that
line can see appear beside the console, with objects that open in place.
The `>` prompt then asks about the stopped call, and can change it.

    Cmd/Ctrl-\  F8     stop now on whatever line is running; again, carry on
    F10  /line         step to the next line that runs, wherever it is
    /pause             hold the sketch at the next frame
    /step              run on to the next frame and hold there
    /continue          carry on, from either kind of pause

The debugger is on for every run, so an uncaught error stops on the line
that threw, with its frame in the pane and the prompt, until Continue (F8)
ends the run. With DevTools open neither happens, and `breakpoint` does
nothing: the two cannot share the page.

## Panels

Screen, editor and console are resizable -- drag the splitters between them.
Sizes are remembered. Ctrl-e hides and shows the editor. Detaching panels
into their own windows, and driving all of this from a sketch, is planned:
see NOTES.md.

## Which version

**Help -> About** shows the version and what it is running on -- Electron,
Chromium, Node and the OS -- with a Copy button that puts exactly that text
on the clipboard, for a bug report.

The version is never bumped by a commit. `package.json` holds the release
number, set by hand; at startup the app asks git for the rest -- the commit
count, the abbreviated commit id, and `-dirty` when the checkout has
uncommitted changes:

    0.0.1+142.c7e7f6a-dirty

Run without git installed, or where git cannot answer, it shows the bare
release number and says why there is no commit id. A packaged build has no
`.git`; the step that makes one is to write the same string into
`version-stamp.txt` at the app's root (from a full clone -- a shallow one
counts a single commit), and where there is no `.git` the app reads that
file's first line instead. In a checkout git is always asked and the stamp
is ignored, so one left behind by a packaging run cannot go stale, and
`.gitignore` keeps it out of commits. With neither, the version is the bare
release number. `src/main/version.coffee` has the details.

## Layout

    src/main/       Electron main process; serves app:// with COOP/COEP
    src/renderer/   SAB owner, worker lifecycle, rAF present loop
    src/runtime/    the drawing API, runs inside the worker
    examples/       seed sketches, copied out on first run
    test/           integration suite -- npm test

## Tests

`npm test` drives the real app through `executeJavaScript`, in parts:

    npm test                                every part
    BEANS_TESTS=buffers npm test            one
    BEANS_TESTS=buffers,lifecycle npm test  a few

The parts are `editor image repl buffers stepping debugging focus lifecycle
drawing color loading shell about input random sound perf`. Each starts from a reset app --
scratch loaded, buffer blank, worker restarted -- so running one alone means
the same thing as running it in the middle of everything else, and a part
that fails does not take the ones after it with it. The whole suite takes a
few minutes; one part is a few seconds. It exits nonzero when a check fails.

`VAR=x npm test` is the POSIX shells' way to set a switch. From cmd.exe it
is `set BEANS_TESTS=buffers` and then `npm test`; from PowerShell,
`$env:BEANS_TESTS='buffers'` and then `npm test`. Either way it stays set
for the rest of that window, so clear it to run every part again.

Add a check to `test/parts/<area>.coffee`; the handles it takes off `t` are
listed at the top of the file and defined in `test/toolkit.coffee`.

The test window is not shown, so a run never takes focus. `BEANS_SHOW=1` shows
it if you want to watch one go by, and `BEANS_MINIMIZE=1` minimises it, which
is how you check that a sketch still runs when the window is not on screen --
Chromium throttles a minimised window, and the present loop is what wakes a
sketch parked in `buffer.swap`.

## License

The code is MIT; the documentation is CC BY-SA 4.0. [LICENSE](LICENSE) says
which files are which and lists the third-party pieces, and
[CREDITS.md](CREDITS.md) says who made what.
