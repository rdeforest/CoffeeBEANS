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

- `assets/` -- images pulled off the internet, cached so a sketch still runs
  when the venue wifi is bad or the URL has rotted.
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

### Open question

Where does a surface live? Worker-local memory is enough for anything the
worker draws itself. Hardware sprites are different -- the main thread
composites those during the blit, so they have to be in the SAB, which
means an allocator and a free list. The cheap answer is worker-local by
default, promoted into the SAB only when registered as a sprite. Decide
before writing the type, because it changes what a surface handle is.
