// The address of each screen (design §3, §9) and the address rules web/_redirects follows for the planner (the switch).
import { describe, expect, it } from "vitest";
import redirectsFile from "../../../../web/_redirects?raw";
import { SCREENS, screenForPath, screenHref } from "./screens";

describe("the screens", () => {
  it("are the old planner's nine, in its order and with its names", () => {
    expect(SCREENS.map((s) => s.name)).toEqual(["Home", "Routes", "Tails", "Hubs", "Check", "Review", "Interline", "Photos", "Reference"]);
  });

  it("each has its own address under /planner/", () => {
    expect(SCREENS.map(screenHref)).toEqual([
      "/planner/", "/planner/routes", "/planner/tails", "/planner/hubs", "/planner/check",
      "/planner/review", "/planner/interline", "/planner/photos", "/planner/reference",
    ]);
    for (const s of SCREENS) expect(screenForPath(screenHref(s))?.id).toBe(s.id);
  });

  it("maps an address below a screen to that screen, and anything else to none", () => {
    expect(screenForPath("/planner")?.id).toBe("home");
    expect(screenForPath("/planner/review/VS")?.id).toBe("review");
    expect(screenForPath("/planner/routes/")?.id).toBe("routes");
    expect(screenForPath("/planner/nothing-here")).toBeNull();
    expect(screenForPath("/planner/old/")).toBeNull();
    expect(screenForPath("/planner/next/routes")).toBeNull();
    expect(screenForPath("/plannerish")).toBeNull();
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

  it("serves the new planner's page for /planner/ and every screen's address (the switch)", () => {
    expect(resolve("/planner")).toBe("301 /planner/");
    for (const s of SCREENS) expect(resolve(screenHref(s)), screenHref(s)).toBe("200 /app/");
    expect(resolve("/planner/review/VS")).toBe("200 /app/");
    expect(resolve("/planner/routes/PA/JFK-ORD")).toBe("200 /app/");
  });

  it("sends each address used while it was built (/planner/next/...) to the same address under /planner/", () => {
    expect(resolve("/planner/next")).toBe("301 /planner/");
    expect(resolve("/planner/next/")).toBe("301 /planner/");
    expect(resolve("/planner/next/routes")).toBe("301 /planner/routes");
    expect(resolve("/planner/next/review/VS")).toBe("301 /planner/review/VS");
    expect(resolve("/planner/next/routes/PA/JFK-ORD")).toBe("301 /planner/routes/PA/JFK-ORD");
  });

  it("serves the old planner's own file at /planner/old/ (the way back), and the new planner's files as they are", () => {
    expect(resolve("/planner/old")).toBe("301 /planner/old/");
    expect(resolve("/planner/old/")).toBe("200 /planner/");
    expect(resolve("/planner/old/anything")).toBe("200 /planner/");
    expect(resolve("/app/assets/index-abc123.js")).toBe("file");
    expect(resolve("/")).toBe("file");
  });

  it("never proxies to a path ending in /index or /index.html, which Cloudflare drops as an infinite loop", () => {
    for (const r of rules) {
      if (r.status === "200" && /\/\*?$/.test(r.from)) expect(r.to, r.from).not.toMatch(/\/index(\.html)?$/);
    }
  });
});
