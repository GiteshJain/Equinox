// The planner's own build (decision #23): the moment it was built and the change it was built from, as the build wrote
// them in (vite.config.ts). Check's Systems board shows them, so a failed deploy after a merge is plain to see.

export interface BuildStamp {
  /** When the build ran (ISO, UTC). */
  at: string;
  /** The change it was built from (the commit's full id), or "" when the build couldn't tell. */
  commit: string;
  /** That change's title, when the build could read it. */
  subject: string;
}

/** The stamp this planner was built with, or null when it has none. */
export function buildStamp(): BuildStamp | null {
  const at = import.meta.env.EQ_BUILD_AT ?? "";
  if (!at) return null;
  return { at, commit: import.meta.env.EQ_BUILD_COMMIT ?? "", subject: import.meta.env.EQ_BUILD_SUBJECT ?? "" };
}
