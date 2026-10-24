// POST /functions/v1/label-item. Built in week 5.
//
// It already runs every safety check (sign-in, kill switch, limits,
// monthly budget) so the rules are in place before any paid model is
// connected. Until then it answers 501 "not built yet".
//
// In week 5: after the checks, call reserveSpend() right before the paid
// model, and recordUse() only after a successful result.

import { error } from "../_shared/http.ts";
import { checkPaidRequest } from "../_shared/paid.ts";

// Estimated cost of one call, in cents; set from the chosen model's price.
const COST_CENTS = 1;

Deno.serve(async (req) => {
  if (req.method !== "POST") return error("Use POST.", 405);
  const result = await checkPaidRequest(req, "label", COST_CENTS);
  if (result instanceof Response) return result;
  return error("Coming in a later update.", 501);
});
