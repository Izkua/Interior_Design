// Access to our database and to sign-in checks, from inside Edge Functions.
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase to
// every Edge Function automatically. The service role key skips row level
// security, so it must never be sent to the app.

import { createClient, type SupabaseClient, type User } from "npm:@supabase/supabase-js@2.45.4";
import { secret } from "./http.ts";

let admin: SupabaseClient | undefined;

export function adminClient(): SupabaseClient {
  admin ??= createClient(secret("SUPABASE_URL"), secret("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return admin;
}

/**
 * The signed-in person who sent the request, or null for guests.
 * The token is checked with Supabase Auth, so it can't be faked.
 */
export async function currentUser(req: Request): Promise<User | null> {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "");
  // Guests send the publishable key instead of a sign-in token.
  if (!token || token.startsWith("sb_publishable_")) return null;
  const { data, error } = await adminClient().auth.getUser(token);
  if (error || !data.user) return null;
  return data.user;
}

/** Counts one request against a limit; false means "too many". */
export async function underRateLimit(bucket: string, max: number, windowSeconds: number): Promise<boolean> {
  const { data, error } = await adminClient().rpc("hit_rate_limit", {
    p_bucket: bucket,
    p_max: max,
    p_window_seconds: windowSeconds,
  });
  if (error) throw error;
  return data === true;
}

/** Records spend if it stays under this month's limits; false = hard stop. */
export async function trySpend(
  service: string,
  units: number,
  cents: number,
  maxUnits: number | null,
  maxCents: number | null,
): Promise<boolean> {
  const { data, error } = await adminClient().rpc("try_spend", {
    p_service: service,
    p_units: units,
    p_cents: cents,
    p_max_units: maxUnits,
    p_max_cents: maxCents,
  });
  if (error) throw error;
  return data === true;
}

export async function config<T>(key: string): Promise<T> {
  const { data, error } = await adminClient().from("app_config").select("value").eq("key", key).single();
  if (error) throw error;
  return data.value as T;
}
