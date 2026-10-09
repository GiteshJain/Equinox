# Skills for sessions working on this repository

Every Claude session or helper that works on this repository picks these up (decision #26). They're instructions
only, with no scripts.

| Skill | What it covers | Source |
|---|---|---|
| `supabase/` | Supabase in general: access rules (RLS), keys, the Data API, debugging, security traps | `supabase/agent-skills` 0.1.2 |
| `supabase-postgres-best-practices/` | Postgres table design, migrations, indexes, access rules, locking, query speed | `supabase/agent-skills` 1.1.1 |

Copied unchanged from https://github.com/supabase/agent-skills at commit `c9be0e9` (2 Oct 2026), under the MIT licence
(`LICENSE-supabase-agent-skills`). Added 9 Oct 2026 at Gitesh's request. To update: copy the two folders again from a
newer commit, in a pull request that says what changed.

## Where they differ from our rules, ours win
`CLAUDE.md` and `docs/operating-manual.md` come first. In particular:
- **The `supabase` skill's "Making and Committing Schema Changes"** says to try schema changes directly on the database
  with `execute_sql`, then generate a migration. That's written for a local database. Here, the only database within
  reach is the live one, so **never change the live database to try something out**. Write a new file in
  `database/migrations/`, try it on a scratch Postgres in the workspace if needed, and let the *Database rehearsal*
  run it on last night's backup. The Building chat applies it to live after "merge" (`CLAUDE.md`).
- **"Supabase CLI" and "MCP server":** we don't use the Supabase CLI against live, and Supabase is reached through
  the Supabase connector. Skip their setup and login steps.
- **"Skill Feedback":** don't file issues on Supabase's repository from here without Gitesh asking.
