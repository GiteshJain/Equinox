// A pill, as the old planner's: ok (green), warn (amber), bad (red) or mute (grey).
import type { ReactNode } from "react";

export type PillKind = "ok" | "warn" | "bad" | "mute";

export function Pill({ kind, small, children, title }: { kind: PillKind; small?: boolean; children: ReactNode; title?: string }) {
  return <span className={`pill ${kind}${small ? " sm" : ""}`} title={title}>{children}</span>;
}
