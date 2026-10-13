// The globe on Home (spec docs/specs/2026-10-13-home.md §2), drawn with three.js, which is loaded only here (Globe.tsx
// imports this file when Home opens). As the old planner's Home draws its network: every route as an arc in its
// airline's colour, each aircraft in the air as a light along its route, our bases, and day and night as they are at the
// moment given, the night side darker with the dusk line between. The land is the world outline the website uses
// (web/assets/world.js, an equirectangular path 1000 × 500), painted onto the sphere. It turns slowly unless reduced
// motion is asked for; it can be turned by dragging. Nothing here works out where an aircraft is: Home gives it the
// planning library's positions.
import {
  AdditiveBlending, BackSide, BufferGeometry, CanvasTexture, CatmullRomCurve3, Color, Float32BufferAttribute, Group, Mesh,
  MeshBasicMaterial, PerspectiveCamera, Points, PointsMaterial, Scene, ShaderMaterial, SphereGeometry, TubeGeometry, Vector3,
  WebGLRenderer, type Material,
} from "three";

export type LatLon = readonly [number, number];
export interface GlobeRoute { key: string; a: LatLon; b: LatLon; color: string }
export interface GlobePlane { a: LatLon; b: LatLon; share: number }

export interface GlobeScene {
  setNetwork(routes: readonly GlobeRoute[], bases: readonly LatLon[]): void;
  setPlanes(planes: readonly GlobePlane[]): void;
  setSun(now: Date): void;
  dispose(): void;
}

const DEG = Math.PI / 180;

/** A point on the globe (radius r) at a latitude and longitude, as the website's and the old planner's globes place it. */
export function v3(lat: number, lon: number, r = 1): Vector3 {
  const ph = (90 - lat) * DEG, th = (lon + 180) * DEG;
  return new Vector3(-r * Math.sin(ph) * Math.cos(th), r * Math.cos(ph), r * Math.sin(ph) * Math.sin(th));
}

/** The great circle from a to b, lifted a little off the ground in the middle (longer routes higher). */
export function arcPoints(a: LatLon, b: LatLon, n = 48): Vector3[] {
  const A = v3(a[0], a[1]).normalize(), B = v3(b[0], b[1]).normalize(), ang = A.angleTo(B), sn = Math.sin(ang);
  const pts: Vector3[] = [];
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const q = sn < 1e-6 ? A.clone() : A.clone().multiplyScalar(Math.sin((1 - t) * ang) / sn).add(B.clone().multiplyScalar(Math.sin(t * ang) / sn));
    q.multiplyScalar(1.003 + (0.012 + 0.1 * ang / Math.PI) * Math.sin(Math.PI * t));
    pts.push(q);
  }
  return pts;
}

/** Where the sun is overhead at a moment: its declination and the longitude where it is noon. */
export function subsolar(now: Date): LatLon {
  const doy = (now.getTime() - Date.UTC(now.getUTCFullYear(), 0, 0)) / 864e5;
  const decl = -23.44 * Math.cos(2 * Math.PI / 365 * (doy + 10));
  return [decl, (12 - now.getUTCHours() - now.getUTCMinutes() / 60) * 15];
}

function landTexture(world: string): CanvasTexture {
  const c = document.createElement("canvas");
  c.width = 2048;
  c.height = 1024;
  const x = c.getContext("2d");
  if (!x) throw new Error("no 2D canvas for the land");
  x.fillStyle = "#0D1840";
  x.fillRect(0, 0, c.width, c.height);
  x.strokeStyle = "rgba(255,255,255,0.045)";
  x.lineWidth = 1.2;
  for (let lon = -150; lon < 180; lon += 30) {
    const px = (lon + 180) / 360 * c.width;
    x.beginPath(); x.moveTo(px, 0); x.lineTo(px, c.height); x.stroke();
  }
  for (let lat = -60; lat <= 60; lat += 30) {
    const py = (90 - lat) / 180 * c.height;
    x.beginPath(); x.moveTo(0, py); x.lineTo(c.width, py); x.stroke();
  }
  x.save();
  x.scale(c.width / 1000, c.height / 500);
  const land = new Path2D(world);
  x.fillStyle = "#2B4190";
  x.fill(land);
  x.strokeStyle = "#4661B5";
  x.lineWidth = 0.45;
  x.stroke(land);
  x.restore();
  const t = new CanvasTexture(c);
  t.anisotropy = 4;
  return t;
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

export function createGlobe(canvas: HTMLCanvasElement, opts: { world: string; reducedMotion: boolean }): GlobeScene {
  const renderer = new WebGLRenderer({ canvas, antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  const scene = new Scene(), camera = new PerspectiveCamera(32, 1, 0.1, 100), earth = new Group();
  earth.rotation.order = "XYZ";   // turned on its own axis first, then tilted towards the viewer
  scene.add(earth);
  const owned: { dispose(): void }[] = [];   // geometries, materials and textures made here, given back at the end

  // the earth: land and sea from the world outline, darker on the night side, a warm line at dusk
  const land = landTexture(opts.world);
  const sun = { value: new Vector3(1, 0, 0) };
  const earthGeo = new SphereGeometry(1, 96, 96);
  const earthMat = new ShaderMaterial({
    uniforms: { map: { value: land }, sun },
    vertexShader: "varying vec2 vUv; varying vec3 vN; void main(){ vUv = uv; vN = normal; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",
    fragmentShader: "uniform sampler2D map; uniform vec3 sun; varying vec2 vUv; varying vec3 vN; void main(){ float d = dot(normalize(vN), normalize(sun)); float k = smoothstep(-0.12, 0.12, d); vec3 base = texture2D(map, vUv).rgb; vec3 night = base * 0.36 + vec3(0.004, 0.008, 0.03); vec3 c = mix(night, base * 1.06, k); c += vec3(0.96, 0.62, 0.36) * exp(-pow(d / 0.07, 2.0)) * 0.24; gl_FragColor = vec4(c, 1.0); }",
  });
  earth.add(new Mesh(earthGeo, earthMat));
  // the air around it
  const airGeo = new SphereGeometry(1.085, 64, 64);
  const airMat = new ShaderMaterial({
    side: BackSide, blending: AdditiveBlending, transparent: true, depthWrite: false,
    vertexShader: "varying vec3 vN; void main(){ vN = normalize(normalMatrix * normal); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",
    fragmentShader: "varying vec3 vN; void main(){ float i = pow(0.72 - dot(vN, vec3(0.0, 0.0, 1.0)), 3.2); gl_FragColor = vec4(0.36, 0.48, 1.0, 1.0) * i * 1.2; }",
  });
  scene.add(new Mesh(airGeo, airMat));
  owned.push(land, earthGeo, earthMat, airGeo, airMat);

  // routes, bases and aircraft, replaced as Home gives them
  const routes = new Group(), sprite = glowSprite();
  earth.add(routes);
  owned.push(sprite);
  const baseGeo = new BufferGeometry(), planeGeo = new BufferGeometry();
  const baseMat = new PointsMaterial({ size: 0.045, map: sprite, color: new Color("#FFE2A8"), transparent: true, depthWrite: false, blending: AdditiveBlending });
  const planeMat = new PointsMaterial({ size: 0.06, map: sprite, color: new Color("#FFFFFF"), transparent: true, depthWrite: false, blending: AdditiveBlending });
  earth.add(new Points(baseGeo, baseMat), new Points(planeGeo, planeMat));
  owned.push(baseGeo, planeGeo, baseMat, planeMat);
  const arcs = new Map<string, Vector3[]>();
  const arcOf = (a: LatLon, b: LatLon) => {
    const k = `${a[0]},${a[1]}>${b[0]},${b[1]}`;
    let p = arcs.get(k);
    if (!p) arcs.set(k, (p = arcPoints(a, b)));
    return p;
  };
  const routeParts: { dispose(): void }[] = [];

  // the view: turned to show our network (about 30°E), tilted towards the north; dragged by hand; turning slowly
  let rotY = -Math.PI / 2 - 30 * DEG, rotX = 0.35, drag: { x: number; y: number; ry: number; rx: number } | null = null;
  const spin = !opts.reducedMotion;
  let raf = 0, last = 0, onScreen = true, disposed = false;
  const frame = (t: number) => {
    raf = 0;
    const dt = last ? Math.min(64, t - last) : 16;
    last = t;
    if (spin && !drag) rotY += 0.00004 * dt;
    earth.rotation.y = rotY;
    earth.rotation.x = rotX;
    renderer.render(scene, camera);
    if ((spin || drag) && onScreen && !document.hidden && !disposed) raf = requestAnimationFrame(frame);
  };
  const kick = () => {
    if (!raf && !disposed) {
      last = 0;
      raf = requestAnimationFrame(frame);
    }
  };
  const size = () => {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) return;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.position.set(0, 0, 2.45 / (0.573 * Math.min(1, w / h)));   // the globe fills about four fifths of the height
    camera.updateProjectionMatrix();
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
  size();

  return {
    setNetwork(list, bases) {
      if (disposed) return;
      for (const p of routeParts.splice(0)) p.dispose();
      routes.clear();
      const mats = new Map<string, MeshBasicMaterial>();
      for (const r of list) {
        let m = mats.get(r.color);
        if (!m) mats.set(r.color, (m = new MeshBasicMaterial({ color: new Color(r.color), transparent: true, opacity: 0.85, depthWrite: false })));
        const g = new TubeGeometry(new CatmullRomCurve3(arcOf(r.a, r.b)), 48, 0.0017, 4, false);
        routes.add(new Mesh(g, m));
        routeParts.push(g);
      }
      routeParts.push(...(mats.values() as Iterable<Material>));
      const pos: number[] = [];
      for (const b of bases) {
        const p = v3(b[0], b[1], 1.006);
        pos.push(p.x, p.y, p.z);
      }
      baseGeo.setAttribute("position", new Float32BufferAttribute(pos, 3));
      baseGeo.computeBoundingSphere();
      kick();
    },
    setPlanes(list) {
      if (disposed) return;
      const pos: number[] = [];
      for (const p of list) {
        const pts = arcOf(p.a, p.b), i = Math.max(0, Math.min(1, p.share)) * (pts.length - 1), a = Math.floor(i), b = Math.min(a + 1, pts.length - 1);
        const pa = pts[a], pb = pts[b];
        if (!pa || !pb) continue;
        const q = pa.clone().lerp(pb, i - a);
        pos.push(q.x, q.y, q.z);
      }
      planeGeo.setAttribute("position", new Float32BufferAttribute(pos, 3));
      planeGeo.computeBoundingSphere();
      kick();
    },
    setSun(now) {
      if (disposed) return;
      const [lat, lon] = subsolar(now);
      sun.value.copy(v3(lat, lon));
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
      renderer.dispose();
    },
  };
}
