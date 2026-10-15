# How we play: the equinox. playbook

The operating manual's rules, in the order we use them. **The manual wins** wherever the two differ, and this file is
then corrected. Written 15 Oct 2026, after the planner rebuild and Step 5's decisions.

## 1. The game we're playing
- **Six airlines, one group.** Each airline owns its home region, and one airline owns each intercontinental flow.
  **No two of our airlines fly the same city pair**, and a route's owner never changes (manual §2).
- **The goal:** in time, fly every route a real airline flies from each of our hubs and focus cities, at the group's own
  pace. **Growth matters as much as profit:** every batch of aircraft opens new markets, not only more flights on proven
  routes.
- **Fleet:** the A320 family (A320neo, A321neo, A321XLR) and the E195-E2, with the A350 only where range demands it.
  Short and medium haul first; long haul later.

| Airline | Bases | How it grows |
|---|---|---|
| Pan Am | JFK; focus ORD, SFO, SEA | JFK to 750 weekly departures first. Dallas, then LAX, on hold until then |
| Kingfisher | Delhi; focus Hyderabad, Bengaluru, Chennai, Kolkata (on hold) | Take all of India. Mumbai next. The two Delhi–JFK A350s stay |
| Ryanair | Five equal focus cities: CDG, Amsterdam, Barcelona; Milan and Munich next | Point to point inside the EU zone. A321neo and E195 only. Exempt from hubs first |
| Virgin Atlantic | Gatwick, Manchester; focus Edinburgh | No JFK or Delhi. New London routes go to Gatwick before Heathrow |
| China Eastern | Shanghai PVG, Xi'an, Kunming; focus Daxing, Shenzhen | China and China–Europe/India flows |
| Malaysia | KUL | KUL as a world transfer hub: the Asian feeder network before any long haul |

## 2. The growth loop: from order to flying
1. **Can we afford it?** Planner → Review → *Cash, next 14 days*. An order is safe when **0.5M stays in hand at the
   lowest point**, counting the order's own lease. Planned refits aren't in the forecast.
2. **What and where?** Each airline rotates big market → more frequency → smaller feeders. **Hubs first:** every new
   aircraft goes to the main hub until it reaches 750 weekly departures. Other bases get one only for a contested
   route (a rival with over 250 departures a week at that base, or over 2 a day on the route). Ryanair is exempt.
3. **Gitesh orders in the game and says so;** Claude logs it. An order is just the aircraft: routes and cabin are
   decided when it arrives.
4. **When it arrives:** Claude runs the airline's briefing (`brief.py <airline>`) and gives the options: loads, money,
   network and competition. We pick the routes together.
5. **Claude writes the plan cards:**
   - connections at both ends (at least the airport's minimum connection time, and departures within 8 hours);
   - the aircraft used as much as possible;
   - turns with a 10-minute margin;
   - maintenance at 100% or more (aim for 105%);
   - a second daily at least 3 hours from the first;
   - the service code by distance;
   - everything flies direct.
6. **Cabin:** the market's default (a refit is about 0.2M). **Fare:** launch at 100% (Ryanair 85%, economy only).
7. **Gitesh schedules it in the game and presses File in Tails.** The planner checks each card against the game. The
   next evening's capture shows it flying. There are no one-week checks any more.

## 3. Every day
| When | Who | What |
|---|---|---|
| Evening | Gitesh | **Capture all airlines.** Every airline should end "all good". If a page is short or broken, capture that airline again the same evening. **A missed evening loses those loads for good** |
| After the capture | Gitesh | A glance at Home's *Needs attention* and Check's Systems board: all green |
| When you choose | Gitesh | Salaries, by hand, one airline at a time ("Salaries: this airline": 10% above the country average) |
| Overnight | Automatic | The backup (restored and checked), the 10:00 UTC snapshot fallback, the 10:20 clean-ups and the monthly archive. Home and the Systems board say if one fails |

Anything Gitesh needs to check or do goes on the planner's **To-do board**.

## 4. Every Saturday, in this order
1. **World scan** (`gscan.py`, 5 to 10 minutes), so everything after reads this week's rivals.
2. **Weekly report:** a PDF for a CEO. It covers competition by market, risks, opportunities, our plan and progress,
   route profit, growth signals and fare-plan results.
3. **Connection audit** across all hubs: valid connections, near misses, and retimes of 10 minutes or less.
4. **Newsroom:** one roundup post of the week's new routes.
5. **The weekly review together:**
   - the fare plan's tests;
   - what each airline can order (the cash forecast);
   - any trigger that needs a brief (Supabase's plan, for example);
   - the open to-dos.

## 5. First Saturday of the month (as well as the above)
- **Monthly report**, published to the investor library.
- **gander monthly**, covering the whole world (marked as made by AI).
- **Strategy session:** bases, holds, each airline's next step.
- **Supabase's usage page:** egress against 4 GB a month, and the website's calls a day against 1,000. Everything else
  is on the Systems board.
- **The archive:** by the 3rd, the Systems board shows the month archived. The first one is due on 1 December.

## 6. Keep in mind
- **Ownership:**
  - US/UK–India → Kingfisher.
  - US–UK, Europe or China → Pan Am.
  - UK–Europe, China or Malaysia → Virgin.
  - Europe or India–China → China Eastern.
  - Malaysia → Malaysia.
  - Within one airline, the first-listed hub.
- **Ryanair** stays inside the EU zone (EU-27, the UK, Norway, Switzerland, Iceland) and has no interlines in Europe.
- **Interline:**
  - Our airlines always interline with each other.
  - Outside partners: the country's major airline, at major airports, where there's a real domestic market or a
    gateway.
  - Pan Am: none in Canada, Mexico, the Caribbean or Central America.
  - Gulf hub carriers are rivals: decline them.
- **Fares** change only as occasional tests in the fare plan, reviewed on Saturday. A weak route is cut rather than
  launched cheap.
- **Night slots are fine:** the game's demand ignores the time of day.
- **Supabase stays free.** A trigger (350 MB, 4 GB egress, a pause, a paid-only need) means a brief, not an upgrade.
- **How we work:**
  - one item at a time, decided by Gitesh;
  - code goes in a pull request, and goes live on "merge";
  - Claude says first when something takes over 5 minutes;
  - anything that removes something from the database is run by Gitesh in the SQL editor.
