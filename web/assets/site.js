/* equinox. — public website */
(() => {
"use strict";
const SB_URL = "https://ulecwsyedvwcxgdzmhoq.supabase.co", SB_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsZWN3c3llZHZ3Y3hnZHptaG9xIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMTg5MzcsImV4cCI6MjEwNTc5NDkzN30.tC56dOgmPeYB3m58aDy4ADnnaZ3613P6MFp2pVXUj_Y";
// Our airlines' names, codes, colours and text. Since #13 (pull request 8) they come from the data, site_public().airlines
// (the airlines table): this copy is only the fallback for a feed without them.
let AL = {
  "Pan American": { name: "Pan Am", slug: "pan-am", code: "AW", color: "#2A8FD8", photo: "New York", region: "North America and across the Atlantic",
    blurb: "Pan Am is the group's airline for North America and the Atlantic. From New York JFK it connects the United States with Europe, Mexico and the Caribbean, and feeds the rest of the group through London and Paris.",
    role: "Transatlantic and the Americas" },
  "Virgin Atlantic": { name: "Virgin Atlantic", slug: "virgin-atlantic", code: "VS", color: "#8E1537", photo: "London", region: "the United Kingdom and Europe",
    blurb: "Virgin Atlantic flies the group's London network from Gatwick, with Manchester and Edinburgh as further bases, linking Britain with more than thirty European cities and with Pan Am across the Atlantic.",
    role: "London and Europe" },
  "Ryanair": { name: "Ryanair", slug: "ryanair", code: "FR", color: "#F1C21B", photo: "Paris", region: "Europe",
    blurb: "Ryanair flies Europe point to point from Paris CDG and Amsterdam, with simple fares, two aircraft types and quick turnarounds.",
    role: "Europe, point to point" },
  "Kingfisher": { name: "Kingfisher", slug: "kingfisher", code: "KF", color: "#D7263D", photo: "Delhi", region: "India and South Asia",
    blurb: "Kingfisher connects India from its Delhi hub, flying to cities across the country and long-haul from Delhi to London, Paris, Amsterdam and New York.",
    role: "India, South Asia and the long-haul links from Delhi" },
  "China Eastern": { name: "China Eastern", slug: "china-eastern", code: "MU", color: "#1C3F8C", photo: "Shanghai", region: "China and North-East Asia",
    blurb: "China Eastern flies across China from Shanghai Pudong, with bases at Xi'an, Kunming and Beijing Daxing. It links China with Japan, Korea, Taiwan, Hong Kong and South-East Asia.",
    role: "China and North-East Asia" },
  "Malaysia Airlines": { name: "Malaysia Airlines", slug: "malaysia-airlines", code: "MH", color: "#0F8C8C", photo: "Kuala Lumpur", region: "South-East Asia",
    blurb: "Malaysia Airlines connects China, India and South-East Asia through its Kuala Lumpur hub, linking around forty cities.",
    role: "South-East Asia and the KUL connecting hub" }
};
// The site's own order, west to east. The data's order (airlines.position) is the planner's, which differs, so the site
// keeps this one for the airlines it names; any other airline in the data follows, in the data's order.
const SITE_ORDER = ["Pan American", "Virgin Atlantic", "Ryanair", "Kingfisher", "China Eastern", "Malaysia Airlines"];
let ORDER = SITE_ORDER.slice();
const TYPE_SEATS = { "Airbus A321neo": 190, "Airbus A320neo": 165, "Airbus A321XLR": 160, "Airbus A350-900": 300, "Embraer E195-E2": 124 };
const TYPE = { "A321 NEO LIGHT": "Airbus A321neo", "A320NEO LIGHT": "Airbus A320neo", "A321XLR": "Airbus A321XLR", "A350-900ULR": "Airbus A350-900", "E195-E2": "Embraer E195-E2" };
// Which city's photo an airport takes (photo) and the name the site gives it (name): data since 15 Oct, site_public()'s
// content.airport_cities (site_content), shared with the planner's Photos screen. Before, both kept these lists in code.
let CITYPHOTO = {}, NAMES = {};
const REGION = c => ({ US: "Americas", CA: "Americas", MX: "Americas" })[c] || (/^(GB|IE|FR|DE|NL|BE|LU|CH|AT|IT|ES|PT|DK|NO|SE|FI|IS|PL|CZ|SK|HU|SI|HR|GR|CY|MT|RO|BG|EE|LV|LT|TR|RS|BA|ME|MK|AL)$/.test(c) ? "Europe"
  : /^(AE|QA|SA|OM|BH|KW|IL|JO|LB|EG|MA|TN|ZA|KE|ET|NG|GH|SN|TZ)$/.test(c) ? "Middle East and Africa" : /^(IN|PK|BD|LK|NP|MV|BT)$/.test(c) ? "South Asia"
  : /^(CN|HK|MO|TW|JP|KR|MN)$/.test(c) ? "China and North Asia" : /^(MY|SG|TH|ID|PH|VN|KH|LA|MM|BN|AU|NZ|FJ)$/.test(c) ? "South-East Asia and Oceania" : /^(BR|AR|CL|PE|CO|EC|CU|JM|DO|BS|PA|CR|GT)$/.test(c) ? "Americas" : "Other");
const DISCLAIMER = "equinox. is a fan-made, non-commercial project built for the online airline management game AirlineSim (Gander game world). Airline names, logos and trademarks belong to their respective owners and appear here only to identify the airlines as they exist inside the game. This site is not affiliated with, endorsed by or connected to any real airline. No real flights, tickets, fares or investments are offered: every schedule, figure and report is simulated. Everything on this site, from the design to the articles, newsletter and reports, is created entirely by AI.";
const RM = matchMedia("(prefers-reduced-motion: reduce)").matches;

// ---------- utilities ----------
const $ = (s, r = document) => r.querySelector(s), $$ = (s, r = document) => [...r.querySelectorAll(s)];
const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const hm = t => { const [h, m] = String(t || "0:0").split(":").map(Number); return h * 60 + (m || 0); };
const tm = m => { m = ((Math.round(m) % 1440) + 1440) % 1440; return String(Math.floor(m / 60)).padStart(2, "0") + ":" + String(m % 60).padStart(2, "0"); };
const dur = m => `${Math.floor(m / 60)}h ${String(Math.round(m % 60)).padStart(2, "0")}m`;
const fmtN = n => Number(n).toLocaleString("en-US");
const fmtM = (x, s = true) => (s && x >= 0 ? "+" : x < 0 ? "−" : "") + Math.abs(x).toFixed(2) + "M";
const niceDate = d => new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" });
const shortDate = d => new Date(d + (String(d).length === 10 ? "T12:00:00Z" : "")).toLocaleDateString("en-GB", { day: "numeric", month: "short" });
const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

// ---------- data ----------
let INV = null; let D = null, AP = {}, COUNTRIES = {}, LEGS = [], DEST = [], MEDIA = { photos: {}, videos: {} }, HUBS = [];
const photo = k => (MEDIA.photos[k] || null);
const photoUrl = k => photo(k) ? photo(k).url : null;
const video = k => MEDIA.videos[k] || null;
const apPhoto = c => (MEDIA.airports && MEDIA.airports[c] && MEDIA.airports[c].url) || (CITYPHOTO[c] && photoUrl(CITYPHOTO[c])) || null;
const apName = c => NAMES[c] || (AP[c] ? String(AP[c][2]).replace(/\s*\(.*$/, "").replace(/^Ingliston, /, "").replace(/,.*$/, "") : c);
const apCountry = c => (AP[c] ? COUNTRIES[AP[c][3]] || AP[c][3] : "");
const off = c => (AP[c] && AP[c][4] != null ? AP[c][4] : 0);
const logo = a => (MEDIA.logos && MEDIA.logos[a] && MEDIA.logos[a].url) || (window.EQ_LOGOS || {})[a] || "";   // an uploaded logo first, then the in-game one

async function load() {
  const cached = sessionStorage.getItem("eq_site_v1");
  const apP = fetch("/assets/airports.json").then(r => r.json());
  let data = null;
  if (cached) { try { const c = JSON.parse(cached); if (Date.now() - c.t < 60e3) data = c.d; } catch (e) {} }
  if (!data) {
    const r = await fetch(SB_URL + "/rest/v1/rpc/site_public", { method: "POST", headers: { apikey: SB_KEY, Authorization: "Bearer " + SB_KEY, "Content-Type": "application/json" }, body: "{}" });
    if (!r.ok) throw new Error("data " + r.status);
    data = await r.json(); try { sessionStorage.setItem("eq_site_v1", JSON.stringify({ t: Date.now(), d: data })); } catch (e) {}
  }
  const a = await apP; AP = a.ap; COUNTRIES = a.countries; D = data; MEDIA = (D.content && D.content.media) || MEDIA;
  const ac = (D.content && D.content.airport_cities) || {}; NAMES = ac.name || {}; CITYPHOTO = ac.photo || {};
  useAirlines(D.airlines); derive();
}
// The airlines from the data, when the feed has them; a field the data leaves empty keeps the copy's value.
function useAirlines(list) {
  if (!Array.isArray(list)) return;
  const al = {}, at = {};
  list.forEach((a, i) => {
    if (!a || !a.key) return; const c = AL[a.key] || {};
    al[a.key] = { name: a.name || c.name || a.key, slug: a.slug || c.slug || String(a.name || a.key).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, ""),
      code: a.code || c.code || "", color: a.color || c.color || "#9AA4BF", photo: a.photo || c.photo || "", region: a.region || c.region || "",
      blurb: a.blurb || c.blurb || "", role: a.role || c.role || "" };
    at[a.key] = i;
  });
  if (!Object.keys(al).length) return;
  const rank = k => SITE_ORDER.includes(k) ? SITE_ORDER.indexOf(k) : SITE_ORDER.length + at[k];
  AL = al; ORDER = Object.keys(al).sort((x, y) => rank(x) - rank(y));
}
function derive() {
  const tails = Object.fromEntries(D.tails.map(t => [t.id, t]));

  LEGS = [];
  for (const f of D.freqs) {
    const [al, hub, dest] = f.r.split("|"); const meta = AL[al]; if (!meta) continue;
    const t = tails[f.t] || {}; const type = TYPE[String(t.type || "").toUpperCase()] || t.type || ""; const seats = TYPE_SEATS[type] || 150;
    const days = new Set(String(f.days || "1234567").split("").map(Number));
    const mk = (no, from, to, dep, arr) => {
      const dl = hm(dep), al2 = hm(arr); let d = (al2 - off(to) * 60) - (dl - off(from) * 60); while (d <= 15) d += 1440; while (d > 1440 + 600) d -= 1440;
      return { al, code: meta.code, no: meta.code + no, from, to, dep: dl, arr: al2, dur: d, days, type, seats, tail: f.t, launched: f.l };
    };
    if (f.a && f.b) LEGS.push(mk(f.o, hub, dest, f.a, f.b));
    if (f.c && f.d) LEGS.push(mk(f.k, dest, hub, f.c, f.d));
  }
  const by = {};
  for (const l of LEGS) for (const c of [l.from, l.to]) {
    by[c] = by[c] || { code: c, als: new Set(), weekly: 0 }; by[c].als.add(l.al);
  }
  for (const l of LEGS) by[l.from].weekly += l.days.size;
  DEST = Object.values(by).map(d => ({ ...d, city: apName(d.code), country: apCountry(d.code), cc: AP[d.code] ? AP[d.code][3] : "", region: REGION(AP[d.code] ? AP[d.code][3] : "") })).sort((a, b) => b.weekly - a.weekly);
  HUBS = D.hubs.filter(h => h.role !== "focus" || true);
}
const boardHubs = () => { const w = c => LEGS.filter(l => l.from === c).reduce((a, l) => a + l.days.size, 0); const live = new Set(D.freqs.map(f => f.r.split("|")[0] + "|" + f.r.split("|")[1]));   // a hub counts once its own airline flies from it
  return [...new Set(D.hubs.filter(h => h.role !== "focus" && AL[h.airline] && live.has(h.airline + "|" + h.code)).map(h => h.code))].filter(c => AP[c]).sort((a, b) => w(b) - w(a)); };
const stats = al => {
  const legs = al ? LEGS.filter(l => l.al === al) : LEGS;
  const routes = new Set(D.freqs.filter(f => !al || f.r.startsWith(al + "|")).map(f => f.r)).size;
  const weekly = legs.reduce((a, l) => a + l.days.size, 0);
  const seats = legs.reduce((a, l) => a + l.days.size * l.seats, 0);
  const dests = new Set(legs.flatMap(l => [l.from, l.to])).size;
  const fleet = D.tails.filter(t => !al || t.airline === al).length;
  const onorder = (D.onorder || []).filter(o => !al || o.airline === al).length;
  return { routes, weekly, seats, dests, fleet, onorder };
};
// time helpers in UTC minutes since Monday 00:00 of the current UTC week
const nowWeekMin = () => { const n = new Date(); const dow = (n.getUTCDay() + 6) % 7; return dow * 1440 + n.getUTCHours() * 60 + n.getUTCMinutes() + n.getUTCSeconds() / 60; };
function airborne() {
  const now = nowWeekMin(), out = [];
  for (const l of LEGS) {
    for (const d of l.days) {
      const depU = (d - 1) * 1440 + l.dep - off(l.from) * 60;
      for (const w of [-10080, 0, 10080]) { const s = depU + w, p = (now - s) / l.dur; if (p > 0 && p < 1) out.push({ l, p }); }
    }
  }
  return out;
}

// ---------- globe (three.js) ----------
const DEG = Math.PI / 180;
function v3(lat, lon, r = 1) { const phi = (90 - lat) * DEG, th = (lon + 180) * DEG; return new THREE.Vector3(-r * Math.sin(phi) * Math.cos(th), r * Math.cos(phi), r * Math.sin(phi) * Math.sin(th)); }
function subsolar() { const n = new Date(); const start = Date.UTC(n.getUTCFullYear(), 0, 0); const doy = (n - start) / 864e5; const decl = -23.44 * Math.cos(2 * Math.PI / 365 * (doy + 10)); const hrs = n.getUTCHours() + n.getUTCMinutes() / 60; return [decl, (12 - hrs) * 15]; }
function makeGlobe(canvas, opts = {}) {
  if (!window.THREE) return null;
  const R = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
  R.setPixelRatio(Math.min(devicePixelRatio, opts.dpr || 1.8));
  const scene = new THREE.Scene(), cam = new THREE.PerspectiveCamera(32, 1, 0.1, 100);
  const world = new THREE.Group(); scene.add(world);
  const earthG = new THREE.Group(); world.add(earthG);
  const tl = new THREE.TextureLoader(); tl.setCrossOrigin("anonymous");
  const base = "https://cdn.jsdelivr.net/npm/three-globe@2.31.1/example/img/";
  const uni = { dayTex: { value: tl.load(base + "earth-day.jpg") }, nightTex: { value: tl.load(base + "earth-night.jpg") }, sun: { value: new THREE.Vector3(1, 0, 0) } };
  const earth = new THREE.Mesh(new THREE.SphereGeometry(1, 96, 96), new THREE.ShaderMaterial({ uniforms: uni,
    vertexShader: "varying vec2 vUv; varying vec3 vN; void main(){ vUv=uv; vN=normal; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);} ",
    fragmentShader: "uniform sampler2D dayTex; uniform sampler2D nightTex; uniform vec3 sun; varying vec2 vUv; varying vec3 vN; void main(){ float d=dot(normalize(vN),normalize(sun)); float k=smoothstep(-0.14,0.14,d); vec3 day=texture2D(dayTex,vUv).rgb*0.92; vec3 night=texture2D(nightTex,vUv).rgb*1.35+vec3(0.012,0.02,0.06); vec3 c=mix(night,day,k); float tw=exp(-pow(d/0.09,2.0)); c+=vec3(0.95,0.55,0.38)*tw*0.30; gl_FragColor=vec4(c,1.0);} " }));
  earthG.add(earth);
  const atmo = new THREE.Mesh(new THREE.SphereGeometry(1.085, 64, 64), new THREE.ShaderMaterial({ side: THREE.BackSide, blending: THREE.AdditiveBlending, transparent: true,
    vertexShader: "varying vec3 vN; void main(){ vN=normalize(normalMatrix*normal); gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);} ",
    fragmentShader: "varying vec3 vN; void main(){ float i=pow(0.72-dot(vN,vec3(0,0,1.0)),3.2); gl_FragColor=vec4(0.36,0.48,1.0,1.0)*i*1.2;} " }));
  world.add(atmo);
  // routes
  const routeGeo = {}, colorOf = a => new THREE.Color((AL[a] || {}).color || "#ffffff");
  const lines = new THREE.Group(); earthG.add(lines);
  const curve = (a, b, n = 48) => {
    const A = v3(AP[a][0], AP[a][1]).normalize(), B = v3(AP[b][0], AP[b][1]).normalize(); const ang = A.angleTo(B); const pts = [];
    for (let i = 0; i <= n; i++) { const t = i / n; const s = Math.sin(ang); const p = s < 1e-6 ? A.clone() : A.clone().multiplyScalar(Math.sin((1 - t) * ang) / s).add(B.clone().multiplyScalar(Math.sin(t * ang) / s)); p.multiplyScalar(1.003 + (0.012 + 0.10 * ang / Math.PI) * Math.sin(Math.PI * t)); pts.push(p); }
    return pts;
  };
  const seen = new Set(), byAl = {};
  for (const f of D.freqs) {
    const [al, h, d] = f.r.split("|"); if (!AP[h] || !AP[d] || seen.has(f.r)) continue; seen.add(f.r);
    const pts = curve(h, d); routeGeo[h + d] = pts; routeGeo[d + h] = pts.slice().reverse();
    const cv = new THREE.CatmullRomCurve3(pts);   // silver hairlines
    const m = new THREE.Mesh(new THREE.TubeGeometry(cv, 64, opts.lineW || 0.0013, 5, false), new THREE.MeshBasicMaterial({ color: new THREE.Color("#DCE3F5"), transparent: true, opacity: 0.42, depthWrite: false }));
    m.userData.al = al; lines.add(m); (byAl[al] = byAl[al] || []).push(m);
  }
  // live aircraft
  const spr = (() => { const c = document.createElement("canvas"); c.width = c.height = 64; const x = c.getContext("2d"); const g = x.createRadialGradient(32, 32, 0, 32, 32, 32); g.addColorStop(0, "rgba(255,255,255,1)"); g.addColorStop(.25, "rgba(255,255,255,.85)"); g.addColorStop(1, "rgba(255,255,255,0)"); x.fillStyle = g; x.fillRect(0, 0, 64, 64); return new THREE.CanvasTexture(c); })();
  const planeGeo = new THREE.BufferGeometry(); const planeMat = new THREE.PointsMaterial({ size: opts.planeSize || 0.05, map: spr, vertexColors: true, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending });
  const planes = new THREE.Points(planeGeo, planeMat); earthG.add(planes);
  let hidden = new Set(), airCount = 0;
  const updatePlanes = () => {
    const air = airborne().filter(x => !hidden.has(x.l.al)); airCount = air.length;
    const pos = [], col = [];
    for (const { l, p } of air) { const pts = routeGeo[l.from + l.to]; if (!pts) continue; const i = p * (pts.length - 1), a = Math.floor(i), b = Math.min(a + 1, pts.length - 1); const q = pts[a].clone().lerp(pts[b], i - a); pos.push(q.x, q.y, q.z); col.push(1, 1, 1); }
    planeGeo.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3)); planeGeo.setAttribute("color", new THREE.Float32BufferAttribute(col, 3)); planeGeo.computeBoundingSphere();
    if (opts.onCount) opts.onCount(airCount);
  };
  // hub markers
  const hubCodes = [...new Set(D.hubs.map(h => h.code))].filter(c => AP[c]);
  const hubGeo = new THREE.BufferGeometry().setFromPoints(hubCodes.map(c => v3(AP[c][0], AP[c][1], 1.006)));
  earthG.add(new THREE.Points(hubGeo, new THREE.PointsMaterial({ size: 0.045, map: spr, color: 0xFFE2A8, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending })));
  const labels = [];
  if (opts.labels) for (const c of hubCodes) { const e = document.createElement("div"); e.className = "hublabel"; e.textContent = c; canvas.parentElement.appendChild(e); labels.push({ e, v: v3(AP[c][0], AP[c][1], 1.01) }); }
  // sun & motion
  const setSun = () => { const [la, lo] = subsolar(); uni.sun.value.copy(v3(la, lo)); };
  setSun(); updatePlanes();
  let rotY = -(opts.lon ?? 75) * DEG - Math.PI / 2, rotX = (opts.tilt ?? 18) * DEG, vY = 0, drag = null;
  earthG.rotation.order = "YXZ";
  const el = canvas;
  el.addEventListener("pointerdown", e => { drag = { x: e.clientX, y: e.clientY, ry: rotY, rx: rotX }; el.setPointerCapture(e.pointerId); el.style.cursor = "grabbing"; });
  el.addEventListener("pointermove", e => { if (!drag) return; const dx = (e.clientX - drag.x) / el.clientWidth, dy = (e.clientY - drag.y) / el.clientHeight; vY = dx * 2.6 - (rotY - drag.ry); rotY = drag.ry + dx * 3.2; rotX = Math.max(-0.6, Math.min(0.9, drag.rx + dy * 1.6)); });
  const end = () => { drag = null; el.style.cursor = "grab"; }; el.addEventListener("pointerup", end); el.addEventListener("pointercancel", end); el.style.cursor = "grab"; el.style.touchAction = "pan-y";
  const resize = () => { const w = el.clientWidth, h = el.clientHeight; R.setSize(w, h, false); cam.aspect = w / h; const z = opts.zoom || 3.4; cam.position.set(0, 0, w < 700 ? z * 1.35 : z); cam.updateProjectionMatrix(); world.position.x = w > 900 ? (opts.offsetX || 0) : 0; world.position.y = w > 900 ? 0 : (opts.offsetYMobile || 0); };
  resize(); const ro = new ResizeObserver(resize); ro.observe(el);
  let raf = 0, last = performance.now(), tick = 0, alive = true, onScreen = true;
  const vis = new IntersectionObserver(es => { onScreen = es[0].isIntersecting; }, { threshold: 0 }); vis.observe(el);
  const proj = new THREE.Vector3(), camDir = new THREE.Vector3();
  const loop = t => {
    if (!alive) return; raf = requestAnimationFrame(loop);
    if (!onScreen || document.hidden) { last = t; return; }   // nothing to draw: save the battery
    const dt = Math.min(64, t - last); last = t;
    if (!drag && !RM) rotY += (opts.spin ?? 0.00006) * dt + vY * 0.02, vY *= 0.94;
    earthG.rotation.y = rotY; earthG.rotation.x = rotX;
    if ((tick += dt) > 4000) { tick = 0; setSun(); updatePlanes(); }
    R.render(scene, cam);
    if (labels.length) { const w = el.clientWidth, h = el.clientHeight; cam.getWorldDirection(camDir); for (const L of labels) { const p = L.v.clone().applyMatrix4(earthG.matrixWorld); const facing = p.clone().normalize().dot(cam.position.clone().sub(p).normalize()) > 0.15; proj.copy(p).project(cam); L.e.style.left = ((proj.x + 1) / 2 * w) + "px"; L.e.style.top = ((1 - proj.y) / 2 * h) + "px"; L.e.style.opacity = facing ? 1 : 0; } }
  };
  raf = requestAnimationFrame(loop);
  return { destroy() { alive = false; cancelAnimationFrame(raf); ro.disconnect(); vis.disconnect(); R.dispose(); labels.forEach(l => l.e.remove()); }, filter(al, on) { (byAl[al] || []).forEach(m => m.visible = on); on ? hidden.delete(al) : hidden.add(al); updatePlanes(); }, count: () => airCount };
}

// ---------- shell: nav, footer, modal ----------
function shell() {
  document.body.insertAdjacentHTML("afterbegin", `
  <a class="sr" href="#main">Skip to content</a>
  <header class="nav on-dark" id="nav">
    <a href="/" data-link aria-label="equinox. home" class="wm">equinox<i class="dot"></i></a>
    <nav class="links" aria-label="Main">
      <a href="/flights" data-link>Flights</a><a href="/destinations" data-link>Destinations</a><a href="/network" data-link>Network</a>
      <a href="/airlines" data-link>Our airlines</a><a href="/news" data-link>Newsroom</a><a href="/investors" data-link>Investors</a>
    </nav>
    <a class="btn sun staff" href="/planner/">Staff login</a>
    <button class="burger" aria-label="Open menu" id="burger"><span></span><span></span></button>
  </header>
  <div class="sheet" id="sheet"><a href="/flights" data-link>Flights</a><a href="/destinations" data-link>Destinations</a><a href="/network" data-link>Network</a><a href="/airlines" data-link>Our airlines</a><a href="/news" data-link>Newsroom</a><a href="/newsletter" data-link>gander monthly</a><a href="/investors" data-link>Investors</a><a href="/about" data-link>About</a><a href="/planner/">Staff login</a></div>
  <main id="main"></main>
  <footer class="foot" data-nav="dark">
    <div class="wrap">
      <p class="big wm" aria-hidden="true">equinox<i class="dot"></i></p>
      <div class="cols">
        <div><p class="small" style="max-width:36ch;color:#AEB7D2">Six airlines, one network. Planned around the sun, flown in AirlineSim's Gander world.</p></div>
        <div><h5>Fly</h5><a href="/flights" data-link>Flight schedules</a><a href="/destinations" data-link>Destinations</a><a href="/network" data-link>Live network</a></div>
        <div><h5>Group</h5><a href="/airlines" data-link>Our airlines</a><a href="/news" data-link>Newsroom</a><a href="/newsletter" data-link>gander monthly</a><a href="/about" data-link>About equinox.</a></div>
        <div><h5>Investors</h5><a href="/investors" data-link>Investor relations</a><a href="/investors#reports" data-link>Reports</a><a href="/planner/">Staff login</a></div>
      </div>
      <div class="disc"><p>Fan-made and non-commercial, for the game AirlineSim. Airline names and logos belong to their owners and identify in-game airlines only; not affiliated with or endorsed by any real airline. No real flights, fares or investments. Created entirely by AI. <a href="/about#disclaimer" data-link style="display:inline;color:#fff">Read the full disclaimer</a>.</p><p>© ${new Date().getFullYear()} equinox.</p></div>
    </div>
  </footer>
  <div class="veil" id="veil"></div>
  <div class="modal" id="disc" role="dialog" aria-modal="true" aria-labelledby="disc-t"><div class="box"><span class="wm" style="font-size:20px">equinox<i class="dot"></i></span><h2 id="disc-t" style="margin-top:22px">Before you board</h2><p>${esc(DISCLAIMER)}</p><div class="row"><button class="btn solid" id="disc-ok">Continue to the site</button><a class="btn ghost" href="/about#disclaimer" data-link id="disc-more">Read more</a></div></div></div>`);
  $("#burger").onclick = () => { const s = $("#sheet"); const o = !s.classList.contains("open"); s.classList.toggle("open", o); document.body.style.overflow = o ? "hidden" : ""; };
  if (!sessionStorage.getItem("eq_disc_ok")) setTimeout(() => $("#disc").classList.add("open"), 1600);
  const close = () => { sessionStorage.setItem("eq_disc_ok", "1"); $("#disc").classList.remove("open"); };
  $("#disc-ok").onclick = close; $("#disc-more").addEventListener("click", close);
}

// ---------- components ----------
const logoImg = (a, h = 32) => logo(a) ? `<img src="${logo(a)}" alt="${esc(AL[a].name)}" style="max-height:${h}px;width:auto">` : `<b>${esc(AL[a].name)}</b>`;
const alChip = a => `<span class="chip-al"><i style="background:${AL[a].color}"></i>${esc(AL[a].name)}</span>`;
function searchPanel(opts = {}) {
  const d = opts.date || new Date().toISOString().slice(0, 10);
  return `<form class="search" data-search autocomplete="off">
    <div class="field"><label for="s-from">From</label><input id="s-from" name="from" placeholder="City or airport" value="${esc(opts.from || "")}" required><div class="ac" data-lenis-prevent></div></div>
    <div class="field"><label for="s-to">To</label><input id="s-to" name="to" placeholder="City or airport" value="${esc(opts.to || "")}" required><div class="ac" data-lenis-prevent></div></div>
    <div class="field"><label for="s-date">Date</label><input id="s-date" name="date" type="date" value="${d}"></div>
    <button class="btn sun" type="submit">Find flights</button></form>`;
}
function wireSearch(root, onSubmit) {
  const form = $("[data-search]", root); if (!form) return;
  const pool = DEST.map(d => ({ code: d.code, city: d.city, country: d.country }));
  for (const inp of $$("input[name=from], input[name=to]", form)) {
    const box = inp.parentElement.querySelector(".ac"); let idx = -1, list = [];
    const show = () => {
      const q = inp.value.trim().toLowerCase(); idx = -1;
      list = (q ? pool.filter(p => p.code.toLowerCase().startsWith(q) || p.city.toLowerCase().includes(q) || String(p.country).toLowerCase().startsWith(q)) : pool).slice(0, 8);
      box.innerHTML = list.map((p, i) => `<button type="button" data-i="${i}"><b>${p.code}</b><span>${esc(p.city)}<small>${esc(p.country)}</small></span></button>`).join("");
      box.classList.toggle("open", list.length > 0 && document.activeElement === inp);
    };
    const pick = i => { const p = list[i]; if (!p) return; inp.value = `${p.city} (${p.code})`; inp.dataset.code = p.code; box.classList.remove("open"); };
    inp.addEventListener("input", () => { delete inp.dataset.code; show(); });
    inp.addEventListener("focus", show);
    inp.addEventListener("blur", () => setTimeout(() => box.classList.remove("open"), 160));
    inp.addEventListener("keydown", e => { if (!box.classList.contains("open")) return; if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); idx = Math.max(0, Math.min(list.length - 1, idx + (e.key === "ArrowDown" ? 1 : -1))); $$("button", box).forEach((b, i) => b.classList.toggle("on", i === idx)); } if (e.key === "Enter" && idx >= 0) { e.preventDefault(); pick(idx); } });
    box.addEventListener("mousedown", e => { const b = e.target.closest("button"); if (b) { e.preventDefault(); pick(+b.dataset.i); } });
  }
  form.addEventListener("submit", e => { e.preventDefault(); const code = inp => inp.dataset.code || resolveCode(inp.value); const f = code($("input[name=from]", form)), t = code($("input[name=to]", form)); onSubmit({ from: f, to: t, date: $("input[name=date]", form).value }); });
}
function resolveCode(v) { const m = String(v).match(/\(([A-Z0-9]{3})\)/); if (m) return m[1]; const q = String(v).trim().toLowerCase(); const d = DEST.find(d => d.code.toLowerCase() === q) || DEST.find(d => d.city.toLowerCase() === q) || DEST.find(d => d.city.toLowerCase().startsWith(q)); return d ? d.code : String(v).trim().toUpperCase(); }

// trip search: direct, one stop and two stops through group hubs, timed with real transfer windows. Every transfer uses
// the planning library's connection test (web/assets/rules.js, #19): at least the airport's own minimum connection time
// (from the game; 90 minutes where unknown) and at most the feed's connection_max_wait_h hours (manual §4; 8 on a feed
// without it).
function findTrips(A, B, dateStr) {
  const date = new Date(dateStr + "T00:00:00Z"); const w = (date.getUTCDay() + 6) % 7 + 1;
  const hubSet = new Set(D.hubs.map(h => h.code)); const C = (D.content || {}); const MCT = C.mct || {};
  const mw = C.connection_max_wait_h, maxWait = mw != null && mw !== "" && Number.isFinite(Number(mw)) ? Number(mw) : 8;
  const R = window.EqRules.connections; const lim = c => R.limitsFrom(MCT[c], maxWait);
  const legAt = (l, dayOffset) => { const depU = dayOffset * 1440 + l.dep - off(l.from) * 60; return { l, depU, arrU: depU + l.dur }; };
  const fromA = LEGS.filter(l => l.from === A && l.days.has(w)).map(l => legAt(l, 0));
  const next = (x, dest, wantTo) => {   // departures from x.l.to after arrival that make a valid connection
    const out = [], arr = x.arrU, at = x.l.to, L = lim(at);
    for (const l of LEGS) { if (l.from !== at || l.to === x.l.from || (wantTo && l.to !== wantTo)) continue; for (let k = -1; k <= 2; k++) { const dayW = ((w - 1 + k) % 7 + 7) % 7 + 1; if (!l.days.has(dayW)) continue; const y = legAt(l, k); if (R.isConnection(y.depU - arr, L)) out.push(y); } }
    return out;
  };
  const trips = [];
  for (const x of fromA) if (x.l.to === B) trips.push([x]);
  for (const x of fromA) if (x.l.to !== B) for (const y of next(x, B, B)) trips.push([x, y]);
  if (trips.length < 4) for (const x of fromA) if (x.l.to !== B && hubSet.has(x.l.to)) for (const y of next(x, null, null)) if (y.l.to !== B && y.l.to !== A && hubSet.has(y.l.to)) for (const z of next(y, B, B)) trips.push([x, y, z]);
  const seen = new Set();
  return trips.map(t => ({ legs: t, total: t[t.length - 1].arrU - t[0].depU })).filter(t => { const k = t.legs.map(x => x.l.no).join(); if (seen.has(k)) return false; seen.add(k); return true; })
    .sort((a, b) => a.legs.length - b.legs.length || a.total - b.total).slice(0, 12);
}
function tripCard(t, dateStr) {
  const f = t.legs[0], z = t.legs[t.legs.length - 1];
  const localDayShift = (u, c) => Math.floor((u + off(c) * 60) / 1440);
  const plus = localDayShift(z.arrU, z.l.to) - localDayShift(f.depU, f.l.from);
  const stopsTxt = t.legs.length === 1 ? "Direct" : `${t.legs.length - 1} stop${t.legs.length > 2 ? "s" : ""} via ${t.legs.slice(0, -1).map(x => x.l.to).join(", ")}`;
  return `<article class="trip">
    <div class="when"><div><b>${tm(f.l.dep)}</b><small>${f.l.from}</small></div><div class="path">${t.legs.slice(0, -1).map((_, i) => `<i style="left:${(i + 1) / t.legs.length * 100}%"></i>`).join("")}</div><div><b>${tm(z.l.arr)}${plus > 0 ? `<sup style="font-size:13px">+${plus}</sup>` : ""}</b><small>${z.l.to}</small></div></div>
    <div class="legs">${t.legs.map((x, i) => `<div class="lg">${alChip(x.l.al)}<b>${x.l.no}</b><span>${x.l.from} ${tm(x.l.dep)} to ${x.l.to} ${tm(x.l.arr)}</span><span>${esc(x.l.type)}</span></div>${i < t.legs.length - 1 ? `<div class="conn">Change in ${esc(apName(x.l.to))}: ${dur(t.legs[i + 1].depU - x.arrU)}</div>` : ""}`).join("")}</div>
    <div class="dur"><b>${dur(t.total)}</b>${stopsTxt}</div></article>`;
}
function departures(code, n = 9) {
  const now = new Date(), loc = now.getUTCHours() * 60 + now.getUTCMinutes() + off(code) * 60; const dow = ((now.getUTCDay() + 6) % 7) + 1;
  const items = [];
  for (const l of LEGS.filter(l => l.from === code)) for (const k of [0, 1]) { const dw = ((dow - 1 + k) % 7) + 1; if (!l.days.has(dw)) continue; const t = l.dep + k * 1440; const loc2 = ((loc % 1440) + 1440) % 1440; const delta = t - loc2; if (delta > -25 && delta < 20 * 60) items.push({ l, delta, t }); }
  items.sort((a, b) => a.delta - b.delta);
  return { local: ((loc % 1440) + 1440) % 1440, rows: items.slice(0, n) };
}
function boardHTML(codes, active) {
  return `<div class="board" data-board><div class="tabs" role="tablist" data-lenis-prevent>${codes.map(c => `<button role="tab" data-hub="${c}" class="${c === active ? "on" : ""}">${esc(apName(c))} <span style="opacity:.6">${c}</span></button>`).join("")}</div><div data-board-body></div></div>`;
}
function renderBoard(root, code) {
  const { local, rows } = departures(code);
  $("[data-board-body]", root).innerHTML = `<div class="clock"><span>Departures from ${esc(apName(code))}, local time</span><b>${tm(local)}</b></div>
   <table><thead><tr><th>Time</th><th>Flight</th><th>To</th><th class="hide-s">Aircraft</th><th>Status</th></tr></thead><tbody>
   ${rows.length ? rows.map((r, i) => { const st = r.delta < 0 ? ["gone", "Departed"] : r.delta < 40 ? ["boarding", "Boarding"] : ["", r.delta < 90 ? "On time" : "Scheduled"]; return `<tr><td class="t"><span class="flap" style="animation-delay:${i * 40}ms">${tm(r.l.dep)}</span></td><td>${alChip(r.l.al)} <span style="opacity:.7;margin-left:6px">${r.l.no}</span></td><td class="dest">${esc(apName(r.l.to))}</td><td class="hide-s" style="color:#9AA4C4">${esc(r.l.type)}</td><td><span class="st ${st[0]}">${st[1]}</span></td></tr>`; }).join("") : `<tr><td colspan="5" style="color:#9AA4C4">No departures in the next hours.</td></tr>`}
   </tbody></table>`;
}
function wireBoard(root, codes) {
  const b = $("[data-board]", root); if (!b || !codes.length) return; let cur = codes[0], manual = false, hover = false; const tabs = $(".tabs", b);
  const go = c => { cur = c; $$(".tabs button", b).forEach(x => { const on = x.dataset.hub === c; x.classList.toggle("on", on); if (on) tabs.scrollTo({ left: x.offsetLeft - tabs.clientWidth / 2 + x.clientWidth / 2, behavior: RM ? "auto" : "smooth" }); }); renderBoard(b, c); };
  $$(".tabs button", b).forEach(x => x.onclick = () => { manual = true; b.classList.add("held"); go(x.dataset.hub); });
  b.addEventListener("pointerenter", () => hover = true); b.addEventListener("pointerleave", () => hover = false);
  go(cur);
  const iv = setInterval(() => { if (!document.body.contains(b)) return clearInterval(iv); renderBoard(b, cur); }, 30000);
  const cyc = setInterval(() => { if (!document.body.contains(b)) return clearInterval(cyc); if (manual || hover || document.hidden || RM) return; go(codes[(codes.indexOf(cur) + 1) % codes.length]); }, 15000);
}
const postCard = (p, cls = "") => `<a class="post ${cls}" href="/news/${p.slug}" data-link>${p.image ? `<div class="ph"><img loading="lazy" src="${imgOf(p.image)}" alt=""></div>` : ""}<div class="tx"><div class="meta"><span class="tag">${esc(p.tag || "News")}</span><span>${niceDate(p.at)}</span></div><h3>${esc(p.title)}</h3><p>${esc(p.summary || "")}</p></div></a>`;
const nlFeature = () => { const i = (D.reports || []).find(r => r.kind === "newsletter" && r.status === "published"); if (!i) return ""; return `<a class="nl-feature" href="/newsletter" data-link><div class="nlf-cover"><span>gander monthly</span><b>${esc((i.title.split(":")[0] || "").replace("gander monthly, ", ""))}</b><i></i></div><div class="nlf-tx"><p class="kick" style="color:#F6B44B;margin:0">Newsletter</p><h3>gander monthly</h3><p>${esc(i.summary || "")}</p><span class="btn sun">Read ${esc((i.title.split(":")[0] || "").replace("gander monthly, ", "") || "the latest issue")}</span></div></a>`; };
const imgOf = k => String(k).startsWith("photo:") ? photoUrl(k.slice(6)) || "" : k;
function videoTag(k, cls = "") { const v = video(k); return v ? `<video class="${cls}" autoplay muted loop playsinline preload="metadata" poster="${v.poster}"><source src="${v.url}" type="video/mp4"></video>` : ""; }

// ---------- PDF viewer (pdf.js renders the pages, so it works on phones too) ----------
async function loadPdfJs() {
  if (window.pdfjsLib) return window.pdfjsLib;
  await new Promise((res, rej) => { const s = document.createElement("script"); s.src = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js"; s.onload = res; s.onerror = rej; document.head.appendChild(s); });
  window.pdfjsLib.GlobalWorkerOptions.workerSrc = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";
  return window.pdfjsLib;
}
function b64bytes(b64) { const bin = atob(b64), u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); return u; }
async function openPdf(bytes, title, filename) {
  const m = document.createElement("div"); m.className = "pdfv"; m.setAttribute("role", "dialog"); m.setAttribute("aria-modal", "true"); m.setAttribute("aria-label", title);
  m.innerHTML = `<div class="pdfv-bar"><b>${esc(title)}</b><span class="small" id="pdfv-n" style="color:#9AA4C4"></span><div class="pdfv-acts"><button class="btn ghost" id="pdfv-dl">Download</button><button class="btn sun" id="pdfv-x">Close</button></div></div><div class="pdfv-pages" id="pdfv-pages" data-lenis-prevent><p style="color:#C9D1EA">Opening…</p></div>`;
  document.body.appendChild(m); document.body.style.overflow = "hidden"; if (lenis) lenis.stop();
  const close = () => { m.remove(); document.body.style.overflow = ""; if (lenis) lenis.start(); removeEventListener("keydown", onKey); };
  const onKey = e => { if (e.key === "Escape") close(); }; addEventListener("keydown", onKey);
  $("#pdfv-x", m).onclick = close;
  $("#pdfv-dl", m).onclick = () => { const url = URL.createObjectURL(new Blob([bytes], { type: "application/pdf" })); const a = document.createElement("a"); a.href = url; a.download = filename; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 60000); };
  try {
    const lib = await loadPdfJs(); const doc = await lib.getDocument({ data: bytes.slice() }).promise;
    const box = $("#pdfv-pages", m); box.innerHTML = ""; $("#pdfv-n", m).textContent = `${doc.numPages} pages`;
    const width = Math.min(box.clientWidth - 32, 1000), dpr = Math.min(2, devicePixelRatio || 1);
    for (let i = 1; i <= doc.numPages; i++) {
      if (!document.body.contains(m)) return;
      const page = await doc.getPage(i), v1 = page.getViewport({ scale: 1 }), vp = page.getViewport({ scale: width / v1.width * dpr });
      const c = document.createElement("canvas"); c.width = vp.width; c.height = vp.height; c.style.width = width + "px"; c.style.height = (vp.height / dpr) + "px"; box.appendChild(c);
      await page.render({ canvasContext: c.getContext("2d"), viewport: vp }).promise;
    }
  } catch (e) { $("#pdfv-pages", m).innerHTML = `<p style="color:#C9D1EA">This document couldn't be shown here. Use Download instead.</p>`; }
}

// ---------- pages ----------
const P = {};
P.home = () => {
  const s = stats(); const h = ["Delhi", "New York", "Shanghai", "Kuala Lumpur", "London", "Paris"];
  const tiles = [["Delhi", "DEL", "t1"], ["Shanghai", "PVG", "t2"], ["New York", "JFK", "t3"], ["Kuala Lumpur", "KUL", "t4"], ["Istanbul", "IST", "t5"], ["Barcelona", "BCN", "t6"]];
  const posts = (D.posts || []).slice(0, 3);
  const top = DEST.slice(0, 40).map(d => d.city);
  const mainHubs = boardHubs();
  const rep = (D.reports || []).find(r => r.status === "published");
  return `
  <section class="hero" data-nav="dark">
    <canvas class="globe" id="hero-globe" aria-label="Live map of equinox. flights"></canvas><div class="shade"></div>
    <div class="inner">
      <span class="live"><i class="pulse"></i><span id="air-count">${fmtN(airborne().length)}</span> equinox. flights in the air right now</span>
      <h1 class="h-hero" id="hero-h">six airlines,<br>one sky.</h1>
      <div class="horizon" aria-hidden="true"></div>
      <p class="lead" style="color:#C9D1EA;max-width:52ch">Pan Am, Virgin Atlantic, Ryanair, Kingfisher, China Eastern and Malaysia Airlines, flying as one network to ${s.dests} destinations.</p>
      ${searchPanel()}
    </div>
  </section>
  <div class="marquee light" aria-hidden="true"><div class="track">${[...top, ...top].map((c, i) => i % 5 === 0 ? `<i>${esc(c)}</i>` : esc(c)).join("<span>·</span>")}</div></div>
  <section class="sec light" data-nav="light">
    <div class="wrap">
      <div class="sec-head"><div><p class="kick">Where we fly</p><h2 class="h2 rv">From a dawn departure in Delhi to a late arrival in New York.</h2></div><p class="lead rv">${s.dests} destinations on four continents, connected through hubs timed so the next flight is waiting when you land.</p></div>
      <div class="mosaic">${tiles.map(([c, code, cls]) => `<a class="tile ${cls}" href="/flights?to=${code}" data-link>${(apPhoto(code) || photoUrl(c)) ? `<img loading="lazy" src="${apPhoto(code) || photoUrl(c)}" alt="${esc(c)}">` : ""}<div class="cap"><b>${esc(c)}</b><span>${esc(apCountry(code))}<br>${(DEST.find(d => d.code === code) || { weekly: 0 }).weekly} departures a week</span></div></a>`).join("")}</div>
      <p style="margin-top:28px"><a class="link" href="/destinations" data-link>See all ${s.dests} destinations</a></p>
    </div>
  </section>
  <section class="sec paper" data-nav="light" style="padding-bottom:clamp(60px,8vw,110px)">
    <div class="wrap">
      <div class="sec-head"><div><p class="kick">Our airlines</p><h2 class="h2 rv">Each airline owns its corner of the map.</h2></div><div style="display:grid;gap:18px;justify-items:end"><p class="lead rv">Six brands that know their home markets, and one network that links them: book across airlines as a single trip.</p><div class="rail-nav"><button type="button" data-rail-go="-1" aria-label="Previous airlines"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 18l-6-6 6-6"/></svg></button><button type="button" data-rail-go="1" aria-label="More airlines"><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 18l6-6-6-6"/></svg></button></div></div></div>
      <div class="rail" data-rail>${ORDER.map(a => { const st = stats(a), m = AL[a]; return `<a class="al-card" href="/airlines/${m.slug}" data-link>${photoUrl(m.photo) ? `<img class="bg" loading="lazy" src="${photoUrl(m.photo)}" alt="">` : ""}<span class="logo">${logoImg(a)}</span><div class="body"><p class="small" style="color:#C9D1EA;margin:0 0 6px">${esc(m.role)}</p><h3>${esc(m.name)}</h3><div class="facts"><div><b>${st.fleet}</b><span>aircraft</span></div><div><b>${st.dests}</b><span>destinations</span></div><div><b>${fmtN(st.weekly)}</b><span>flights a week</span></div></div></div><span class="stripe" style="background:${m.color}"></span></a>`; }).join("")}</div>
    </div>
  </section>
  <section class="cine" data-nav="dark" id="cine"><div class="stick">${videoTag("dusk_window")}<div class="tint"></div><p data-words>We plan around the sun. Every hub has its waves, every wave its connections, so a morning in Delhi becomes an evening in London and a night flight to New York.</p></div></section>
  <section class="sec dark" data-nav="dark">
    <div class="wrap">
      <div class="sec-head"><div><p class="kick">Live departures</p><h2 class="h2">Right now at our hubs.</h2></div><p class="lead">Every departure board on this site runs on the real schedule. Times are local to each airport.</p></div>
      ${boardHTML(mainHubs, mainHubs[0])}
    </div>
  </section>
  <section class="sec dark night-2" data-nav="dark">
    <div class="wrap">
      <div class="sec-head"><div><p class="kick">Newsroom</p><h2 class="h2">What's new across the group.</h2></div><p class="lead"><a class="link" href="/news" data-link style="color:#fff">All news</a></p></div>
      ${nlFeature()}<div class="news-grid">${posts[0] ? postCard(posts[0], "big") : ""}<div class="side">${posts.slice(1).map(p => postCard(p, "row")).join("")}</div></div>
    </div>
  </section>
  <section class="sec dark" data-nav="dark">
    <div class="wrap">
      <div class="sec-head"><div><p class="kick">Investors</p><h2 class="h2">Growing on every front.</h2></div><p class="lead">${rep ? `Latest: <a class="link" href="/investors#reports" data-link style="color:#fff">${esc(rep.title)}</a>.` : ""} The full figures are in our reports.</p></div>
      <div class="figs">${figs().map(f => `<div class="fig"><b data-count="${f.v}">${f.txt}</b><span>${f.l}</span>${f.d ? `<em>${f.d}</em>` : ""}</div>`).join("")}</div>
      <p style="margin-top:40px"><a class="btn sun" href="/investors" data-link>Investor relations</a></p>
    </div>
  </section>`;
};
P.home.after = root => {
  const g = makeGlobe($("#hero-globe"), { lon: 72, tilt: 0, offsetX: 0.62, zoom: 4.35, offsetYMobile: 0.62, onCount: n => { const e = $("#air-count"); if (e) e.textContent = fmtN(n); } });
  wireSearch(root, q => go(`/flights?from=${q.from}&to=${q.to}&date=${q.date}`));
  wireBoard(root, boardHubs());
  wireRail(root); cineWords(root);
  return () => g && g.destroy();
};
function figs() {
  const s = stats();
  return [{ v: s.fleet, txt: fmtN(s.fleet), l: "aircraft in service" }, { v: s.dests, txt: fmtN(s.dests), l: "destinations" }, { v: s.weekly, txt: fmtN(s.weekly), l: "flights every week" }];
}
function finance() {
  const cash = D.cash || {}, capex = D.capex || [], dates = Object.keys(cash).sort();
  const per = {};
  for (const a of ORDER) {
    const pts = dates.filter(d => cash[d] && cash[d][a] != null).map(d => [d, +cash[d][a]]);
    const prof = [];
    for (let i = 1; i < pts.length; i++) { const [d0, c0] = pts[i - 1], [d1, c1] = pts[i]; const days = Math.max(1, (new Date(d1) - new Date(d0)) / 864e5); const add = capex.filter(x => x.airline === a && x.kind !== "loss" && x.date > d0 && x.date <= d1).reduce((s, x) => s + (+x.m || 0), 0); prof.push([d1, (c1 - c0 + add) / days, days]); }
    const fd = Object.keys(D.fixed7 || {}).filter(d => D.fixed7[d][a] != null).sort().pop();
    per[a] = { pts, prof, cash: pts.length ? pts[pts.length - 1][1] : null, fixed: fd ? +D.fixed7[fd][a] : null };
  }
  const last = ORDER.reduce((s, a) => s + (per[a].prof.length ? per[a].prof[per[a].prof.length - 1][1] : 0), 0);
  const wk = ORDER.reduce((s, a) => { const p = per[a].prof.slice(-6); const dd = p.reduce((x, y) => x + y[2], 0); return s + (dd ? p.reduce((x, y) => x + y[1] * y[2], 0) / dd : 0); }, 0);
  const cashT = ORDER.reduce((s, a) => s + (per[a].cash || 0), 0);
  return { per, dates, group: { last: dates.length > 1 ? last : null, avg: dates.length > 1 ? wk : null, cash: dates.length ? cashT : null } };
}
function wireRail(root) {
  const r = $("[data-rail]", root); if (!r) return;
  const btns = $$("[data-rail-go]", root);
  const upd = () => { const max = r.scrollWidth - r.clientWidth - 4; btns.forEach(b => { b.disabled = (+b.dataset.railGo < 0 && r.scrollLeft <= 4) || (+b.dataset.railGo > 0 && r.scrollLeft >= max); }); };
  btns.forEach(b => b.onclick = () => { const card = r.querySelector(".al-card"); const step = card ? card.getBoundingClientRect().width + 16 : r.clientWidth * 0.8; r.scrollBy({ left: step * +b.dataset.railGo, behavior: RM ? "auto" : "smooth" }); });
  r.addEventListener("scroll", upd, { passive: true }); new ResizeObserver(upd).observe(r); upd();
}
function cineWords(root) {
  const sec = $("#cine", root); if (!sec) return; const p = $("[data-words]", sec);
  p.innerHTML = p.textContent.split(" ").map(w => `<span class="w">${esc(w)}</span> `).join(""); const ws = $$(".w", p);
  const upd = () => { const r = sec.getBoundingClientRect(); const prog = Math.max(0, Math.min(1, (-r.top) / (r.height - innerHeight))); const n = Math.round(prog * ws.length * 1.15); ws.forEach((w, i) => w.classList.toggle("lit", i < n)); };
  onScroll(upd); upd();
}

P.flights = (q) => {
  const from = q.get("from") || "", to = q.get("to") || "", date = q.get("date") || new Date().toISOString().slice(0, 10);
  const label = c => c && AP[c] ? `${apName(c)} (${c})` : "";
  return `<section class="phead short" data-nav="dark">${videoTag("landing_night")}<div class="tint"></div><div class="inner"><h1 class="h1">Flight schedules</h1><p class="lead">Every equinox. flight, direct and with connections through our hubs. No fares here, just the timetable as it flies.</p></div></section>
  <section class="sec light" data-nav="light" style="padding-top:48px">
    <div class="wrap">
      ${searchPanel({ from: label(from), to: label(to), date })}
      <div style="display:flex;gap:18px;align-items:center;margin-top:18px;flex-wrap:wrap"><label class="toggle"><input type="checkbox" id="direct-only">Direct flights only</label><span class="small" id="res-note"></span></div>
      <div class="res" id="results">${from && to ? "" : `<div class="empty">Choose where you're flying from and to. Try Chicago to Kochi, or London to Kuala Lumpur.</div>`}</div>
    </div>
  </section>
  <section class="sec paper" data-nav="light">
    <div class="wrap split">
      <div><p class="kick">Flight lookup</p><h2 class="h2">Know your flight number?</h2><p class="lead" style="margin-top:14px">Enter it to see the route, times, aircraft and days of operation.</p>
        <form id="fl-form" style="display:flex;gap:8px;margin-top:22px;max-width:420px"><div class="field" style="flex:1;background:var(--porcelain)"><label for="fl-no">Flight number</label><input id="fl-no" placeholder="AW1001" style="text-transform:uppercase"></div><button class="btn solid" style="border-radius:18px;padding:0 24px">Look up</button></form>
        <div id="fl-out" style="margin-top:22px"></div></div>
      <div><p class="kick">Our codes</p><table class="tbl"><thead><tr><th>Airline</th><th>Code</th><th class="num">Flights a week</th></tr></thead><tbody>${ORDER.map(a => `<tr><td>${alChip(a)}</td><td><b>${AL[a].code}</b></td><td class="num">${fmtN(stats(a).weekly)}</td></tr>`).join("")}</tbody></table></div>
    </div>
  </section>
  <section class="sec dark" data-nav="dark"><div class="wrap"><div class="sec-head"><div><h2 class="h2">Live departures</h2></div><p class="lead">Updated every 30 seconds from the timetable.</p></div>${boardHTML(boardHubs(), boardHubs()[0])}</div></section>`;
};
P.flights.after = (root, q) => {
  const run = (f, t, d) => {
    const out = $("#results"); const direct = $("#direct-only").checked;
    if (!AP[f] || !AP[t]) { out.innerHTML = `<div class="empty">We couldn't find ${!AP[f] ? "the departure" : "the destination"} airport. Pick one from the list as you type.</div>`; return; }
    let trips = findTrips(f, t, d); if (direct) trips = trips.filter(x => x.legs.length === 1);
    const day = new Date(d + "T12:00:00Z").toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" });
    $("#res-note").textContent = trips.length ? `${trips.length} option${trips.length > 1 ? "s" : ""} on ${day}` : "";
    if (trips.length) { out.innerHTML = trips.map(x => tripCard(x, d)).join(""); return; }
    let alt = null; for (let k = 1; k <= 7 && !alt; k++) { const dd = new Date(new Date(d + "T12:00:00Z").getTime() + k * 864e5).toISOString().slice(0, 10); let tr = findTrips(f, t, dd); if (direct) tr = tr.filter(x => x.legs.length === 1); if (tr.length) alt = dd; }
    const altDay = alt && new Date(alt + "T12:00:00Z").toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long" });
    out.innerHTML = `<div class="empty">No equinox. ${direct ? "direct flight" : "connection"} from ${esc(apName(f))} to ${esc(apName(t))} on ${day}.${alt ? ` The nearest day with flights is <b>${altDay}</b>.<p style="margin-top:16px"><button class="btn solid" id="alt-day">Show ${altDay}</button></p>` : " Nothing in the following week either: try a nearby airport."}</div>`;
    if (alt) $("#alt-day").onclick = () => { $("#s-date").value = alt; history.replaceState(null, "", `/flights?from=${f}&to=${t}&date=${alt}`); run(f, t, alt); };
  };
  wireSearch(root, q2 => { history.replaceState(null, "", `/flights?from=${q2.from}&to=${q2.to}&date=${q2.date}`); run(q2.from, q2.to, q2.date); });
  $("#direct-only").onchange = () => { const p = new URLSearchParams(location.search); if (p.get("from") && p.get("to")) run(p.get("from"), p.get("to"), p.get("date") || new Date().toISOString().slice(0, 10)); };
  if (q.get("from") && q.get("to")) run(q.get("from"), q.get("to"), q.get("date") || new Date().toISOString().slice(0, 10));
  else if (q.get("to")) { const i = $("#s-to"); i.value = `${apName(q.get("to"))} (${q.get("to")})`; i.dataset.code = q.get("to"); $("#s-from").focus(); }
  $("#fl-form").onsubmit = e => { e.preventDefault(); const v = $("#fl-no").value.trim().toUpperCase().replace(/\s+/g, ""); const ls = LEGS.filter(l => l.no === v); $("#fl-out").innerHTML = ls.length ? ls.map(l => `<div class="trip" style="grid-template-columns:1fr"><div class="legs"><div class="lg">${alChip(l.al)}<b>${l.no}</b></div><div class="when" style="margin-top:6px"><div><b>${tm(l.dep)}</b><small>${esc(apName(l.from))} (${l.from})</small></div><div class="path"></div><div><b>${tm(l.arr)}</b><small>${esc(apName(l.to))} (${l.to})</small></div></div><div class="lg">${esc(l.type)}, ${dur(l.dur)}, ${l.days.size === 7 ? "daily" : [...l.days].map(d => DAYS[d - 1]).join(" ")}</div></div></div>`).join("") : `<div class="empty" style="text-align:left">No flight ${esc(v)} in the current timetable. Flight numbers start with the airline code, for example AW1001 or KF1001.</div>`; };
  wireBoard(root, boardHubs());
};

P.destinations = () => {
  const regions = ["All", "Americas", "Europe", "Middle East and Africa", "South Asia", "China and North Asia", "South-East Asia and Oceania"].filter(r => r === "All" || DEST.some(d => d.region === r));
  return `<section class="phead short" data-nav="dark">${videoTag("city_night")}<div class="tint"></div><div class="inner"><h1 class="h1">${DEST.length} destinations</h1><p class="lead">Pick a city to see who flies there and how often, then find your flights.</p></div></section>
  <section class="sec light" data-nav="light" style="padding-top:44px"><div class="wrap">
    <div style="display:flex;flex-wrap:wrap;gap:14px;justify-content:space-between;align-items:center;margin-bottom:28px"><div class="pills" id="reg">${regions.map((r, i) => `<button class="pill ${i ? "" : "on"}" data-r="${r}">${r}</button>`).join("")}</div>
    <div class="field" style="background:#fff;min-width:260px;box-shadow:0 0 0 1px var(--line)"><label for="dq">Search</label><input id="dq" placeholder="City or country"></div></div>
    <div id="dgrid"></div></div></section>`;
};
P.destinations.after = root => {
  let reg = "All", q = "";
  const AREAS = ["Americas", "Europe", "Middle East and Africa", "South Asia", "China and North Asia", "South-East Asia and Oceania", "Other"];
  const card = d => { const ph = apPhoto(d.code); return `<a class="dcard" href="/flights?to=${d.code}" data-link>${ph ? `<img loading="lazy" src="${ph}" alt="">` : `<span class="noimg"></span><span class="code">${d.code}</span>`}<div class="tx"><b>${esc(d.city)}</b><span>${d.weekly} departures a week</span><div class="dots">${[...d.als].map(a => `<i title="${esc(AL[a].name)}" style="background:${AL[a].color}"></i>`).join("")}</div></div></a>`; };
  const draw = () => {
    const list = DEST.filter(d => (reg === "All" || d.region === reg) && (!q || (d.city + " " + d.country + " " + d.code).toLowerCase().includes(q)));
    if (!list.length) { $("#dgrid").innerHTML = `<div class="empty">No destinations match. Try a different city or area.</div>`; return; }
    $("#dgrid").innerHTML = AREAS.filter(a => list.some(d => d.region === a)).map(a => {
      const inA = list.filter(d => d.region === a); const byC = {}; inA.forEach(d => (byC[d.country] = byC[d.country] || []).push(d));
      const cs = Object.entries(byC).sort((x, y) => y[1].reduce((s, d) => s + d.weekly, 0) - x[1].reduce((s, d) => s + d.weekly, 0));
      return `<section class="area"><div class="area-h"><h2 class="h2">${esc(a)}</h2><span class="small">${inA.length} destination${inA.length > 1 ? "s" : ""} in ${cs.length} ${cs.length > 1 ? "countries" : "country"}</span></div>
        ${cs.map(([c, ds]) => `<div class="country"><h3 class="h3">${esc(c)}</h3><div class="grid-dest">${ds.sort((x, y) => y.weekly - x.weekly).map(card).join("")}</div></div>`).join("")}</section>`;
    }).join("");
  };
  $$("#reg .pill").forEach(b => b.onclick = () => { reg = b.dataset.r; $$("#reg .pill").forEach(x => x.classList.toggle("on", x === b)); draw(); });
  $("#dq").oninput = e => { q = e.target.value.trim().toLowerCase(); draw(); }; draw();
};
P.network = () => {
  const s = stats();
  return `<section class="netstage" data-nav="dark"><canvas id="net-globe" aria-label="Live map of the equinox. network"></canvas>
    <div class="panel"><span class="live"><i class="pulse"></i><span id="net-air">${fmtN(airborne().length)}</span> flights in the air right now</span><h1 class="h1">The live network.</h1><p class="lead" style="color:#C9D1EA">${s.routes} routes and ${fmtN(s.weekly)} flights a week. Drag to turn the globe; the shadow is today's real night.</p></div>
    <div class="legend" id="legend">${ORDER.map(a => `<button data-al="${esc(a)}"><i style="background:${AL[a].color}"></i>${esc(AL[a].name)}</button>`).join("")}</div></section>
  <section class="sec light" data-nav="light"><div class="wrap"><div class="sec-head"><div><h2 class="h2">Hubs and bases</h2></div><p class="lead">Hubs are built for connections; bases fly point to point.</p></div>
    <div class="tbl-wrap" data-lenis-prevent><table class="tbl"><thead><tr><th>Airport</th><th>Airline</th><th>Role</th><th class="num">Departures a week</th></tr></thead><tbody>
    ${D.hubs.filter(h => AL[h.airline] && AP[h.code]).map(h => `<tr><td><b>${esc(apName(h.code))}</b> <span class="small">${h.code}</span></td><td>${alChip(h.airline)}</td><td>${h.role === "focus" ? "Base" : "Hub"}</td><td class="num">${LEGS.filter(l => l.from === h.code && l.al === h.airline).reduce((a, l) => a + l.days.size, 0)}</td></tr>`).join("")}</tbody></table></div></div></section>`;
};
P.network.after = () => {
  const g = makeGlobe($("#net-globe"), { lon: 45, tilt: 0, zoom: 3.75, labels: true, routeOpacity: 0.5, planeSize: 0.045, spin: 0.00004, onCount: n => { const e = $("#net-air"); if (e) e.textContent = fmtN(n); } });
  $$("#legend button").forEach(b => b.onclick = () => { const off2 = !b.classList.contains("off"); b.classList.toggle("off", off2); g && g.filter(b.dataset.al, !off2); });
  return () => g && g.destroy();
};

P.airlines = () => `<section class="phead short" data-nav="dark">${videoTag("takeoff")}<div class="tint"></div><div class="inner"><h1 class="h1">Our airlines</h1><p class="lead">Six airlines, each with a home market, a role in the group, and a network built to connect with the other five.</p></div></section>
  <section class="sec light" data-nav="light"><div class="wrap"><div class="al-grid">${ORDER.map(a => { const m = AL[a], st = stats(a); return `<a href="/airlines/${m.slug}" data-link class="al-tile" style="--c:${m.color}"><div class="ph">${photoUrl(m.photo) ? `<img loading="lazy" src="${photoUrl(m.photo)}" alt="">` : ""}<span class="logo">${logoImg(a, 40)}</span></div><div class="tx"><p class="small" style="margin:0">${esc(m.role)}</p><h3>${esc(m.name)}</h3><p class="bl">${esc(m.blurb)}</p><div class="fx"><div><b>${st.fleet}</b><span>aircraft</span></div><div><b>${st.dests}</b><span>destinations</span></div><div><b>${fmtN(st.weekly)}</b><span>flights a week</span></div></div></div></a>`; }).join("")}</div></div></section>`;
P.airline = slug => {
  const a = ORDER.find(k => AL[k].slug === slug); if (!a) return P.notfound();
  const m = AL[a], st = stats(a); const fleet = {}; D.tails.filter(t => t.airline === a).forEach(t => { const k = TYPE[String(t.type).toUpperCase()] || t.type; fleet[k] = (fleet[k] || 0) + 1; });
  const oo = {}; (D.onorder || []).filter(o => o.airline === a).forEach(o => { const k = TYPE[String(o.type).toUpperCase()] || o.type; oo[k] = (oo[k] || 0) + 1; });
  const hubs = D.hubs.filter(h => h.airline === a);
  const routes = {}; LEGS.filter(l => l.al === a).forEach(l => { const k = [l.from, l.to].sort().join("-"); routes[k] = routes[k] || { a: l.from, b: l.to, n: 0 }; routes[k].n += l.days.size; });
  const rl = Object.values(routes).sort((x, y) => y.n - x.n);
  const posts = (D.posts || []).filter(p => p.airline === a).slice(0, 2);
  return `<section class="phead al-hero" data-nav="dark">${photoUrl(m.photo) ? `<img class="bg" src="${photoUrl(m.photo)}" alt="">` : ""}<div class="tint"></div><div class="inner"><span class="logo-pill">${logoImg(a, 44)}</span><h1 class="h1">${esc(m.name)}</h1><p class="lead">${esc(m.blurb)}</p><span style="display:block;height:4px;width:120px;background:${m.color};border-radius:4px"></span></div></section>
  <section class="sec light" data-nav="light"><div class="wrap split">
    <div><p class="kick">At a glance</p><div class="facts-list"><div><b>${st.fleet}</b><span>aircraft in service</span></div><div><b>${st.dests}</b><span>destinations</span></div><div><b>${fmtN(st.weekly)}</b><span>flights a week</span></div><div><b>${fmtN(st.seats)}</b><span>seats a week</span></div></div></div>
    <div><p class="kick">Fleet</p><table class="tbl"><thead><tr><th>Aircraft</th><th class="num">In service</th></tr></thead><tbody>${Object.keys(fleet).map(k => `<tr><td><b>${esc(k)}</b></td><td class="num">${fleet[k]}</td></tr>`).join("")}</tbody></table>
      <p class="kick" style="margin-top:34px">Hubs and bases</p><table class="tbl"><tbody>${hubs.map(h => `<tr><td><b>${esc(apName(h.code))}</b> <span class="small">${h.code}</span></td><td>${h.role === "focus" ? "Base, point to point" : "Hub, timed connections"}</td></tr>`).join("")}</tbody></table></div>
  </div></section>
  <section class="al-map2" data-nav="dark"><div class="map2" id="al-map" role="img" aria-label="${esc(m.name)} route map"></div><div class="panel"><p class="kick" style="color:#F6B44B">Route map</p><h2 class="h2">${esc(m.name)}${m.name.endsWith("s") ? "'" : "'s"} network, live.</h2><p class="lead" style="color:#C9D1EA">${rl.length} routes from ${hubs.filter(h => h.role !== "focus").map(h => esc(apName(h.code))).join(" and ") || "its bases"}. The moving dots are ${esc(m.name)} aircraft in the air right now.</p></div></section>
  <section class="sec paper" data-nav="light"><div class="wrap"><div class="sec-head"><div><h2 class="h2">Where ${esc(m.name)} flies</h2></div><p class="lead">${rl.length} routes, with weekly flights in both directions.</p></div>
    <div class="routes-list">${rl.map(r => `<div><b>${esc(apName(r.a))} – ${esc(apName(r.b))}</b><span>${r.n} a week</span></div>`).join("")}</div>
    <p style="margin-top:32px"><a class="btn solid" href="/flights?from=${hubs[0] ? hubs[0].code : ""}" data-link>Find ${esc(m.name)} flights</a></p></div></section>
  ${posts.length ? `<section class="sec light" data-nav="light"><div class="wrap"><h2 class="h2" style="margin-bottom:32px">Latest from ${esc(m.name)}</h2><div class="news-grid">${posts.map(p => postCard(p)).join("")}</div></div></section>` : ""}`;
};
P.airline.after = () => {
  const slug = location.pathname.split("/").filter(Boolean)[1]; const a = ORDER.find(k => AL[k].slug === slug); if (!a) return;
  const stop = airlineMap($("#al-map"), a); return stop;
};
function airlineMap(el, a) {
  if (!el || !window.EQ_WORLD) return null;
  const X = lon => (lon + 180) / 360 * 1000, Y = lat => (90 - lat) / 180 * 500;
  const toV = (la, lo) => { const p = la * DEG, l = lo * DEG; return [Math.cos(p) * Math.cos(l), Math.cos(p) * Math.sin(l), Math.sin(p)]; };
  const gc = (h, d, n = 48) => {
    const A = toV(AP[h][0], AP[h][1]), B = toV(AP[d][0], AP[d][1]); const om = Math.acos(Math.min(1, Math.max(-1, A[0] * B[0] + A[1] * B[1] + A[2] * B[2]))); const s = Math.sin(om), out = [];
    for (let i = 0; i <= n; i++) { const t = i / n, k1 = s < 1e-6 ? 1 - t : Math.sin((1 - t) * om) / s, k2 = s < 1e-6 ? t : Math.sin(t * om) / s; const v = [k1 * A[0] + k2 * B[0], k1 * A[1] + k2 * B[1], k1 * A[2] + k2 * B[2]]; out.push([X(Math.atan2(v[1], v[0]) / DEG), Y(Math.atan2(v[2], Math.hypot(v[0], v[1])) / DEG)]); }
    for (let i = 1; i < out.length; i++) { while (out[i][0] - out[i - 1][0] > 500) out[i][0] -= 1000; while (out[i][0] - out[i - 1][0] < -500) out[i][0] += 1000; }
    return out;
  };
  const routes = {}, weekly = {};
  for (const f of D.freqs) { const [al, h, d] = f.r.split("|"); if (al !== a || !AP[h] || !AP[d]) continue; routes[h + "|" + d] = { h, d, p: gc(h, d) }; }
  for (const l of LEGS) if (l.al === a) { weekly[l.to] = (weekly[l.to] || 0) + l.days.size; }
  const rs = Object.values(routes); if (!rs.length) return null;
  let x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9; rs.forEach(r => r.p.forEach(([x, y]) => { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y); }));
  const draw = () => {
    const wide = el.clientWidth > 900, ratio = el.clientWidth / Math.max(1, el.clientHeight);
    // keep the whole network in view and leave room for the text panel (left on wide screens, bottom on phones)
    const bx0 = wide ? x0 - (x1 - x0) * 0.55 - 20 : x0, by1 = wide ? y1 : y1 + (y1 - y0) * 0.6 + 20;
    const padX = Math.max(14, (x1 - bx0) * 0.06), padY = Math.max(14, (by1 - y0) * 0.1);
    let vw = (x1 - bx0) + 2 * padX, vh = (by1 - y0) + 2 * padY; if (vw / vh < ratio) vw = vh * ratio; else vh = vw / ratio;
    const cx = (bx0 + x1) / 2, cy = (y0 + by1) / 2;
    const u = vw / 900, col = AL[a].color, hubs = new Set(D.hubs.filter(h => h.airline === a).map(h => h.code));
    const ports = [...new Set(rs.flatMap(r => [r.h, r.d]))];
    const labelled = new Set([...hubs, ...Object.entries(weekly).sort((x, y) => y[1] - x[1]).slice(0, 10).map(e => e[0])]);
    el.innerHTML = `<svg viewBox="${cx - vw / 2} ${cy - vh / 2} ${vw} ${vh}" preserveAspectRatio="xMidYMid meet"><defs><filter id="glow"><feGaussianBlur stdDeviation="${u * 2.2}" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
      <rect x="-2000" y="-1000" width="5000" height="3000" fill="#0A1230"/><path d="${window.EQ_WORLD}" fill="#17255C" stroke="#22336F" stroke-width="${u * 0.6}"/>
      <g fill="none" stroke="#DCE3F5" stroke-width="${u * 0.9}" stroke-linecap="round" opacity=".55">${rs.map(r => `<path d="M${r.p.map(q => q[0].toFixed(2) + "," + q[1].toFixed(2)).join(" L")}"><title>${esc(apName(r.h))} – ${esc(apName(r.d))}</title></path>`).join("")}</g>
      <g>${ports.map(c => { const x = X(AP[c][1]), y = Y(AP[c][0]), hub = hubs.has(c); return `<circle cx="${x}" cy="${y}" r="${u * (hub ? 5 : 2.6)}" fill="${hub ? "#F6B44B" : "#FFE2A8"}" stroke="${hub ? "#fff" : "none"}" stroke-width="${u * 1.2}"><title>${esc(apName(c))}</title></circle>`; }).join("")}</g>
      <g font-family="Manrope, sans-serif" font-weight="700">${ports.filter(c => labelled.has(c)).map(c => { const x = X(AP[c][1]), y = Y(AP[c][0]), hub = hubs.has(c); return `<text x="${x + u * 7}" y="${y + u * 3.5}" font-size="${u * (hub ? 13 : 10)}" fill="${hub ? "#fff" : "#C9D1EA"}" paint-order="stroke" stroke="#0A1230" stroke-width="${u * 3}">${esc(apName(c))}</text>`; }).join("")}</g>
      <g id="am-planes"></g></svg>`;
    planes(u);
  };
  const planes = u => {
    const g = el.querySelector("#am-planes"); if (!g) return;
    g.innerHTML = airborne().filter(x => x.l.al === a).map(({ l, p }) => { const r = routes[l.from + "|" + l.to] || routes[l.to + "|" + l.from]; if (!r) return ""; const pts = routes[l.from + "|" + l.to] ? r.p : r.p.slice().reverse(); const i = p * (pts.length - 1), k = Math.floor(i), q = pts[k], n2 = pts[Math.min(k + 1, pts.length - 1)], f = i - k; const x = q[0] + (n2[0] - q[0]) * f, y = q[1] + (n2[1] - q[1]) * f; return `<circle cx="${x}" cy="${y}" r="${u * 3.6}" fill="#fff"><title>${l.no} ${esc(apName(l.from))} to ${esc(apName(l.to))}</title></circle><circle cx="${x}" cy="${y}" r="${u * 8}" fill="#fff" opacity=".18"/>`; }).join("");
  };
  draw(); const ro = new ResizeObserver(() => draw()); ro.observe(el);
  const iv = setInterval(() => { if (!document.hidden) { const vb = el.querySelector("svg"); if (vb) planes(vb.viewBox.baseVal.width / 900); } }, 5000);
  return () => { ro.disconnect(); clearInterval(iv); };
}
P.news = () => { const ps = D.posts || []; return `<section class="phead short" data-nav="dark">${videoTag("boarding_dusk")}<div class="tint"></div><div class="inner"><h1 class="h1">Newsroom</h1><p class="lead">New routes, new aircraft, partnerships and results from across the group.</p></div></section>
  <section class="sec light" data-nav="light"><div class="wrap">${nlFeature()}<div class="news-grid" style="margin-bottom:18px">${ps[0] ? postCard(ps[0], "big") : ""}<div class="side">${ps.slice(1, 3).map(p => postCard(p, "row")).join("")}</div></div>
  <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:18px">${ps.slice(3).map(p => postCard(p)).join("")}</div></div></section>`; };
P.article = slug => { const p = (D.posts || []).find(x => x.slug === slug); if (!p) return P.notfound(); const ph = String(p.image || "").startsWith("photo:") ? photo(p.image.slice(6)) : null;
  return `<section class="sec light" data-nav="light" style="padding-top:150px"><div class="wrap"><article class="article"><p class="small"><a class="link" href="/news" data-link>Newsroom</a> <span style="margin:0 8px">/</span> ${esc(p.tag || "")}</p><h1 class="h1" style="font-size:clamp(34px,4.6vw,64px);margin:18px 0 18px">${esc(p.title)}</h1><p class="small" style="margin-bottom:34px">${niceDate(p.at)}${p.airline && AL[p.airline] ? ` <span style="margin:0 8px">/</span> ${esc(AL[p.airline].name)}` : ""}</p>
  ${p.image ? `<div class="hero-img"><img src="${imgOf(p.image)}" alt=""></div>${ph ? `<p class="credit" style="margin:-30px 0 40px">Photo: ${esc(ph.creator || "unknown")}, ${esc((ph.license || "").toUpperCase())} ${esc(ph.license_version || "")}</p>` : ""}` : ""}
  <p class="lead" style="color:var(--ink);font-size:22px;margin-bottom:28px">${esc(p.summary || "")}</p><div class="body">${String(p.body || "").split(/\n\n+/).map(x => `<p>${esc(x)}</p>`).join("")}</div>
  <p style="margin-top:40px;display:flex;gap:10px;flex-wrap:wrap">${p.tag === "Newsletter" ? `<a class="btn solid" href="/newsletter" data-link>Read gander monthly</a>` : ""}<a class="btn ghost" href="/news" data-link>Back to the newsroom</a></p></article></div></section>`; };

function invLocked() {
  return `<section class="phead" data-nav="dark">${videoTag("pink_window")}<div class="tint"></div><div class="inner"><h1 class="h1">Investor relations</h1><p class="lead">For the equinox. group's investors and leadership.</p></div></section>
  <section class="sec light" data-nav="light"><div class="wrap"><div class="inv-gate">
    <span class="wm" style="font-size:18px">equinox<i class="dot"></i></span><h2 class="h2" style="margin:18px 0 10px">Restricted access</h2>
    <p>This section holds the group's results, market positions and confidential reports. It contains sensitive commercial information and is not for sharing: please don't forward, publish or post anything from it, in full or in part.</p>
    <form id="inv-form" autocomplete="off"><label class="agree"><input type="checkbox" id="inv-ok"><span>I agree to keep everything in investor relations confidential.</span></label>
    <div class="field" style="background:#fff;margin-top:14px;box-shadow:0 0 0 1px var(--line)"><label for="inv-pw">Investor password</label><input id="inv-pw" type="password" placeholder="Enter the password"></div>
    <p class="small" id="inv-msg" role="alert" style="min-height:20px;margin:10px 0 0;color:#B4234B"></p>
    <button class="btn solid" id="inv-go" disabled>Enter investor relations</button></form></div></div></section>`;
}
async function invUnlock(pw) {
  const r = await fetch(SB_URL + "/rest/v1/rpc/site_investor", { method: "POST", headers: { apikey: SB_KEY, Authorization: "Bearer " + SB_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ p_password: pw }) });
  const j = await r.json(); if (!j || !j.ok) return false;
  INV = { pw, ...j }; D.reports = [...(D.reports || []).filter(r => r.kind === "newsletter"), ...(j.reports || [])]; D.cash = j.cash || {}; D.fixed7 = j.fixed7 || {}; D.capex = j.capex || []; D.content = { ...(D.content || {}), markets: j.markets || null };
  try { sessionStorage.setItem("eq_inv", pw); } catch (e) {}
  return true;
}
P.investors = () => {
  if (!INV) return invLocked();
  const fin = finance(), mk = (D.content && D.content.markets) || null, reps = D.reports || [];
  return `<section class="phead" data-nav="dark">${videoTag("pink_window")}<div class="tint"></div><div class="inner"><h1 class="h1">Investor relations</h1><p class="lead">How the equinox. group is growing, at a glance. The detailed figures are in our weekly, monthly and annual reports.</p><p><a class="btn sun" href="#reports" data-link>Read the reports</a></p></div></section>
  <section class="sec dark" data-nav="dark"><div class="wrap"><div class="figs" style="grid-template-columns:repeat(3,1fr)">${figs().map(f => `<div class="fig"><b>${f.txt}</b><span>${f.l}</span>${f.d ? `<em>${f.d}</em>` : ""}</div>`).join("")}</div></div></section>
  <section class="sec light" data-nav="light"><div class="wrap">
    <div class="sec-head"><div><p class="kick">Growth</p><h2 class="h2">A network that doubled in a week.</h2></div><p class="lead">Aircraft and routes in service, by the day each was first scheduled.</p></div>
    <div class="cards-2"><div class="panel-l"><h3 class="h3">Aircraft in service</h3>${growthChart("fleet")}</div><div class="panel-l"><h3 class="h3">Routes flown</h3>${growthChart("routes")}</div></div>
    <div class="panel-l" style="margin-top:18px"><h3 class="h3">Daily results by airline</h3><p class="small" style="margin:4px 0 0">Bars above the line are days in profit. Hover a bar for the airline and day; the amounts are in the reports.</p>${profitChart(fin)}</div>
  </div></section>
  ${mk ? `<section class="sec paper" data-nav="light"><div class="wrap"><div class="sec-head"><div><p class="kick">Market position</p><h2 class="h2">Where we lead, and where we're the challenger.</h2></div><p class="lead">Our share of seats in each market we fly, against the market leader, from a scan of every airline in the game.</p></div>
    <div class="panel-l">${marketBars(mk.markets)}</div>
    <h3 class="h3" style="margin:56px 0 8px">Our share of departures at our hubs</h3><p class="small" style="margin:0 0 22px">Each ring is one airport; the coloured part is our airline's share of all departures there.</p>
    <div class="rings">${mk.hubs.map(h => ring(h)).join("")}</div></div></section>` : ""}
  <section class="sec dark" data-nav="dark" id="reports"><div class="wrap"><div class="sec-head"><div><p class="kick">Reports</p><h2 class="h2">The full numbers live here.</h2></div><p class="lead">Weekly briefings and the annual report, written for the group's leadership.</p></div>
    ${["weekly", "annual"].map(k => `<h3 class="h3" style="margin:36px 0 6px">${k[0].toUpperCase() + k.slice(1)}</h3>${reps.filter(r => r.kind === k).map(r => `<div class="rep ${r.status !== "published" ? "upcoming" : ""}"><span class="ic"></span><div><h4>${esc(r.title)}</h4><p>${esc(r.summary || "")}${r.at ? ` Published ${niceDate(r.at)}.` : ""}</p></div>${r.status === "published" && r.has_pdf ? `<button class="btn sun" data-report="${r.id}">Read the report</button>` : `<span class="small">Coming soon</span>`}</div>`).join("") || `<p class="small">None yet.</p>`}`).join("")}
  </div></section>
  <section class="sec light" data-nav="light"><div class="wrap"><div class="sec-head"><div><p class="kick">Strategy</p><h2 class="h2">One network, six owners.</h2></div><p class="lead">Each airline owns one part of the world, and every long-haul flow belongs to exactly one of them, so the group never competes with itself. Growth rotates between opening big markets, adding flights where routes are full, and building the feeder routes that fill the hubs.</p></div>
    <div class="roles">${ORDER.map(a => `<a class="role" href="/airlines/${AL[a].slug}" data-link style="--c:${AL[a].color}"><span class="logo">${logoImg(a, 30)}</span><b>${esc(AL[a].name)}</b><span>${esc(AL[a].role)}</span></a>`).join("")}</div></div></section>`;
};
P.investors.after = root => {
  if (!INV) {
    const ok = $("#inv-ok", root), pw = $("#inv-pw", root), go = $("#inv-go", root), msg = $("#inv-msg", root);
    const upd = () => { go.disabled = !(ok.checked && pw.value.length); }; ok.onchange = upd; pw.oninput = () => { msg.textContent = ""; upd(); };
    $("#inv-form", root).onsubmit = async e => { e.preventDefault(); if (go.disabled) return; go.disabled = true; go.textContent = "Checking…";
      if (await invUnlock(pw.value)) render(); else { msg.textContent = "That password isn't right."; go.textContent = "Enter investor relations"; upd(); pw.select(); } };
    const saved = sessionStorage.getItem("eq_inv"); if (saved) invUnlock(saved).then(okd => { if (okd) render(); });
    return;
  }
  $$("[data-report]", root).forEach(b => b.onclick = async () => {   // inside investor relations, reports download straight away
    const lbl = b.textContent; b.textContent = "Opening…"; b.disabled = true;
    try { const r = await fetch(SB_URL + "/rest/v1/rpc/site_report", { method: "POST", headers: { apikey: SB_KEY, Authorization: "Bearer " + SB_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ p_id: +b.dataset.report, p_password: INV.pw }) });
      const j = await r.json(); if (!j || !j.ok) throw new Error("locked");
      openPdf(b64bytes(j.pdf), (j.title || "Report") + " (confidential)", "equinox_CONFIDENTIAL_" + (j.title || "report").replace(/[^\w]+/g, "_") + ".pdf");
    } catch (e) { alert("The report couldn't be downloaded. Try again in a moment."); }
    b.textContent = lbl; b.disabled = false; });
  if (location.hash === "#reports") setTimeout(() => { const e = $("#reports"); e && scrollToEl(e); }, 300);
};
function reportGate(id, title) {
  const m = document.createElement("div"); m.className = "modal"; m.setAttribute("role", "dialog"); m.setAttribute("aria-modal", "true"); m.setAttribute("aria-labelledby", "rg-t");
  m.innerHTML = `<div class="box"><span class="wm" style="font-size:18px">equinox<i class="dot"></i></span><h2 id="rg-t" style="margin-top:20px">Confidential report</h2>
    <p><b>${esc(title)}</b> is written for the equinox. group's leadership. It contains sensitive commercial information: our airlines' results, plans, risks and competitor analysis.</p>
    <p>It is not for sharing. Please don't forward, publish or post it, in full or in part.</p>
    <label class="agree"><input type="checkbox" id="rg-ok"><span>I agree to keep this report confidential and not to share it.</span></label>
    <div class="field" style="background:var(--porcelain);margin-top:14px"><label for="rg-pw">Investor password</label><input id="rg-pw" type="password" autocomplete="off" placeholder="Enter the password"></div>
    <p class="small" id="rg-msg" role="alert" style="min-height:20px;margin:10px 0 0;color:#B4234B"></p>
    <div class="row" style="margin-top:12px"><button class="btn solid" id="rg-go" disabled>Download the report</button><button class="btn ghost" id="rg-x">Cancel</button></div></div>`;
  document.body.appendChild(m); requestAnimationFrame(() => m.classList.add("open"));
  const ok = $("#rg-ok", m), pw = $("#rg-pw", m), go = $("#rg-go", m), msg = $("#rg-msg", m);
  const close = () => { m.classList.remove("open"); setTimeout(() => m.remove(), 400); removeEventListener("keydown", esc2); };
  const esc2 = e => { if (e.key === "Escape") close(); }; addEventListener("keydown", esc2);
  const upd = () => { go.disabled = !(ok.checked && pw.value.length); };
  ok.onchange = upd; pw.oninput = () => { msg.textContent = ""; upd(); }; pw.onkeydown = e => { if (e.key === "Enter" && !go.disabled) go.click(); };
  $("#rg-x", m).onclick = close; m.addEventListener("click", e => { if (e.target === m) close(); });
  setTimeout(() => ok.focus(), 50);
  go.onclick = async () => {
    go.disabled = true; go.textContent = "Checking…";
    try {
      const r = await fetch(SB_URL + "/rest/v1/rpc/site_report", { method: "POST", headers: { apikey: SB_KEY, Authorization: "Bearer " + SB_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ p_id: id, p_password: pw.value }) });
      const j = await r.json();
      if (!j || !j.ok) { msg.textContent = "That password isn't right."; go.textContent = "Download the report"; upd(); pw.select(); return; }
      const bin = atob(j.pdf), u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
      const url = URL.createObjectURL(new Blob([u], { type: "application/pdf" }));
      const a = document.createElement("a"); a.href = url; a.download = "equinox_CONFIDENTIAL_" + (j.title || "report").replace(/[^\w]+/g, "_") + ".pdf"; document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 60000);
      close();
    } catch (e) { msg.textContent = "The report couldn't be downloaded. Try again in a moment."; go.textContent = "Download the report"; upd(); }
  };
}
function profitChart(fin) {
  const dates = [...new Set(ORDER.flatMap(a => fin.per[a].prof.map(p => p[0])))].sort(); if (!dates.length) return `<p class="small">Results appear after two nightly reports.</p>`;
  const W = 1100, H = 320, L = 56, B = 34, T = 16, Rr = 10; const vals = ORDER.flatMap(a => fin.per[a].prof.map(p => p[1])); const mx = Math.max(0.5, ...vals), mn = Math.min(0, ...vals);
  const y = v => T + (mx - v) / (mx - mn) * (H - T - B); const gw = (W - L - Rr) / dates.length, bw = Math.min(22, (gw - 16) / ORDER.length);
  let s = `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="Profit a day by airline">`;
  for (let k = 0; k <= 4; k++) { const v = mn + (mx - mn) * k / 4; s += `<line class="axis" x1="${L}" x2="${W - Rr}" y1="${y(v)}" y2="${y(v)}"/>`; } s += `<text x="${L - 8}" y="${y(0) + 4}" text-anchor="end">0</text>`;
  dates.forEach((d, i) => { const x0 = L + i * gw + (gw - bw * ORDER.length) / 2; ORDER.forEach((a, j) => { const p = fin.per[a].prof.find(q => q[0] === d); if (!p) return; const v = p[1]; s += `<rect x="${x0 + j * bw}" y="${Math.min(y(v), y(0))}" width="${bw - 3}" height="${Math.max(1, Math.abs(y(v) - y(0)))}" rx="3" fill="${AL[a].color}"><title>${AL[a].name}, ${shortDate(d)}: ${v >= 0 ? "profit" : "loss"}</title></rect>`; }); s += `<text x="${L + i * gw + gw / 2}" y="${H - 10}" text-anchor="middle">${shortDate(d)}</text>`; });
  s += `<line x1="${L}" x2="${W - Rr}" y1="${y(0)}" y2="${y(0)}" stroke="#5D6785" stroke-width="1"/></svg>`;
  return s + `<div class="pills" style="margin-top:14px">${ORDER.map(a => `<span class="badge">${alChip(a)}</span>`).join("")}</div>`;
}
function growthChart(kind) {
  const first = {};
  for (const f of D.freqs) { const k = kind === "fleet" ? f.t : f.r; if (f.l && (!first[k] || f.l < first[k])) first[k] = f.l; }
  const ds = [...new Set(Object.values(first))].sort(); if (!ds.length) return "";
  const pts = ds.map(d => [d, Object.values(first).filter(x => x <= d).length]);
  const W = 520, H = 220, L = 14, B = 28, T = 26, mx = pts[pts.length - 1][1] * 1.12; const x = i => L + i / (pts.length - 1 || 1) * (W - L - 14), y = v => T + (1 - v / mx) * (H - T - B);
  const path = pts.map((p, i) => `${i ? "L" : "M"}${x(i)},${y(p[1])}`).join(""); const id = "g" + kind;
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="${kind === "fleet" ? "Aircraft" : "Routes"} in service over time"><defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4B3BA8" stop-opacity=".35"/><stop offset="1" stop-color="#4B3BA8" stop-opacity="0"/></linearGradient></defs>
    <path d="${path}L${x(pts.length - 1)},${y(0)}L${x(0)},${y(0)}Z" fill="url(#${id})"/><path d="${path}" fill="none" stroke="#4B3BA8" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>
    <circle cx="${x(pts.length - 1)}" cy="${y(pts[pts.length - 1][1])}" r="5" fill="#F6B44B" stroke="#fff" stroke-width="2"/>
    ${pts.map((p, i) => i === 0 || i === pts.length - 1 ? `<text x="${x(i)}" y="${H - 8}" text-anchor="${i ? "end" : "start"}">${shortDate(p[0])}</text>` : "").join("")}</svg>`;
}
function marketBars(ms) {
  const list = ms.slice().sort((a, b) => b.share - a.share).slice(0, 12); const W = 1100, rowH = 44, L = 270, H = list.length * rowH + 30;
  const x = v => L + v * (W - L - 30);
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="Our share against the market leader">
    ${list.map((m, i) => { const y0 = 14 + i * rowH; const lead = m.top[0]; const leadIsUs = ["Ryanair", "Kingfisher", "Pan Am", "Virgin", "China Eastern", "Malaysia"].includes(lead[0]);
      return `<text x="0" y="${y0 + 17}" style="font:600 14px Manrope;fill:currentColor">${esc(m.market)}</text>
      <rect x="${L}" y="${y0 + 4}" width="${W - L - 30}" height="18" rx="9" fill="rgba(127,140,180,.16)"/>
      <rect x="${L}" y="${y0 + 4}" width="${Math.max(4, x(m.share) - L)}" height="18" rx="9" fill="url(#tw)"><title>${esc(m.market)}: our share ${(m.share * 100).toFixed(0)}%</title></rect>
      ${leadIsUs ? "" : `<line x1="${x(lead[1])}" x2="${x(lead[1])}" y1="${y0}" y2="${y0 + 26}" stroke="#0E1630" stroke-width="2"><title>Leader: ${esc(lead[0])}</title></line>`}
      <text x="${Math.min(W - 40, x(m.share) + 8)}" y="${y0 + 18}" style="font:700 12px Manrope;fill:#4B3BA8">${leadIsUs ? "leader" : ""}</text>`; }).join("")}
    <defs><linearGradient id="tw" x1="0" x2="1"><stop offset="0" stop-color="#4B3BA8"/><stop offset=".6" stop-color="#E86A92"/><stop offset="1" stop-color="#F6B44B"/></linearGradient></defs></svg>
    <div class="pills" style="margin-top:12px"><span class="badge"><i style="display:inline-block;width:22px;height:8px;border-radius:4px;background:linear-gradient(90deg,#4B3BA8,#E86A92,#F6B44B)"></i>Our share</span><span class="badge"><i style="display:inline-block;width:2px;height:14px;background:#0E1630"></i>Market leader</span></div>`;
}
function ring(h) {
  const col = { "Pan Am": "#2A8FD8", Kingfisher: "#D7263D", Ryanair: "#F1C21B", Virgin: "#8E1537", "China Eastern": "#1C3F8C", Malaysia: "#0F8C8C" }[h.airline] || "#4B3BA8";
  const r = 34, c = 2 * Math.PI * r, f = Math.max(0.02, Math.min(1, h.share));
  return `<div class="ring" title="${esc(h.airline)} at ${esc(apName(h.hub))}"><svg viewBox="0 0 90 90"><circle cx="45" cy="45" r="${r}" fill="none" stroke="rgba(127,140,180,.18)" stroke-width="10"/><circle cx="45" cy="45" r="${r}" fill="none" stroke="${col}" stroke-width="10" stroke-linecap="round" stroke-dasharray="${f * c} ${c}" transform="rotate(-90 45 45)"/><text x="45" y="50" text-anchor="middle" style="font:500 15px Unbounded;fill:currentColor">${Math.round(h.share * 100)}%</text></svg><b>${esc(apName(h.hub))}</b><span>${esc(h.airline)}${h.rank === 1 ? ", the largest" : ""}</span></div>`;
}
P.newsletter = () => {
  const iss = (D.reports || []).filter(r => r.kind === "newsletter").sort((x, y) => (x.status === "published" ? 0 : 1) - (y.status === "published" ? 0 : 1) || String(y.at || "").localeCompare(String(x.at || "")));
  return `<section class="phead short" data-nav="dark">${videoTag("clouds_day")}<div class="tint"></div><div class="inner"><p class="kick" style="color:#F6B44B">Newsletter</p><h1 class="h1">gander monthly</h1><p class="lead">A monthly look at the world's airlines: who's biggest, where the traffic is, who leads each market and who's growing fastest. Researched and written entirely by AI. Free to read and to share.</p></div></section>
  <section class="sec light" data-nav="light"><div class="wrap"><div class="nl-list">${iss.map((r, i) => `<article class="nl-issue ${r.status !== "published" ? "upcoming" : ""}"><div class="nl-cover"><span class="wm" style="font-size:15px;color:#fff">gander monthly</span><b>${esc((r.title.split(":")[0] || "").replace("gander monthly, ", ""))}</b><span class="nl-line"></span></div><div class="nl-tx"><p class="small" style="margin:0">${r.status === "published" && r.at ? niceDate(r.at) : "Next issue"}</p><h3 class="h3">${esc(r.title.split(": ")[1] || r.title)}</h3><p>${esc(r.summary || "")}</p>${r.status === "published" && r.has_pdf ? `<button class="btn solid" data-nl="${r.id}">Read the issue</button>` : `<span class="badge">Coming soon</span>`}</div></article>`).join("") || `<div class="empty">The first issue is on its way.</div>`}</div></div></section>`;
};
P.newsletter.after = root => {
  $$("[data-nl]", root).forEach(b => b.onclick = async () => {
    const lbl = b.textContent; b.textContent = "Opening…"; b.disabled = true;
    try {
      const r = await fetch(SB_URL + "/rest/v1/rpc/site_newsletter", { method: "POST", headers: { apikey: SB_KEY, Authorization: "Bearer " + SB_KEY, "Content-Type": "application/json" }, body: JSON.stringify({ p_id: +b.dataset.nl }) });
      const j = await r.json(); if (!j || !j.ok) throw new Error("unavailable");
      openPdf(b64bytes(j.pdf), j.title || "gander monthly", (j.title || "gander monthly").replace(/[^\w]+/g, "_") + ".pdf");
    } catch (e) { alert("The issue couldn't be opened. Try again in a moment."); }
    b.textContent = lbl; b.disabled = false;
  });
};
P.about = () => {
  const ph = MEDIA.photos || {};
  return `<section class="phead short" data-nav="dark">${videoTag("city_dusk")}<div class="tint"></div><div class="inner"><h1 class="h1">About equinox.</h1><p class="lead">A fan-made airline group, planned and flown inside the online game AirlineSim.</p></div></section>
  <section class="sec light" data-nav="light"><div class="wrap split"><div><h2 class="h2">What this is</h2></div><div><p class="lead" style="color:var(--ink)">equinox. runs six airlines in AirlineSim's Gander world as one coordinated group. Every schedule, aircraft and figure on this site comes from the game and from the group's own planning tools, and updates as the airlines grow.</p>
    <p class="lead" style="margin-top:18px">The name comes from the moment day and night are equal: the airlines plan their connection banks around the sun, so the globe on our front page shows the real line between day and night as you look at it.</p></div></div></section>
  <section class="sec paper" data-nav="light" id="disclaimer"><div class="wrap split"><div><h2 class="h2">Disclaimer</h2></div><div><p class="lead" style="color:var(--ink)">${esc(DISCLAIMER)}</p><p class="lead" style="margin-top:18px">The project makes no money: there are no ads, sales or sign-ups. If you represent one of the airlines named here and would like anything changed or removed, the in-game owner of the corresponding AirlineSim enterprise can be contacted through the game.</p></div></div></section>
  <section class="sec light" data-nav="light"><div class="wrap"><h2 class="h2" style="margin-bottom:28px">Credits</h2><div class="split"><div><p class="lead">Videos from Mixkit under the Mixkit free licence. Earth textures from NASA's Blue Marble and Black Marble imagery, via the three-globe project. Typefaces: Unbounded and Manrope, from Google Fonts. Built with three.js and Lenis.</p></div>
    <div class="tbl-wrap" data-lenis-prevent><table class="tbl"><thead><tr><th>Photo</th><th>By</th><th>Licence</th></tr></thead><tbody>${[...Object.entries(ph), ...Object.entries(MEDIA.airports || {}).map(([c, p]) => [apName(c), p])].map(([k, p]) => `<tr><td>${esc(k)}</td><td>${p.page ? `<a class="link" href="${esc(p.page)}" target="_blank" rel="noopener">${esc(p.creator || "unknown")}</a>` : esc(p.creator || "unknown")}</td><td>${p.uploaded && !p.license ? "Used with permission" : esc(String(p.license || "").toUpperCase()) + " " + esc(p.license_version || "")}</td></tr>`).join("")}</tbody></table></div></div></div></section>`;
};
P.notfound = () => `<section class="phead short" data-nav="dark"><div class="tint"></div><div class="inner"><h1 class="h1">This page has flown.</h1><p class="lead">The page you're looking for isn't on our network. <a class="link" href="/" data-link style="color:#fff">Return to the home page</a>.</p></div></section>`;

// ---------- router, scrolling, transitions ----------
let lenis = null; const scrollFns = new Set(); let cleanup = null;
function onScroll(fn) { scrollFns.add(fn); }
function scrollToEl(e) { lenis ? lenis.scrollTo(e, { offset: -90 }) : e.scrollIntoView({ behavior: "smooth" }); }
function navTheme() {
  const nav = $("#nav"); if (!nav) return; let dark = false;
  for (const s of $$("[data-nav]")) { const r = s.getBoundingClientRect(); if (r.top <= 40 && r.bottom >= 40) { dark = s.dataset.nav === "dark"; break; } }
  nav.classList.toggle("on-dark", dark);
}
function routeOf(path) {
  const seg = path.replace(/\/+$/, "").split("/").filter(Boolean);
  if (!seg.length) return ["home"]; if (seg[0] === "airlines" && seg[1]) return ["airline", seg[1]]; if (seg[0] === "news" && seg[1]) return ["article", seg[1]];
  return [P[seg[0]] ? seg[0] : "notfound"];
}
const TITLES = { home: "equinox. six airlines, one sky", newsletter: "gander monthly", flights: "Flight schedules", destinations: "Destinations", network: "Live network", airlines: "Our airlines", news: "Newsroom", investors: "Investor relations", about: "About" };
async function render(first) {
  const [name, arg] = routeOf(location.pathname); const q = new URLSearchParams(location.search);
  if (cleanup) { try { cleanup(); } catch (e) {} cleanup = null; } scrollFns.clear();
  const main = $("#main"); main.innerHTML = P[name](name === "airline" || name === "article" ? arg : q);
  document.title = name === "home" ? TITLES.home : `${TITLES[name] || (name === "airline" ? (AL[ORDER.find(k => AL[k].slug === arg)] || {}).name : "equinox.") || "equinox."} | equinox.`;
  $$(".nav .links a").forEach(a => a.classList.toggle("on", a.getAttribute("href") !== "/" && location.pathname.startsWith(a.getAttribute("href"))));
  if (lenis) lenis.scrollTo(0, { immediate: true }); else scrollTo(0, 0);
  const after = P[name].after; const c = after ? after(main, q) : null; if (typeof c === "function") cleanup = c;
  const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } }), { threshold: 0.2 });
  $$(".rv", main).forEach(e => io.observe(e));
  onScroll(navTheme); navTheme();
  $$("video", main).forEach(v => { v.muted = true; v.play().catch(() => {}); });
}
async function go(href) {
  const u = new URL(href, location.origin); if (u.pathname.startsWith("/planner")) { location.href = u.href; return; }
  $("#sheet").classList.remove("open"); document.body.style.overflow = "";
  const veil = $("#veil");
  if (!RM) await veil.animate([{ transform: "translateY(100%)" }, { transform: "translateY(0)" }], { duration: 420, easing: "cubic-bezier(.7,0,.3,1)", fill: "forwards" }).finished;
  history.pushState(null, "", u.pathname + u.search + u.hash); await render();
  if (!RM) veil.animate([{ transform: "translateY(0)" }, { transform: "translateY(-100%)" }], { duration: 520, easing: "cubic-bezier(.7,0,.3,1)", fill: "forwards" });
}
document.addEventListener("click", e => { const a = e.target.closest("a[data-link]"); if (!a || e.metaKey || e.ctrlKey || e.shiftKey || a.target === "_blank") return; e.preventDefault(); const u = new URL(a.href); if (u.pathname === location.pathname && u.hash) { const t = $(u.hash); if (t) { scrollToEl(t); return; } } go(a.href); });
addEventListener("popstate", () => render());

async function preloader() {
  const seen = sessionStorage.getItem("eq_pre"); if (seen || RM) return;
  sessionStorage.setItem("eq_pre", "1");
  const el = document.createElement("div"); el.className = "pre"; el.innerHTML = `<span class="wm">${"equinox".split("").map(c => `<span class="ch">${c}</span>`).join("")}<i class="dot ch" style="box-shadow:0 0 0 1.5px #fff"></i></span><span class="line"></span>`; document.body.appendChild(el);
  const chs = $$(".ch", el); chs.forEach((c, i) => c.animate([{ transform: "translateY(110%)", opacity: 0 }, { transform: "none", opacity: 1 }], { duration: 700, delay: 120 + i * 55, easing: "cubic-bezier(.2,.7,.1,1)", fill: "forwards" }));
  $(".line", el).animate([{ transform: "scaleX(0)" }, { transform: "scaleX(1)" }], { duration: 1100, delay: 250, easing: "cubic-bezier(.6,0,.2,1)", fill: "forwards" });
  return el;
}
async function boot() {
  shell();
  const pre = await preloader();
  try { await load(); } catch (e) { $("#main").innerHTML = `<section class="phead short" data-nav="dark"><div class="tint"></div><div class="inner"><h1 class="h1">We can't reach the timetable.</h1><p class="lead">Check your connection and reload the page.</p></div></section>`; if (pre) pre.remove(); return; }
  if (window.Lenis && !RM) { lenis = new Lenis({ lerp: 0.1, smoothWheel: true, syncTouch: false, autoResize: true }); new ResizeObserver(() => lenis.resize()).observe($("#main")); const raf = t => { lenis.raf(t); requestAnimationFrame(raf); }; requestAnimationFrame(raf); lenis.on("scroll", () => scrollFns.forEach(f => f())); }
  else addEventListener("scroll", () => scrollFns.forEach(f => f()), { passive: true });
  await render(true);
  if (pre) { await new Promise(r => setTimeout(r, 900)); pre.classList.add("done"); setTimeout(() => pre.remove(), 1100);
    const h = $("#hero-h"); if (h) h.animate([{ transform: "translateY(30px)", opacity: 0 }, { transform: "none", opacity: 1 }], { duration: 1100, delay: 350, easing: "cubic-bezier(.2,.7,.1,1)", fill: "backwards" }); }
}
boot();
})();
