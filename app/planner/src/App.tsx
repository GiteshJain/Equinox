// The shell (decision #18, build pull request 1): sign-in and the staff check, then the header and the nine screens.
import type { ComponentType } from "react";
import { Outlet, createBrowserRouter } from "react-router";
import { BASENAME } from "./data/config";
import { PREVIEW } from "./data/preview";
import { useAccess } from "./data/session";
import { Check } from "./screens/check/Check";
import { Home } from "./screens/home/Home";
import { Hubs } from "./screens/hubs/Hubs";
import { Interline } from "./screens/interline/Interline";
import { Photos } from "./screens/photos/Photos";
import { Reference } from "./screens/reference/Reference";
import { Review } from "./screens/review/Review";
import { Routes } from "./screens/routes/Routes";
import { SCREENS, type ScreenId } from "./screens/screens";
import { Tails } from "./screens/tails/Tails";
import { Band, Clocks } from "./ui/Clocks";
import { ErrorBox } from "./ui/ErrorBox";
import { Header } from "./ui/Header";
import { Messages } from "./ui/Messages";
import { SignIn } from "./ui/SignIn";

const COMPONENTS: Record<ScreenId, ComponentType> = {
  home: Home, routes: Routes, tails: Tails, hubs: Hubs, check: Check, review: Review, interline: Interline, photos: Photos,
  reference: Reference,
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
      { path: "*", element: <NotFound /> },
    ],
  },
], { basename: ROUTER_BASENAME });
