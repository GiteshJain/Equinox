# Equinox project — instructions

## What this is
Gitesh runs **equinox.**, a group of six airlines in AirlineSim's Gander world: Pan Am, Kingfisher, Ryanair,
Virgin Atlantic, China Eastern and Malaysia Airlines. Their bases are in the operating manual, §2.

Systems:
- **Website and planner:** equinox-alliance.com (planner at /planner/, staff login), on Cloudflare Pages.
- **Database:** Supabase project `ulecwsyedvwcxgdzmhoq`. The nightly capture fills the game_* tables.
- **Code and documents:** GitHub repository `GiteshJain/Equinox`.

## The rulebook
- **The operating manual is the rulebook:** `docs/operating-manual.md` in the repository, copied in this project's
  files as `claude/operating-manual.md`. It holds the rules in force only. Follow it.
- **The manual wins** over memory and every other document. Memory holds how Gitesh likes to work, never game rules.
- **When a rule changes, in the same turn:** replace the old sentence in the manual (never add the new rule beside the
  old one), log the old wording and the reason in `docs/rule-history.md`, and update the project copies
  (`claude/operating-manual.md`, `claude/rule-history.md`). Rule changes Gitesh agrees in chat are committed directly.
- **The playbook** (`docs/playbook.md`, copy `claude/playbook.md`) gives the steps and points to the manual for every
  rule; it never restates them.
- Foundation decisions and their reasons are in `docs/decisions.md` (copy: `claude/decisions.md`).

## Starting a chat
- Read the operating manual, `docs/decisions.md` and the latest handover note for this kind of chat
  (`claude/handover-<kind>.md`, if there is one). The Building chat also reads the map (`claude/architecture.md`);
  any chat following a routine reads the playbook. Read `claude/rule-history.md` only when changing a rule.
- Check the planner's current state (aircraft waiting, open to-dos) before advising.
- In the first reply, tell Gitesh the name to give this chat: "<Kind> · <date>" (e.g. "Building · 23 Oct").
  Chats can't rename themselves.

## Handing over
- When a chat gets long, it writes a handover note (`docs/handovers/<date>-<kind>.md`, copy
  `claude/handover-<kind>.md`): what's open, what's waiting on Gitesh, what the next chat should do first.
- It then tells Gitesh to rename it "Archive · <Kind> · <date>" and to start the new chat with
  "Read the handover and continue".
