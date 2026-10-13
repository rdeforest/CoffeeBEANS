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
