# equinox.

Everything behind the equinox. airline group in AirlineSim's Gander world: the public website and staff planner at
equinox-alliance.com, the database behind them, the nightly game capture, and the scripts that build reports and plans.

## Start here

| To understand | Read |
|---|---|
| How the pieces fit together, what runs when, where keys are kept, what to do when something breaks | [`docs/architecture.md`](docs/architecture.md) |
| How a Claude session works on this repository | [`CLAUDE.md`](CLAUDE.md) |
| Supabase's guidance for database work (and where our rules win) | [`.claude/skills/README.md`](.claude/skills/README.md) |
| What each planner screen shows and where its numbers come from | [`docs/planner-guide.md`](docs/planner-guide.md) |
| What each database table, view and function holds or does | [`docs/data.md`](docs/data.md) (generated from the database) |
| The rules everyone works by | [`docs/operating-manual.md`](docs/operating-manual.md) |
| Why things are the way they are | [`docs/decisions.md`](docs/decisions.md) and the briefs in [`docs/briefs/`](docs/briefs/) |
| How to run the report, newsletter, scanner and optimiser scripts | [`scripts/README.md`](scripts/README.md) |
| The automatic checks | [`tests/README.md`](tests/README.md) |

## Folders

| Folder | What's in it |
|---|---|
| `web/` | The public website and the planner (`web/planner/`), published by Cloudflare Pages from `main` |
| `functions/` | Cloudflare Pages Functions: `/api/game-schedule` (an airline's live schedule from the game) |
| `database/migrations/` | Every database change, in the order it was applied |
| `database/` | `rehearse.sh` tries new changes on a copy of last night's backup and checks the descriptions; `describe.sql` and `describe.py` make `docs/data.md` |
| `database/tests/` | Database tests, run by `rehearse.sh` on the copy of last night's backup and rolled back afterwards |
| `database/backup/` | `download.sh` gets last night's backup from Cloudflare R2 for the rehearsal (or for a new test sample); `config.sh` and `counts.sql` are copies of the backup job's settings and row counts |
| `database/current/` | The full definition of every database function and view, recovered on 8 Oct; a change to one updates it in the same pull request |
| `scripts/` | Weekly report, gander monthly, world scanner, schedule optimiser |
| `capture/` | The one-button capture userscript, the bookmark (keys are placeholders) and the salary userscript (one airline, by hand) |
| `tests/` | The automatic checks run on every pull request |
| `docs/` | The map, the planner guide, the table guide, the manual, the decisions and their briefs |

## How changes are made
Every code change is a pull request. The checks run on it, Cloudflare builds a preview (look-only), and database
changes are rehearsed on a copy of last night's backup, read from Cloudflare R2. Gitesh approves with "merge", and
merging publishes it. Every pull request that changes how something works updates these documents in the same pull
request. Data-only changes (plan cards, to-dos) go straight into the planner. Decisions #2, #8 and #9 have the detail.

**Never committed:** keys, passwords and live game data. Keys live in the database or as GitHub secrets;
placeholders like `__CAPTURE_KEY__` mark where they are filled in. The one exception is small, dated samples of game
data in `tests/fixtures/` for the automatic checks (decision #9), never the database, keys or sign-in data.

**Backups** live outside this repository. The private repository `equinox-backups` runs the nightly backup and puts
each copy in Cloudflare R2. Each night's copy is kept 30 days. The month's first is kept for good, in R2 and as a file
on a GitHub release in `equinox-backups` (decisions #6 and #16). Its README says how to restore.

Recovered into this repository on 8 Oct 2026 from the live site, the database and Netlify, after a workspace reset.
