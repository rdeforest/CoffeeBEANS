# Manual tests not yet run

Tests that only a person can run, on a platform someone here has, that
nobody has run yet. A stopgap until a QA tracker exists: Robert means to
re-implement QA-Tracker (qa.thatsnice.org) fresh, and this list moves there
when it does. Strike an entry when it has been run, and say what happened.

Each entry: what to do, what should happen, where it came from.

## Windows (Robert has no Windows machine; needs a tester)

- **A CRLF sketch opens clean.** Make a sketch in Notepad (CRLF line
  endings), open it in CoffeeBEANS: it is not marked dirty, `/e` to another
  sketch is not refused, and the file on disk is not rewritten. If it is
  edited, it is saved with LF (decided by Claude, 2026-10-05). From K4,
  overnight 2026-10-05, play-test item 9.
- **The hidden test window.** `npm test` from cmd.exe or PowerShell runs the
  suite; its window shows unfocused and stays up for the whole run. From C1,
  overnight 2026-10-05.
- **AltGr at the prompt.** On a German layout, AltGr+ß types `\` in the
  prompt and the editor and does not pause the sketch; AltGr letters type
  normally during Ctrl-R search. From P1, overnight 2026-10-05; reasoned, not
  measured.

## macOS (Robert's MacBook)

- Everything on `docs/overnight/done/2026-10-05.md`'s play-test list, and in
  particular: Ctrl-Enter, Ctrl-S and Ctrl-. are literal Ctrl, not Cmd; the
  CI by-hand run missed the first save in a folder created outside the app.
- **Undo and redo, Cmd-Z and Cmd-Shift-Z.** Found dead at the prompt by
  Robert on 2026-10-05; Edit > Undo and Redo added for it in K7, overnight
  2026-10-06, and proved on Linux only by clicking the menu items from the
  suite. On the Mac, by hand:
  1. Type `abc` at the prompt, Cmd-Z: the line empties. Cmd-Shift-Z: `abc`
     is back. The same from the Edit menu with the mouse.
  2. In the editor, type a line, pause, type another; Cmd-Z takes away
     exactly the second (not both), and Cmd-Shift-Z puts it back. If one
     Cmd-Z takes two steps, the menu's key fired as well as CodeMirror's.
     Claude expected (reasoned, not measured) that Chromium gives the page
     the key first and the menu only a key the page left alone, as a real
     key behaved on Linux (P1, 2026-10-05); nobody has seen it on a Mac.
  3. The same with Edit > Vim Keys ticked, in insert mode and with `u` and
     Ctrl-R in normal mode.
  4. Edit > Undo from the menu with the editor focused: one step.
  5. Click the canvas, Cmd-Z: neither the prompt nor the sketch changes.
