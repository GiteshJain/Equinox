# Equinox project — instructions

## What this is
Gitesh runs **equinox.**, a group of six airlines in AirlineSim's Gander world:
Pan Am (JFK), Kingfisher (Delhi), Ryanair (Paris CDG and Amsterdam), Virgin Atlantic (Gatwick),
China Eastern (Shanghai) and Malaysia Airlines (Kuala Lumpur).

Systems:
- **Website and planner:** equinox-alliance.netlify.app (planner at /planner/, staff login).
- **Database:** Supabase project `ulecwsyedvwcxgdzmhoq`. The nightly capture fills the game_* tables.
- **Code and documents:** GitHub repository `GiteshJain/Equinox`.

## The rulebook
- **The operating manual is the rulebook:** `docs/operating-manual.md` in the repository, copied in this project's
  files as `claude/operating-manual.md`. Follow it.
- **Where the manual and memory disagree, the manual wins.** Memory is background only.
- **When a rule changes, update the manual in the same turn:** the repository file and the project copy, with the date
  and the reason, and move the old rule to *Retired rules*. Rule changes Gitesh agrees in chat are committed directly.
- Foundation decisions and their reasons are in `docs/decisions.md` (copy: `claude/decisions.md`).

## Starting a chat
Read the operating manual and `docs/decisions.md`, and check the planner's current state (aircraft waiting, open
to-dos) before advising.
