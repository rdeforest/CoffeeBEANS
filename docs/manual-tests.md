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
  particular: undo/redo at the prompt (Cmd-Z, Cmd-Shift-Z) may be dead, since
  the Edit menu has no undo/redo roles (inferred by the integration review);
  Ctrl-Enter, Ctrl-S and Ctrl-. are literal Ctrl, not Cmd; the CI by-hand run
  missed the first save in a folder created outside the app.
