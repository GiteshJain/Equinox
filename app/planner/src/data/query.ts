// TanStack Query for every read (design §5): a screen's data is kept while you move around and read again when it's
// stale or after a save.
import { QueryClient } from "@tanstack/react-query";

/** The one place that says how long read data stays fresh before it's read again. */
export const STALE_MS = 60_000;

export const queryClient = new QueryClient({
  defaultOptions: { queries: { staleTime: STALE_MS, retry: 1, refetchOnWindowFocus: false } },
});

/**
 * Every read of a table's rows is keyed ["table", <table>, ...]: after a save, save.ts puts the answer into every read
 * of the tables it touched and reads them again.
 */
export const tableKey = (table: string, ...rest: unknown[]) => ["table", table, ...rest] as const;
