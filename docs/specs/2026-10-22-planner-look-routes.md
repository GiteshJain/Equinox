# The planner's new look, step 3: Routes (22 Oct 2026)

Brief `docs/briefs/2026-10-22-planner-design.md`, option B in steps (Gitesh, 22 Oct). Steps 1 (foundation, #71) and 2
(Today, #72) are live. This step rebuilds the Routes screen's layout to the approved mockup (the "equinox. planner
redesign" canvas, artboard Routes). Everything Routes does today stays: picking a route, its detail, adding, editing
and removing frequencies, adding a route, removing unflown routes, the filters and sorts. No figure, save or query
changes.

## What Routes looks like after this
1. **Head:** the title "Routes" in display type, and the airline switch as one segmented control beside it (each
   airline's colour dot and short name; the selected one in night). Below 1100 px it sits under the title and scrolls
   sideways inside itself if it must, never the page.
2. **A list beside its detail, both in view.** On wide screens the list is a panel of about 440 px on the left and the
   detail fills the rest. The list panel scrolls inside itself (its height is the window's under the top bar, minus the
   page head) and so does the detail, so the page itself no longer grows to thousands of pixels. The selected route is
   marked in the list (porcelain row with a violet bar on its left).
3. **One row of tools on top of the list:** a search box ("Find a destination"), the base picker ("From JFK ▾", the
   same bases as the current Bases pills, All included), and a **Filters** button that opens a panel with everything
   else the screen filters and sorts by today: demand stars, markets, km from and to, active only, sort, and the
   "Remove N unflown routes shown" action. A small count under the tools, "32 flying · 243 to open" (the screen's
   existing count, in words). "Add route" stays as a button in the head or the tools row.
4. **Slimmer list rows:** destination city (bold) and its code (faint), then "1,222 km · 2 a day" (or "not flown") and
   the trunk tag where it has one; on the right the load as now (coloured as now). Stars and market move to the detail.
5. **The detail:** the route as "New York → Atlanta" in display type with its code pair, a muted line with the airline,
   distance, stars and market; then the figures the detail already shows, as a row of big numbers where they are
   numbers; then the frequencies (each with its tail, named "N003AW (JFK)", and its flight numbers) with the existing
   edit controls; then the loads; and a link to the route's page ("The route's story", the existing route page) when the
   route is flown. With no route picked, the detail shows a short prompt, as now.
6. **Phones (under 760 px):** the list only, full width; tapping a route opens its detail full screen with a "← Routes"
   back button at the top; the browser's back button does the same.

## Checks
- `bash tests/run_all.sh` green; the database rehearsal green: Routes opens at 1280 and 380 px with no errors and no
  sideways scroll, and every save on Routes (add, edit and remove a frequency, add a route, remove unflown routes)
  still works. The screens' figures tests must not move. Keep every `data-figure`, id and data attribute the tests use;
  change a test only where the layout requires it (e.g. opening Filters first), and say which in the pull request.
- Update `docs/planner-guide.md` (Routes).
- Look at the rehearsal's Routes screenshots (routes-1280, routes-380, route-*-1280, route-*-380) before reporting.

## Not in this build
Systems (step 4); any change to data, figures, saves or queries.
