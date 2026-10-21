// The shell (decision #18, build pull request 1): sign-in and the staff check, then the header and the nine screens
// (grouped by when they're used since 20 Oct: spec docs/specs/2026-10-20-today-performance-systems.md).
import { useEffect, type ComponentType } from "react";
import { Outlet, createBrowserRouter, useLocation, useNavigate } from "react-router";
import { BASENAME } from "./data/config";
import { PREVIEW } from "./data/preview";
import { useAccess } from "./data/session";
import { Home } from "./screens/home/Home";
import { Interline } from "./screens/interline/Interline";
import { Performance } from "./screens/performance/Performance";
import { Photos } from "./screens/photos/Photos";
import { Reference } from "./screens/reference/Reference";
import { Routes } from "./screens/routes/Routes";
import { SCREENS, movedTo, type ScreenId } from "./screens/screens";
import { Systems } from "./screens/systems/Systems";
import { Tails } from "./screens/tails/Tails";
import { Today } from "./screens/today/Today";
import { Band, Clocks } from "./ui/Clocks";
import { ErrorBox } from "./ui/ErrorBox";
import { Header } from "./ui/Header";
import { Messages } from "./ui/Messages";
import { SignIn } from "./ui/SignIn";

const COMPONENTS: Record<ScreenId, ComponentType> = {
  home: Home, today: Today, routes: Routes, tails: Tails, performance: Performance, interline: Interline, photos: Photos, reference: Reference,
  systems: Systems,
};

function PreviewNotice() {
  if (!PREVIEW) return null;
  return (
    <div className="eqpreview" role="status">
      Preview: changes here aren't saved. <a href="https://equinox-alliance.com/planner/">Open the live planner</a>
    </div>
  );
}

function Shell() {
  const [access, retry] = useAccess();
  if (access.kind === "checking") return <main className="view"><div className="loading">Opening the planner…</div></main>;
  if (access.kind === "signed-out") return <SignIn message={access.message} />;
  if (access.kind === "check-failed") {
    return (
      <main className="view">
        <ErrorBox error={access.message} />
        <button type="button" className="primary" onClick={retry}>Try again</button>
      </main>
    );
  }
  return (
    <div data-shell>
      <Header />
      <Band />
      <Clocks />
      <Outlet />
    </div>
  );
}

function Root() {
  return (
    <>
      <Shell />
      <Messages />
      <PreviewNotice />
    </>
  );
}

function NotFound() {
  return (
    <main className="view">
      <div className="vh">
        <h1>Not found</h1>
        <p>There's no such screen in the planner. <a href={BASENAME + "/"}>Home</a></p>
      </div>
    </main>
  );
}

/** An address of a screen that went on 20 Oct (Check, Review, Hubs), reached inside the planner: on to its new one, as
 *  web/_redirects sends the browser's (movedTo). */
function Moved() {
  const loc = useLocation();
  const navigate = useNavigate();
  const to = movedTo(loc.pathname, loc.search) ?? "/";
  useEffect(() => { navigate(to + loc.hash, { replace: true }); }, [to, loc.hash, navigate]);
  return <main className="view"><div className="loading">Opening…</div></main>;
}

function RouteError() {
  return <main className="view"><ErrorBox error="Something went wrong on this screen. Reload the page to try again." /></main>;
}

// The router's base ends in a slash, so Home's own address is /planner/ as Cloudflare serves it (React Router builds
// Home's link as the base itself). main.tsx moves a bare /planner to it before the router starts.
export const ROUTER_BASENAME = BASENAME + "/";

export const createPlannerRouter = () => createBrowserRouter([
  {
    path: "/",
    element: <Root />,
    errorElement: <RouteError />,
    children: [
      ...SCREENS.map((s) => {
        const Component = COMPONENTS[s.id];
        return s.path === "" ? { index: true, element: <Component /> } : { path: `${s.path}/*`, element: <Component /> };
      }),
      ...["check", "review", "hubs"].map((p) => ({ path: `${p}/*`, element: <Moved /> })),
      { path: "*", element: <NotFound /> },
    ],
  },
], { basename: ROUTER_BASENAME });
