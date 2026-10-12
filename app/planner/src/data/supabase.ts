// The one Supabase client (design §5): the live project, its public key, and the preview guard (decision #8).
import { createClient } from "@supabase/supabase-js";
import type { Database } from "../db/types";
import { AUTH_STORAGE_KEY, SB_KEY, SB_URL } from "./config";
import { PREVIEW, guardFetch } from "./preview";

export const supabase = createClient<Database>(SB_URL, SB_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, storageKey: AUTH_STORAGE_KEY },
  global: { fetch: guardFetch(PREVIEW) },
});
