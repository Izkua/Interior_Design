// POST /functions/v1/search-products
// Body: the app's CatalogQuery. Returns { products: AppProduct[], cached: boolean }.
//
// Order of checks: rate limit (per person, or per device for guests) →
// 24-hour cache → monthly credit cap (hard stop) → Channel3.

import { error, json, secret } from "../_shared/http.ts";
import { adminClient, config, currentUser, trySpend, underRateLimit } from "../_shared/supabase.ts";
import { type AppQuery, cacheKey, type C3Product, channel3Request, normalize } from "../_shared/products.ts";

const CACHE_HOURS = 24;

Deno.serve(async (req) => {
  if (req.method !== "POST") return error("Use POST.", 405);

  let query: AppQuery;
  try {
    query = await req.json();
  } catch {
    return error("The request body must be JSON.", 400);
  }

  const settings = await config<{ monthly_search_limit: number; searches_per_10_min: number }>("catalog");

  // 1. Rate limit.
  const user = await currentUser(req);
  const device = req.headers.get("x-device-id")?.slice(0, 64);
  const bucket = user ? `user:${user.id}` : device ? `device:${device}` : null;
  if (!bucket) return error("Missing device ID.", 400);
  if (!(await underRateLimit(bucket, settings.searches_per_10_min, 600))) {
    return error("Too many searches. Try again in a few minutes.", 429);
  }

  // 2. Cache.
  const key = await cacheKey(query);
  const db = adminClient();
  const { data: cached } = await db.from("product_cache").select("response, created_at").eq("key", key).maybeSingle();
  if (cached && Date.now() - new Date(cached.created_at).getTime() < CACHE_HOURS * 3600_000) {
    return json({ products: cached.response, cached: true });
  }

  // 3. Hard stop at the monthly credit limit (1 credit per search).
  if (!(await trySpend("channel3", 1, 0, settings.monthly_search_limit, null))) {
    return error("The catalog has reached its monthly limit. Showing saved products instead.", 503);
  }

  // 4. Ask Channel3.
  const response = await fetch("https://api.trychannel3.com/v1/search", {
    method: "POST",
    headers: { "x-api-key": secret("CHANNEL3_API_KEY"), "Content-Type": "application/json" },
    body: JSON.stringify(channel3Request(query)),
  });
  if (!response.ok) {
    console.error("Channel3 error", response.status, await response.text());
    return error("The catalog didn't answer.", 502);
  }
  const body = (await response.json()) as { products: C3Product[] };

  // Products with a size come first; the app never marks unsized ones as fitting.
  const products = body.products
    .map(normalize)
    .filter((p) => p !== null)
    .sort((a, b) => Number(b!.widthCm !== null) - Number(a!.widthCm !== null));

  await db.from("product_cache").upsert({ key, response: products, created_at: new Date().toISOString() });
  return json({ products, cached: false });
});
