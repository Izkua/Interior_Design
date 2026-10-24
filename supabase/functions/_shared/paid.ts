// The checks every paid feature (AI images, item labeling, room scans)
// goes through before spending any money:
//   1. The person must be signed in (a verified token).
//   2. The feature's switch in app_config must be on (the kill switch).
//   3. Per-person limits: for images, 3 a day and 10 a month.
//   4. The feature's monthly budget must have room (hard stop).
// Only then would the real work run: call reserveSpend() just before the
// paid call, and recordUse() after it succeeds, so a failed attempt never
// uses up someone's allowance.

import type { User } from "npm:@supabase/supabase-js@2.45.4";
import { error } from "./http.ts";
import { adminClient, config, currentUser, trySpend } from "./supabase.ts";

type Kind = "image" | "label" | "scan";

interface FeatureConfig {
  enabled: boolean;
  per_day?: number;
  per_month?: number;
  monthly_budget_cents: number;
}

const CONFIG_KEY: Record<Kind, string> = { image: "image_generation", label: "labeling", scan: "room_scan" };

/** Returns the user if every check passes, or the Response to send back. */
export async function checkPaidRequest(req: Request, kind: Kind, costCents: number): Promise<User | Response> {
  const user = await currentUser(req);
  if (!user) return error("Sign in to use this.", 401);

  const settings = await config<FeatureConfig>(CONFIG_KEY[kind]);
  if (!settings.enabled) return error("This is paused for now. Please try again later.", 503);

  const used = await usage(user.id, kind);
  if (settings.per_day !== undefined && used.today >= settings.per_day) {
    return error(`You've used today's ${settings.per_day}. More tomorrow.`, 429);
  }
  if (settings.per_month !== undefined && used.month >= settings.per_month) {
    return error(`You've used this month's ${settings.per_month}.`, 429);
  }

  // Is there room left in this month's budget? (Checked here; the money is
  // only reserved by reserveSpend, right before the real work.)
  const spent = await spentThisMonth(kind);
  if (spent + costCents > settings.monthly_budget_cents) {
    return error("This month's budget is used up. It resets on the 1st.", 503);
  }
  return user;
}

/**
 * Reserves the cost right before calling a paid model. The database adds
 * it only if it stays under the budget, so two requests at once can't both
 * slip past. Returns false at the hard stop.
 */
export async function reserveSpend(kind: Kind, costCents: number): Promise<boolean> {
  const settings = await config<FeatureConfig>(CONFIG_KEY[kind]);
  return await trySpend(kind, 1, costCents, null, settings.monthly_budget_cents);
}

async function spentThisMonth(kind: Kind): Promise<number> {
  const now = new Date();
  const month = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString().slice(0, 10);
  const { data, error: e } = await adminClient().from("spend_ledger").select("cents")
    .eq("month", month).eq("service", kind).maybeSingle();
  if (e) throw e;
  return data?.cents ?? 0;
}

/** Records one successful use against the person's allowance. */
export async function recordUse(userID: string, kind: Kind, costCents: number) {
  await adminClient().from("usage_events").insert({ user_id: userID, kind, cost_cents: costCents });
}

export async function usage(userID: string, kind: Kind): Promise<{ today: number; month: number }> {
  const db = adminClient();
  const now = new Date();
  const startOfDay = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())).toISOString();
  const startOfMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();
  const count = async (since: string) => {
    const { count, error: e } = await db.from("usage_events").select("id", { count: "exact", head: true })
      .eq("user_id", userID).eq("kind", kind).gte("created_at", since);
    if (e) throw e;
    return count ?? 0;
  };
  return { today: await count(startOfDay), month: await count(startOfMonth) };
}
