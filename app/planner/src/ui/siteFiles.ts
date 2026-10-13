// The website's own files the planner draws with (design §9: the world outline and logos come from the website's files,
// no longer embedded in the planner): web/assets/world.js (window.EQ_WORLD, the world outline as an SVG path on a
// 1000 × 500 equirectangular map) and web/assets/logos.js (window.EQ_LOGOS, each airline's in-game logo by its planner
// name, as the old planner embedded them). Each is loaded once, as the website loads it, and read rather than copied.
declare global {
  interface Window {
    EQ_WORLD?: string;
    EQ_LOGOS?: Record<string, string>;
  }
}

export const WORLD_FILE = "/assets/world.js";
export const LOGOS_FILE = "/assets/logos.js";

const loading = new Map<string, Promise<void>>();

function loadScript(src: string): Promise<void> {
  let p = loading.get(src);
  if (!p) {
    p = new Promise<void>((resolve, reject) => {
      const s = document.createElement("script");
      s.src = src;
      s.async = true;
      s.onload = () => resolve();
      s.onerror = () => {
        loading.delete(src);
        reject(new Error(`${src} couldn't be loaded`));
      };
      document.head.appendChild(s);
    });
    loading.set(src, p);
  }
  return p;
}

/** The world outline (an SVG path in a 1000 × 500 box). */
export async function loadWorld(): Promise<string> {
  if (!window.EQ_WORLD) await loadScript(WORLD_FILE);
  if (!window.EQ_WORLD) throw new Error(`the world outline wasn't in ${WORLD_FILE}`);
  return window.EQ_WORLD;
}

/** The airlines' in-game logos by planner name (data URLs). */
export async function loadLogos(): Promise<Record<string, string>> {
  if (!window.EQ_LOGOS) await loadScript(LOGOS_FILE);
  return window.EQ_LOGOS ?? {};
}
