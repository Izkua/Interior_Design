// Turning a catalog product's photo into a 3D model (GLB) with Stability
// AI's Stable Fast 3D. One call per product, ever: the result is saved in
// Supabase Storage and everyone after that gets the saved copy for free.
//
// Price (check before turning it on): Stability lists Stable Fast 3D at
// 2 credits per successful model, and 1 credit = $0.01, so about $0.02.
// Failed calls aren't charged. Credits are prepaid on Stability's site
// (no auto-reload), and our own cap is in app_config.model_3d.

import type { C3Product } from "./products.ts";

/** What one model costs us, in cents (rounded up). */
export const MODEL_COST_CENTS = 2;

export const BUCKET = "product-models";

type C3Image = NonNullable<C3Product["images"]>[number];

/**
 * The photo that gives the best 3D model: a three-quarter view on a plain
 * background shows the front, a side, and the top at once, so the model
 * has to guess less. Then the main photo on a plain background, then any
 * plain-background photo, then the main photo as it is. Never a
 * lifestyle shot, size chart, or close-up if anything else exists.
 */
export function bestImage(images: C3Image[] | undefined): string | null {
  const list = images ?? [];
  const avoid = new Set(["lifestyle", "size_chart", "detail", "packaging", "product_information", "merchant_information", "on_model", "in_use"]);
  const usable = list.filter((i) => !avoid.has(i.shot_type ?? ""));
  const pick =
    usable.find((i) => i.shot_type === "angle_view" && i.cleaned_url) ??
    usable.find((i) => (i.shot_type === "hero" || i.is_main_image) && i.cleaned_url) ??
    usable.find((i) => i.cleaned_url) ??
    usable.find((i) => i.is_main_image) ??
    usable[0] ??
    list.find((i) => i.is_main_image) ??
    list[0];
  return pick ? (pick.cleaned_url ?? pick.url) : null;
}

/** Product ids are used as file names, so only safe characters. */
export function modelPath(productID: string): string | null {
  return /^[A-Za-z0-9_-]{1,64}$/.test(productID) ? `${productID}.glb` : null;
}

/** Calls Stable Fast 3D with one photo; returns the GLB file. */
export async function makeModel(apiKey: string, photo: Uint8Array, mime: string): Promise<Uint8Array> {
  const form = new FormData();
  form.append("image", new Blob([photo as unknown as BlobPart], { type: mime }), "product");
  // 1024 px textures: sharp enough on a phone, and a small file.
  form.append("texture_resolution", "1024");
  form.append("foreground_ratio", "0.85");
  const response = await fetch("https://api.stability.ai/v2beta/3d/stable-fast-3d", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });
  if (!response.ok) {
    throw new Error(`Stable Fast 3D answered ${response.status}: ${(await response.text()).slice(0, 300)}`);
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  // Every GLB file starts with "glTF".
  if (bytes.length < 20 || new TextDecoder().decode(bytes.slice(0, 4)) !== "glTF") {
    throw new Error("Stable Fast 3D didn't return a GLB file.");
  }
  return bytes;
}
