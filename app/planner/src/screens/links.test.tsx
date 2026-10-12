// Every screen's link in the header goes to that screen's own address (a bug the rehearsal found on 12 Oct: Home's
// link went to /planner/next, which Cloudflare redirects, because React Router builds Home's link as the router's base).
import { createElement } from "react";
import { renderToString } from "react-dom/server";
import { NavLink, RouterProvider, createMemoryRouter } from "react-router";
import { describe, expect, it } from "vitest";
import { ROUTER_BASENAME } from "../App";
import { SCREENS, screenHref, screenRoute } from "./screens";

describe("the header's links", () => {
  it("each screen's link is its address as Cloudflare serves it", () => {
    const Links = () => createElement("nav", null, SCREENS.map((s) => createElement(NavLink, { key: s.id, to: screenRoute(s) }, s.name)));
    const router = createMemoryRouter([{ path: "/*", element: createElement(Links) }],
      { basename: ROUTER_BASENAME, initialEntries: ["/planner/next/routes"] });
    const html = renderToString(createElement(RouterProvider, { router }));
    const hrefs = [...html.matchAll(/href="([^"]+)"/g)].map((m) => m[1]);
    expect(hrefs).toEqual(SCREENS.map(screenHref));
  });
});
