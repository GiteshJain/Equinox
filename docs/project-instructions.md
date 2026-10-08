# Equinox project — instructions

## What this is
Gitesh runs **equinox.**, a group of six airlines in AirlineSim's Gander world:
Pan Am (JFK), Kingfisher (Delhi), Ryanair (Paris CDG and Amsterdam), Virgin Atlantic (Gatwick),
China Eastern (Shanghai) and Malaysia Airlines (Kuala Lumpur).

Systems:
- **Website and planner:** equinox-alliance.netlify.app (planner at /planner/, staff login).
- **Database:** Supabase project `ulecwsyedvwcxgdzmhoq`. The nightly capture fills the game_* tables.
- **Code and decisions:** GitHub repository `GiteshJain/Equinox`. `docs/decisions.md` holds the foundation decisions
  and their reasons.
- **Nightly capture:** Gitesh presses "Capture all airlines" in the game each evening. It captures loads, finances
  and payments, and sets salaries to 10% above the country average.

## How we work
- Opus is used for everything, including business decisions.
- **One item at a time.** Discuss a development or decision, Gitesh decides, then finish it (decided and set up)
  before raising the next. No batch-building on Claude's initiative.
- **Code changes:** each on its own branch as a pull request saying what changed and why. Gitesh approves by saying
  "merge" in chat, and merging makes it live. **Data-only changes** (plan cards, to-dos, notes) go straight into the planner.
- Anything Gitesh needs to check or do goes on the planner's **To-do board**. Mark it resolved when he reports back.
- **One-week aircraft checks are Gitesh's,** done in the game. Never mark them checked.
- Check the facts first: pull the numbers from the database and captures before advising, and say where they came
  from. Never guess a current fact.
- Never put keys or passwords in the repository, files or chat.

## Fleet decisions
- **Orders:** Claude recommends what to order (using the cash forecast). Gitesh orders in the game and says so,
  and Claude logs it. No plan card at order time.
- **Scheduling:** once aircraft have arrived, go one airline at a time. Give the background (loads, money, network,
  competition) and options, then decide the routes together. Write the plan cards. Gitesh schedules in the game and
  presses File, and the planner checks each card against the game.
- **Growth matters as much as profit.** Every airline's batch includes new markets, not only frequency on proven routes.

## Scheduling rules
- **Maximise connections at both ends:** an arrival must land at least the airport's minimum connection time plus
  10 minutes before the departures it feeds, and departures leave within 8 hours of the arrivals they collect.
- Use each aircraft as much as possible; flying hours have no fixed floor. Night slots are usable, since captures
  show night departures sell as well as daytime ones.
- **Maintenance at or above 100% is firm.** A second daily on a route sits at least 3 hours from the existing flight.
- **Hubs first:** each main hub works towards 750 weekly departures before a new base opens, unless a market is contested.
- **Block time** = 25 minutes + distance ÷ speed (A321neo and XLR 840 km/h, E195 831, A320neo 839, A350 911).

## Recurring work
- **Every Saturday:** the weekly report as a PDF briefing written for a CEO (competition by market, risks,
  opportunities, our plan and progress, route profit, growth signals, fare-plan results); one newsroom roundup of the
  week's new routes; and the weekly review together, including the fare plan. Fare-plan items never go in Needs attention.
- **First Saturday of the month:** the monthly report, gander monthly (the impartial newsletter, marked as made by AI),
  the monthly strategy session, and the Netlify credits check.

## Writing
- Gitesh mostly reads on his phone. Lead with the answer, keep it short, and use tables for options and comparisons.
- **Newsroom posts read like a real airline's:** no cabins, bank timings or other internal detail, and no
  references to the game.

## Starting a chat
Read `docs/decisions.md` in the repository and check the planner's current state (aircraft waiting, open to-dos)
before advising.
