// TanStack Query for every read (design §5): a screen's data is kept while you move around and read again when it's
// stale or after a save.
import { QueryClient } from "@tanstack/react-query";

/** The one place that says how long read data stays fresh before it's read again. */
export const STALE_MS = 60_000;

/**
 * The captured figures change only when a capture comes in, so they stay fresh for 15 minutes (24 Oct): read again
 * every minute, every screen re-ran twenty or more heavy calls, and on the small database they slowed one another past
 * their limits while the morning's capture and scan were writing. A save that changes a figure still reads it again at
 * once (its screen invalidates it), and Reload reads the capture's state. The capture's and the systems' state stay at
 * a minute: they are light, and they say whether tonight's capture is in.
 */
export const FIGURES_STALE_MS = 15 * 60_000;

export const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: STALE_MS, retry: 1, refetchOnWindowFocus: false } },
});
// later defaults win where keys overlap (TanStack Query merges every matching default in the order set)
queryClient.setQueryDefaults(["figures"], { staleTime: FIGURES_STALE_MS });
queryClient.setQueryDefaults(["table", "fare_plan", "ladder"], { staleTime: FIGURES_STALE_MS });
queryClient.setQueryDefaults(["figures", "capture_status"], { staleTime: STALE_MS });
queryClient.setQueryDefaults(["figures", "system_status"], { staleTime: STALE_MS });

/**
 * Every read of a table's rows is keyed ["table", <table>, ...]: after a save, save.ts puts the answer into every read
 * of the tables it touched and reads them again.
 */
export const tableKey = (table: string, ...rest: unknown[]) => ["table", table, ...rest] as const;
