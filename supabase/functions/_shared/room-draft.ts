// The draft-room contract scan-room must return (version 1). The app's
// parser (RoomDraftParser in Rooms/Scan/RoomDraft.swift) checks it.
//
// Request body: { photos: string[] (base64 JPEG, ≤1024 px), known: { kind:
// "firstWall" | "doorHeight", lengthCm: number }, previousCorners?: {x,y}[] }

export interface RoomDraft {
  version: 1;
  /** Centimeters, seen from above; the app fixes the order and origin. */
  corners: { x: number; y: number }[];
  /** walls[i] runs corners[i] → corners[i + 1]. */
  walls?: { seen?: boolean; confidence?: number }[];
  features?: { kind: "door" | "window" | "outlet"; wall: number; offsetCm: number; widthCm?: number; confidence?: number }[];
  /** True when the outline goes all the way around the room. */
  closed?: boolean;
  /** Where the person should point the camera next. */
  next?: { direction?: "left" | "right" | "behind" | "ahead" | "up" | "down" | "done"; hint?: string };
}
