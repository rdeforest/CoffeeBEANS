# Design notes

Decisions and intentions that are not obvious from the code. Things already
built are described in the README; this file is for what is coming and why.

## Panels

There are three panels: the **screen**, the **editor**, and the **console**.
Today they are docked in a fixed arrangement and resizable by dragging the
splitters between them. Sizes persist in localStorage, and a window that
shrinks below a panel's size gives room back without overwriting the size
the user chose.

The intent is that all three become fully independent:

- **Detachable by the user** -- drag a panel out into its own window, and
  drop it back to re-dock it.
- **Controllable from a sketch** -- detach, re-attach, resize, move,
  minimize and restore, all callable from code:

      panels.console.detach
      panels.console.move 1920, 0
      panels.screen.resize 1280, 800
      panels.editor.minimize

That second half is the point. A sketch that wants the whole display for
itself should be able to say so, and a demo recorded for a stream should be
able to put the console on the second monitor without anyone touching a
mouse.

### The hard part, recorded now so it is not a surprise later

Detaching the **screen** panel is qualitatively harder than the other two.
The canvas presents the framebuffer straight out of the SharedArrayBuffer,
so a second BrowserWindow hosting that canvas needs access to the same SAB.
Electron's ordinary `ipcRenderer` path serializes, which will not do.

The candidate route is `MessageChannelMain`: create a channel in the main
process and hand a `MessagePort` to each renderer, then post the SAB over
that port. Both windows are same-origin under `app://` and cross-origin
isolated already, which are the preconditions. **This is unverified.**
Confirm a SharedArrayBuffer actually survives that transfer before designing
anything on top of it -- if it does not, the fallback is to keep presentation
in the original window and make the detached "screen" a mirror fed frames
over the port, which costs a copy per frame and changes the timing story.

The editor and console have no such constraint. They are DOM and text; a
second window can own them outright.

### One naming decision to make deliberately

`minimize`, `move` and `resize` mean different things docked and detached.
Docked, `minimize` collapses a panel to nothing and `move` reorders it in
the layout. Detached, both are straightforward BrowserWindow operations.
Either the verbs mean the obvious thing in each mode, or detaching is
required before the window-ish verbs work. Pick one before writing the API,
not after.

## Input, and what it deliberately does not do yet

Keys are a bitmap: one bit per key for "held", one for "went down since you
last looked". That answers *is this key down*. It does not answer *what did
they type*, and the difference matters as soon as anyone wants a sketch that
accepts text -- keyboard layout, shifted characters, dead keys and IME all
live on the other side of that line.

The mechanism for text is different: a ring buffer of characters in the SAB
with an atomic head and tail, filled from `keydown`'s resolved `event.key`
rather than `event.code`. That is BASIC's `INKEY$`. Worth doing when
something needs it, not before.

Also missing on purpose, in rough order of likely demand:

- `keys.released`, the falling edge. Same sticky-bit trick as `hit`, one
  more bank of 8 words.
- Key repeat. The bitmap has no notion of it; a sketch that wants repeat
  can count frames itself, which is usually what you want anyway.
- Gamepads. The Gamepad API is polled already, so it maps onto this design
  cleanly -- main thread reads pads each frame and writes the header.

Header words 32..63 are spare and reserved for exactly this sort of thing.

## The data directory

    ~/.local/share/coffeebeans/
      sketches/

`$XDG_DATA_HOME` is honoured, and `BEANS_DATA_HOME` overrides it outright --
which is how the test suite gets a disposable copy at `$PWD/test_tmp`. That
suite removes its directory when everything passes and leaves it behind when
anything fails, so a failure can be picked over afterwards.

Seeding happens only when the whole data directory is absent. An existing
one with no sketches in it is a user who deleted their sketches, not a fresh
install, and re-seeding would be obnoxious.

Expected to land beside `sketches/`:

- `assets/` -- done. Images pulled off the internet are cached here on
  first fetch, keyed by a hash of the URL.
- a preferences file, in YAML. Panel sizes currently live in localStorage,
  which is the wrong home for anything a person might want to edit or copy
  between machines; they should move here.

## Capture and redraw, for feedback effects

The eventual want: sample a region of the screen and redraw it scaled and
rotated, repeatedly, so a vertical line becomes two branches becomes a tree.

The thing to notice before building it is that **four separate features want
the same underlying type**: an off-screen pixel surface with a blit that can
scale and rotate.

- capture-and-redraw, above
- sprites, which are surfaces the main thread composites
- images loaded from disk or the network
- bitmap font glyphs, which are just small sprites

Design that surface type once and all four fall out. Designing them
separately means writing the same sampling loop four times.

### Sampling

Iterate the *destination* pixels over the transformed bounding box and
inverse-transform each one back into the source. Forward mapping leaves
holes whenever the transform magnifies. Nearest-neighbour by default --
the crunch is the aesthetic, and it is what makes the moire in the hallway
sketch interesting rather than a defect. Bilinear can be an option later.

### The part that is easy to get wrong

For feedback effects the source and the destination are the same buffer.
Sampling from a region you are simultaneously writing gives progressive
smearing; sampling a snapshot gives clean recursion. Both are legitimate
effects, so the choice has to be explicit rather than an accident of loop
order. That argues for two operations, not one:

    snap = capture 0, 0, 320, 200      # a surface, detached from the screen
    draw snap, x, y, scale: 0.7, angle: 0.4

`capture` copies; `draw` blits. If someone wants smearing they can blit the
screen to itself deliberately once that is a separate, named thing.

### Still open

Where does a surface live? Worker-local memory is enough for anything the
worker draws itself. Hardware sprites are different -- the main thread
composites those during the blit, so they have to be in the SAB, which
means an allocator and a free list. The cheap answer is worker-local by
default, promoted into the SAB only when registered as a sprite. Decide
before writing the type, because it changes what a surface handle is.

## What is left of sprites

Surfaces, get/put/stamp and pixel-accurate `overlaps` are in. What is not is
the *hardware* half: sprites that live outside both framebuffers, composited
by the main thread during present, so moving one does not dirty the picture
underneath.

Worth being honest about the payoff. Every sketch so far is a `cls` and
redraw loop, and in that shape hardware sprites buy nothing -- the
background is being repainted anyway. Where they do pay is the case with no
full redraw: a cursor over a canvas you do not want to touch, which is
exactly the paint-app shape. Build them when something needs that, not
before.

When it happens it needs a sprite arena in the SAB, because the main thread
has to read the pixels. Surfaces stay worker-local by default and only get
copied in when registered as a sprite; sprite counts are small and stable,
so a slot allocator is enough and no general-purpose heap is needed.

## Smaller things noticed while building surfaces

- `get` allocates a fresh Uint32Array every call. `examples/tree.coffee`
  makes seven per frame, which is a couple of megabytes of garbage a frame.
  A `get x1, y1, x2, y2, into: existing` form would reuse the storage.
- `stamp` samples nearest neighbour. Bilinear would want to be an option
  rather than a replacement -- the crunch is the aesthetic.
- `overlaps` tests alpha per pixel over the overlapping rectangle. A cached
  1-bit mask per surface would be faster, at the cost of invalidating it on
  every draw into that surface. Not worth the bug surface yet.

## Line styles and fill patterns

Wanted eventually, and they fit the existing shape: both are state, like the
current colour. A line style is a repeating bit pattern consumed along the
walk; a fill pattern is an 8x8 tile indexed by destination coordinates, which
is how every paint program of that era did it. Neither changes any signature.

## Scope shadowing, three times now

Worth writing down as a rule, because it has bitten in three different
contexts with three different symptoms and no error message in any of them:

1. `history` in the renderer silently became `window.history`, because
   assigning a read-only global fails quietly in sloppy mode.
2. `onmessage` in a sketch nulled the worker's inbox, because assigning a
   non-callable to an event handler sets it to null.
3. `load` declared as a top-level `const` in worker-boot.js shadowed the
   runtime's `load` for every sketch, because a classic worker's top-level
   `const` lives in the global *lexical* environment, which indirect eval
   can see and which wins over globalThis.

The rule that covers all three: **anything that shares a scope with sketch
code must declare nothing at that scope.** Our modules compile wrapped, the
bootstrap lives inside an IIFE, and the worker listens with
addEventListener rather than assigning onmessage. A test asserts the
runtime globals are still reachable from a bare sketch, which is the
cheapest way to catch the next one.

## Flood fill

Wanted: `fill x, y[, borderRule[, color]]`. The two cases already asked for
are "stop at anything that is not the colour under x, y" and "stop at
anything whose red component is above 0.1". Those are the same walk with a
different predicate, so the border rule is a function from a pixel colour to
stop-or-continue, defaulting to "not the seed colour", plus a few named
rules so the common cases read like BASIC. Not designed yet; workshop the
argument shape before writing the walk.

## A line count in the editor

The sixty-line wall on the lander sketch worked, and the count was done by
hand in a separate REPL. The editor should show it: non-blank, non-comment
lines, in the status area, updated as you type. Pico-8's token counter is
the precedent, and it is the reason a generation of people finished games
there. A configurable limit that turns the count red is the natural second
step; refusing to run past it is a third, and probably a step too far.

## Known defects, found 2026-09-12, cleared 2026-09-15

All eight are fixed and each has a test that fails against the code before
its fix. Kept as a list because the shape of them is instructive: every one
was a case of state or a guard that was *almost* right.

- Runtime error lines. The stack regex looked for `<anonymous>`, but
  CoffeeScript emits `//# sourceURL=<the filename we passed>`, so it never
  matched. Sketches now compile with a real source map under a regex-safe
  script id, and a stack frame maps back through it. Column matters: at
  column 0 most compiled lines carry no mapping at all, so a miss walks
  backwards to the nearest one.
- `buffer.fps` stored a header word nobody read. The renderer now gates the
  swap branch on it, which is the branch that serves a swap, so a sketch
  asking for 30fps spends the rest of its time asleep.
- `screen` accepted 0, negative and over-sized dimensions and let the
  renderer throw in `createImageData` once a frame, which reported the
  mistake as a wall of errors far from the line that caused it. It throws
  at the call now.
- Autosave truncated before writing. Saves go to a staging file and rename
  into place; a rename is atomic, so a watcher can only ever read the old
  file or the new one, never a half-written one. Ignoring our own writes
  turned out to be unnecessary once the read cannot be partial.
- Seeding could write over a sketch of the same name. It now skips anything
  already on disk while still recording it as offered, so the copy is not
  made and is never attempted again.
- `fs.watch` had no error listener, so removing the sketches directory took
  the main process down with it.
- The `app://` guard compared with `startsWith ROOT` and no separator.
- `COLORS.fromHSV` exists, in degrees, beside `fromRGB`.

While fixing the fps cap: `screen` already reset double buffering, and the
frame cap is a mode in exactly the same sense, so it resets that too. A
leftover cap from a stopped sketch silently slowing the next one is the
same failure as a leftover page mode, and it caught me inside a test.

## Scope shadowing, three times now

Worth writing down as a rule, because it has bitten in three different
contexts with three different symptoms and no error message in any of them:

1. `history` in the renderer silently became `window.history`, because
   assigning a read-only global fails quietly in sloppy mode.
2. `onmessage` in a sketch nulled the worker's inbox, because assigning a
   non-callable to an event handler sets it to null.
3. `load` declared as a top-level `const` in worker-boot.js shadowed the
   runtime's `load` for every sketch, because a classic worker's top-level
   `const` lives in the global *lexical* environment, which indirect eval
   can see and which wins over globalThis.

The rule that covers all three: **anything that shares a scope with sketch
code must declare nothing at that scope.** Our modules compile wrapped, the
bootstrap lives inside an IIFE, and the worker listens with
addEventListener rather than assigning onmessage. A test asserts the
runtime globals are still reachable from a bare sketch, which is the
cheapest way to catch the next one.

## Flood fill

Wanted: `fill x, y[, borderRule[, color]]`. The two cases already asked for
are "stop at anything that is not the colour under x, y" and "stop at
anything whose red component is above 0.1". Those are the same walk with a
different predicate, so the border rule is a function from a pixel colour to
stop-or-continue, defaulting to "not the seed colour", plus a few named
rules so the common cases read like BASIC. Not designed yet; workshop the
argument shape before writing the walk.

## A line count in the editor

The sixty-line wall on the lander sketch worked, and the count was done by
hand in a separate REPL. The editor should show it: non-blank, non-comment
lines, in the status area, updated as you type. Pico-8's token counter is
the precedent, and it is the reason a generation of people finished games
there. A configurable limit that turns the count red is the natural second
step; refusing to run past it is a third, and probably a step too far.

## Known defects, queued

Found by a code review on 2026-09-12 and deliberately left out of the worker
lifecycle fix, so they do not get lost:

- Runtime error line numbers never show. `worker-boot.js` matches
  `<anonymous>:N:` in the stack, but CoffeeScript's inline source map adds a
  `sourceURL`, so frames read `sketch (region):N:` and `line` is always
  undefined. It would also be a JS line, not a CoffeeScript one; map it back
  through the source map.
- `buffer.fps` stores a header word the renderer never reads. Either pace
  swaps in `frame` or drop it from `:help`.
- `screen` accepts 0, negative and over-sized dimensions; the renderer then
  throws in `createImageData` every frame. Clamp or throw in `screen`.
- Autosave writes with truncate-then-write, and the watcher can fire on the
  truncate and read a blank file 60ms later, which the editor then accepts
  and autosaves back. Needs a slow disk or a large file. Write to a temp
  file and rename, and ignore watcher events while our own write is in
  flight.
- Seeding copies an example over a user sketch of the same name if the name
  is not yet in `.seeded`, and a pre-manifest directory with an emptied
  `sketches/` gets re-seeded. Skip names already on disk, but still record
  them.
- `fs.watch` on the sketches directory has no error listener; removing the
  directory while the app runs throws in the main process.
- The `app://` path guard uses `startsWith ROOT` without a trailing
  separator.
- The rainbow in `curve.coffee` had to be hand-built from a hue ramp. A
  `COLORS.fromHSV` beside `fromRGB` would have saved the detour.

## Why the tail of a print burst can lag

Prints batch: the first in a 16ms window goes immediately and the rest ride
along, flushed at the next print, the next swap, or the end of the run. So
`print 'a'` then `print 'b'` then ten seconds of computation with no swap
shows `a` at once and `b` ten seconds later.

Neither `yield` nor `setTimeout` fixes this. A timer only runs when the
worker's event loop is free, and during a long synchronous stretch it is
not; while parked in `Atomics.wait` the thread is blocked outright and
timers do not fire either. Generators would work, but only by making every
sketch a generator and having the runner drive it, which is a different
execution model than the one the blocking design is built on.

The real fix is to stop routing prints through `postMessage` at all and put
them in a ring buffer in the SAB: the worker writes UTF-8 at print time and
the renderer drains the ring every frame regardless of what the worker does
next. That is the same mechanism audio will want for sample data, so it is
worth building once, for both.

## Ending global collisions, properly

Sketches compile bare on purpose -- their top-level `var`s land on
globalThis, which is how definitions survive between eval-region runs. The
live image *is* that sharing, which is also why collisions are possible.
Wrapping sketch code in a function would end the collisions and end the
live image with it.

There is a way to have both. CoffeeScript emits its declarations as a
single leading `var a, b, c;`, so the runner can read that list without a
full parse, run the sketch inside a function, and copy the declared names
in and out of a persistent object:

    var a = image.a, b = image.b;     // restore (re-declaring does not clear)
    <compiled sketch>                 // its own `var a, b, c;` is harmless
    image.a = a; image.b = b;         // harvest

Free variables like `line` and `point` still resolve outward to the runtime
API on globalThis, so nothing about the API changes. Sketch names would stop
touching globalThis entirely, which closes the class for good.

Two things to decide first. It shifts compiled line numbers, so it has to
land together with the source-map work rather than after it. And shadowing
becomes impossible: today `line = 5` in a sketch really does replace the
drawing command until a restart, which is arguably correct for a BASIC and
would stop being possible. Worth choosing deliberately rather than
inheriting.
