// Sign-in, as the old planner's (design §4): email and password, no sign-up (#11). The staff check follows by itself.
import { useState, type FormEvent } from "react";
import { signIn } from "../data/session";

export function SignIn({ message }: { message: string }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [said, setSaid] = useState<string | null>(null);
  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setSaid("Working…");
    const problem = await signIn(email.trim(), password);
    setSaid(problem);
    setBusy(false);
  }
  return (
    <div className="gate" id="gate">
      <div className="gwrap">
        <div className="gart">
          <div className="orb"></div>
          <div className="gbrand"><span className="eqwm">equinox<i></i></span></div>
          <div>
            <h1>Day and night, on schedule.</h1>
            <p>The equinox. planner: routes, rotations, banks and loads across the group's airlines. Staff only.</p>
            <p style={{ marginTop: 14, opacity: 0.6, fontSize: 12 }}>Fan-made and non-commercial, for the game AirlineSim. Airline names and logos belong to their owners.</p>
          </div>
        </div>
        <div className="gform">
          <form className="gbox" onSubmit={(e) => void submit(e)}>
            <h2>Sign in</h2>
            <p className="gsub">Open the equinox. planner. <a href="/">Back to the website</a></p>
            <input id="g-email" type="email" placeholder="Email" autoComplete="username" value={email}
              onChange={(e) => setEmail(e.target.value)} />
            <input id="g-pass" type="password" placeholder="Password" autoComplete="current-password" value={password}
              onChange={(e) => setPassword(e.target.value)} />
            <button id="g-in" className="primary" type="submit" disabled={busy}>Sign in</button>
            <div className="gmsg" id="g-msg" role="status">{said ?? message}</div>
          </form>
        </div>
      </div>
    </div>
  );
}
