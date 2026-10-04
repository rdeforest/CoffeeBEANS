# Roadmap: CoffeeBEANS on Steam

Set by Robert on 2026-10-04, written up by Claude the same day. This is the
schedule; NOTES.md is the design diary and AGENTS.md the working state.

## The goal

CoffeeBEANS becomes a game: a story about programming in the late '80s and
early '90s, with a conspiracy that only *this* player can unravel -- by
simulating gravity, growing L-systems, and the other things the sandbox
already does. It plays like Turing Complete's tree of challenges: features
unlock as challenges are solved, and a sandbox mode has everything open.

**Completely done by Friday 2027-07-30.** Everything after that date is slack
for the slips game schedules always have, and other people's schedules
compound. The public target is **Steam Next Fest, October 2027**; the game
releases after the fest ends, as Next Fest requires.

## Decided

| | |
|---|---|
| Platform | Electron. Steam's pain points get handled as they come up. |
| Code licence | MIT. Anyone can build it free; the Steam version is the one built and tested as a unit, with cloud saves and sharing code with friends. |
| Art | Owned by the artist, licensed to Robert for the game and its marketing. |
| Music | Robert's, under a Creative Commons licence (which one: TBD). |
| Mascot | *Inspired by* Agent Calico and designed fresh with the artist to be legally distinct from it: that character was created by someone else on company time, so nothing is taken from earlier Agent Calico material. |
| Proving a solution | Some challenges are proved by the player demonstrating the outcomes: the lander both lands *and* crashes, and an unpiloted lander crashes. |
| Windows | Built and tested in CI, plus Windows playtesters. Robert does not run Windows. |
| Credit | Full credit to Claude and Anthropic, plus a doc for others on working this way. Steam's AI disclosure applies to shipped content players consume (story text, examples, help), not to coding assistance. |

## Phases

### 0. Foundations -- Mon 2026-10-05 to Fri 2026-12-11

- `LICENSE` for the code; a credits and third-party notices file
  (Electron/Chromium, CoffeeScript, CodeMirror, font8x8); a home for asset licences.
- Packaged builds for Windows, macOS and Linux from GitHub Actions, and the
  test suite running on all three. The repo is private, so minutes count:
  Linux and Windows on every push, macOS on release builds only.
- Engine pieces the game needs: seeded `rnd` (NOTES.md, Seeded randomness),
  feature gating by progress, a sandbox mode with gating off, and a way for
  the game to notice a demonstrated outcome.
- Design doc v1: the story outline, the challenge tree, the mascot brief.
- Start looking for an artist.

**Milestone:** all three platforms build and pass in CI; design doc v1.

*Buffer: 2026-12-14 to 2027-01-08 (holidays and slip).*

### 1. Vertical slice -- Mon 2027-01-11 to Fri 2027-04-02

- The tutorial with the mascot (placeholder art is fine), the first branch
  of the challenge tree (six to eight challenges), one story beat, gating
  working, the sandbox.
- Artist contracted by the end of January; mascot design through March.
- Steamworks account, Steam Direct fee, tax and bank details.
- First playtests in March, Windows testers included.

**Milestone:** a slice a stranger can play without Robert in the room.

*Buffer: 2027-04-05 to 2027-04-23.*

### 2. Production -- Mon 2027-04-26 to Fri 2027-07-02

- The full challenge tree and the full story; art and music in.
- **Coming Soon page live by Fri 2027-05-28**, which means submitting it for
  review by Fri 2027-05-14 (Valve asks for at least seven business days).
  Wishlists are what Next Fest amplifies, so earlier is better. Needs
  capsule art and screenshots from the artist by then.
- Steam Cloud for sketches and progress; Steam Workshop for sharing code.
- Second round of playtests in June.

### 3. Finish -- Mon 2027-07-05 to Fri 2027-07-30

- Bug fixing and polish; the trailer; the demo build cut and frozen.

**Milestone: done.**

### After done: slack, then the fest

- From Mon 2027-08-02, slack. If nothing slipped: press, streams, demo polish.
- Next Fest registration is expected around the start of September 2027.
  Valve has not announced the October 2027 dates; check when it does.
- Demo through build review a few weeks before the fest.
- Next Fest, mid-to-late October 2027 (expected); release after it ends.

## Game content (todo)

Ideas for the challenge tree, not yet placed in it.

- **Pseudo-random numbers, as a hack** (Robert, 2026-10-04). Before the game
  gives the player `randomize` and `rnd`, they implement a simple
  pseudo-random number generator themselves and use it to decode a message
  -- exploiting the fact that a "random" stream is perfectly predictable to
  anyone who knows the generator and the seed. A good first lesson for a
  novice, it fits the hacking side of the story, and it needs no graphics.
  Solving it unlocks the built-in generator (NOTES.md, Seeded randomness).

## The dial

When the schedule slips, the number of challenges and the length of the story
give, not the done date. The demo's scope is fixed first, so the fest is safe
whatever happens to the full game.

## Risks

- **The artist.** Their availability sets the store page date. Find them early.
- **Windows-only bugs**, found late. CI catches crashes; only testers catch feel.
- **Steam and Electron**: the overlay, the Steamworks binding, Linux sandboxing
  inside Steam's runtime. Known territory, not yet walked.
- **Scope**: story and challenges are the easiest things to keep adding to.
- **Valve's dates** for October 2027 are not out yet.
