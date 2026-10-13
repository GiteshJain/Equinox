// The planning library (decision #19, design §7): the planning rules in one home, for the new planner, the website's
// trip search, the optimiser and Claude. Plain data in, plain data out; no screen code, no clock, no network.
// Each part is exported under its name (time, block, turns, connections, banks, maintenance, aircraftWeek, schedule,
// positions, optimiser), plus card (a plan card checked against all of them) and airport (connection times, night
// bans). What each does, with an example: lib/rules/README.md.
//   import { buildRules, connections } from "@rules";
//   const rules = buildRules(await rulesInput());      // rules_input()'s answer
//   connections.connectionsAt(rules, "JFK").city_pairs;
export * from "./types.js";
export { RulesError, buildRules, findAircraft, findType, pairKey, setting, settingNumber, typeKey, typeOfAircraft, worldRule, worldRuleNumber } from "./input.js";
export * as time from "./time.js";
export * as airport from "./airport.js";
export * as block from "./block.js";
export * as turns from "./turns.js";
export * as connections from "./connections.js";
export * as banks from "./banks.js";
export * as maintenance from "./maintenance.js";
export * as aircraftWeek from "./aircraftWeek.js";
export * as schedule from "./schedule.js";
export * as positions from "./positions.js";
export * as optimiser from "./optimiser.js";
export * as card from "./card.js";
export type { BlockAnswer, Distance } from "./block.js";
export type { TurnCheck } from "./turns.js";
export type { BankRow, CityPair, ConnectionLimits, ConnectionsAnswer, Link, LinkedLeg } from "./connections.js";
export type { ArrivalBank, BankWindow } from "./banks.js";
export type { AircraftWeek, WeekLeg } from "./aircraftWeek.js";
export type { Maintenance, NoMaintenance } from "./maintenance.js";
export type { AirportDepartures, FlightNumberClash, NextPair, NightBanHit, RouteGapHit } from "./schedule.js";
export type { Position } from "./positions.js";
export type { OptimiseAnswer, OptimiseOptions, OptimisedPlan, PlannedLeg } from "./optimiser.js";
export type { Card, CardLeg } from "./card.js";
