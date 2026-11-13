// Visualize with Google's Gemini 2.5 Flash Image ("Nano Banana").
//
// It edits a real photo of the room when one is given (or draws the room
// when not), using a top-down plan of the layout and photos of the
// person's own pieces as references, so the picture shows their actual
// furniture where the plan puts it.
//
// Price (check before turning it on): about $0.039 per 1024 px picture
// (Google bills per output token; ~1,290 tokens per image), plus a tiny
// amount for the input photos. Google bills after use, so our own hard
// cap (app_config.image_generation.monthly_budget_cents) and the kill
// switch are what stop spending. Set a budget alert in Google Cloud too.

import { type ImageProvider, RejectedError, type VisualizeInput } from "./image-provider.ts";

const MODEL = "gemini-2.5-flash-image";

interface Part {
  text?: string;
  inline_data?: { mime_type: string; data: string };
}

export class NanoBananaProvider implements ImageProvider {
  name = `google-${MODEL}`;
  costCents = 4;

  constructor(private apiKey: string) {}

  async generate(input: VisualizeInput, layoutText: string): Promise<{ bytes: Uint8Array; mime: string }> {
    const parts: Part[] = [{ text: prompt(input, layoutText) }];
    if (input.roomPhoto) parts.push({ inline_data: { mime_type: "image/jpeg", data: input.roomPhoto } });
    if (input.planImage) parts.push({ inline_data: { mime_type: "image/png", data: input.planImage } });
    for (const photo of (input.piecePhotos ?? []).slice(0, 4)) {
      parts.push({ text: `Reference photo of the "${photo.name}":` });
      parts.push({ inline_data: { mime_type: photo.mime ?? "image/jpeg", data: photo.data } });
    }

    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": this.apiKey },
      body: JSON.stringify({
        contents: [{ role: "user", parts }],
        generationConfig: { responseModalities: ["IMAGE"] },
      }),
    });
    const body = await response.json().catch(() => null);
    if (!response.ok) {
      const message = body?.error?.message ?? `status ${response.status}`;
      // Safety blocks and unreadable photos come back as 400s.
      if (response.status === 400) throw new RejectedError("That picture couldn't be made from this photo. Try another photo or style.");
      throw new Error(`Gemini answered ${response.status}: ${String(message).slice(0, 300)}`);
    }
    const candidate = body?.candidates?.[0];
    if (body?.promptFeedback?.blockReason || candidate?.finishReason === "SAFETY") {
      throw new RejectedError("That picture couldn't be made. Try a different room photo.");
    }
    for (const part of candidate?.content?.parts ?? []) {
      const data = part.inlineData ?? part.inline_data;
      if (data?.data) {
        const bytes = Uint8Array.from(atob(data.data), (c) => c.charCodeAt(0));
        return { bytes, mime: data.mimeType ?? data.mime_type ?? "image/png" };
      }
    }
    throw new RejectedError("No picture came back. Try again.");
  }
}

/** What to ask for, in plain words. Exported for tests. */
export function prompt(input: VisualizeInput, layoutText: string): string {
  const style = {
    modern: "modern",
    scandinavian: "Scandinavian, light and natural",
    warm: "warm and cozy",
    minimal: "minimal and uncluttered",
  }[input.style] ?? input.style;
  const lines = [
    input.roomPhoto
      ? "Edit the first image, a real photo of my room. Keep the room itself exactly as it is: the walls, floor, windows, doors, ceiling, light and camera angle. Rearrange and restyle only the furniture."
      : "Create a realistic photo of a room, seen from the doorway at eye height.",
    input.planImage
      ? "The next image is a top-down floor plan of the layout I want. Each labeled box is a piece of furniture, drawn to scale; place each piece where the plan shows it."
      : "",
    (input.piecePhotos?.length ?? 0) > 0
      ? "The reference photos are my own pieces: show those exact pieces (same shape, color, and material), not different ones."
      : "",
    `Style: ${style}.`,
    layoutText,
    "Keep every piece at a realistic size for the room. No people, text, labels, or logos. A natural, photographic look.",
  ];
  return lines.filter(Boolean).join("\n");
}
