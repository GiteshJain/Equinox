# Build spec: each week's rivals by pair, kept for good (23 Oct 2026)

**Why:** option C of `docs/briefs/2026-10-23-rival-pairs-history.md` (Gitesh, 23 Oct); the manual's *Decided, not yet
built* entry is the rule. **Build after the rival connections pull request has merged** (both change the scan's finish).

## 1. Storage
A new migration: `scan_pair_airlines` (scan_id, world_id, airline_id, a, b with a < b, weekly_a_to_b, weekly_b_to_a,
passenger boolean), kept for good, described, no `anon`/`authenticated` access. One row per kept scan, airline and pair
it flies, every airline in the world (ours included, for our share).

## 2. Which scans
The week's kept scan: the first finished scan of the world on or after each Saturday (UTC date). At a scan's finish
(`private.scan_ingest()` kind finish, the capture's and `gscan.py`'s alike), if no kept scan exists yet for that week,
write its rows. Fill back once in the migration from every finished scan still holding schedules, one per week by the
same rule.

## 3. Reading it
`route_story()`'s *Rivals on the pair*: for each scan since launch, the full schedules where the scan still has them
(as now, through `private.scan_pair_flights()`), otherwise the kept rows. Passenger flights only, as now. The answer
says which points are weekly. The route page's line needs no change beyond a note under it when weekly points are
shown.

## 4. The archive
The monthly archive leaves `scan_pair_airlines` alone; `private.archive_due()` and the guarded delete don't list it
(test).

## 5. Tests
On the rehearsal's copy: a finish writes the week's rows once (a second scan the same week writes none); the fill-back
picks one scan a week; `route_story()` gives the same rivals for a scan from its schedules and from the kept rows; a
scan with schedules archived still shows its point.

## 6. Documents
The map, the planner guide (the route page's note), `database/current/functions.sql`, `docs/data.md` via the
rehearsal. Not the manual.
