# Build spec: new frequencies and the fare ladder (21 Oct 2026)

**Why:** Gitesh, 21 Oct. "Only new routes until 31 Oct" may be dropped soon, and then routes will gain frequencies.
Manual §5 now says:
- a route that gained a frequency in the last 7 days **holds** on the fare ladder;
- every plan card shows the fare level of each route it flies.

Gitesh thinks the game prices a new flight number at the default price, not at its route's level. The result page of
Ticket price adjustment lists "Changed Airport Pairs", which suggests prices belong to the pair. Part 3 settles it from
the captures and fixes it either way.

Build this **after** the fares userscript (`docs/specs/2026-10-21-fares-userscript.md`) is merged, because part 3
feeds it.

## 1. A new frequency holds the route for a week
- **`private.fig_fare_ladder()`** (new migration, `CREATE OR REPLACE`, same arguments): a route whose newest live
  rotation launched within `fare_ladder_capacity_hold_days` (a new setting, 7, described), while its first rotation is
  older than that, **holds**.
  - Its reason: "a flight added on 2 Nov: judged at its new size from 9 Nov".
  - The order of the checks: after `planned`, `young` and `few`, before the sold-out share.
  - Launch days come from `private.fig_freqs()` (`launched_on`), as the route's age does.
  - A frequency taken away isn't tracked (its rotation is deleted). Say so in the description; it's a later item if it
    matters.
- **Database test** (`fare_ladder_test.sql`):
  - a route sold out 14 of 14 with a rotation launched 3 days ago holds, with that reason;
  - the same route after 8 days moves;
  - a route whose only rotation is new is still "new route".

## 2. The plan card shows each route's fare level
- **On the card's legs, per route the card flies,** its level per cabin:
  - "economy +10%, business +5% of the default price", from `fare_ladder()`'s routes (the level, or this week's new
    level once it's on the fare plan);
  - **launch** (+0%, Ryanair −15%) for a route the airline doesn't fly yet.
- **Where it shows:** Tails → Deliveries (each leg's route, once per route), the card check's output (the library's
  `check a plan card`, so the Scheduling chat sees it), and the airline briefing's plan cards.
- **Where the planner gets it:** read `fare_ladder()` for the card's airline. Nothing new is stored on the card.
- **The playbook** (setting up a new aircraft in the game): "set each new flight's fare to its route's level from the
  card (Ticket price adjustment, default price), or leave it to the fares userscript's next run" (part 3).

## 3. A route whose fare doesn't match its level gets set back
- **In `private.fig_fare_ladder()`:** a route and cabin with `index_matches` false gets a **set back** change.
  - Conditions: it's not planned this week; its latest captured day is after its newest rotation launched; and the
    route isn't new.
  - The change: one action each way at its level (route by route, both classes together when both are off by the same
    level), marked `fix: true`, with the reason "captured fare at 100%, level 110%".
  - It is not a ladder move: `move` stays as it is.
  - These go first in `actions`, ahead of the week's moves.
- **Known on 21 Oct (Gitesh):** every route was then at its launch level, legacy airlines 100% of the default price
  and Ryanair 85%, including Ryanair's four early cuts. So each route's baseline fare is its captured fare on 21 Oct
  (the latest captured day on or before it), at the launch level. A route launched later starts at launch level too,
  so its baseline is its first captured fare. A new flight on an existing route launches at the route's level (manual
  §5).
- **Compare each flight, not the day's average:** a route is off its level when any flight of its latest captured day
  sold at a fare more than 1 point off its level (one cheap flight among three would barely move an average).
- **The fare index has to be right first.** Today it's "latest fare ÷ first fare × launch level", which is wrong for
  Ryanair's four early cuts (BRI–CDG, CDG–SOF, CDG–SPU, CDG–VLC: index about 72, level 85).
  - Fix: take the first fare at the launch level only from days after any cut, i.e. the first fare is the earliest day
    whose fare is within 1% of the later run of fares. Or more simply, read the level from the latest fare against the
    route's fare at the latest level the fare plan recorded.
  - Choose the simplest rule that gives index = level for every route on today's data, and say which.
  - Show the counts of mismatches before and after on the rehearsal's copy.
- **`capture_fare_actions()`** (from the fares userscript) also returns the `fix` actions, so the userscript sets them
  back on its next run. They need no fare plan row: the capture ticks nothing off, and the index matching again is the
  proof.
- **Performance's fare ladder** lists the set-back changes first, in their own short list ("3 routes off their level").
- **Tests:**
  - database: a route whose latest captured fare is at 100% while its level is 110% gets two `fix` actions at +10%;
    one planned this week gets none; a new route gets none;
  - the userscript test: a `fix` action builds the same GET as any other.

## Docs
- Manual §5: name the setting; when this merges, take it out of "Decided, not yet built".
- `docs/planner-guide.md`: the card's fares, the set-back list.
- `docs/architecture.md`: `fare_ladder()`'s description.
- `docs/playbook.md`: the setup step above.
- `tests/README.md`.

## Not in this build
- Tracking a removed frequency.
- Rival pauses (competition analysis).
