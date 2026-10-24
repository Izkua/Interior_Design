// GET /functions/v1/get-product?id=<channel3 product id>
// Returns { product: AppProduct }. Cached for a day like searches.

import { error, json, secret } from "../_shared/http.ts";
import { adminClient, config, currentUser, trySpend, underRateLimit } from "../_shared/supabase.ts";
import { type C3Product, normalize } from "../_shared/products.ts";

Deno.serve(async (req) => {
  const id = new URL(req.url).searchParams.get("id");
  if (!id || !/^[A-Za-z0-9_-]{1,64}$/.test(id)) return error("Missing or bad product id.", 400);

  const settings = await config<{ monthly_search_limit: number; searches_per_10_min: number }>("catalog");
  const user = await currentUser(req);
  const device = req.headers.get("x-device-id")?.slice(0, 64);
  const bucket = user ? `user:${user.id}` : device ? `device:${device}` : null;
  if (!bucket) return error("Missing device ID.", 400);
  if (!(await underRateLimit(bucket, settings.searches_per_10_min, 600))) return error("Too many requests.", 429);

  const db = adminClient();
  const key = `product:${id}`;
  const { data: cached } = await db.from("product_cache").select("response, created_at").eq("key", key).maybeSingle();
  if (cached && Date.now() - new Date(cached.created_at).getTime() < 24 * 3600_000) {
    return json({ product: cached.response, cached: true });
  }

  if (!(await trySpend("channel3", 1, 0, settings.monthly_search_limit, null))) {
    return error("The catalog has reached its monthly limit.", 503);
  }

  const response = await fetch(`https://api.trychannel3.com/v1/products/${encodeURIComponent(id)}`, {
    headers: { "x-api-key": secret("CHANNEL3_API_KEY") },
  });
  if (response.status === 404) return error("No such product.", 404);
  if (!response.ok) return error("The catalog didn't answer.", 502);

  const product = normalize((await response.json()) as C3Product);
  if (!product) return error("That product has no offers.", 404);
  await db.from("product_cache").upsert({ key, response: product, created_at: new Date().toISOString() });
  return json({ product, cached: false });
});
