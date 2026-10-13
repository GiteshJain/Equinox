// The planning library for the website (decision #19, design §7, "For the website"): what the trip search needs, and
// nothing else. `npm run build` bundles this file into web/assets/rules.js (not committed; Cloudflare builds it), which
// the website loads before site.js and reads as window.EqRules:
//   const lim = EqRules.connections.limitsFrom(content.mct[code], content.connection_max_wait_h);
//   EqRules.connections.isConnection(departure - arrival, lim);   // minutes from landing to the onward departure
// The rule is connections.ts's, the same one the planner and Claude's command use: at least the airport's minimum
// connection time (90 minutes where it has none), at most connection_max_wait_h hours (manual §4).
import { DEFAULT_MCT_MIN, isConnection, limitsFrom } from "./connections.js";

export const connections = { isConnection, limitsFrom, DEFAULT_MCT_MIN };
