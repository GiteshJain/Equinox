#!/usr/bin/env node
/// <reference types="node" />
// The planning library as a command, for Claude and the scripts (design §7, spec §3). Answers in JSON on standard
// output; errors go to standard error with a non-zero exit.
//
//   node lib/rules/dist/cli.js <command> <input.json> [arguments]
//
// input.json is rules_input()'s answer (scripts: export_for_report(secret, 'rules'); see scripts/README.md).
//   block <origin> <dest> <type>                 the block-time estimate for a leg not yet timed
//   connections <airport>                        every connection there, with days and gaps, the city pairs and banks
//   aircraft [registration]                      one aircraft's week and maintenance; every aircraft's figures without one
//   check-card <card.json> [--fares <ladder.json>]
//                                                a plan card's legs checked against every rule, at both ends, and its
//                                                cabin (config_id) against the one its routes call for (cabin, 21 Oct);
//                                                with fare_ladder()'s answer for its airline (or the briefing's), each
//                                                route's fare level (fares, 21 Oct; once per direction since 26 Oct)
//   optimise <base> <dest,dest,...> --type <type> [--start 05:00-11:00] [--step 5] [--hubs X,Y] [--airline <id>]
//                                                the best day's schedule for one aircraft
// The optimiser's start window and step default to plan.py's (05:00 to 11:00 local at the base, every 5 minutes):
// search settings, not rules.
import { readFileSync, realpathSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { forAircraft as aircraftWeekFor } from "./aircraftWeek.js";
import { blockFor, timedLegs } from "./block.js";
import { checkCard, type Card, type FareLadder } from "./card.js";
import { connectionsAt } from "./connections.js";
import { RulesError, buildRules } from "./input.js";
import { forAircraft as maintenanceFor } from "./maintenance.js";
import { optimise } from "./optimiser.js";
import { parseClock } from "./time.js";
import type { Json, Rules, RulesInput } from "./types.js";

const USAGE = `usage: node lib/rules/dist/cli.js <command> <input.json> [arguments]
  block <origin> <dest> <type>
  connections <airport>
  aircraft [registration]
  check-card <card.json> [--fares <ladder.json>]
  optimise <base> <dest,dest,...> --type <type> [--start 05:00-11:00] [--step 5] [--hubs X,Y] [--airline <id>]
input.json is rules_input()'s answer (export_for_report(secret, 'rules') for the scripts); ladder.json is fare_ladder()'s
answer for the card's airline (select public.fare_ladder(<airline id>)), or the briefing's (its fare_ladder).`;

class UsageError extends Error {}

function readJson(path: string): unknown {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (e) {
    throw new UsageError(`can't read ${path}: ${(e as Error).message}`);
  }
}

/** rules_input()'s answer, also when saved wrapped (as the data API answers an RPC, or as a one-row result). */
function unwrap(x: unknown): RulesInput {
  let v = x;
  if (Array.isArray(v) && v.length === 1) v = v[0];
  if (v && typeof v === "object" && !("settings" in v)) {
    const inner = (v as Record<string, unknown>).rules_input ?? (v as Record<string, unknown>).export_for_report;
    if (inner) v = inner;
  }
  return v as RulesInput;
}

/** fare_ladder()'s answer, also when saved wrapped (as the data API answers an RPC, a one-row result, or the airline
 *  briefing's document or JSON, whose fare_ladder it is). */
function unwrapLadder(x: unknown): FareLadder {
  let v = x;
  if (Array.isArray(v) && v.length === 1) v = v[0];
  for (let i = 0; i < 2 && v && typeof v === "object" && !Array.isArray((v as Record<string, unknown>).routes); i++) {
    const o = v as Record<string, unknown>;
    v = o.fare_ladder ?? (o.briefing as Record<string, unknown> | undefined)?.fare_ladder ?? v;
  }
  if (!v || typeof v !== "object" || !Array.isArray((v as Record<string, unknown>).routes)) {
    throw new UsageError("--fares needs fare_ladder()'s answer (or the briefing's fare_ladder): a document with its routes");
  }
  return v as FareLadder;
}

function options(args: string[]): { pos: string[]; opt: Record<string, string> } {
  const pos: string[] = [], opt: Record<string, string> = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i] ?? "";
    if (a.startsWith("--")) {
      const [k, v] = a.slice(2).split("=", 2);
      if (!k) throw new UsageError(`bad option ${a}`);
      if (v !== undefined) opt[k] = v;
      else {
        const next = args[i + 1];
        if (next === undefined || next.startsWith("--")) throw new UsageError(`--${k} needs a value`);
        opt[k] = next;
        i++;
      }
    } else pos.push(a);
  }
  return { pos, opt };
}

function aircraftAnswer(rules: Rules, registration: string | undefined): Json {
  const legs = timedLegs(rules);
  if (registration) {
    const week = aircraftWeekFor(rules, registration, legs);
    if (!week) throw new RulesError(`no aircraft ${registration} in the input`);
    return { aircraft_week: week, maintenance: maintenanceFor(rules, registration, legs, week) } as unknown as Json;
  }
  const flying = new Set(legs.map((l) => l.aircraft_id));
  const out = [];
  for (const a of rules.aircraft.values()) {
    if (a.status !== "active" && !flying.has(a.id)) continue;
    const week = aircraftWeekFor(rules, a, legs);
    if (!week) continue;
    const m = maintenanceFor(rules, a, legs, week);
    out.push({
      aircraft_id: a.id, registration: a.registration, airline_id: a.airline_id, type: week.type, base_code: week.base_code, status: a.status ?? null,
      legs_week: week.legs_week, block_min_week: week.block_min_week, block_hours_day: week.block_hours_day, routes: week.routes,
      route_ids: week.route_ids, gaps_at_target: week.gaps_at_target, estimated_legs: week.estimated_legs,
      maintenance_ratio: m?.ratio ?? null, maintenance_pct: m && m.ratio != null ? m.pct : null, maintenance_level: m && m.ratio != null ? m.level : null,
      turns_short: week.legs.filter((l) => l.turn?.short).length, turns_tight: week.legs.filter((l) => l.turn?.tight).length,
      position_breaks: week.legs.filter((l) => !l.position_ok).length, overlaps: week.legs.filter((l) => l.overlap).length,
    });
  }
  return out as unknown as Json;
}

function window(s: string): { from: number; to: number } {
  const [a, b] = s.split("-", 2).map((x) => parseClock(x));
  if (a == null || b == null) throw new UsageError(`--start must be HH:MM-HH:MM, not ${s}`);
  return { from: a, to: b };
}

export function run(argv: string[]): Json {
  const [command, inputPath, ...rest] = argv;
  if (!command || command === "help" || command === "--help") throw new UsageError("");
  if (!inputPath) throw new UsageError("give the input file (rules_input()'s answer)");
  const rules = buildRules(unwrap(readJson(inputPath)));
  const { pos, opt } = options(rest);
  switch (command) {
    case "block": {
      const [o, d, t] = pos;
      if (!o || !d || !t) throw new UsageError("block <origin> <dest> <type>");
      return blockFor(rules, o, d, t, opt.airline ? Number(opt.airline) : null) as unknown as Json;
    }
    case "connections": {
      const [ap] = pos;
      if (!ap) throw new UsageError("connections <airport>");
      return connectionsAt(rules, ap) as unknown as Json;
    }
    case "aircraft":
      return aircraftAnswer(rules, pos[0]);
    case "check-card": {
      const [cardPath] = pos;
      if (!cardPath) throw new UsageError("check-card <card.json> [--fares <ladder.json>]");
      const fares = opt.fares ? unwrapLadder(readJson(opt.fares)) : null;
      return checkCard(rules, readJson(cardPath) as Card, { fares }) as unknown as Json;
    }
    case "optimise":
    case "optimize": {
      const [base, dests] = pos;
      if (!base || !dests || !opt.type) throw new UsageError("optimise <base> <dest,dest,...> --type <type>");
      const type = /^\d+$/.test(opt.type) ? Number(opt.type) : opt.type;
      return optimise(rules, {
        base, destinations: dests.split(",").map((x) => x.trim()).filter(Boolean), type,
        airlineId: opt.airline ? Number(opt.airline) : null,
        start: window(opt.start ?? "05:00-11:00"), step: opt.step ? Number(opt.step) : 5,
        extraHubs: opt.hubs ? opt.hubs.split(",").map((x) => x.trim()).filter(Boolean) : [],
      }) as unknown as Json;
    }
    default:
      throw new UsageError(`unknown command ${command}`);
  }
}

const isMain = (() => {
  try {
    return process.argv[1] != null && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href;
  } catch {
    return false;
  }
})();

if (isMain) {
  try {
    process.stdout.write(JSON.stringify(run(process.argv.slice(2)), null, 2) + "\n");
  } catch (e) {
    if (e instanceof UsageError) {
      process.stderr.write((e.message ? e.message + "\n" : "") + USAGE + "\n");
      process.exit(2);
    }
    process.stderr.write(`error: ${e instanceof Error ? e.message : String(e)}\n`);
    process.exit(1);
  }
}
