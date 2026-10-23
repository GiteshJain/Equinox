# Building chat handover — 23 Oct 2026, evening

For the next Building chat. Start as the project instructions say (the manual, `docs/decisions.md`, this note and the
map), then the planner's state. The manual wins over this note. Previous note: `docs/handovers/2026-10-23-building.md`.

## Nothing is open in the repository
No open pull requests. Main is at `265b148` or later. Every migration on main is applied to live and recorded, up to
`20261023160000_rival_pairs_history`; each changed function was checked against `database/current/functions.sql`
(md5 of the definition, whitespace removed) after it was applied.

## Built and live today (23 Oct)
| PR | What | Manual |
|---|---|---|
| #92 | The fare ladder under launch: jumps to 80% then 60% (Ryanair 75/60), each held 2 weeks and judged on revenue a flight against the launch baseline; "cut or keep?" at the end; under launch it only climbs or holds | §5 |
| #93 | Rivals' fleets and aircraft on order read from each enterprise's overview page with every scan (capture 1.8, `gscan.py`); Competition's Order books; fleet column in the report's three competitors | §7 |
| #94 | Rivals' one-stop connections on our pairs, worked out at the scan's finish, detour ≤ 1.5×; shown beside direct, never counted | §3 |
| #95 | Each week's rivals by pair kept for good (`scan_pair_airlines`), so the route page's rival line survives the archive | §7 |

Briefs and specs: `docs/briefs/2026-10-23-*.md`, `docs/specs/2026-10-23-*.md`. Data-only today: to-do #166 closed
(replaced by #167); Ukraine's region set to Russia & Central Asia (the old planner's list); a manual backup run at
14:46 UTC.

## Waiting on Gitesh
- **Capture 1.8** on the iPhone (Userscripts app; he had the key there) and the Mac when he's back: until then scans
  skip the fleet pages. Same raw link as before.
- **#161, Saturday (Saturday review chat):** the fares script's first real run, safely. The ladder now lists 8 jumps,
  among them Delhi–JFK economy, which is being handed back (#165): skip it. KUL–Kochi and LGW–Oslo qualify only just
  (79–80% full).
- **#167** can be closed once he agrees: part (1) is built (#92); part (2) needed no build (a new flight on a flown route
  is filed at 100% and Apply fare plan's "set back" fixes it after the next capture; Ryanair's cargo by hand). The
  to-do's text was never reworded (the update was cancelled at the approval prompt).

## For the next Building chat
- **After tonight's capture:** check the scan's note names capture 1.8, the fleet pages read ("N fleet pages, M
  failed"), "connections: N rivals on M of our pairs", and that week 43's pairs were kept (or "pairs not kept").
- **#160, around 5 Nov:** fit the maintenance estimate per type and cabin to the game's figures.
- **Applying migrations from the chat:** `apply_migration` came back "cancelled" four times today (the approval never
  reached Gitesh); twice it worked. For big migrations (60 KB+), go straight to the SQL-editor fallback (manual §1): give
  him the raw link, then record the version in `supabase_migrations.schema_migrations` and check each function's md5
  against `functions.sql`. Never re-type a function by hand without that check: comments inside function bodies count.
- **Helpers' rehearsal lessons** (put them in every build brief): add new settings to `rules_input_test.sql`'s list;
  have `clean_up_test.sql` set aside exactly the new fields that reach `export_for_report('figures')`; generate
  `docs/data.md`, `functions.sql` and the planner's types from a database with every migration applied; a test fed by
  live data (the saves test picking "the first removed route") can break on data alone.
- **Checks:** `gh pr checks --watch` is blocked here (GraphQL); wait with the REST API for all three check runs
  (Checks, Database rehearsal, Cloudflare Pages) to complete, in one background wait. The rehearsal once hung to its
  30-minute limit; re-running it was enough.
- **Flagged, not decided** (carried): `game_balance` and `game_pnl` keep one row per UTC date; the stylesheet blocks
  each new-look step added could be folded together.
- **Office PC:** extensions may be blocked by IT; the capture runs from the iPhone instead. Don't suggest loading an
  unpacked extension to get round a company policy.
