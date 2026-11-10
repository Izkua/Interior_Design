// POST /functions/v1/generate-3d
// Body: { productId: string, cachedOnly?: boolean }  (a Channel3 product id)
// Returns { url, generated } : a link to the product's 3D model (GLB).
// With cachedOnly, nothing new is made: { url: null } if none exists yet.
//
// Or, for the person's own furniture:
// Body: { photo: base64 PNG/JPEG }  (the piece cut out of their photo)
// Returns { glb: base64 } . Their photo and model are not stored or
// shared here; the app keeps the model on the phone.
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
import { bestImage, BrokenModelError, BUCKET, MODEL_COST_CENTS, makeModel, modelPath } from "../_shared/model-3d.ts";

Deno.serve(safely(async (req) => {
  if (req.method !== "POST") return error("Use POST.", 405);

  let body: { productId?: unknown; photo?: unknown; cachedOnly?: unknown };
  try {
    body = await req.json();
  } catch {
    return error("The request body must be JSON.", 400);
  }
  if (typeof body.photo === "string") return await fromOwnPhoto(req, body.photo);

  const productID = String(body.productId ?? "");
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
  if (body.cachedOnly === true) return json({ url: null, generated: false });

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
    // A broken result isn't counted against the person's allowance.
    if (e instanceof BrokenModelError) {
      return error("The 3D model came out broken, so it wasn't saved and didn't use your credit. Try a cleaner cutout: clear things off the piece, or erase them.", 422);
    }
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

/** A model of the person's own piece, from their photo. Always a new,
 * paid model, so every safety check applies. */
async function fromOwnPhoto(req: Request, base64: string): Promise<Response> {
  const allowed = await checkPaidRequest(req, "model3d", MODEL_COST_CENTS);
  if (allowed instanceof Response) return allowed;
  const stabilityKey = Deno.env.get("STABILITY_API_KEY");
  if (!stabilityKey) return error("3D models aren't set up yet.", 501);

  if (base64.length > 8_000_000) return error("The photo is too large.", 413);
  let photo: Uint8Array;
  try {
    photo = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  } catch {
    return error("The photo couldn't be read.", 400);
  }
  const mime = photo[0] === 0x89 ? "image/png" : photo[0] === 0xff ? "image/jpeg" : null;
  if (!mime) return error("Send a PNG or JPEG photo.", 400);

  if (!(await reserveSpend("model3d", MODEL_COST_CENTS))) {
    return error("This month's budget for 3D models is used up. It resets on the 1st.", 503);
  }
  let glb: Uint8Array;
  try {
    glb = await Promise.race([
      makeModel(stabilityKey, photo, mime),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error("timeout")), 60_000)),
    ]);
  } catch (e) {
    console.error("3D model failed", e instanceof Error ? e.message : e);
    // A broken result isn't counted against the person's allowance.
    if (e instanceof BrokenModelError) {
      return error("The 3D model came out broken, so it wasn't saved and didn't use your credit. Try a cleaner cutout: clear things off the piece, or erase them.", 422);
    }
    if (e instanceof Error && e.message === "timeout") return error("The 3D model took too long.", 504);
    return error("The 3D model couldn't be made.", 502);
  }
  await recordUse(allowed.id, "model3d", MODEL_COST_CENTS);
  let binary = "";
  for (let i = 0; i < glb.length; i += 0x8000) binary += String.fromCharCode(...glb.subarray(i, i + 0x8000));
  return json({ glb: btoa(binary) });
}
