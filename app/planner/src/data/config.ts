// Where the new planner lives and what it talks to (decision #18, design §3 and §4).

// The live Supabase project and its public (anon) key, the same as the old planner's (web/planner/index.html, SB_URL
// and SB_KEY). The key is public by design: what it can reach is decided by the database's rules (the map, "Where keys
// are kept"). tests/planner_next_test.py reads these two lines to answer the planner from the rehearsal's copy instead.
export const SB_URL = "https://ulecwsyedvwcxgdzmhoq.supabase.co";
export const SB_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsZWN3c3llZHZ3Y3hnZHptaG9xIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAyMTg5MzcsImV4cCI6MjEwNTc5NDkzN30.tC56dOgmPeYB3m58aDy4ADnnaZ3613P6MFp2pVXUj_Y";

// Decision #8: only these addresses save. Every other address (a Cloudflare preview, a local test server) is a
// look-only preview: it reads the live data and sends no writes.
export const LIVE_HOSTS: readonly string[] = ["equinox-alliance.com", "www.equinox-alliance.com"];

// The planner's address: web/_redirects maps everything under it to the page (the switch, 14 Oct; it was /planner/next
// while it was built, and those addresses now redirect here). The old planner's address, /planner/old/, redirects here
// too since the clean-up removed it, and nothing in this planner links to it (design §11, §12).
export const BASENAME = "/planner";

// Kept on this device: the sign-in (its own key, so the old planner's sign-in, under gander-auth, is left alone) and the
// local/UTC choice. Nothing else is kept on the device (design §14, choice 3).
export const AUTH_STORAGE_KEY = "equinox-planner-auth";
export const TIME_MODE_STORAGE_KEY = "equinox-planner-time-mode";
