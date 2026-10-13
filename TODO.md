# To do

Ideas and small features agreed but not yet scheduled. Bugs and gaps found
while building live in AGENTS.md ("Still open"); the schedule is
`docs/ROADMAP.md`. Robert prioritises this list.

## Left and right Shift (Robert, 2026-10-12)

`keys.down()` cannot tell the two Shift keys apart. Add `lshift` /
`leftshift` and `rshift` / `rightshift`, and make `shift` mean either one
(left or right held). From playtest 7, the hodgepodge machine, where g
lowers and shift-g raises. Ctrl, Alt and Meta have the same two sides;
whether they get the same names is not decided.

## A skeleton sketch, and maybe events (Robert, 2026-10-12; to talk about)

Robert's sketches repeat one pattern: display setup, a global config, and a
`main()` that initialises and then loops -- update the sim, update the
display, check the inputs. `otto.coffee` (in CoffeeBEANS-content's
`sketches/`) is him noodling on abstracting that out into a skeleton
sketch. Not yet decided what to do with it.

One direction: an optional event-based model, as Pico-8 has (`_init`,
`_update`, `_draw`), where the runtime owns the loop and the sketch fills
in handlers. Very un-BASIC, but it would cut the boilerplate. To be talked
about before anything is built.

## An uncaught exception in main, as a bug report (Robert, 2026-10-12)

Replaces what a player sees today (since 2026-10-08: `sayProblem` in the
console with an offer of `/reload`). Robert's strategy, from the 10-06 brief:

- save a bug report, serialized as YAML, in a reports folder;
- tell the player clearly that it is not them, it is us;
- ask whether they want to file a bug report to help;
- if so, walk them through it (the 📣🐞 dialog's steps);
- at startup, delete all but the ten most recent reports.

To settle when it is planned: YAML is a new dependency (settings chose JSON
in K2 to avoid one); whether the console line and `/reload` stay alongside;
and redaction, which stays best effort with the report shown before saving.

## Line endings: always the platform's, with a setting (Robert, 2026-10-12)

From the 10-06 brief: "Default to converting all sketches to local system
line termination all the time, add persistent settings for changing the
defaults." Today (U2, 2026-10-06, also Robert's call) a save keeps the
file's own majority ending and only a file with none takes the platform's;
seeded examples take the platform's (2026-10-08). The new rule would
rewrite a LF sketch as CRLF on Windows at its next save. Confirm with
Robert that this replaces U2 before building.

## Eval after DevTools: least surprise (Robert, 2026-10-12; to talk about)

Built on 2026-10-08 as Robert asked then: the worker DevTools took is
enabled again at the next Eval while idle, and refused at once while busy
("pausing works again from the next Run, or an Eval once it has stopped").
Robert wants it to be unsurprising and does not yet see how. Details in
AGENTS.md, "Never re-attach".

## A last-known-good Windows build

CI keeps no builds today: packaged builds are still Phase 0 work, and an
uploaded workflow artifact expires (90 days by default). A tagged release
with its builds attached would keep one for good.
