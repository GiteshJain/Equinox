// A screen not rebuilt yet (design §9): its name, one line saying it's still in the old planner, and a link there.
import type { ReactNode } from "react";
import { OLD_PLANNER } from "../data/config";
import type { Screen } from "../screens/screens";

export function NotBuilt({ screen, children }: { screen: Screen; children?: ReactNode }) {
  return (
    <main className="view" data-screen={screen.id}>
      <div className="vh">
        <h1>{screen.name}</h1>
        <p data-not-built>
          {screen.name} is still in the old planner. <a href={OLD_PLANNER}>Open it in the old planner</a>
        </p>
      </div>
      {children}
    </main>
  );
}
