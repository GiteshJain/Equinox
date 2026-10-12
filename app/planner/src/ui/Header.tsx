// The header (spec §3): the brand as the old planner shows it, the nine screens, the local/UTC toggle, the save state
// and sign-out. On a phone the screens wrap onto their own row, which scrolls sideways inside itself.
import { NavLink } from "react-router";
import { useSaveState, saver } from "../data/saving";
import { signOut } from "../data/session";
import { useTimeMode } from "../data/timeMode";
import { SCREENS, screenRoute } from "../screens/screens";

export function Header() {
  const save = useSaveState();
  const [mode, toggle] = useTimeMode();
  return (
    <header className="eq-header">
      <NavLink className="brand" to="/" end aria-label="equinox. planner home">
        <span className="eqwm">equinox<i></i></span><span className="eqtag">planner</span>
      </NavLink>
      <nav className="eq-nav" aria-label="Sections">
        {SCREENS.map((s) => (
          <NavLink key={s.id} to={screenRoute(s)} end={s.id === "home"} data-screen-link={s.id}>{s.name}</NavLink>
        ))}
      </nav>
      <div className="hctl">
        {save.kind === "failed" ? (
          <button type="button" className={"savestate " + save.kind} data-save-state={save.kind} onClick={() => void saver.retry()}
            title="Send the changes that didn't get through again">{save.label}</button>
        ) : (
          <span className={"savestate " + save.kind} data-save-state={save.kind}>{save.label}</span>
        )}
        <button type="button" className="tm" id="timemode" data-time-mode={mode} onClick={toggle}
          title="Switch between local and UTC times">{mode === "utc" ? "UTC" : "Local"}</button>
        <button type="button" className="tm" id="signout" onClick={() => void signOut()}>Sign out</button>
      </div>
    </header>
  );
}
