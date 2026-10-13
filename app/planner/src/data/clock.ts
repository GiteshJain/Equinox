// The moment the screens show, moved on each minute (the old planner redrew Home each minute). The planner itself never
// keeps time apart from this: the planning library takes the moment as an argument, and the captured figures' p_as_of
// is this moment too.
import { useEffect, useState } from "react";

export const MINUTE = 60_000;

/** Now, updated at the start of every step (a minute by default). */
export function useNow(stepMs: number = MINUTE): Date {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    let t: ReturnType<typeof setTimeout>;
    const next = () => stepMs - (Date.now() % stepMs) || stepMs;
    const tick = () => {
      setNow(new Date());
      t = setTimeout(tick, next());
    };
    t = setTimeout(tick, next());
    return () => clearTimeout(t);
  }, [stepMs]);
  return now;
}
