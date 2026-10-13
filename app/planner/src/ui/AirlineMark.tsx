// An airline's mark: its logo when one is given, else a dot in its colour (airlines.livery_color), as the old planner's lv().
import type { CSSProperties } from "react";

export function AirlineMark({ color, logo, name, size = 9 }: { color: string | null | undefined; logo?: string | null; name?: string; size?: number }) {
  if (logo) return <img className="almark" src={logo} alt={name ?? ""} height={size + 9} />;
  const style = { "--lv": color || "#8B96A8", width: size, height: size } as CSSProperties;
  return <i className="lv" style={style} aria-hidden="true" />;
}
