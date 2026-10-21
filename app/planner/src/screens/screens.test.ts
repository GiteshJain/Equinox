// The address of each screen (design §3, §9) and the address rules web/_redirects follows for the planner (the switch),
// and since 20 Oct (spec docs/specs/2026-10-20-today-performance-systems.md) the screens grouped by when they're used,
// with Check's, Review's and Hubs' old addresses each going to its new one.
import { describe, expect, it } from "vitest";
import redirectsFile from "../../../../web/_redirects?raw";
import { SCREENS, itemRoute, movedTo, screenForPath, screenHref } from "./screens";

describe("the screens", () => {
  it("are the ten grouped by when they're used: Home, Today, Routes, Tails, Performance, Competition, Interline, Photos, Reference, Systems", () => {
    // Competition since 21 Oct (spec docs/specs/2026-10-21-competition-analysis.md §3), after Performance
    expect(SCREENS.map((s) => s.name)).toEqual(["Home", "Today", "Routes", "Tails", "Performance", "Competition", "Interline", "Photos", "Reference", "Systems"]);
    expect(SCREENS.map((s) => s.name)).not.toContain("Hubs");
  });

  it("each has its own address under /planner/", () => {
    expect(SCREENS.map(screenHref)).toEqual([
      "/planner/", "/planner/today", "/planner/routes", "/planner/tails", "/planner/performance", "/planner/competition",
      "/planner/interline", "/planner/photos", "/planner/reference", "/planner/systems",
    ]);
    for (const s of SCREENS) expect(screenForPath(screenHref(s))?.id).toBe(s.id);
  });

  it("maps an address below a screen to that screen, and anything else to none", () => {
    expect(screenForPath("/planner")?.id).toBe("home");
    expect(screenForPath("/planner/performance/VS")?.id).toBe("performance");
    expect(screenForPath("/planner/routes/")?.id).toBe("routes");
    expect(screenForPath("/planner/nothing-here")).toBeNull();
    expect(screenForPath("/planner/old/")).toBeNull();
    expect(screenForPath("/planner/next/routes")).toBeNull();
    expect(screenForPath("/planner/review/VS")).toBeNull();
    expect(screenForPath("/planner/check")).toBeNull();
    expect(screenForPath("/planner/hubs")).toBeNull();
    expect(screenForPath("/plannerish")).toBeNull();
  });

  it("links where each thing is fixed: an aircraft, an airline's route, an airline, a part of a screen", () => {
    expect(itemRoute("tails", { tail: "N001AW" })).toBe("/tails/N001AW");
    expect(itemRoute("routes", { airline: "PA", hub: "JFK", dest: "ORD" })).toBe("/routes/PA/JFK-ORD");
    expect(itemRoute("performance", { airline: "PA", hub: "JFK", dest: "ORD" })).toBe("/performance/PA/JFK-ORD");
    expect(itemRoute("performance", { airline: "VS" })).toBe("/performance/VS");
    expect(itemRoute("performance")).toBe("/performance");
    expect(itemRoute("competition", { airline: "MU" })).toBe("/competition/MU");
    expect(screenForPath("/planner/competition/MU")?.id).toBe("competition");
    expect(itemRoute("today", { hash: "todo" })).toBe("/today#todo");
    expect(itemRoute("home")).toBe("/");
    expect(itemRoute("systems")).toBe("/systems");
  });

  it("sends each old address of Check, Review and Hubs to its new one, inside the planner", () => {
    expect(movedTo("/check")).toBe("/today");
    expect(movedTo("/check", "?aircraft=N001AW")).toBe("/today?aircraft=N001AW");
    // Check's daily load report on a day is Performance's Flights by day on it now; so is Today with a day (where
    // web/_redirects sends /planner/check?day=…)
    expect(movedTo("/check", "?day=2026-10-12")).toBe("/performance?day=2026-10-12");
    expect(movedTo("/today", "?day=2026-10-12")).toBe("/performance?day=2026-10-12");
    expect(movedTo("/review")).toBe("/performance");
    expect(movedTo("/review/VS")).toBe("/performance/VS");
    expect(movedTo("/review/PA/JFK-ORD")).toBe("/performance/PA/JFK-ORD");
    expect(movedTo("/hubs")).toBe("/performance");
    expect(movedTo("/hubs/DEL", "?day=2")).toBe("/performance");
    expect(movedTo("/today")).toBeNull();
    expect(movedTo("/performance/VS")).toBeNull();
    expect(movedTo("/routes")).toBeNull();
  });
});

describe("web/_redirects", () => {
  // Rules as Cloudflare applies them: the first rule whose source matches wins; a source's * matches anything, which a
  // target's :splat repeats; a 200 rule serves the file at its target without looking at the rules again.
  const rules = redirectsFile.split("\n")
    .map((l: string) => l.trim()).filter((l: string) => l && !l.startsWith("#")).map((l: string) => l.split(/\s+/))
    .map(([from = "", to = "", status = "302"]: string[]) => ({ from, to, status }));
  const escape = (p: string) => p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const resolve = (path: string) => {
    for (const x of rules) {
      const m = new RegExp("^" + x.from.split("*").map(escape).join("(.*)") + "$").exec(path);
      if (m) return `${x.status} ${x.to.replace(":splat", m[1] ?? "")}`;
    }
    return "file";
  };

  it("serves the planner's page for /planner/ and every screen's address (the switch)", () => {
    expect(resolve("/planner")).toBe("301 /planner/");
    for (const s of SCREENS) expect(resolve(screenHref(s)), screenHref(s)).toBe("200 /app/");
    expect(resolve("/planner/performance/VS")).toBe("200 /app/");
    expect(resolve("/planner/routes/PA/JFK-ORD")).toBe("200 /app/");
  });

  it("sends Check's, Review's and Hubs' old addresses (301) to Today and Performance (20 Oct)", () => {
    expect(resolve("/planner/check")).toBe("301 /planner/today");
    expect(resolve("/planner/check/")).toBe("301 /planner/today");
    expect(resolve("/planner/review")).toBe("301 /planner/performance");
    expect(resolve("/planner/review/")).toBe("301 /planner/performance/");
    expect(resolve("/planner/review/VS")).toBe("301 /planner/performance/VS");
    expect(resolve("/planner/review/PA/JFK-ORD")).toBe("301 /planner/performance/PA/JFK-ORD");
    expect(resolve("/planner/hubs")).toBe("301 /planner/performance");
    expect(resolve("/planner/hubs/DEL")).toBe("301 /planner/performance");
  });

  it("sends each address used while it was built (/planner/next/...) to the same address under /planner/", () => {
    expect(resolve("/planner/next")).toBe("301 /planner/");
    expect(resolve("/planner/next/")).toBe("301 /planner/");
    expect(resolve("/planner/next/routes")).toBe("301 /planner/routes");
    expect(resolve("/planner/next/review/VS")).toBe("301 /planner/review/VS");
    expect(resolve("/planner/next/routes/PA/JFK-ORD")).toBe("301 /planner/routes/PA/JFK-ORD");
  });

  it("sends the old planner's address (/planner/old/..., gone with the clean-up) to /planner/, and the planner's files as they are", () => {
    expect(resolve("/planner/old")).toBe("301 /planner/");
    expect(resolve("/planner/old/")).toBe("301 /planner/");
    expect(resolve("/planner/old/anything")).toBe("301 /planner/");
    expect(resolve("/planner/old/index.html")).toBe("301 /planner/");
    expect(resolve("/app/assets/index-abc123.js")).toBe("file");
    expect(resolve("/")).toBe("file");
  });

  it("never proxies to a path ending in /index or /index.html, which Cloudflare drops as an infinite loop", () => {
    for (const r of rules) {
      if (r.status === "200" && /\/\*?$/.test(r.from)) expect(r.to, r.from).not.toMatch(/\/index(\.html)?$/);
    }
  });
});
