// The address of each screen (design §3, §9) and the address rules web/_redirects follows for the new planner.
import { describe, expect, it } from "vitest";
import redirectsFile from "../../../../web/_redirects?raw";
import { SCREENS, screenForPath, screenHref } from "./screens";

describe("the screens", () => {
  it("are the old planner's nine, in its order and with its names", () => {
    expect(SCREENS.map((s) => s.name)).toEqual(["Home", "Routes", "Tails", "Hubs", "Check", "Review", "Interline", "Photos", "Reference"]);
  });

  it("each has its own address under /planner/next/", () => {
    expect(SCREENS.map(screenHref)).toEqual([
      "/planner/next/", "/planner/next/routes", "/planner/next/tails", "/planner/next/hubs", "/planner/next/check",
      "/planner/next/review", "/planner/next/interline", "/planner/next/photos", "/planner/next/reference",
    ]);
    for (const s of SCREENS) expect(screenForPath(screenHref(s))?.id).toBe(s.id);
  });

  it("maps an address below a screen to that screen, and anything else to none", () => {
    expect(screenForPath("/planner/next")?.id).toBe("home");
    expect(screenForPath("/planner/next/review/VS")?.id).toBe("review");
    expect(screenForPath("/planner/next/routes/")?.id).toBe("routes");
    expect(screenForPath("/planner/next/nothing-here")).toBeNull();
    expect(screenForPath("/planner/routes")).toBeNull();
    expect(screenForPath("/planner/nextish")).toBeNull();
  });
});

describe("web/_redirects", () => {
  // Rules as Cloudflare applies them: the first rule whose source matches wins; a source's * matches anything.
  const rules = redirectsFile.split("\n")
    .map((l: string) => l.trim()).filter((l: string) => l && !l.startsWith("#")).map((l: string) => l.split(/\s+/))
    .map(([from = "", to = "", status = "302"]: string[]) => ({ from, to, status }));
  const escape = (p: string) => p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const resolve = (path: string) => {
    const r = rules.find((x) => new RegExp("^" + x.from.split("*").map(escape).join(".*") + "$").test(path));
    return r ? `${r.status} ${r.to}` : "file";
  };

  it("serves the new planner's page for every screen's address, above the old planner's lines", () => {
    expect(resolve("/planner/next")).toBe("301 /planner/next/");
    for (const s of SCREENS) expect(resolve(screenHref(s)), screenHref(s)).toBe("200 /app/");
    expect(resolve("/planner/next/review/VS")).toBe("200 /app/");
  });

  it("leaves the old planner and the new planner's own files as they were", () => {
    expect(resolve("/planner")).toBe("301 /planner/");
    expect(resolve("/planner/")).toBe("200 /planner/");
    expect(resolve("/planner/routes")).toBe("200 /planner/");
    expect(resolve("/app/assets/index-abc123.js")).toBe("file");
    expect(resolve("/")).toBe("file");
  });

  it("never proxies to a path ending in /index or /index.html, which Cloudflare drops as an infinite loop", () => {
    for (const r of rules) {
      if (r.status === "200" && /\/\*?$/.test(r.from)) expect(r.to, r.from).not.toMatch(/\/index(\.html)?$/);
    }
  });
});
