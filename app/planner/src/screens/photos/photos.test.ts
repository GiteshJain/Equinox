// Photos' list and words, as the old eqDests, eqCity and eqPhotoOf (the uploads themselves are tried in the rehearsal).
import { describe, expect, it } from "vitest";
import { cityOf, destinations, fitWidth, logoPath, photoOf, photoPath } from "./model";

describe("Photos", () => {
  it("the destinations: every airport a rotation touches, its flights a week at both ends, busiest first (the first met first on a tie)", () => {
    const d = destinations([{ hub: "DEL", dest: "BOM", days: 7 }, { hub: "DEL", dest: "GOI", days: 3 }, { hub: "BOM", dest: "GOI", days: 0 }],
      new Map([["DEL", "Delhi"], ["BOM", "Mumbai (Chhatrapati Shivaji)"], ["GOI", "Dabolim, Goa"]]));
    expect(d.map((x) => `${x.code} ${x.n} ${x.city}`)).toEqual(["BOM 14 Mumbai", "DEL 10 Delhi", "GOI 10 Goa"]);
  });
  it("an airport's name: the website's own, else its city without brackets or what follows a comma, else its code", () => {
    expect([cityOf("LGW", "Crawley"), cityOf("XYZ", "Somewhere (North), Region"), cityOf("QQQ", null)]).toEqual(["London Gatwick", "Somewhere", "QQQ"]);
  });
  it("a photo: the airport's own (uploaded or free-licensed, removable), else its city's (not removable), else none", () => {
    const media = { photos: { London: { url: "https://x/london.jpg", creator: "A" } }, airports: { LGW: { url: "https://x/lgw.jpg", uploaded: true, path: "airports/LGW-1.jpg" } } };
    expect(photoOf(media, "LGW")).toEqual({ url: "https://x/lgw.jpg", kind: "Uploaded", credit: "", removable: true });
    expect(photoOf(media, "LHR")).toEqual({ url: "https://x/london.jpg", kind: "City photo", credit: "A", removable: false });
    expect(photoOf(media, "BOM")).toBeNull();
  });
  it("uploads: their names in the bucket, and their size, never enlarged", () => {
    expect(photoPath("LGW", 1760000000000)).toBe("airports/LGW-1760000000000.jpg");
    expect(logoPath("Virgin Atlantic", 5)).toBe("logos/virgin-atlantic-5.png");
    expect(fitWidth(3200, 2400, 1600)).toEqual({ width: 1600, height: 1200 });
    expect(fitWidth(800, 600, 1600)).toEqual({ width: 800, height: 600 });
  });
});
