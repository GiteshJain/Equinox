# Working on equinox.

Any Claude session that changes this repository starts here (decision #26). Gitesh reads on his phone and decides
everything; builds follow a spec from the Building chat in the Equinox project.

## Read first
1. `docs/architecture.md`: the map of the parts, how data moves, what runs when, where keys live and how to recover.
2. `docs/operating-manual.md`: the rules in force. Where it disagrees with anything else, including memory, it wins.
3. The spec you were given. `docs/decisions.md` and `docs/briefs/` say why things are the way they are.

## Rules for every build
- **A build never pushes to `main` and never merges.** Work on a new branch and open a pull request that says what
  changed, why and how it was tested. Gitesh approves by saying "merge" in the Building chat.
- **Run the checks before opening the pull request:** `bash tests/run_all.sh` (see `tests/README.md`). Never ask for a
  merge while one is red. Every bug fixed gets a test. If a change is meant to move a number, update the saved answers
  and say in the pull request which moved and why.
- **Database changes** are a new file in `database/migrations/`, with a description on every new table, view and
  function, its own grants for what needs to reach it (new tables in `public` get no access by default), and a test
  in `database/tests/` when they change how something behaves. The *Database rehearsal* check
  tries them on last night's backup and runs the tests there. Never change the live database: the Building chat
  applies a change only after "merge".
- **For database work, read `.claude/skills/supabase-postgres-best-practices/SKILL.md`** and the rule files it points
  to. Supabase's skills are in `.claude/skills/`; where they differ from these rules, these rules win
  (`.claude/skills/README.md`).
- **Update the docs in the same pull request** when how something works changes (the list is in the manual, §1).
- **Never commit keys, passwords or live game data.** Placeholders like `__CAPTURE_KEY__` mark where keys go. Small,
  dated samples in `tests/fixtures/` are the one exception.
- **The planner is the app in `app/planner/`** (React and TypeScript, served at `/planner/` since 14 Oct; each screen in
  `src/screens/`, its logic in a `model.ts` with unit tests beside it), and its rules are the planning library in
  `lib/rules/`. The old planner and its adapter went with the clean-up (build pull request 14).
- **Stay inside the spec.** If something outside it looks wrong, say so in the pull request instead of changing it.
- **Write plainly:** short sentences, the answer first, no jargon where a plain word works.
