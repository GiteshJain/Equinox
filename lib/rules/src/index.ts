// The planning library (decision #19, design §7): the planning rules in one home, for the new planner, the website's
// trip search, the optimiser and Claude. Plain data in, plain data out; no screen code, no clock, no network.
// Each part is exported under its name (time, block, turns, connections, banks, maintenance, aircraftWeek, schedule,
// positions, summary, checks, optimiser, tails, and for the Check screen game, loadReport and growth), plus card (a plan card
// checked against all of them, the cabin its routes call for: cabinFor, and since 21 Oct each route's fare level from
// fare_ladder(): cardFares) and airport (connection times, night bans). The
// Cabins board's part, cabins, went on 21 Oct with the board. What each does, with an example: lib/rules/README.md.
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
export * as summary from "./summary.js";
export * as checks from "./checks.js";
export * as optimiser from "./optimiser.js";
export * as card from "./card.js";
export * as frequency from "./frequency.js";
export * as service from "./service.js";
export * as tails from "./tails.js";
export * as game from "./game.js";
export * as loadReport from "./loadReport.js";
export * as growth from "./growth.js";
export type { BlockAnswer, Distance } from "./block.js";
export type { TurnCheck } from "./turns.js";
export type { BankRow, CityPair, ConnectionLimits, ConnectionsAnswer, Link, LinkedLeg } from "./connections.js";
export type { ArrivalBank, BankWindow } from "./banks.js";
export type { AircraftWeek, WeekLeg } from "./aircraftWeek.js";
export type { Maintenance, NoMaintenance } from "./maintenance.js";
export type { AirportDepartures, CapWarning, FlightNumberClash, NextPair, NightBanHit, RouteGapHit } from "./schedule.js";
export type { Position } from "./positions.js";
export type { AirlineCard, CardBase, KeyFigures, NowFigures, SummaryFigures } from "./summary.js";
export type { CheckFacts, OneWeekCheck } from "./checks.js";
export type { ZoneClock } from "./time.js";
export type { OptimiseAnswer, OptimiseOptions, OptimisedPlan, PlannedLeg } from "./optimiser.js";
export type { CabinFare, CabinRouteShare, CabinSuggestion, Card, CardLeg, FareLadder, FareLadderRow, RouteFare } from "./card.js";
export type { Wave } from "./banks.js";
export type { ConnectingFlight, FrequencyChecks, FrequencyEnds, FrequencyView, LocalTimes, OtherLeg, StoredLeg, Way } from "./frequency.js";
export type { ServiceCheck, ServiceIssue, ServiceLeg, ServiceLegAnswer, ServiceProfile } from "./service.js";
export type { TailIssue } from "./tails.js";
export type { CardCheck, CheckRow, Frequency, GameComparison, GameFix, GameFlight, GameIssue, ImportCandidate, LegToCheck, PlannerEntry } from "./game.js";
export type { DayFlight } from "./loadReport.js";
export type { GrowthRoute, LoggedMove, Move, MoveCandidates, MoveFacts, PlannedCardLeg, QueueCell, ReadinessRow, RouteLoad, SizeRule } from "./growth.js";
