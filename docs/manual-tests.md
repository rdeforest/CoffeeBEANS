# Manual tests not yet run

Tests that only a person can run, on a platform someone here has, that
nobody has run yet. A stopgap until a QA tracker exists: Robert means to
re-implement QA-Tracker (qa.thatsnice.org) fresh, and this list moves there
when it does. Strike an entry when it has been run, and say what happened.

Each entry: what to do, what should happen, where it came from.

## Windows (Robert has no Windows machine; needs a tester)

- **A CRLF sketch opens clean.** Make a sketch in Notepad (CRLF line
  endings), open it in CoffeeBEANS: it is not marked dirty, `/e` to another
  sketch is not refused, and the file on disk is not rewritten. Edited, it
  stays CRLF (Notepad++'s status bar, or `Format-Hex`), and the console does
  not say "reloaded from disk" (U2, overnight 2026-10-06, after Robert decided
  line endings follow the platform). From K4, overnight 2026-10-05,
  play-test item 9.
- **A new sketch is CRLF, an LF one stays LF.** `/e something-new`, type
  two lines, wait a moment: the file is CRLF. Then edit an LF sketch made
  elsewhere (VS Code set to LF, or one of the shipped examples, which are
  copied as they are in git, LF): it is still LF. The `lifecycle` part
  checks both on the Windows CI job; this is the by-hand look, through a
  player's own editor. From U2, overnight 2026-10-06.
- **The hidden test window.** `npm test` from cmd.exe or PowerShell runs the
  suite; its window shows unfocused and stays up for the whole run. From C1,
  overnight 2026-10-05.
- **AltGr at the prompt.** On a German layout, AltGr+ß types `\` in the
  prompt and the editor and does not pause the sketch; AltGr letters type
  normally during Ctrl-R search. From P1, overnight 2026-10-05; reasoned, not
  measured.

## macOS (Robert's MacBook)

- Everything on `docs/overnight/done/2026-10-05.md`'s play-test list, and in
  particular: undo/redo at the prompt (Cmd-Z, Cmd-Shift-Z) -- confirmed dead
  by Robert on 2026-10-05, fix queued as K7 for the night of 2026-10-06, to
  be re-tested on the Mac once it lands;
  Ctrl-Enter, Ctrl-S and Ctrl-. are literal Ctrl, not Cmd; the CI by-hand run
  missed the first save in a folder created outside the app.
