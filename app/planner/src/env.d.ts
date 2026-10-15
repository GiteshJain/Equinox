// What the build writes into the planner (vite.config.ts, decision #23): when it was built and the change it came from.
interface ImportMetaEnv {
  readonly EQ_BUILD_AT?: string;
  readonly EQ_BUILD_COMMIT?: string;
  readonly EQ_BUILD_SUBJECT?: string;
}
