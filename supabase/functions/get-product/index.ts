// GET /functions/v1/get-product?id=<channel3 product id>
// Returns { product: AppProduct } with a current price and a fresh buy link.
//
// Channel3 doesn't charge for product details, so this doesn't count toward
// the monthly search cap and isn't cached: buy links are short-lived and
// should be fetched right before they're shown. It's still rate-limited.

import { error, json } from "../_shared/http.ts";
import { config, currentUser, underRateLimit } from "../_shared/supabase.ts";
import { type C3Product, normalize } from "../_shared/products.ts";

Deno.serve(async (req) => {
  const id = new URL(req.url).searchParams.get("id");
  if (!id || !/^[A-Za-z0-9_-]{1,64}$/.test(id)) return error("Missing or bad product id.", 400);

  const settings = await config<{ searches_per_10_min: number }>("catalog");
  const user = await currentUser(req);
  const device = req.headers.get("x-device-id")?.slice(0, 64);
  const bucket = user ? `user:${user.id}` : device ? `device:${device}` : null;
  if (!bucket) return error("Missing device ID.", 400);
  // Product pages are opened more often than searches are made.
  if (!(await underRateLimit(`${bucket}:product`, settings.searches_per_10_min * 2, 600))) {
    return error("Too many requests.", 429);
  }

  const apiKey = Deno.env.get("CHANNEL3_API_KEY");
  if (!apiKey) return error("The live catalog isn't set up yet.", 503);

  const response = await fetch(
    `https://api.trychannel3.com/v1/products/${encodeURIComponent(id)}?length_unit=cm`,
    { headers: { "x-api-key": apiKey } },
  );
  // 404 also means "no offer in this locale", per Channel3's docs.
  if (response.status === 404) return error("This product isn't available any more.", 404);
  if (!response.ok) {
    console.error("Channel3 error", response.status, await response.text());
    return error("The catalog didn't answer.", 502);
  }

  const product = normalize((await response.json()) as C3Product);
  if (!product) return error("That product has no offers.", 404);
  return json({ product });
});
