# equinox.

Everything behind the equinox. airline group in AirlineSim (Gander world): the public website, the staff planner,
the database structure, the scripts that build reports and plans, and the nightly game capture.

| Folder | What's in it |
|---|---|
| `web/` | The public website and the planner (`web/planner/`), published by Cloudflare Pages from `main` |
| `functions/` | Cloudflare Pages Functions: `/api/game-schedule` (an airline's live schedule from the game) |
| `database/migrations/` | Every database change, in the order it was applied. `database/rehearse.sh` tries new ones on a copy of last night's backup (run on every pull request that changes the database) |
| `database/current/` | Today's definitions of all database functions and views (the source of truth until the rebuild) |
| `scripts/` | Weekly report, newsletter, world scanner, schedule optimiser |
| `capture/` | The one-button capture userscript and the bookmark (keys are placeholders) |
| `tests/` | The automatic checks run on every pull request (see `tests/README.md`) |
| `docs/` | Decisions, design and the operating manual |

**Never committed:** keys, passwords and live game data. Keys live in the database or as GitHub secrets;
placeholders like `__CAPTURE_KEY__` mark where they are filled in. The one exception is small, dated samples of game
data in `tests/fixtures/` for the automatic checks (decision #9), never the database, keys or sign-in data.

Recovered into this repository on 8 Oct 2026 from the live site, the database and Netlify, after a workspace reset.
