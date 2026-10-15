# API credits for unattended jobs — 14 Oct 2026 (decision #25)

**Decision:** whether to use the $100 a month in API credits for jobs Claude runs on its own, which ones, and with what
spending cap. Also the question parked with #25 on 10 Oct: Fable as a decision helper.

**Recommendation:** B. One job: Claude drafts the weekly report early on Saturday, on the API credits, under a hard
monthly cap.
- **The weekly report is the heaviest recurring Claude work.** Writing it in the Saturday chat uses your Claude plan's
  weekly limit, which ran short this week (40% gone by Tuesday).
- **The API credits are separate, and unused.** A Saturday job can pull the numbers, run the world scan (#22's step),
  and have Claude write the draft from them. The Saturday chat then reviews and edits the draft with you instead of
  writing it from scratch, and publishes it as now.
- **The cap is hard.** A monthly spending limit on the API key stops the job at the limit, whatever happens. Start at
  $40 a month; the first month's real cost tells us where it should sit.
- **Nothing else needs it yet.** #21 to #24 chose no alerts and no unattended jobs, so this would be the only one.

One pull request, about 2 to 3 hours. Up to the cap a month, from credits that are otherwise unused.

*Columns adapted for a non-game decision.*

| Option | What changes | Effort | Gain | Risk | Easy to undo? |
|---|---|---|---|---|---|
| A. Not now | Nothing. The credits stay unused; the report is written in the Saturday chat as now | None | None | The report keeps using your weekly Claude limit | — |
| **B. A weekly report draft** | **A GitHub job each Saturday at 06:00 UTC runs the scan, pulls the numbers and asks Claude through the API to write the draft, saved as an unpublished report for the Saturday review. API key in GitHub's settings with a $40 monthly limit** | **1 pull request, about 2 to 3 hours** | **The Saturday chat starts from a written draft; less of your weekly limit used** | **A weaker draft than one written with you (it's reviewed before anything is published); a leaked key could spend up to the cap** | **Yes: switch the job off or delete the key** |
| C. B, plus more drafts | B, plus drafts of the newsroom's weekly roundup and the monthly gander newsletter | 1 pull request, about 3 to 4 hours | More of the recurring writing done ahead | More to review; a higher cap ($60 to $80) | Yes |
| D. Use Claude's scheduled tasks instead | The same draft written by a Claude scheduled task | A scheduled task, no build | No key to keep | It runs on your Claude plan's usage, not the API credits, so it doesn't save your weekly limit | Yes |

## Background

### What the credits could pay for
- **Nothing runs on them today.** Every Claude job so far happens in a chat, on your Claude plan.
- **#21 to #24, all decided 14 Oct, chose no unattended jobs:** page checks without an alert (#21), the world scan as a
  Saturday step (#22), a Systems board without an account token (#23), and a briefing command run from a chat (#24).
- **The recurring writing:** the weekly report (Saturdays, a CEO-style PDF briefing, manual §7), the newsroom's weekly
  roundup, and gander monthly (first Saturday).

### How B would work
1. Saturday 06:00 UTC (01:00 in Chicago), a GitHub Action runs the world scan, then `report/pull.py` and
   `report/analyze.py`, as the Saturday chat does now.
2. It sends the numbers, the scan's summaries and the report's standing instructions (manual §7: competition by market,
   risks, opportunities, our plan and progress, route profit, growth signals, fare-plan results) to Claude through the
   API, and asks for the draft.
3. It saves the draft as an unpublished report (`site_reports`, status draft) and builds its PDF. Nothing goes on the
   website.
4. The Saturday chat opens the draft, checks every number against the figures, edits it with you, and publishes it as
   now.

- **The cap:** the API key gets a monthly spending limit in Anthropic's console, so the job can't spend past it. The job
  also caps each run's length. It writes one `job_runs` row (job `report_draft`), and #23's Systems board shows it.
- **The model:** the same one used everywhere (Opus, your 8 Oct preference).

### Parked with #25: Fable as a decision helper
On 10 Oct you parked an idea: Opus gathers the data, and a Fable helper decides from a short summary. Your standing
preference since 8 Oct is Opus for everything, including decisions. Nothing in #21 to #24 needs it, so I'd leave it as
is. Say if you want a brief on it on its own.

### Risks
- **The draft misreads a number.** The Saturday chat checks every figure against `figures.json` before publishing, as it
  does now.
- **A leaked key.** It sits only in GitHub's settings, and the cap limits the damage. Delete it and issue a new one.
- **The first cost estimate is a guess.** The limit holds whatever the real cost; the first month's spend sets it.

## Outcome
14 Oct 2026: Gitesh chose **A**: not now. No unattended job on the API credits; the weekly report stays in the Saturday
chat. Fable as a decision helper stays parked (Opus for everything). Recorded in `docs/decisions.md`.
