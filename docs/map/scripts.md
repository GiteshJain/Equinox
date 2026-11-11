# Scripts

One part of the map, `docs/architecture.md`, in full. The map has the short version; a build that changes this part adds its dated note here, not in the map.

## What it is

Python scripts Claude runs for the weekly report, gander monthly, the world scan by hand (the fallback since the capture scans, 21 Oct) and the airline briefing. The weekly report's money comes from the captured figures and its airlines, bases and networks from the planning library's input, through `export_for_report()`; since 22 Oct each airline against its three biggest competitors comes from the figures too (`competition()`'s `competitors`, `self` and `scans`, growth against the week-before scan; manual §7), since 23 Oct with each rival's fleet, aircraft on order and the week's change, and the flagged rivals in the risks (`order_flags`), and each rival's connecting departures on the airline's pairs in a column beside direct, never added (`connecting_weekly`), and since 30 Oct each airline's contested pairs with our economy fare against the cheapest rival's and the game's passenger share each way from the latest market read (`contested`, `market_run`; spec `docs/specs/2026-10-30-market-pages-planner.md` §5), and since 3 Nov a Fare results section per airline (`fare_results()` through `export_for_report()`'s kind `fare_results`, pulled into `fare_results.json`: the title line, the top 5 directions by profit a week gained, every direction whose load fell and the at-cap count; spec `docs/specs/2026-11-03-fare-results.md` §3); its week's words from a `notes.json` the Saturday review writes. The airline briefing (#24, `scripts/briefing/brief.py <airline>`) gathers one airline's whole background before scheduling, each figure from its one home (below, *Which call answers which question*). The schedule optimiser is the planning library's command.

## Where

`scripts/`, how to run them in `scripts/README.md`
