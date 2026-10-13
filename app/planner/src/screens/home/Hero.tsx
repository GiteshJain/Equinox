// The operations hero at the top of Home (the old planner's eqHeroEnsure and eqHeroUpdate): the large globe with the
// greeting, how many aircraft are in the air, and four tiles (flights today, departing in the next hour, aircraft and
// routes, the average load). On the old Home it stands in for the page heading and the key-figure row. three.js and the
// globe's scene load only when Home opens (a file of their own in the build). Without WebGL the hero shows its words and
// tiles over the dark sky, as the old one does when its globe can't start.
import { useEffect, useRef, useState } from "react";
import type { HeroFigures } from "./figures";
import type { HeroPlane, HeroRoute, HeroScene } from "./heroScene";

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

export function Hero({ figures, hello, routes, planes, now }: {
  figures: HeroFigures | null; hello: string; routes: readonly HeroRoute[]; planes: readonly HeroPlane[]; now: Date;
}) {
  const ref = useRef<HTMLCanvasElement>(null);
  const [webgl] = useState(hasWebGL);
  const [scene, setScene] = useState<HeroScene | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    if (!webgl) return;
    let alive = true;
    let made: HeroScene | null = null;
    import("./heroScene")
      .then((m) => {
        if (!alive || !ref.current) return;
        made = m.createHero(ref.current, { reducedMotion: reducedMotion() });
        setScene(made);
      })
      .catch(() => {
        if (alive) setFailed(true);
      });
    return () => {
      alive = false;
      made?.dispose();
    };
  }, [webgl]);

  useEffect(() => {
    scene?.setRoutes(routes);
  }, [scene, routes]);
  useEffect(() => {
    scene?.setSun(now);
    scene?.setPlanes(planes);
  }, [scene, routes, planes, now]);

  return (
    <section id="eqhero" data-hero data-globe={!webgl ? "no-webgl" : failed ? "failed" : scene ? "ready" : "loading"}>
      <canvas id="eqglobe" ref={ref} aria-label="Live network" />
      <div className="eqh-shade" />
      <div className="eqh-in">
        <p className="eqh-hi" id="eqh-hi">{hello}</p>
        <h1 className="eqh-t"><span id="eqh-air" data-hero-air>{figures?.in_air ?? 0}</span> aircraft in the air.</h1>
        <span className="eqh-line" />
        <div className="eqh-tiles" data-figure="home: the network now">
          {(figures?.tiles ?? []).map((t) => (
            <div key={t.id} data-hero-tile={t.id}><b>{t.value}</b><span>{t.label}</span></div>
          ))}
        </div>
      </div>
    </section>
  );
}
