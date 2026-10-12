// Look-only previews (decision #8, design §4): saving works only at equinox-alliance.com and www.equinox-alliance.com.
import { LIVE_HOSTS } from "./config";

/** True for every address that must not save: anything but the two live addresses, exactly. */
export function isPreview(hostname: string): boolean {
  return !LIVE_HOSTS.includes(hostname);
}

/** This page's answer, worked out once when it loads. */
export const PREVIEW: boolean = typeof location === "undefined" ? true : isPreview(location.hostname);

// The only calls a preview may send that aren't plain reads: the staff check. Sign-in (/auth/v1/) is allowed too.
const READ_ONLY_RPCS = new Set(["is_planner_user"]);

/**
 * The safety net under save.ts's own preview check, as the old planner has it: on a preview, any request to the data API
 * or file storage that could write (anything but GET and HEAD, apart from the staff check) is answered here, refused, and
 * never leaves the page.
 */
export function guardFetch(preview: boolean, send: typeof fetch = (input, init) => globalThis.fetch(input, init)): typeof fetch {
  return (input, init) => {
    if (preview) {
      const method = (init?.method ?? (input instanceof Request ? input.method : "GET")).toUpperCase();
      if (method !== "GET" && method !== "HEAD") {
        const path = new URL(input instanceof Request ? input.url : String(input)).pathname;
        const rpc = /^\/rest\/v1\/rpc\/([^/]+)/.exec(path)?.[1];
        if ((path.startsWith("/rest/v1/") && !(rpc && READ_ONLY_RPCS.has(rpc))) || path.startsWith("/storage/v1/")) {
          return Promise.resolve(new Response(JSON.stringify({ code: "preview", message: "Preview: changes aren't saved" }),
            { status: 403, headers: { "content-type": "application/json" } }));
        }
      }
    }
    return send(input, init);
  };
}
