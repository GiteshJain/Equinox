# Spec: the route's story on Routes — 30 Oct 2026

*Building chat. Gitesh, 30 Oct: on Routes the right side of a wide screen is empty; show the route's story there
instead of clicking "How it's doing ›". Decided the same day (Building chat): the layout below. No database change.*

## What
On Routes, a route's detail (`/planner/routes/<airline>/<hub>-<dest>`) also shows the route's story: the same boards
as Performance's route page, from the same reads (`route_story()`, `route_loads()`, the start's input), drawn by the
same components. Nothing is worked out a second time: move the route page's boards into shared components (e.g.
`screens/performance/RouteStory.tsx`) that both screens render.

| Screen width | Where the story goes on Routes |
|---|---|
| 1,600 px and wider | A third column to the right of the route detail, its own scroll, as tall as the screen |
| 1,100 to 1,600 px | Under the frequencies, its boards open |
| Under 1,100 px (phones) | Not shown; "How it's doing ›" opens the route page, as now |

The boards on Routes, in this order: the last 7 days' tiles, Since launch, Load by direction, Rival fares, Market share,
Rivals over time, Loads by flight, Profit an aircraft hour. Not on Routes (they're already there or belong to the route
page): Events, Rivals on the pair table, Connections. A "Full story ›" link at the top opens the route page.

Reads only when a route is open, cached as the route page's are (switching routes reads the new one; going back to a
route already read doesn't read again within the cache time). A route not flown yet shows nothing in the story column
but "Not flown yet". Every board handles no data as it does on the route page.

Performance's route page is unchanged in what it shows.

## Checks
Unit tests for the shared boards' figures (they move, so the route page's tests follow them); the screens run on the
copy at 1280, 1700 and 380 px with no errors and no sideways scroll (add 1700 for Routes' route detail); the route
page still shows all ten boards. Docs: the map's Routes paragraph, `docs/planner-guide.md`.
