# equinox.

Everything behind the equinox. airline group in AirlineSim (Gander world): the public website, the staff planner,
the database structure, the scripts that build reports and plans, and the nightly game capture.

| Folder | What's in it |
|---|---|
| `web/` | The public website and the planner (`web/planner/`), as deployed today |
| `database/migrations/` | Every database change, in the order it was applied |
| `database/current/` | Today's definitions of all database functions and views (the source of truth until the rebuild) |
| `scripts/` | Weekly report, newsletter, world scanner, schedule optimiser |
| `capture/` | The one-button capture userscript and the bookmark (keys are placeholders) |
| `tests/` | Browser tests for the planner |
| `docs/` | Decisions, design and the operating manual |

**Never committed:** keys, passwords and live game data. Keys live in the database or as GitHub secrets;
placeholders like `__CAPTURE_KEY__` mark where they are filled in.

Recovered into this repository on 8 Oct 2026 from the live site, the database and Netlify, after a workspace reset.
