// Check: not rebuilt yet (build pull request 9). Until then it links to the old planner.
import { NotBuilt } from "../../ui/NotBuilt";
import { screen } from "../screens";

export const Check = () => <NotBuilt screen={screen("check")} />;
