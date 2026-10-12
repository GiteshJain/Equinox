// Sign-in and the staff check (design §4): Supabase's sign-in, then is_planner_user(). Sign-ups stay off (#11), so
// there's no form for them. An account that isn't staff is signed out with the old planner's message.
import { useEffect, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { queryClient } from "./query";
import { supabase } from "./supabase";

export type Access =
  | { kind: "checking" }
  | { kind: "signed-out"; message: string }
  | { kind: "staff"; session: Session }
  | { kind: "check-failed"; message: string };

export const NOT_STAFF = "This account doesn't have access to the planner.";

// Kept across the sign-out that follows a refused account, so the form can say why.
let pending = "";

async function decide(session: Session | null): Promise<Access> {
  if (!session) {
    const message = pending;
    pending = "";
    return { kind: "signed-out", message };
  }
  const { data, error } = await supabase.rpc("is_planner_user");
  if (error) return { kind: "check-failed", message: `Couldn't check access to the planner: ${error.message}` };
  if (data !== true) {
    pending = NOT_STAFF;
    await supabase.auth.signOut();
    queryClient.clear();
    return { kind: "signed-out", message: NOT_STAFF };
  }
  return { kind: "staff", session };
}

/** Who is using the planner, kept up to date as they sign in and out. */
export function useAccess(): [Access, () => void] {
  const [access, setAccess] = useState<Access>({ kind: "checking" });
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    let alive = true;
    let staffUser: string | null = null;
    const { data } = supabase.auth.onAuthStateChange((event, session) => {
      // A refreshed token for the same staff member needs no new check.
      if (event === "TOKEN_REFRESHED" && session && session.user.id === staffUser) return;
      // Run outside the callback: supabase-js asks that its own calls aren't awaited inside it.
      setTimeout(() => {
        void decide(session).then((a) => {
          if (!alive) return;
          staffUser = a.kind === "staff" ? a.session.user.id : null;
          setAccess(a);
        });
      }, 0);
    });
    return () => {
      alive = false;
      data.subscription.unsubscribe();
    };
  }, [attempt]);
  return [access, () => setAttempt((n) => n + 1)];
}

/** Signs in; answers the message to show, or null when it went through (the staff check follows by itself). */
export async function signIn(email: string, password: string): Promise<string | null> {
  if (!email) return "Enter your email.";
  if (password.length < 8) return "The password needs at least 8 characters.";
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (!error) return null;
  if (/confirm/i.test(error.message)) return "Your email isn't confirmed yet. Ask Claude to confirm the account.";
  if (/invalid/i.test(error.message)) return "That email and password don't match an account.";
  return "Sign-in failed: " + error.message;
}

export async function signOut(): Promise<void> {
  await supabase.auth.signOut();
  queryClient.clear();
}
