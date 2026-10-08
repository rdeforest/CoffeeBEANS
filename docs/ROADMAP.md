# Roadmap: CoffeeBEANS on Steam

Set by Robert on 2026-10-04, written up by Claude the same day. This is the
schedule; NOTES.md is the design diary and AGENTS.md the working state.

**On hold since 2026-10-07.** Robert dropped the Steam target for a new
venture; this file is kept as the record of the plan, not as a schedule.
AGENTS.md, "Status", says where things stand.

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
| Licences | Code MIT, documentation CC BY-SA 4.0 (`LICENSE`, 2026-10-04). Anyone can build the code free; the Steam version is the one built and tested as a unit, with cloud saves and sharing code with friends. |
| Art | Owned by the artist, licensed to Robert for the game and its marketing. |
| Music | Robert's, under Creative Commons 4.0 -- BY or BY-SA, not yet chosen -- plus an explicit grant that streams and videos of the game may use it on any terms (Robert, 2026-10-04). |
| Mascot | An original character, designed with the artist. Her brief belongs in the content repository, below. |
| Proving a solution | Some challenges are proved by the player demonstrating the outcomes: the lander both lands *and* crashes, and an unpiloted lander crashes. |
| Repositories | Two, below. Both private until there are playtesters. The engine moves to the `thatsnice` GitHub org with a fresh history when it goes public (Robert, 2026-10-04). |
| Windows | Built and tested in CI, plus Windows playtesters. Robert does not run Windows. |
| Credit | Full credit to Claude and Anthropic, plus a doc for others on working this way. Steam's AI disclosure applies to shipped content players consume (story text, examples, help), not to coding assistance. |

## Repositories

Decided 2026-10-04, on Claude's suggestion: split by what may be public, not
by stage of development.

- **This repository, the engine:** the language, the runtime, the editor, the
  debugger, the sandbox, the tests. MIT. When it goes public it carries the
  issues and the CI -- standard GitHub runners are free for public
  repositories, and bigger (4 vCPU rather than 2).
- **A content repository, private:** the story, the challenge tree and its
  solutions, the mascot's brief, the art, the music. Spoilers, and work the
  artist licenses to Robert rather than to everyone. Steam builds need both,
  so they are made here or on Robert's machines; that is a few release builds
  a month, well inside the private minutes.

**Revised by Robert, 2026-10-05.** This repository's history already holds
the story and challenge solutions, so it stays private for good. Two new
repositories, created private that day in the `thatsnice` organization:

- **`thatsnice/CoffeeBEANS`** -- the engine's public home, empty for now. It
  hosts the issues (the in-app report points there) and goes public when
  play testers arrive. Its name is still open until then. The code moves in
  later, in pieces, as an edited history meant to be read: how the thing
  was built, step by step.
- **`thatsnice/CoffeeBEANS-content`** -- the story, the challenge tree and its
  solutions, the art, the music. Private. The story, the challenge ideas and
  `sketches/` moved there the same day.

Work continues in this repository until the move.

Open:

- **How the art is handled** -- Robert's todo, 2026-10-04: where the files
  live, what the artist's licence says, and the free-build question below,
  settled together.
- **What a free build from source contains.** Built from this repository
  alone it is the engine and the sandbox, without the story. If the free
  build is meant to be the whole game, the content has to go public at some
  point (at release, say), and the art can only go with it if the artist's
  licence allows. Robert's call.
- **How playtesters get builds.** Playtest builds contain the content, so a
  public repository's releases are the wrong place for them. Candidates:
  releases in the private content repository with the testers added as
  readers, or Steam's own playtest and beta-key tools (what those need
  before a store page exists: not checked). Feedback can still come in as
  issues on the public engine repository.
- **The artist's licence** has to cover the Steam build, playtest builds,
  the store page and marketing, and say whether the art may ever sit in a
  public repository.

## Phases

### 0. Foundations -- Mon 2026-10-05 to Fri 2026-12-11

- ~~`LICENSE` for the code; a credits and third-party notices file~~ --
  `LICENSE`, `LICENSE-MIT`, `LICENSE-CC-BY-SA`, `CREDITS.md`, 2026-10-04.
  Still to come: the content repository and its licences.
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

## Game content

Moved on 2026-10-05 to `thatsnice/CoffeeBEANS-content`, with the story and
Robert's sketches: `docs/challenges.md` there holds the challenge ideas.
New game design goes there, not here.

## Robert's own todo

- Fix the `thatsnice/music` repository's licence: it says CC BY-SA 2.0,
  while its own README describes attribution only. Move to 4.0 and add the
  streaming grant above.
- Talk to the candidate artists.

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
