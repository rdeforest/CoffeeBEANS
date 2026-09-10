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
