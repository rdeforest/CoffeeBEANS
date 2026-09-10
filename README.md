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

Ctrl-Enter and `:run` evaluate into the *live* worker, so definitions persist
between runs -- define a function in one region, call it from another. That is
BASIC's immediate mode. `:restart` is `RUN`: a clean scope.

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
    sketches/       your stuff
    test/           integration suite -- npm test
