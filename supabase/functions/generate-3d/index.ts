// POST /functions/v1/generate-3d
// Body: { productId: string }  (a Channel3 product id)
// Returns { url, generated } : a link to the product's 3D model (GLB).
//
// Each product's model is made once and saved; after that anyone gets the
// saved copy for free, with no sign-in needed. Making a new one goes
// through the usual paid checks: sign-in, the model_3d kill switch,
// per-person daily and monthly limits, and the monthly budget (hard stop).
// A failed attempt never uses up anyone's allowance.

import { error, json, safely, secret } from "../_shared/http.ts";
import { checkPaidRequest, recordUse, reserveSpend } from "../_shared/paid.ts";
import { adminClient, config, currentUser, underRateLimit } from "../_shared/supabase.ts";
import type { C3Product } from "../_shared/products.ts";
import { bestImage, BUCKET, MODEL_COST_CENTS, makeModel, modelPath } from "../_shared/model-3d.ts";

Deno.serve(safely(async (req) => {
  if (req.method !== "POST") return error("Use POST.", 405);

  let productID: string;
  try {
    productID = String((await req.json()).productId ?? "");
  } catch {
    return error("The request body must be JSON.", 400);
  }
  const path = modelPath(productID);
  if (!path) return error("Missing or bad product id.", 400);

  const db = adminClient();
  const publicURL = () => db.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;

  // Already made? Free for everyone, just rate-limited.
  const user = await currentUser(req);
  const device = req.headers.get("x-device-id")?.slice(0, 64);
  const bucket = user ? `user:${user.id}` : device ? `device:${device}` : null;
  if (!bucket) return error("Missing device ID.", 400);
  if (!(await underRateLimit(`${bucket}:model3d`, 30, 600))) return error("Too many requests.", 429);

  const { data: saved, error: lookupError } = await db.from("product_models").select("path")
    .eq("product_id", productID).maybeSingle();
  if (lookupError) throw lookupError;
  if (saved) return json({ url: publicURL(), generated: false });

  // Making a new one costs money: every safety check first.
  const allowed = await checkPaidRequest(req, "model3d", MODEL_COST_CENTS);
  if (allowed instanceof Response) return allowed;
  const stabilityKey = Deno.env.get("STABILITY_API_KEY");
  if (!stabilityKey) return error("3D models aren't set up yet.", 501);

  // The product's photos, straight from the catalog (free), so nobody can
  // attach a made-up picture to a real product.
  const c3 = await fetch(`https://api.trychannel3.com/v1/products/${encodeURIComponent(productID)}`, {
    headers: { "x-api-key": secret("CHANNEL3_API_KEY") },
  });
  if (c3.status === 404) return error("This product isn't available any more.", 404);
  if (!c3.ok) return error("The catalog didn't answer.", 502);
  const imageURL = bestImage(((await c3.json()) as C3Product).images);
  if (!imageURL) return error("This product has no photo to work from.", 422);

  const photo = await fetch(imageURL);
  const mime = photo.headers.get("content-type") ?? "image/jpeg";
  if (!photo.ok || !mime.startsWith("image/")) return error("The product photo couldn't be loaded.", 502);
  const photoBytes = new Uint8Array(await photo.arrayBuffer());
  if (photoBytes.length > 10_000_000) return error("The product photo is too large.", 422);

  if (!(await reserveSpend("model3d", MODEL_COST_CENTS))) {
    return error("This month's budget for 3D models is used up. It resets on the 1st.", 503);
  }

  let glb: Uint8Array;
  try {
    glb = await Promise.race([
      makeModel(stabilityKey, photoBytes, mime),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error("timeout")), 60_000)),
    ]);
  } catch (e) {
    console.error("3D model failed", e instanceof Error ? e.message : e);
    if (e instanceof Error && e.message === "timeout") return error("The 3D model took too long.", 504);
    return error("The 3D model couldn't be made.", 502);
  }

  const { error: uploadError } = await db.storage.from(BUCKET).upload(path, glb, {
    contentType: "model/gltf-binary",
    upsert: true,
  });
  if (uploadError) throw uploadError;
  const { error: saveError } = await db.from("product_models").upsert({ product_id: productID, path, image_url: imageURL });
  if (saveError) throw saveError;
  await recordUse(allowed.id, "model3d", MODEL_COST_CENTS);

  return json({ url: publicURL(), generated: true });
}));
