import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QueryClientProvider } from "@tanstack/react-query";
import { RouterProvider } from "react-router/dom";
import { BASENAME } from "./data/config";
import { createPlannerRouter } from "./App";
import { queryClient } from "./data/query";
import { exposeForChecks } from "./data/saving";
import { openingFacts } from "./data/useStoredFigures";
import "./ui/styles.css";

// Cloudflare sends /planner to /planner/ (web/_redirects); this does the same anywhere else, before the router reads
// the address.
if (location.pathname === BASENAME) history.replaceState(history.state, "", BASENAME + "/" + location.search + location.hash);
// the glass look (to-do 225) is the planner's only look: <html data-look="glass"> is in index.html, so sign-in and the
// landing page open in it too
exposeForChecks();
const router = createPlannerRouter();
// the checks move between screens and routes as a click would (tests/routes_side_by_side_test.py), not by reloading
if (window.__eqPlanner) window.__eqPlanner.go = (to) => void router.navigate(to);
if (window.__eqPlanner) window.__eqPlanner.figures = openingFacts;

const root = document.getElementById("root");
if (!root) throw new Error("the page has no #root");
createRoot(root).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  </StrictMode>,
);
