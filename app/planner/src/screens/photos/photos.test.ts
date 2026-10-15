// Photos' list and words, as the old eqDests, eqCity and eqPhotoOf (the uploads themselves are tried in the rehearsal),
// with which city's photo an airport takes and the name the website gives it as data since 15 Oct (content.airport_cities).
import { readFileSync } from "node:fs";
import { gunzipSync } from "node:zlib";
import { describe, expect, it } from "vitest";
import { cityOf, destinations, fitWidth, logoPath, photoOf, photoPath, type AirportCities, type Media } from "./model";

const lists: AirportCities = { name: { LGW: "London Gatwick", BOM: "Mumbai", GOI: "Goa" }, photo: { LHR: "London", LGW: "London" } };

describe("Photos", () => {
  it("the destinations: every airport a rotation touches, its flights a week at both ends, busiest first (the first met first on a tie)", () => {
    const d = destinations([{ hub: "DEL", dest: "BOM", days: 7 }, { hub: "DEL", dest: "GOI", days: 3 }, { hub: "BOM", dest: "GOI", days: 0 }],
      new Map([["DEL", "Delhi"], ["BOM", "Mumbai (Chhatrapati Shivaji)"], ["GOI", "Dabolim, Goa"]]), lists.name);
    expect(d.map((x) => `${x.code} ${x.n} ${x.city}`)).toEqual(["BOM 14 Mumbai", "DEL 10 Delhi", "GOI 10 Goa"]);
  });
  it("an airport's name: the website's own (the data's list), else its city without brackets or what follows a comma, else its code", () => {
    expect([cityOf("LGW", "Crawley", lists.name), cityOf("XYZ", "Somewhere (North), Region", lists.name), cityOf("QQQ", null, lists.name)])
      .toEqual(["London Gatwick", "Somewhere", "QQQ"]);
  });
  it("a photo: the airport's own (uploaded or free-licensed, removable), else its city's (the data's list; not removable), else none", () => {
    const media: Media = { photos: { London: { url: "https://x/london.jpg", creator: "A" } }, airports: { LGW: { url: "https://x/lgw.jpg", uploaded: true, path: "airports/LGW-1.jpg" } },
      cities: lists };
    expect(photoOf(media, "LGW")).toEqual({ url: "https://x/lgw.jpg", kind: "Uploaded", credit: "", removable: true });
    expect(photoOf(media, "LHR")).toEqual({ url: "https://x/london.jpg", kind: "City photo", credit: "A", removable: false });
    expect(photoOf(media, "BOM")).toBeNull();
    expect(photoOf({ ...media, cities: undefined }, "LHR")).toBeNull();
  });
  it("uploads: their names in the bucket, and their size, never enlarged", () => {
    expect(photoPath("LGW", 1760000000000)).toBe("airports/LGW-1760000000000.jpg");
    expect(logoPath("Virgin Atlantic", 5)).toBe("logos/virgin-atlantic-5.png");
    expect(fitWidth(3200, 2400, 1600)).toEqual({ width: 1600, height: 1200 });
    expect(fitWidth(800, 600, 1600)).toEqual({ width: 800, height: 600 });
  });
});

// Nothing visible moves (spec 2026-10-15 last leftovers §2): with the lists exactly as the migration puts them in
// site_content (database/migrations/20261015220000_last_leftovers.sql), every airport gets the name and photo this screen
// and the website gave before they moved out of the code (tests/fixtures/airport_cities.expected.json, recorded at 7fc2a99
// on the test sample's media, each airport's city from web/assets/airports.json).
describe("Photos with the lists as data: the same as before for every airport", () => {
  const root = new URL("../../../../../", import.meta.url);
  const text = (path: string) => readFileSync(new URL(path, root), "utf8");
  const parts = text("database/migrations/20261015220000_last_leftovers.sql").split("$airport_cities$");
  const cities = JSON.parse(parts[1] ?? "null") as AirportCities;
  const want = (JSON.parse(text("tests/fixtures/airport_cities.expected.json")) as { airports: Record<string, [string, string | null]> }).airports;
  const ap = (JSON.parse(text("web/assets/airports.json")) as { ap: Record<string, [number, number, string, string, number]> }).ap;
  const sample = JSON.parse(gunzipSync(readFileSync(new URL("tests/fixtures/sample_2026-10-10.json.gz", root))).toString("utf8")) as
    { site_public: { content: { media: Media } } };
  it("the migration holds the lists once, and the recorded answers cover every airport", () => {
    expect(parts).toHaveLength(3);
    expect(Object.keys(cities.name).length).toBeGreaterThan(0);
    expect(Object.keys(cities.photo).length).toBeGreaterThan(0);
    expect(Object.keys(want).sort()).toEqual(Object.keys(ap).sort());
  });
  it("each airport's name and photo", () => {
    const media: Media = { ...sample.site_public.content.media, cities };
    const moved = Object.keys(want).filter((code) => {
      const got = [cityOf(code, ap[code]?.[2], cities.name), photoOf(media, code)?.url ?? null];
      return JSON.stringify(got) !== JSON.stringify(want[code]);
    });
    expect(moved).toEqual([]);
  });
});
