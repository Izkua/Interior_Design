// POST /functions/v1/delete-account
// Deletes the signed-in person's account for good: their profile, their
// usage history, and their sign-in. Apple requires this inside the app.
//
// The profile and usage rows go automatically when the auth user is
// deleted ("on delete cascade" in the database), but they are removed
// first anyway so nothing is left if a later step fails.

import { error, json } from "../_shared/http.ts";
import { adminClient, currentUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return error("Use POST.", 405);
  const user = await currentUser(req);
  if (!user) return error("Sign in first.", 401);

  const db = adminClient();
  const steps = [
    () => db.from("usage_events").delete().eq("user_id", user.id),
    () => db.from("profiles").delete().eq("id", user.id),
    () => db.from("rate_limits").delete().like("bucket", `user:${user.id}%`),
  ];
  for (const step of steps) {
    const { error: e } = await step();
    if (e) {
      console.error("delete-account step failed", e);
      return error("Couldn't delete your data. Please try again.", 500);
    }
  }

  // Uses the service role, which exists only inside this function.
  const { error: authError } = await db.auth.admin.deleteUser(user.id);
  if (authError) {
    console.error("deleteUser failed", authError);
    return error("Couldn't delete your sign-in. Please try again.", 500);
  }
  return json({ deleted: true });
});
