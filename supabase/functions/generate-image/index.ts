// POST /functions/v1/generate-image
// Body: VisualizeInput (see ../_shared/image-provider.ts).
// Returns { image: base64 } on success.
//
// Order: safety checks (sign-in, kill switch, 3/day, 10/month, budget) →
// reserve the cost → call the model → record the use only on success.
// Until a model is chosen it answers 501 "not built yet", after the checks.

import { error, json } from "../_shared/http.ts";
import { checkPaidRequest, recordUse, reserveSpend } from "../_shared/paid.ts";
import { chosenProvider, describeLayout, RejectedError, type VisualizeInput } from "../_shared/image-provider.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return error("Use POST.", 405);

  const provider = chosenProvider();
  const user = await checkPaidRequest(req, "image", provider?.costCents ?? 0);
  if (user instanceof Response) return user;
  if (!provider) return error("Coming in a later update.", 501);

  let input: VisualizeInput;
  try {
    input = await req.json();
  } catch {
    return error("The request body must be JSON.", 400);
  }
  if (!Array.isArray(input.corners) || input.corners.length < 3 || !Array.isArray(input.pieces)) {
    return error("Missing room or furniture.", 400);
  }

  if (!(await reserveSpend("image", provider.costCents))) {
    return error("This month's budget is used up. It resets on the 1st.", 503);
  }

  try {
    const result = await Promise.race([
      provider.generate(input, describeLayout(input)),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error("timeout")), 80_000)),
    ]);
    // Counted against the person's allowance only now, after success.
    await recordUse(user.id, "image", provider.costCents);
    let binary = "";
    for (const byte of result.bytes) binary += String.fromCharCode(byte);
    return json({ image: btoa(binary), mime: result.mime });
  } catch (e) {
    if (e instanceof RejectedError) return error(e.message, 422);
    if (e instanceof Error && e.message === "timeout") return error("The picture took too long.", 504);
    console.error("image provider failed", e);
    return error("The picture couldn't be made.", 502);
  }
});
