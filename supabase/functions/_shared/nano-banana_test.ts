// Run with: deno test supabase/functions/_shared/
import { assert, assertEquals } from "jsr:@std/assert@1";
import { prompt } from "./nano-banana.ts";

Deno.test("asks to edit the real room when there's a photo", () => {
  const text = prompt({ style: "warm", corners: [], features: [], pieces: [], roomPhoto: "x", planImage: "y" }, "LAYOUT");
  assert(text.includes("Edit the first image"));
  assert(text.includes("top-down floor plan"));
  assert(text.includes("warm and cozy"));
  assert(text.includes("LAYOUT"));
});

Deno.test("draws a room when there's no photo, and uses the pieces' photos", () => {
  const text = prompt({
    style: "modern", corners: [], features: [], pieces: [],
    piecePhotos: [{ name: "Sofa", data: "z" }],
  }, "");
  assert(text.includes("Create a realistic photo"));
  assert(text.includes("my own pieces"));
  assertEquals(text.includes("Edit the first image"), false);
});
