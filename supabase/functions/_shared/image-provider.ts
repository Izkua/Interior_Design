// The slot for whichever image model is chosen in week 5.
//
// Every candidate model gets the same input and returns the same output,
// so trying three models means writing three small adapters, not changing
// the function. Nothing here calls a paid service yet.

export type Style = "modern" | "scandinavian" | "warm" | "minimal";

export interface Piece {
  name: string;
  type: string;
  widthCm: number;
  depthCm: number;
  heightCm: number;
  x: number;
  y: number;
  rotation: number;
}

/** What the app sends (matches VisualizeRequest in the Swift code). */
export interface VisualizeInput {
  style: Style;
  corners: { x: number; y: number }[];
  features: { kind: string; wall: number; offsetCm: number; widthCm: number }[];
  pieces: Piece[];
  /** Base64 JPEG of the real room, ≤1024 px, optional. */
  roomPhoto?: string;
}

export interface ImageProvider {
  /** For logs and the spend ledger, e.g. "provider-model-name". */
  name: string;
  /** What one picture costs, in cents, from the provider's price list. */
  costCents: number;
  /** Returns a PNG or JPEG. Throw RejectedError if the model refuses. */
  generate(input: VisualizeInput, prompt: string): Promise<{ bytes: Uint8Array; mime: string }>;
}

/** The model refused the request (content rules, unreadable photo). */
export class RejectedError extends Error {}

/** A plain-English description of the layout, for the model. */
export function describeLayout(input: VisualizeInput): string {
  const xs = input.corners.map((c) => c.x), ys = input.corners.map((c) => c.y);
  const width = Math.round(Math.max(...xs) - Math.min(...xs));
  const length = Math.round(Math.max(...ys) - Math.min(...ys));
  const pieces = input.pieces.map((p) =>
    `${p.name} (${Math.round(p.widthCm)}×${Math.round(p.depthCm)} cm) at ${Math.round(p.x)},${Math.round(p.y)} cm`
  ).join("; ");
  return [
    `A realistic photo of a ${input.style} style room, about ${width} by ${length} cm, seen from the doorway.`,
    `Furniture, positioned from a top-down plan with the origin at the top-left corner: ${pieces}.`,
    input.roomPhoto ? "Keep the walls, floor, windows, and light from the reference photo." : "",
    "Do not add text, people, or logos.",
  ].filter(Boolean).join(" ");
}

/**
 * The chosen provider, or null until one is picked.
 *
 * TODO(week 5): after testing three models on real room photos, add an
 * adapter here, e.g. `return new SomeProvider(secret("IMAGE_API_KEY"))`.
 * Store the key with Supabase secrets, never in the app. Check the
 * provider's current price and set costCents from it.
 */
export function chosenProvider(): ImageProvider | null {
  return null;
}
