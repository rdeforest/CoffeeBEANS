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
