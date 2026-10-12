# Website data in smaller pieces — 12 Oct 2026 (decision #20)

**Decision:** whether the website's data should be split into smaller pieces, or served differently, now.

**Recommendation:** A. Not now; keep the one call and set triggers.
- The website's one call, `site_public()`, is 109 KB today, and #13 already moved it onto the tables.
- About 40 calls a day reach Supabase. With the photos from our own storage, that's under 5% of the free plan's
  5 GB of egress a month.
- Splitting it saves little at this size. If a trigger fires, the step is C: one small pull request puts Cloudflare's
  cache in front, so Supabase answers at most once a minute however many people visit.

$0 a month, no build.

*Columns adapted for a non-game decision.*

| Option | What changes | Effort | Gain today | Risk | Easy to undo? |
|---|---|---|---|---|---|
| **A. Keep the one call, with triggers** | **Nothing now. Revisit when a trigger fires** | **None** | **None needed** | **A sudden rush of visitors (a post on Discord, say) all reach Supabase. Even 2,000 visits in a day is about 220 MB, so it would take a lasting rush to matter** | **Yes** |
| B. Split into calls per page | Each page loads its own piece (network, destinations and photos, newsroom) | 1 to 2 pull requests | 30 to 60 KB less on some pages | More calls per visit; each page's piece to keep right | Yes |
| C. Cloudflare's cache in front | A small Cloudflare function serves the website's data, asking Supabase at most once a minute | 1 small pull request | Faster for distant visitors; Supabase's load no longer grows with visitors | Data up to a minute old: a photo uploaded in the planner shows within a minute, not at once | Yes: point the site back at Supabase |
| D. Files rebuilt by a job | A job writes the website's data as files after each capture or planner change | 2 pull requests, plus a job to watch | As C | If the job fails, the website shows old data until someone notices | Yes |

## Background

### What the website loads today
Live database and Supabase's logs, 12 Oct; repository `main`.
- **From Supabase, once per visit:** `site_public()`, 109 KB before compression. It's sent as a POST, so browsers
  can't keep a copy.

  | Part | Size |
  |---|---|
  | Photo and video links (`content.media`: 99 airports, 35 photos, 8 videos) | 49 KB |
  | Flights (`freqs`) | 39 KB |
  | Newsroom posts | 9 KB |
  | Aircraft | 6 KB |
  | Airlines, reports, hubs, connection times, interlines | 6 KB |

- **From our photo storage:** the destination photos uploaded through the planner (57 files, 51 KB on average).
- **From Cloudflare:** the page and its files, 370 KB (about 130 KB compressed). That includes the world map (95 KB)
  and the logos (75 KB), which Cloudflare serves, not Supabase.
- **Traffic:** Supabase's logs show 40 calls to `site_public()` in the 24 hours to 13:22 UTC today. That's about
  4.4 MB a day before compression, roughly 130 MB a month, plus the photos.

### Where #20 came from
It was item 13 on the 8 Oct list, "later; low priority". Back then `site_public()` converted the whole planner row on
every visit. #13 (pull request 8) moved it onto the tables, so the work behind each call is now small. The size stayed
about the same (design §12 noted that).

### How it grows
Flights and aircraft grow with the fleet, and the photo links with destinations. At three times today's fleet the call
would be roughly 250 KB, still small.

### What the website doesn't need from #20
- The new planner's per-screen loading is part of #18.
- #19's library reaches the website's trip search as a built file, with no rebuild of the website.

### Noticed, not part of this decision
86 of the website's photos and videos load straight from other sites: 43 airport photos and 35 other photos (Wikimedia,
rawpixel, StockSnap and a WordPress image host), and 8 videos (Mixkit). If one of those sites removes a file or blocks
use from other sites, that picture goes blank. Copying them into our own photo storage would be a small separate item,
if you want it.

## Triggers for C
Any one of these means a brief in the Building chat:
- `site_public()` passes 500 KB (109 KB today);
- the website's calls pass 1,000 a day (about 40 today);
- Supabase's egress passes 4 GB in a month (already a #17 trigger) with the website a large part of it.

They're looked at with the monthly usage check (manual §7), and by #23's monitoring once that's built.

## Scenarios and the risk of waiting
- **Traffic stays as it is:** nothing to do, and nothing spent.
- **gander monthly or the site gets shared widely:** even 2,000 visits a day is about 6.5 GB a month before
  compression. That would reach the egress trigger within a few weeks, and C is one small pull request when it does.
  Compression cuts the real figure a lot.
- **Waiting costs nothing measurable.** Nothing else depends on #20: the planner shell doesn't wait on it.

## What would change the recommendation
- **If you plan to promote the site** (Discord, the gander monthly launch): do C first, so a rush never reaches
  Supabase.
- **If you'd rather have the finished setup now and never think about it:** C is one small pull request. The cost is
  that photo uploads appear within a minute instead of at once.

## Sources
- Live database, 12 Oct: `site_public()` 109,277 bytes (`content` 50,502, of which `media` 49,085; `freqs` 38,904;
  `posts` 9,300; `tails` 5,924); `site-photos` bucket, 57 files, 2.9 MB; media links by host.
- Supabase logs, edge requests in the 24 hours to 12 Oct 13:22 UTC: 40 calls to `/rest/v1/rpc/site_public`.
- Repository `main` (12 Oct): `web/index.html`, `web/assets/site.js` (the `site_public` call at line 70),
  `web/assets/` file sizes; `docs/design/2026-10-09-data-model.md` §12; `docs/planner-guide.md` (Photos).
- Decision #17's triggers (manual §1); the 8 Oct list (Building chat, item 13).

## Outcome
Open.
