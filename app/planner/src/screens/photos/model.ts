// Photos' list and words (the old planner's eqDests, eqCity, eqPhotoOf and eqPhotosHTML; spec
// docs/specs/2026-10-14-interline-photos-reference.md). Plain data in, plain data out, so the unit tests can run it. The
// photos are the website's (site_public()'s content.media: city photos by city, destination photos by airport, airline
// logos by the planner's name); uploads go through the same storage bucket and functions the old screen uses
// (upload.ts).
//
// Which city's photo an airport takes and the name the website gives it are data since 15 Oct (spec
// docs/specs/2026-10-15-last-leftovers.md §2): site_content's airport_cities, which site_public() gives the website and
// this screen as content.airport_cities. Before, the website (web/assets/site.js, CITYPHOTO and NAMES) and this screen
// (CITY_PHOTO and NAMES) each kept the same lists in their code.

/** What site_public() gives under content.airport_cities: name, the name the website gives an airport; photo, the city
 *  whose photo (media.photos) an airport without its own takes. */
export interface AirportCities { name: Record<string, string>; photo: Record<string, string> }
export const NO_CITIES: AirportCities = { name: {}, photo: {} };

/** What site_public() gives under content.media, with content.airport_cities beside it (cities). */
export interface Media {
  photos?: Record<string, { url: string; creator?: string | null }>;
  airports?: Record<string, { url: string; creator?: string | null; uploaded?: boolean; path?: string | null }>;
  logos?: Record<string, { url: string; path?: string | null }>;
  cities?: AirportCities;
}

/** An airport's name as the website gives it (the old eqCity): the website's own name, else the airport's city without
 *  anything in brackets or after a comma, else its code. */
export function cityOf(code: string, city: string | null | undefined, names: Readonly<Record<string, string>>): string {
  if (names[code]) return names[code];
  return city != null ? String(city).replace(/\s*\(.*$/, "").replace(/,.*$/, "") : code;
}

/** The destinations (the old eqDests): every airport a rotation flies to or from, with its flights a week (each
 *  rotation's days, at both ends; an airport's in the order first met), most first. */
export function destinations(rotations: readonly { hub: string; dest: string; days: number }[], cities: ReadonlyMap<string, string | null>,
  names: Readonly<Record<string, string>>): { code: string; n: number; city: string }[] {
  const w = new Map<string, number>();
  for (const f of rotations) {
    const n = f.days || 7;
    w.set(f.hub, (w.get(f.hub) ?? 0) + n);
    w.set(f.dest, (w.get(f.dest) ?? 0) + n);
  }
  return [...w].map(([code, n]) => ({ code, n, city: cities.has(code) ? cityOf(code, cities.get(code), names) : names[code] ?? code }))
    .map((d, i) => ({ d, i })).sort((a, b) => b.d.n - a.d.n || a.i - b.i).map((x) => x.d);
}

export interface PhotoOf { url: string; kind: "Uploaded" | "Free-licensed" | "City photo"; credit: string; removable: boolean }
/** An airport's photo on the website (the old eqPhotoOf): its own (uploaded, or free-licensed), else its city's (the
 *  city content.airport_cities names for it). */
export function photoOf(media: Media, code: string): PhotoOf | null {
  const ap = media.airports?.[code];
  if (ap) return { url: ap.url, kind: ap.uploaded ? "Uploaded" : "Free-licensed", credit: ap.creator || "", removable: true };
  const k = media.cities?.photo[code];
  const p = k ? media.photos?.[k] : undefined;
  if (p) return { url: p.url, kind: "City photo", credit: p.creator || "", removable: false };
  return null;
}

/** Where an upload goes in the site-photos bucket, as the old screen named them. */
export const photoPath = (code: string, nowMs: number) => `airports/${code}-${nowMs}.jpg`;
export const logoPath = (airline: string, nowMs: number) => `logos/${airline.toLowerCase().replace(/[^a-z]+/g, "-")}-${nowMs}.png`;
/** The longest side an upload keeps (the old screen's: 1,600 px for a photo, 1,200 for a logo), never enlarged. */
export const PHOTO_WIDTH = 1600;
export const LOGO_WIDTH = 1200;
export function fitWidth(width: number, height: number, max: number): { width: number; height: number } {
  const k = Math.min(1, max / width);
  return { width: Math.round(width * k), height: Math.round(height * k) };
}

/** The screen's answer, its title (since 23 Oct, spec docs/specs/2026-10-23-planner-look-photos.md): how many destinations
 *  have no photo, or that every one has. */
export const photosTitle = (missing: number) =>
  missing === 0 ? "Every destination has a photo" : `${missing} destination${missing === 1 ? "" : "s"} missing a photo`;

/** The words after an upload, as the old screen's note. */
export const photoLiveWords = (city: string) => `${city}'s photo is live on the website. A visitor who already has the site open sees it within a minute.`;
export const logoLiveWords = (airline: string) => `${airline}'s new logo is live on the website.`;
export const PREVIEW_WORDS = "This is a preview, so changes here aren't saved. Make this change on the live planner at equinox-alliance.com.";
