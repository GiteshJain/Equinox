// Photos' list and words (the old planner's eqDests, eqCity, eqPhotoOf and eqPhotosHTML; spec
// docs/specs/2026-10-14-interline-photos-reference.md). Plain data in, plain data out, so the unit tests can run it. The
// photos are the website's (site_public()'s content.media: city photos by city, destination photos by airport, airline
// logos by the planner's name); uploads go through the same storage bucket and functions the old screen uses
// (upload.ts).
//
// CITY_PHOTO and NAMES are the website's own lists (web/assets/site.js's CITYPHOTO and NAMES; the old planner kept the
// same copies, EQ_CITYPHOTO and EQ_NAMES): which city photo stands for an airport, and the name the website gives an
// airport. They're the website's words, not rule numbers; design §16 lists making them data, with the website's, after the
// switch.
export const CITY_PHOTO: Readonly<Record<string, string>> = {
  JFK: "New York", LGA: "New York", EWR: "New York", LHR: "London", LGW: "London", CDG: "Paris", AMS: "Amsterdam",
  DEL: "Delhi", BOM: "Mumbai", PVG: "Shanghai", PEK: "Beijing", PKX: "Beijing", KUL: "Kuala Lumpur",
  HKG: "Hong Kong", BKK: "Bangkok", DMK: "Bangkok", BCN: "Barcelona", FCO: "Rome", IST: "Istanbul", DPS: "Bali",
  HND: "Tokyo", NRT: "Tokyo", COK: "Kochi", CGK: "Jakarta", CAI: "Cairo", MAD: "Madrid", LIS: "Lisbon",
  ORD: "Chicago", EDI: "Edinburgh", DUB: "Dublin", VCE: "Venice", PRG: "Prague", HGH: "Hangzhou", GOI: "Goa",
  HKT: "Phuket", SIN: "Singapore"
};
export const NAMES: Readonly<Record<string, string>> = {
  CDG: "Paris", ORY: "Paris Orly", LHR: "London Heathrow", LGW: "London Gatwick", STN: "London Stansted",
  LTN: "London Luton", JFK: "New York JFK", EWR: "Newark", LGA: "New York LaGuardia", KUL: "Kuala Lumpur",
  MXP: "Milan", LIN: "Milan Linate", PVG: "Shanghai", SHA: "Shanghai Hongqiao", PEK: "Beijing",
  PKX: "Beijing Daxing", DEL: "Delhi", BOM: "Mumbai", HND: "Tokyo Haneda", NRT: "Tokyo Narita", BKK: "Bangkok",
  DMK: "Bangkok Don Mueang", XIY: "Xi'an", ORD: "Chicago", IAD: "Washington Dulles", DCA: "Washington",
  DFW: "Dallas–Fort Worth", MAN: "Manchester", EDI: "Edinburgh", AMS: "Amsterdam", KTI: "Phnom Penh", GOI: "Goa",
  COK: "Kochi", BLR: "Bengaluru", MAA: "Chennai", CCU: "Kolkata", HYD: "Hyderabad", SZX: "Shenzhen",
  CAN: "Guangzhou", KMG: "Kunming", CTU: "Chengdu", TFU: "Chengdu Tianfu", CKG: "Chongqing", HGH: "Hangzhou",
  ICN: "Seoul", CGK: "Jakarta", DPS: "Bali", SIN: "Singapore", HKG: "Hong Kong", MNL: "Manila",
  SGN: "Ho Chi Minh City", HAN: "Hanoi", IST: "Istanbul", CAI: "Cairo", DXB: "Dubai", FCO: "Rome", BCN: "Barcelona",
  MAD: "Madrid", LIS: "Lisbon", MUC: "Munich", FRA: "Frankfurt", ZRH: "Zurich", VIE: "Vienna", CPH: "Copenhagen",
  OSL: "Oslo", ARN: "Stockholm", DUB: "Dublin", BRU: "Brussels", PRG: "Prague", BUD: "Budapest", WAW: "Warsaw",
  KRK: "Krakow", ATH: "Athens", NCE: "Nice", LYS: "Lyon", MRS: "Marseille", TLS: "Toulouse", AGP: "Malaga",
  PMI: "Palma de Mallorca", VLC: "Valencia", OPO: "Porto", NAP: "Naples", VCE: "Venice", CGN: "Cologne",
  BER: "Berlin", GVA: "Geneva", YYZ: "Toronto", MEX: "Mexico City", CUN: "Cancún", LAX: "Los Angeles",
  SFO: "San Francisco", SEA: "Seattle", MIA: "Miami", ATL: "Atlanta", BOS: "Boston", DEN: "Denver", CLT: "Charlotte",
  DTW: "Detroit", BNA: "Nashville", MCO: "Orlando"
};

/** What site_public() gives under content.media. */
export interface Media {
  photos?: Record<string, { url: string; creator?: string | null }>;
  airports?: Record<string, { url: string; creator?: string | null; uploaded?: boolean; path?: string | null }>;
  logos?: Record<string, { url: string; path?: string | null }>;
}

/** An airport's name as the website gives it (the old eqCity): the website's own name, else the airport's city without
 *  anything in brackets or after a comma, else its code. */
export function cityOf(code: string, city: string | null | undefined): string {
  if (NAMES[code]) return NAMES[code];
  return city != null ? String(city).replace(/\s*\(.*$/, "").replace(/,.*$/, "") : code;
}

/** The destinations (the old eqDests): every airport a rotation flies to or from, with its flights a week (each
 *  rotation's days, at both ends; an airport's in the order first met), most first. */
export function destinations(rotations: readonly { hub: string; dest: string; days: number }[], cities: ReadonlyMap<string, string | null>):
  { code: string; n: number; city: string }[] {
  const w = new Map<string, number>();
  for (const f of rotations) {
    const n = f.days || 7;
    w.set(f.hub, (w.get(f.hub) ?? 0) + n);
    w.set(f.dest, (w.get(f.dest) ?? 0) + n);
  }
  return [...w].map(([code, n]) => ({ code, n, city: cities.has(code) ? cityOf(code, cities.get(code)) : NAMES[code] ?? code }))
    .map((d, i) => ({ d, i })).sort((a, b) => b.d.n - a.d.n || a.i - b.i).map((x) => x.d);
}

export interface PhotoOf { url: string; kind: "Uploaded" | "Free-licensed" | "City photo"; credit: string; removable: boolean }
/** An airport's photo on the website (the old eqPhotoOf): its own (uploaded, or free-licensed), else its city's. */
export function photoOf(media: Media, code: string): PhotoOf | null {
  const ap = media.airports?.[code];
  if (ap) return { url: ap.url, kind: ap.uploaded ? "Uploaded" : "Free-licensed", credit: ap.creator || "", removable: true };
  const k = CITY_PHOTO[code];
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

/** The words after an upload, as the old screen's note. */
export const photoLiveWords = (city: string) => `${city}'s photo is live on the website. A visitor who already has the site open sees it within a minute.`;
export const logoLiveWords = (airline: string) => `${airline}'s new logo is live on the website.`;
export const PREVIEW_WORDS = "This is a preview, so changes here aren't saved. Make this change on the live planner at equinox-alliance.com.";
