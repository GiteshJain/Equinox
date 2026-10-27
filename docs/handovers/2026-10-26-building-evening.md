# Building chat handover — 26 Oct 2026, evening

For the next Building chat. Start as the project instructions say (the manual, `docs/decisions.md`, this note and the
map), then the planner's state. The manual wins over this note. Previous note: `docs/handovers/2026-10-26-building.md`.

## Nothing is open in the repository
No open pull requests. Every migration on main is applied to live and recorded, up to `20261027030000`; each changed
function was checked against `database/current/functions.sql` (md5 of the definition, whitespace removed). Every
project copy (`claude/*.md`) matches the repository.

## Built and live, 26 Oct afternoon and evening
| PR | What | Manual |
|---|---|---|
| #108 | The fare ladder on each airline's Performance page; the group page has links only (option E of `docs/briefs/2026-10-26-fare-ladder-timeouts.md`: six ladders at once timed out) | — |
| #109 | Fares script 1.2: reads the game's real answer (airport code in its own link inside the brackets); first real run done | §5 |
| #110 | The fare ladder holds a direction the Saturday after it steps up (`fare_ladder_up_hold_weeks` 1) | §5 |
| #111 | Database descriptions tidied after 20–26 Oct | — |
| #112 | The route page shows the cabin by distance; `route_story()` has no cabin field or route-cabin events | §5 |
| #113 | The one-airline capture bookmark retired | — |
| #114 | The fare ladder under launch judged by loads (no revenue test, no revert; at 60% still not filling: cut or keep?) | §5 |

#110, #112 and #114 went through the SQL editor (40–57 KB); #111 from the chat.

## Rule changes agreed tonight (all in the manual and rule-history)
- §5 under launch judged by loads (Gitesh's own proposal; brief `docs/briefs/2026-10-26-under-launch-by-loads.md`).
- §3 Kingfisher's Mumbai exception applied by the Scheduling chat: `competition()` still marks Mumbai's openings
  "hubs first"; for the eight deposit aircraft the Scheduling chat ranks them itself (option B, no build).
- §5 a frequency's Price % is a record only (option C).
- §9 the fares script's permission is text only (no `world_rules` row); §3 the delivery intervals are information only;
  §2 no Subang station; the A350 15,000 km cut-over stays in `competition()`'s code; unused `order_cabin()` and the
  one-week check columns kept (described as unused).

## The document audit (26 Oct evening)
Three read-only helpers checked every document against the manual, the code and live; about 50 factual errors were
fixed (commit `6e7762c`) and 12 rulings taken one at a time (above). Memory holds no game rules. Two account-level memory
notes outside the project mention Netlify, a private repository and the old Review/Check tabs: history, not rules, and
not writable from the project.

## Waiting on Gitesh
Nothing in this chat. The 24 Oct weekly report (owed or folded into 31 Oct?) is the Saturday review chat's question.

## For the next Building chat
- **Saturday 31 Oct:** the first review with the per-direction ladder, the hold after a step up and the loads rule.
  Watch the airline pages' fare ladders load (one call each) and Apply fare plan.
- **#160, around 5 Nov:** fit the maintenance estimate per type and cabin to the game's figures.
- **Open idea, not raised as a decision:** removing the fare ladder's copy buttons (Gitesh said "sure" to listing it).
- **Working copies:** helpers use `/home/claude/equinox`; the Building chat's own commits go through a separate worktree
  (`/home/claude/eq-main`), so the two never share a branch (on 26 Oct a commit landed on a helper's branch).
- **Big migrations:** over about 15 KB, Gitesh pastes the raw file at the merge commit into the SQL editor; check by md5
  afterwards and insert the `schema_migrations` row.
- Helpers' lessons from the earlier note still apply; add: check the latest migration timestamp just before naming a
  file (two clashes on 26 Oct), and keep branches rebased on main.
