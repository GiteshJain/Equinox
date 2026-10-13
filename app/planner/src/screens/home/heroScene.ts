// The operations hero's globe on Home (the old planner's eqGlobeInit, web/planner/index.html), drawn with three.js,
// which is loaded only here (Hero.tsx imports this file when Home opens). As the old planner draws it: the earth from the
// day and night pictures it uses (three-globe's, from cdn.jsdelivr.net, pinned to 2.31.1), lit by the sun at the moment
// given with a warm band at dusk; a glow of air around it; every flying route as a faint line; each aircraft in the air
// as a light along its route. It sits right of centre on a wide screen and higher on a narrow one, turns slowly (not when
// reduced motion is asked for, spec §2), and can be turned by dragging. Nothing here works out where an aircraft is:
// Home gives it the planning library's positions.
import {
  AdditiveBlending, BackSide, BufferGeometry, CanvasTexture, CatmullRomCurve3, Color, Float32BufferAttribute, Group, Mesh,
  MeshBasicMaterial, PerspectiveCamera, Points, PointsMaterial, Scene, ShaderMaterial, SphereGeometry, TextureLoader, TubeGeometry,
  Vector3, WebGLRenderer,
} from "three";

export type LatLon = readonly [number, number];
export interface HeroRoute { key: string; a: LatLon; b: LatLon }
export interface HeroPlane { a: LatLon; b: LatLon; share: number }

export interface HeroScene {
  setRoutes(routes: readonly HeroRoute[]): void;
  setPlanes(planes: readonly HeroPlane[]): void;
  setSun(now: Date): void;
  dispose(): void;
}

/** The pictures the old planner's globe uses (and its page header band). */
export const EARTH_IMAGES = "https://cdn.jsdelivr.net/npm/three-globe@2.31.1/example/img/";

const DEG = Math.PI / 180;

/** A point on the globe (radius r) at a latitude and longitude, as the old planner's globe places it. */
export function v3(lat: number, lon: number, r = 1): Vector3 {
  const ph = (90 - lat) * DEG, th = (lon + 180) * DEG;
  return new Vector3(-r * Math.sin(ph) * Math.cos(th), r * Math.cos(ph), r * Math.sin(ph) * Math.sin(th));
}

/** The great circle from a to b in 48 steps, lifted off the ground in the middle (longer routes higher), as the old. */
export function arcPoints(a: LatLon, b: LatLon): Vector3[] {
  const A = v3(a[0], a[1]).normalize(), B = v3(b[0], b[1]).normalize(), ang = A.angleTo(B), pts: Vector3[] = [];
  for (let i = 0; i <= 48; i++) {
    const t = i / 48, sn = Math.sin(ang);
    const q = sn < 1e-6 ? A.clone() : A.clone().multiplyScalar(Math.sin((1 - t) * ang) / sn).add(B.clone().multiplyScalar(Math.sin(t * ang) / sn));
    q.multiplyScalar(1.003 + (0.012 + 0.1 * ang / Math.PI) * Math.sin(Math.PI * t));
    pts.push(q);
  }
  return pts;
}

/** Where the sun is overhead at a moment: its declination and the longitude where it is noon (the old sun()). */
export function subsolar(now: Date): LatLon {
  const doy = (now.getTime() - Date.UTC(now.getUTCFullYear(), 0, 0)) / 864e5;
  const decl = -23.44 * Math.cos(2 * Math.PI / 365 * (doy + 10));
  return [decl, (12 - now.getUTCHours() - now.getUTCMinutes() / 60) * 15];
}

function glowSprite(): CanvasTexture {
  const c = document.createElement("canvas");
  c.width = c.height = 64;
  const x = c.getContext("2d");
  if (x) {
    const g = x.createRadialGradient(32, 32, 0, 32, 32, 32);
    g.addColorStop(0, "rgba(255,255,255,1)");
    g.addColorStop(0.25, "rgba(255,255,255,.85)");
    g.addColorStop(1, "rgba(255,255,255,0)");
    x.fillStyle = g;
    x.fillRect(0, 0, 64, 64);
  }
  return new CanvasTexture(c);
}

export function createHero(canvas: HTMLCanvasElement, opts: { reducedMotion: boolean }): HeroScene {
  const R = new WebGLRenderer({ canvas, antialias: true, alpha: true });
  R.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.8));
  const scene = new Scene(), cam = new PerspectiveCamera(32, 1, 0.1, 100), earthG = new Group();
  scene.add(earthG);
  const owned: { dispose(): void }[] = [];

  // the earth: the day picture where the sun is up, the night picture (city lights) where it isn't, warm at dusk
  const tl = new TextureLoader();
  tl.setCrossOrigin("anonymous");
  let redraw = () => {};   // once the pictures arrive (the view may be still, with reduced motion)
  const dayTex = tl.load(EARTH_IMAGES + "earth-day.jpg", () => redraw()), nightTex = tl.load(EARTH_IMAGES + "earth-night.jpg", () => redraw());
  const uni = { dayTex: { value: dayTex }, nightTex: { value: nightTex }, sun: { value: new Vector3(1, 0, 0) } };
  const earthGeo = new SphereGeometry(1, 96, 96);
  const earthMat = new ShaderMaterial({
    uniforms: uni,
    vertexShader: "varying vec2 vUv; varying vec3 vN; void main(){ vUv=uv; vN=normal; gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);} ",
    fragmentShader: "uniform sampler2D dayTex; uniform sampler2D nightTex; uniform vec3 sun; varying vec2 vUv; varying vec3 vN; void main(){ float d=dot(normalize(vN),normalize(sun)); float k=smoothstep(-0.14,0.14,d); vec3 day=texture2D(dayTex,vUv).rgb*0.92; vec3 night=texture2D(nightTex,vUv).rgb*1.35+vec3(0.012,0.02,0.06); vec3 c=mix(night,day,k); c+=vec3(0.95,0.55,0.38)*exp(-pow(d/0.09,2.0))*0.30; gl_FragColor=vec4(c,1.0);} ",
  });
  earthG.add(new Mesh(earthGeo, earthMat));
  // the air around it
  const airGeo = new SphereGeometry(1.085, 64, 64);
  const airMat = new ShaderMaterial({
    side: BackSide, blending: AdditiveBlending, transparent: true,
    vertexShader: "varying vec3 vN; void main(){ vN=normalize(normalMatrix*normal); gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.0);} ",
    fragmentShader: "varying vec3 vN; void main(){ float i=pow(0.72-dot(vN,vec3(0,0,1.0)),3.2); gl_FragColor=vec4(0.36,0.48,1.0,1.0)*i*1.2;} ",
  });
  scene.add(new Mesh(airGeo, airMat));
  owned.push(dayTex, nightTex, earthGeo, earthMat, airGeo, airMat);

  // the routes, one faint line each, and the aircraft in the air, replaced as Home gives them
  const routes = new Group();
  earthG.add(routes);
  const routeMat = new MeshBasicMaterial({ color: new Color("#DCE3F5"), transparent: true, opacity: 0.42, depthWrite: false });
  const sprite = glowSprite(), pg = new BufferGeometry();
  const planeMat = new PointsMaterial({ size: 0.05, map: sprite, vertexColors: true, transparent: true, depthWrite: false, blending: AdditiveBlending });
  earthG.add(new Points(pg, planeMat));
  owned.push(routeMat, sprite, pg, planeMat);
  const routeGeo = new Map<string, Vector3[]>();
  const routeParts: { dispose(): void }[] = [];
  const keyOf = (a: LatLon, b: LatLon) => `${a[0]},${a[1]}>${b[0]},${b[1]}`;

  // the view: turned to about 70°E, level; dragged by hand; turning slowly
  let rotY = -(70 * DEG) - Math.PI / 2, rotX = 0, drag: { x: number; y: number; ry: number; rx: number } | null = null;
  earthG.rotation.order = "YXZ";
  const spin = !opts.reducedMotion;
  let raf = 0, last = 0, onScreen = true, disposed = false;
  const loop = (t: number) => {
    raf = 0;
    const dt = last ? Math.min(64, t - last) : 16;
    last = t;
    if (spin && !drag) rotY += 0.00005 * dt;
    earthG.rotation.y = rotY;
    earthG.rotation.x = rotX;
    R.render(scene, cam);
    if ((spin || drag) && onScreen && !document.hidden && !disposed) raf = requestAnimationFrame(loop);
  };
  const kick = () => {
    if (!raf && !disposed) {
      last = 0;
      raf = requestAnimationFrame(loop);
    }
  };
  const size = () => {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    R.setSize(w, h, false);
    cam.aspect = w / h;
    cam.position.set(0, 0, w < 700 ? 4.8 : 4.4);
    cam.updateProjectionMatrix();
    earthG.position.x = w > 900 ? 0.62 : 0;
    earthG.position.y = w > 900 ? 0 : 0.55;
    kick();
  };
  const down = (e: PointerEvent) => {
    drag = { x: e.clientX, y: e.clientY, ry: rotY, rx: rotX };
    canvas.setPointerCapture(e.pointerId);
    kick();
  };
  const move = (e: PointerEvent) => {
    if (!drag) return;
    rotY = drag.ry + (e.clientX - drag.x) / Math.max(1, canvas.clientWidth) * 3.2;
    rotX = Math.max(-0.6, Math.min(0.9, drag.rx + (e.clientY - drag.y) / Math.max(1, canvas.clientHeight) * 1.6));
    kick();
  };
  const up = () => {
    drag = null;
    kick();
  };
  canvas.addEventListener("pointerdown", down);
  canvas.addEventListener("pointermove", move);
  canvas.addEventListener("pointerup", up);
  canvas.addEventListener("pointercancel", up);
  const resize = new ResizeObserver(size);
  resize.observe(canvas);
  const seen = new IntersectionObserver((es) => {
    onScreen = es.some((e) => e.isIntersecting);
    if (onScreen) kick();
  });
  seen.observe(canvas);
  const shown = () => { if (!document.hidden) kick(); };
  document.addEventListener("visibilitychange", shown);
  redraw = kick;
  size();

  return {
    setRoutes(list) {
      if (disposed) return;
      for (const p of routeParts.splice(0)) p.dispose();
      routes.clear();
      routeGeo.clear();
      const seenKeys = new Set<string>();
      for (const r of list) {
        if (seenKeys.has(r.key)) continue;
        seenKeys.add(r.key);
        const pts = arcPoints(r.a, r.b);
        routeGeo.set(keyOf(r.a, r.b), pts);
        routeGeo.set(keyOf(r.b, r.a), pts.slice().reverse());
        const g = new TubeGeometry(new CatmullRomCurve3(pts), 64, 0.0013, 5, false);
        routes.add(new Mesh(g, routeMat));
        routeParts.push(g);
      }
      kick();
    },
    setPlanes(list) {
      if (disposed) return;
      const pos: number[] = [], col: number[] = [];
      for (const p of list) {
        const pts = routeGeo.get(keyOf(p.a, p.b));
        if (!pts) continue;
        const i = Math.max(0, Math.min(1, p.share)) * (pts.length - 1), a = Math.floor(i), b = Math.min(a + 1, pts.length - 1);
        const pa = pts[a], pb = pts[b];
        if (!pa || !pb) continue;
        const q = pa.clone().lerp(pb, i - a);
        pos.push(q.x, q.y, q.z);
        col.push(1, 1, 1);
      }
      pg.setAttribute("position", new Float32BufferAttribute(pos, 3));
      pg.setAttribute("color", new Float32BufferAttribute(col, 3));
      pg.computeBoundingSphere();
      kick();
    },
    setSun(now) {
      if (disposed) return;
      const [lat, lon] = subsolar(now);
      uni.sun.value.copy(v3(lat, lon));
      kick();
    },
    dispose() {
      disposed = true;
      if (raf) cancelAnimationFrame(raf);
      resize.disconnect();
      seen.disconnect();
      document.removeEventListener("visibilitychange", shown);
      canvas.removeEventListener("pointerdown", down);
      canvas.removeEventListener("pointermove", move);
      canvas.removeEventListener("pointerup", up);
      canvas.removeEventListener("pointercancel", up);
      for (const p of routeParts.splice(0)) p.dispose();
      for (const o of owned) o.dispose();
      R.dispose();
    },
  };
}
