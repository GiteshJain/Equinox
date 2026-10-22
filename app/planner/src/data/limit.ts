// A queue for the captured figures, so a screen that asks for many at once doesn't run them all at once (spec
// docs/specs/2026-10-22-performance-load.md). Each figure takes about half a second alone, but twenty together slow one
// another on the small database and some cross staff's statement limit. At most MAX run at a time; the rest wait their
// turn, in the order they asked.
export const MAX_FIGURES_AT_ONCE = 4;

let running = 0;
const waiting: Array<() => void> = [];

/** Runs `run` when fewer than `max` figures are running, and gives back what it gives. A failure passes through. */
export function limited<T>(run: () => PromiseLike<T> | T, max: number = MAX_FIGURES_AT_ONCE): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const start = () => {
      running++;
      Promise.resolve()
        .then(run)
        .then(resolve, reject)
        .finally(() => {
          running--;
          const next = waiting.shift();
          if (next) next();
        });
    };
    if (running < max) start();
    else waiting.push(start);
  });
}

/** For tests: how many are running and how many wait. */
export const queueState = () => ({ running, waiting: waiting.length });
