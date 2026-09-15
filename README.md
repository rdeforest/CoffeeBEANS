# CoffeeBEANS

A BASIC-shaped drawing toy. CoffeeScript in, pixels out, no build step.

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

Each example is offered exactly once, recorded in `.seeded`, so a new
example added in an update arrives on your next launch while an example you
edited keeps your edit and one you deleted stays deleted.

The directory is a directory rather than a bare pile of sketches so it has
somewhere to grow: `assets/` and a preferences file are the next things
expected to land beside `sketches/`.

## Editing

The editor pane is CodeMirror with vim keybindings, and the file on disk is
the only source of truth -- edits autosave, and writes from vim in another
window reload the pane. Running is an operation on a region:

    Ctrl-Enter          run the selection, or the paragraph under the cursor
    Ctrl-r              same, from visual mode
    Ctrl-Shift-Enter    restart the worker and run the whole buffer
    :w                  force a save        :run       run the whole buffer
    :restart            fresh worker        Ctrl-.     stop
    :help [topic]       quick reference in the console pane

A run pressed while a sketch is still running is refused, not queued: the
run buttons grey out and the keyboard bindings say so in the console. Stop
it first, or Restart, which replaces the worker. Otherwise the second run
would fire the instant the first ended and look exactly like the sketch
starting itself again.

Modes persist in the live worker too: the current colour, the draw target,
double buffering, any frame cap. `screen` resets buffering and the cap, like
BASIC's SCREEN reset pages, so a sketch starts in the mode it asks for
rather than the one the last sketch left behind. Put `buffer.on` and
`buffer.fps` after `screen`.

Ctrl-Enter and `:run` evaluate into the *live* worker, so definitions persist
between runs -- define a function in one region, call it from another. That is
BASIC's immediate mode. `:restart` is `RUN`: a clean scope.

A sketch runs in its own scope, so its names cannot collide with the drawing
commands or with anything the app owns. You can still shadow a command --
`line = 5` hides `line` for as long as the session lives -- but the command
itself is never damaged, and `:restart` gives it back.

Ctrl-r stays bound to redo in normal mode; the run binding only takes it in
visual mode, where vim leaves it free.

## Input

Polled, not evented -- a worker parked in `Atomics.wait` cannot receive a
message, so the main thread writes shared memory and the sketch reads it.
That is also how BASIC felt.

    if keys.down 'left' then x -= 2
    print 'jump' if keys.hit 'space'
    point mouse.x, mouse.y if mouse.left

`down` is held right now; `hit` went down since the last frame and is sticky
in shared memory until claimed, so a tap that starts and ends between two
frames is still caught. `buffer.swap` claims them; `keys.poll` does it by
hand for code that never swaps.

**Click the screen to send it keys.** Otherwise the editor keeps them, which
is what you want while you are typing. The canvas gets a coffee-coloured
outline when it holds the keyboard.

## Panels

Screen, editor and console are resizable -- drag the splitters between them.
Sizes are remembered. Ctrl-e hides and shows the editor. Detaching panels
into their own windows, and driving all of this from a sketch, is planned:
see NOTES.md.

## Layout

    src/main/       Electron main process; serves app:// with COOP/COEP
    src/renderer/   SAB owner, worker lifecycle, rAF present loop
    src/runtime/    the drawing API, runs inside the worker
    examples/       seed sketches, copied out on first run
    test/           integration suite -- npm test
