// The top bar (spec docs/specs/2026-10-22-planner-look-foundation.md, "The shell"): one slim bar on night, as the
// website's. The wordmark with "planner"; the nav (Home, Today, Routes, Tails, Performance, Competition, and More, a menu
// with every other screen the router has); the search box; the clock button (UTC now, opening the game clocks); one
// round account button opening the save state, the local/UTC toggle, the Website link and Sign out. Under the bar, the
// website's twilight line. On a phone the nav goes into a menu button and the search box is hidden, as before; nothing
// scrolls sideways. Every screen's link stays in the header (data-screen-link), shut menus included.
import { useEffect, useRef, useState } from "react";
import { NavLink, useLocation } from "react-router";
import { time } from "@rules";
import { useNow } from "../data/clock";
import { useSaveState, saver } from "../data/saving";
import { signOut } from "../data/session";
import { useTimeMode } from "../data/timeMode";
import { SCREENS, screenRoute, type ScreenId } from "../screens/screens";
import { Clocks } from "./Clocks";
import { Search } from "./Search";

/** The screens in the bar itself; every other screen goes under More. */
export const BAR_SCREENS: readonly ScreenId[] = ["home", "today", "routes", "tails", "performance", "competition"];

type Menu = "nav" | "more" | "clocks" | "account" | null;

export function Header() {
  const save = useSaveState();
  const [mode, toggle] = useTimeMode();
  const now = useNow();
  const [open, setOpen] = useState<Menu>(null);
  const root = useRef<HTMLElement>(null);
  const loc = useLocation();

  // A menu shuts when a screen opens (or its link is clicked again), on Escape, and on a click anywhere outside the bar.
  const [at, setAt] = useState(loc.pathname);
  if (at !== loc.pathname) { setAt(loc.pathname); setOpen(null); }
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setOpen(null); };
    const onDown = (e: MouseEvent) => { if (root.current && !root.current.contains(e.target as Node)) setOpen(null); };
    document.addEventListener("keydown", onKey);
    document.addEventListener("mousedown", onDown);
    return () => { document.removeEventListener("keydown", onKey); document.removeEventListener("mousedown", onDown); };
  }, [open]);
  const flip = (m: Exclude<Menu, null>) => setOpen((o) => (o === m ? null : m));

  const bar = SCREENS.filter((s) => BAR_SCREENS.includes(s.id));
  const more = SCREENS.filter((s) => !BAR_SCREENS.includes(s.id));
  const moreOn = more.some((s) => loc.pathname === screenRoute(s) || loc.pathname.startsWith(screenRoute(s) + "/"));
  const utc = time.clock(now.getUTCHours() * 60 + now.getUTCMinutes());

  return (
    <header className="eq-header" ref={root} data-open={open ?? ""}>
      <div className="eq-bar">
        <button type="button" className="eq-navbtn" data-menu="nav" aria-expanded={open === "nav"} aria-controls="eq-nav"
          aria-label="Screens" onClick={() => flip("nav")}><span /><span /><span /></button>
        <NavLink className="brand" to="/" end aria-label="equinox. planner home">
          <span className="eqwm">equinox<i></i></span><span className="eqtag">planner</span>
        </NavLink>
        <nav className={"eq-nav" + (open === "nav" ? " open" : "")} id="eq-nav" aria-label="Sections">
          {bar.map((s) => (
            <NavLink key={s.id} to={screenRoute(s)} end={s.id === "home"} data-screen-link={s.id} onClick={() => setOpen(null)}>{s.name}</NavLink>
          ))}
          <div className={"eq-more" + (open === "more" ? " open" : "")}>
            <button type="button" className={"eq-morebtn" + (moreOn ? " active" : "")} data-menu="more" aria-expanded={open === "more"}
              onClick={() => flip("more")}>More</button>
            <div className="eq-menu eq-moremenu" role="menu">
              {more.map((s) => (
                <NavLink key={s.id} to={screenRoute(s)} data-screen-link={s.id} role="menuitem" onClick={() => setOpen(null)}>{s.name}</NavLink>
              ))}
            </div>
          </div>
        </nav>
        <Search />
        <div className="hctl">
          <div className={"eq-pop" + (open === "clocks" ? " open" : "")}>
            <button type="button" className="eq-clockbtn" data-menu="clocks" aria-expanded={open === "clocks"}
              title="Game time at the hubs" onClick={() => flip("clocks")} data-utc-now>
              <span className="ckic" aria-hidden="true" />{utc}<span className="cku">UTC</span>
            </button>
            <div className="eq-menu eq-clockpanel" aria-label="Game clocks">
              <div className="eq-menuh">Game time at the hubs</div>
              <Clocks />
            </div>
          </div>
          <div className={"eq-pop" + (open === "account" ? " open" : "")}>
            <button type="button" className={"eq-acct " + save.kind} data-menu="account" aria-expanded={open === "account"}
              aria-label={"Account · " + save.label} title={save.label} onClick={() => flip("account")}>
              <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true"><circle cx="12" cy="8.5" r="3.6" fill="none" stroke="currentColor" strokeWidth="1.8" /><path d="M4.8 19.5c1.3-3.4 4-5 7.2-5s5.9 1.6 7.2 5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" /></svg>
              <i className="eq-acctdot" aria-hidden="true" />
            </button>
            <div className="eq-menu eq-acctmenu" role="menu">
              {save.kind === "failed" ? (
                <button type="button" className={"savestate " + save.kind} data-save-state={save.kind} onClick={() => void saver.retry()}
                  title="Send the changes that didn't get through again">{save.label}</button>
              ) : (
                <span className={"savestate " + save.kind} data-save-state={save.kind}>{save.label}</span>
              )}
              <button type="button" className="tm" id="timemode" data-time-mode={mode} onClick={toggle}
                title="Switch between local and UTC times">{mode === "utc" ? "Times in UTC" : "Times in Local"}<span className="tmv">{mode === "utc" ? "UTC" : "Local"}</span></button>
              <a className="eqsite" href="/" title="Open the public website">Website</a>
              <button type="button" className="tm" id="signout" onClick={() => void signOut()}>Sign out</button>
            </div>
          </div>
        </div>
      </div>
      <div className="eq-twilight" aria-hidden="true" />
    </header>
  );
}
