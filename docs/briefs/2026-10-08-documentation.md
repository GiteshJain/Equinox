# Documentation — 8 Oct 2026 (decision #10)

**Decision:** what gets written down about how equinox. works, beyond the rules (the manual) and the decisions, and how
it stays up to date.
**Recommendation:** B. Four short documents now, kept current by rule and by a check:
1. A one-page map of how the pieces fit together.
2. A one-line description on every database table, view and function, with a generated table guide.
3. How to run each script.
4. A refreshed README.

It costs $0 and about half a day. It matters most for #26: every new Claude Code session starts with no memory.

*Columns adapted for a non-game decision: what you get instead of growth, real money instead of game profit.*

| Option | What you get | Cost | Opportunity cost | Risk | Easy to undo? |
|---|---|---|---|---|---|
| A. As now | The rules, the decisions, the README's folder list, the tests' and the backups' notes | $0 | None | Every new chat or session rediscovers how things fit, slowly and sometimes wrongly | — |
| **B. Core docs now, kept current** | **A one-page map, every table, view and function described (in the database and in a generated guide), how to run each script, a README front door; a check fails if a new table has no description** | **$0** | **About half a day** | **Small: some descriptions change at the rebuild (#13)** | **Yes** |
| C. Map now, the rest at the rebuild | The map and the README now; table and script docs during #13 to #22 | $0 | Less work now | The rebuild's first sessions start without a table guide, and the weekly-report scripts stay undocumented until #22 | Yes |
| D. Everything in depth now | Every screen, calculation and function explained line by line | $0 | Several days, much of it on code the rebuild replaces | Effort wasted, and long documents go stale | Yes |

## Background
- **What exists** (8 Oct):
  - The README, a 21-line folder list.
  - The operating manual (rules), the decisions log and 4 briefs.
  - `tests/README.md`, and the restore steps in `equinox-backups`.
- **What's missing:**
  - Nothing explains how the parts connect: the game, the capture, the database, the planner, the website, the
    backups and the checks.
  - Nothing says what each table holds, who writes it or who reads it.
  - Nothing says how to run the nine scripts behind the weekly report, gander monthly, the world scanner and the
    schedule optimiser.
- **The database today** (live check, 8 Oct): 22 tables, 2 views and 23 functions, none with a description.
  - The capture's tables: `game_*`.
  - The planner's own storage: `planner_state`, `planner_loads`, `planner_data`, `planner_meta`, `planner_scripts`,
    `planner_users`.
  - The website: `site_content`, `site_posts`, `site_reports`.
  - The backups' record: `backup_runs`.
  - Three key tables that never leave the database.
- **The cost of missing docs, from this chat today:** finding our six airlines' game IDs, which tables the planner
  reads, and how it loads its route data took about a dozen lookups in the database and the code. Every fresh chat or
  session repeats that.
- **What the rebuild changes:** #13 mainly replaces the planner's own storage (the single `planner_state` row and its
  neighbours). The capture, website, report and backup tables carry on, so most descriptions written now stay true.
- **Claude Code (#26):** a `CLAUDE.md` file in the repository is read at the start of every session. It can point to
  these documents, so each session starts with the map instead of rediscovering it.
- **What B would write:**
  1. `docs/architecture.md`: one page with a diagram. It shows where things live (Cloudflare, Supabase, GitHub), what
     runs when (the evening capture, the 07:17 UTC backup, checks on every pull request), where keys are kept (names
     only) and how to recover from each kind of failure. It's also copied into the project files so every chat sees
     it.
  2. Descriptions on every table, view and function, saved in the database itself so they show in Supabase's table
     editor and travel with the backups. `docs/data.md` is generated from them: each table's columns, what writes it
     and which screens read it.
  3. `scripts/README.md`: for each script, what it's for, what it needs, how to run it and what it produces.
  4. The README as a front door, linking to all of the above.
  5. **Kept current:** every pull request that changes how something works updates the docs in the same pull request.
     The database rehearsal (#8) also fails if a new table, view or function has no description, or if `docs/data.md`
     no longer matches the database.

## Scenarios and the risk of waiting
- **Next few weeks:** under A, each of the other chats keeps rediscovering details, such as which table holds the bank
  statement or how to rerun the weekly report. Under B, they read the map.
- **The rebuild (#13 onwards):** under B, the table guide is the starting point for redesigning the data model, and
  each change updates it in the same pull request. Under C, the first rebuild sessions write the guide while also
  redesigning, which is harder.
- **Waiting:** costs nothing in money, but every new session pays the rediscovery cost. Writing it now, while
  everything is fresh from today's work, is cheaper than later.

## What would change the recommendation
- **If #26 ends with building staying in this chat:** C becomes reasonable, because this chat carries more context
  than a fresh session.
- **If you'd also like a plain-language guide for yourself** (what each planner screen shows and where its numbers
  come from): add it to B as a fifth document, about another hour.

## Outcome
Open: waiting for Gitesh's decision.
