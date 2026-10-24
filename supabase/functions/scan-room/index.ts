// POST /functions/v1/scan-room. Built in week 5.
//
// It already runs every safety check (sign-in, kill switch, limits,
// monthly budget) so the rules are in place before any paid model is
// connected. Until then it answers 501 "not built yet".
//
// In week 5: after the checks, call reserveSpend() right before the paid
// model, and recordUse() only after a successful result.

import { error } from "../_shared/http.ts";
import { checkPaidRequest } from "../_shared/paid.ts";
// Must answer with the contract in ../_shared/room-draft.ts.

// Estimated cost of one call, in cents; set from the chosen model's price.
const COST_CENTS = 2;

Deno.serve(async (req) => {
  if (req.method !== "POST") return error("Use POST.", 405);
  const result = await checkPaidRequest(req, "scan", COST_CENTS);
  if (result instanceof Response) return result;
  return error("Coming in a later update.", 501);
});
