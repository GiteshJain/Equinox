// The globe's place on Home. three.js and the scene are loaded only when Home opens (a file of their own in the build),
// and the land is the website's own world outline, read from its file (web/assets/world.js, served at /assets/world.js)
// rather than a copy. Without WebGL the board says so instead of drawing.
import { useEffect, useRef, useState } from "react";
import type { GlobePlane, GlobeRoute, GlobeScene, LatLon } from "./globeScene";

/** The website's world outline (design §9: the world outline and logos come from the website's files). */
export const WORLD_FILE = "/assets/world.js";

declare global {
  interface Window {
    EQ_WORLD?: string;
  }
}

let worldPromise: Promise<string> | null = null;

/** The world outline, loaded once from the website's file, as the website loads it. */
export function loadWorld(): Promise<string> {
  if (typeof window !== "undefined" && window.EQ_WORLD) return Promise.resolve(window.EQ_WORLD);
  worldPromise ??= new Promise<string>((resolve, reject) => {
    const s = document.createElement("script");
    s.src = WORLD_FILE;
    s.async = true;
    s.onload = () => (window.EQ_WORLD ? resolve(window.EQ_WORLD) : reject(new Error("the world outline wasn't in " + WORLD_FILE)));
    s.onerror = () => {
      worldPromise = null;
      reject(new Error("the world outline couldn't be loaded"));
    };
    document.head.appendChild(s);
  });
  return worldPromise;
}

function hasWebGL(): boolean {
  try {
    const c = document.createElement("canvas");
    const gl = c.getContext("webgl2") ?? c.getContext("webgl");
    gl?.getExtension("WEBGL_lose_context")?.loseContext();
    return !!gl;
  } catch {
    return false;
  }
}

const reducedMotion = () => typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;

export function Globe({ routes, bases, planes, now }: { routes: readonly GlobeRoute[]; bases: readonly LatLon[]; planes: readonly GlobePlane[]; now: Date }) {
  const ref = useRef<HTMLCanvasElement>(null);
  const [webgl] = useState(hasWebGL);
  const [scene, setScene] = useState<GlobeScene | null>(null);
  const [failed, setFailed] = useState<string | null>(null);

  useEffect(() => {
    if (!webgl) return;
    let alive = true;
    let made: GlobeScene | null = null;
    Promise.all([import("./globeScene"), loadWorld()])
      .then(([m, world]) => {
        if (!alive || !ref.current) return;
        made = m.createGlobe(ref.current, { world, reducedMotion: reducedMotion() });
        setScene(made);
      })
      .catch((e: unknown) => {
        if (alive) setFailed(e instanceof Error ? e.message : String(e));
      });
    return () => {
      alive = false;
      made?.dispose();
    };
  }, [webgl]);

  useEffect(() => {
    scene?.setNetwork(routes, bases);
  }, [scene, routes, bases]);
  useEffect(() => {
    scene?.setSun(now);
    scene?.setPlanes(planes);
  }, [scene, planes, now]);

  if (!webgl) return <div className="globe-off" data-globe="no-webgl">The globe needs WebGL, which this browser has switched off.</div>;
  return (
    <div className="globewrap" data-globe={failed ? "failed" : scene ? "ready" : "loading"}>
      <canvas ref={ref} className="globe" role="img" aria-label="The globe: every route, and where each aircraft in the air is now" />
      {failed ? <div className="globe-off">The globe couldn't be drawn: {failed}</div> : null}
    </div>
  );
}
