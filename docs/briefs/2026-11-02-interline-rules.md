# Interline rules: from a short country list to one partner per foreign airport

*Scheduling chat, 2 Nov 2026. Raised by Gitesh: "lets rehaul how we interline, very strict right now".*

## Decision and recommendation
**Decision:** which outside airlines our six airlines interline with (manual §6).

**Recommendation: option B, "feed first".**
- At every foreign airport an airline of ours flies to, outside our own base countries, it signs one local partner: the
  airline that adds the most onward destinations we don't fly from there, in the latest world scan. This covers any
  country, Europe and the Americas included.
- A country can have more than one partner when they serve different airports.
- We accept incoming requests from any airline that flies from an airport we serve.
- Hub rivals stay declined: the Gulf, Türkiye, Singapore, Hong Kong and South Korea.
- The Saturday review lists new airports without a partner, and the Scheduling chat proposes each one.

## Options

| | A: keep today's rules | **B: feed first** | C: everyone but hub rivals | D: everyone |
|---|---|---|---|---|
| Growth | 5 partners; 16 of about 115 foreign airports can have one | about 30 contracts, one per foreign airport worth it; e.g. TAP at Lisbon adds 49 onward places for Ryanair, Aeromexico at Mexico City 45 for Pan Am | Most connections possible, but many partners add nothing we can use | As C, plus the Gulf hubs' networks |
| Profit a week | Unchanged | More connecting passengers on routes that already sell out, so the fare ladder can climb faster; not measurable until a few weeks of captures | As B, with more staff cost per passenger gained | As C, and risks losing connecting passengers to rival hubs |
| Cash at the lowest point | Unchanged | About one network-planning employee per contract per airline (the game's rule): small, about 30 salaries | Larger, a contract per request | Larger again |
| Opportunity cost | Leaves about 75 foreign airports with no feed (Virgin's and Ryanair's Europe, Pan Am's Canada, Mexico and Ireland, South-East Asia for Kingfisher, China Eastern and Malaysia) | Small: a partner that later becomes a rival on our pairs | Staff and attention spent on partners that feed nothing | Feeds Dubai, Doha, Istanbul and Singapore against Kingfisher's and Malaysia's hubs |
| Risk | Low; missed traffic | Low: connections rate lower than direct flights in the game, so they don't displace our own; a partner's weak flights simply go unused | Low to medium | Medium to high: hub carriers "take our connecting traffic rather than feed it" (earlier matrix) |
| Easy to undo | — | Yes: a contract can be cancelled at any time and ends with that accounting week | Yes | Yes, but traffic lost meanwhile |

## Background
**How interlining works in the game** (AirlineSim handbook, "Interlining"):
- A contract links the two airlines' whole networks at once. Connections follow the same rules as our own: each
  airport's minimum connection time, and a wait of up to about 8 hours.
- It costs network-planning staff: at least one employee per airline and contract, more for large partners.
- Connected flights always rate lower than direct flights in the reservation system. A partner adds options for
  passengers who can't fly direct; it doesn't pull them off our own direct flights.
- Either side can cancel at any time. The contract then runs to the end of that accounting week.
- The handbook gives no limit on the number of partners.

**Today's rules** (since 25–28 Sep):
- Outside partners only in about 17 countries with a real domestic market, or that are a gateway to a region we can't
  reach.
- None in Ryanair's Europe zone.
- None for Pan Am in Canada, Mexico, the Caribbean or Central America.
- The Gulf carriers are declined as rivals (since 5 Oct).
- The rule history records a reason only for the Gulf rule.

**Where we stand** (planner and the 2 Nov 16:42 UTC world scan):

| Airline | Foreign airports with a partner possible today | Skipped by the rules | Hub rival | Best partners we're missing (onward places we don't fly) |
|---|---|---|---|---|
| Pan Am | 0 | 4 (Canada, Mexico, Ireland) | 0 | Aeromexico Connect at Mexico City 45; Aer Lingus at Dublin 40; Air Canada at Toronto 10 |
| Kingfisher | 0 | 7 (Bangladesh, Kazakhstan, Sri Lanka, Nepal, Thailand, Vietnam) | 9 | Thai at Bangkok 33; VietJet at Ho Chi Minh City 21 |
| Ryanair | 0 | 23 in 18 countries | 0 | TAP at Lisbon 49; Norra at Helsinki 36; Icelandair at Keflavík 27; Braathens at Stockholm 20; SWISS at Zurich 14; SAS at Copenhagen 11 |
| Virgin | 1 (Russia) | 23 in 18 countries | 3 (Türkiye) | TAP at Lisbon 40; Norra at Helsinki 36; Icelandair 24; Rossiya at St Petersburg 23 (requested 2 Nov); Aer Lingus 20 |
| China Eastern | 4 (Japan, Philippines) | 5 (Thailand, Taiwan, Vietnam) | 4 | Cebu Pacific at Manila 23; Thai 22; VietJet 18; China Airlines at Taipei 10 |
| Malaysia | 11 (Australia, Indonesia, Japan, Philippines) | 13 | 4 | Cebu Pacific at Manila 19; Thai 14; VietJet 13; China Airlines 9 |

Signed today: ANA (China Eastern, Malaysia), Qantas and Garuda (Malaysia). The Philippines is marked "no partner" for
both China Eastern and Malaysia, but Cebu Pacific now flies 23 places from Manila: that row is out of date whatever is
decided.

## Scenarios and the risk of waiting
- **If we wait:** every week our flights to those ~75 airports carry only local passengers. Most of our routes already
  sell out, so the loss is mainly fare level (the ladder climbs on demand), and on the routes still filling, load.
- **If a partner turns rival:** a partner that starts flying our pairs is no worse off with the contract than without
  it. Its passengers still connect on whichever flight rates best. If it becomes a hub carrier against us, we cancel
  the contract, and it ends that week.
- **Ryanair:** the real Ryanair doesn't interline. In Gander it would gain the most (six airports, about 157 onward
  places). If you'd rather keep Ryanair point-to-point for character, B works without it.

## What would change the recommendation
- **Captures show partners filling our seats at lower fares** than local passengers would pay: then interline only
  where our flights don't sell out.
- **Staff cost turns out larger than expected** for big partners: then trim to the partners adding 10 or more onward
  places.
- **The game or the world's owner limits contracts:** then rank the partners by onward places and take the top ones.

Sources: AirlineSim handbook, Interlining (handbook.airlinesim.aero/en/docs/advanced/alliances-and-interlining/interlining);
world scan 18 (2 Nov 2026); planner `interline_agreements`; manual §6; earlier interline matrix (ARCHIVE-2 chat, Oct).
