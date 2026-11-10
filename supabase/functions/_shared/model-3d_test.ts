// Run with: deno test supabase/functions/_shared/
import { assertEquals } from "jsr:@std/assert@1";
import { bestImage, modelPath } from "./model-3d.ts";

Deno.test("prefers a cleaned three-quarter view", () => {
  assertEquals(bestImage([
    { url: "main.jpg", cleaned_url: "main-clean.jpg", is_main_image: true, shot_type: "hero" },
    { url: "room.jpg", shot_type: "lifestyle" },
    { url: "angle.jpg", cleaned_url: "angle-clean.jpg", shot_type: "angle_view" },
  ]), "angle-clean.jpg");
});

Deno.test("falls back to the cleaned main photo, then the main photo", () => {
  assertEquals(bestImage([
    { url: "room.jpg", cleaned_url: "room-clean.jpg", shot_type: "lifestyle" },
    { url: "main.jpg", cleaned_url: "main-clean.jpg", is_main_image: true },
  ]), "main-clean.jpg");
  assertEquals(bestImage([{ url: "chart.jpg", shot_type: "size_chart" }, { url: "main.jpg", is_main_image: true }]), "main.jpg");
  assertEquals(bestImage([{ url: "only.jpg", shot_type: "lifestyle" }]), "only.jpg");
  assertEquals(bestImage([]), null);
});

Deno.test("only safe product ids become file names", () => {
  assertEquals(modelPath("abc_123-X"), "abc_123-X.glb");
  assertEquals(modelPath("../secrets"), null);
  assertEquals(modelPath(""), null);
});
