// The network map's drawing helpers, ported from the old planner's Home (web/planner/index.html: gcPath, nightPolygon,
// clampView, zoomMap, mapPoint, focusAirline and networkMap's load colours). The map is an equirectangular 1000 × 500
// box; the world outline is the website's (web/assets/world.js). Positions only: every figure (routes, round trips,
// loads) comes from the library or the database.

export const MAPW = 1000, MAPH = 500;

export type LatLon = readonly [number, number];
export interface MapView { x: number; y: number; w: number; h: number }

/** A place on the map: x from the longitude, y from the latitude. */
export const toMap = (c: LatLon, W = MAPW, H = MAPH): [number, number] => [(c[1] + 180) / 360 * W, (90 - c[0]) / 180 * H];

/** The great-circle polyline between two [lat, lon] points, split at the dateline (the old gcPath). */
export function gcPath(a: LatLon, b: LatLon, W = MAPW, H = MAPH): string {
  const r = Math.PI / 180, la1 = a[0] * r, lo1 = a[1] * r, la2 = b[0] * r, lo2 = b[1] * r;
  const d = 2 * Math.asin(Math.sqrt(Math.sin((la2 - la1) / 2) ** 2 + Math.cos(la1) * Math.cos(la2) * Math.sin((lo2 - lo1) / 2) ** 2));
  if (!d) return "";
  const n = Math.max(8, Math.min(48, Math.round(d / r / 4)));
  let out = "", prev: number | null = null, pen = "M";
  for (let i = 0; i <= n; i++) {
    const f = i / n, A = Math.sin((1 - f) * d) / Math.sin(d), B = Math.sin(f * d) / Math.sin(d);
    const x = A * Math.cos(la1) * Math.cos(lo1) + B * Math.cos(la2) * Math.cos(lo2), y = A * Math.cos(la1) * Math.sin(lo1) + B * Math.cos(la2) * Math.sin(lo2);
    const z = A * Math.sin(la1) + B * Math.sin(la2);
    const lat = Math.atan2(z, Math.sqrt(x * x + y * y)) / r, lon = Math.atan2(y, x) / r;
    if (prev !== null && Math.abs(lon - prev) > 180) pen = "M";
    out += `${pen}${((lon + 180) / 360 * W).toFixed(1)},${((90 - lat) / 180 * H).toFixed(1)}`;
    pen = "L";
    prev = lon;
  }
  return out;
}

/** The night side as a polygon at a moment (the old nightPolygon): the terminator every 3° and the polar cap in night. */
export function nightPolygon(now: Date, W = MAPW, H = MAPH): string {
  const r = Math.PI / 180, doy = (now.getTime() - Date.UTC(now.getUTCFullYear(), 0, 0)) / 864e5;
  let decl = -23.44 * Math.cos(2 * Math.PI / 365 * (doy + 10));
  if (Math.abs(decl) < 0.05) decl = decl < 0 ? -0.05 : 0.05;
  const subLon = 180 - 15 * (now.getUTCHours() + now.getUTCMinutes() / 60);
  const pts: [number, number][] = [];
  for (let lon = -180; lon <= 180; lon += 3) pts.push([lon, Math.atan(-Math.cos((lon - subLon) * r) / Math.tan(decl * r)) / r]);
  const pole = decl > 0 ? -90 : 90;
  pts.push([180, pole], [-180, pole]);
  return pts.map(([lon, lat]) => `${((lon + 180) / 360 * W).toFixed(1)},${((90 - lat) / 180 * H).toFixed(1)}`).join(" ");
}

/** Keeps a view inside the map, between a tenth of its width and all of it (the old clampView). */
export function clampView(v: MapView): MapView {
  const w = Math.max(90, Math.min(MAPW, v.w)), h = w / 2;
  return { w, h, x: Math.max(0, Math.min(MAPW - w, v.x)), y: Math.max(0, Math.min(MAPH - h, v.y)) };
}

/** The view after zooming by a factor around a point in map units (its middle when none), or null for the whole world. */
export function zoomView(view: MapView | null, factor: number, px?: number, py?: number): MapView | null {
  const v = view ? { ...view } : { x: 0, y: 0, w: MAPW, h: MAPH };
  const nw = v.w / factor, fx = px == null ? 0.5 : (px - v.x) / v.w, fy = py == null ? 0.5 : (py - v.y) / v.h;
  v.x = px == null ? v.x + (v.w - nw) / 2 : px - fx * nw;
  v.w = nw;
  v.h = nw / 2;
  v.y = py == null ? v.y + (v.h * factor - v.h) / 2 : py - fy * v.h;
  const c = clampView(v);
  return c.w >= MAPW - 1 ? null : c;
}

/** The map point under a place on the screen. */
export function mapPoint(rect: { left: number; top: number; width: number; height: number }, view: MapView | null, clientX: number, clientY: number): [number, number] {
  const v = view ?? { x: 0, y: 0, w: MAPW, h: MAPH };
  return [v.x + (clientX - rect.left) / rect.width * v.w, v.y + (clientY - rect.top) / rect.height * v.h];
}

/** The view that centres on an airline's busiest base and takes in its network (the old focusAirline). hub: that base;
 *  points: every airport of its flying routes. Null (the whole world) without a place for the base. */
export function focusView(hub: LatLon | undefined, points: readonly LatLon[]): MapView | null {
  if (!hub) return null;
  const [cx, cy] = toMap(hub);
  let reach = 0;
  for (const p of points) {
    const [x, y] = toMap(p);
    reach = Math.max(reach, Math.abs(x - cx), Math.abs(y - cy) * 2);
  }
  const w = Math.max(220, Math.min(MAPW, reach * 2.3 + 60));
  return clampView({ x: cx - w / 2, y: cy - w / 4, w, h: w / 2 });
}

/** A route's colour by its economy load over 7 days, with one airline picked (the old networkMap's loadCol). */
export const loadColor = (avg: number | null | undefined): string =>
  avg == null ? "#7E8BA3" : avg >= 95 ? "#3FB37F" : avg >= 85 ? "#E0B341" : avg >= 70 ? "#E8853A" : "#E0524B";

/** A route's line width by its round trips a day (the old networkMap). */
export const arcWidth = (perDay: number): string => (1.1 + Math.min(2.2, Math.max(0, perDay - 1) * 0.7)).toFixed(2);

/** Round trips a day as the old map's tip writes them: 2 or 1.4. */
export const perDayWords = (perDay: number): string => (perDay % 1 ? perDay.toFixed(1) : String(perDay));
