# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

An iPhone app that helps people design a room: capture the room and the furniture they own, get recommended layouts, preview a layout as an AI image, and shop for missing pieces within a budget.

- Solo build, about 6 weeks, aiming for TestFlight by end of week 5 and an App Store submission in week 6.
- It is a fun project on a tight budget: **about $50 total** outside the $99/yr Apple Developer fee. Prefer free tiers and on-device work; anything that costs money must have a hard cap.
- Full product spec: `framework.md`. Week-by-week tasks: `build-plan.md`. If this file and those docs disagree, the decisions below are newer.

## Stack

- **App:** Swift + SwiftUI, iOS only, supports every iPhone (LiDAR is optional, never required).
- **Storage:** SwiftData on device. All lengths stored in **centimeters**; convert only for display.
- **Capture:** camera, ARKit (plane detection for AR measure, works without LiDAR), Vision. RoomPlan only on LiDAR devices.
- **Backend:** a small serverless proxy (Supabase Edge Functions or Cloudflare Workers). It holds every API key, checks sign-in tokens, rate-limits, caches products, and enforces the spend cap.
- **Auth:** a managed provider (Supabase Auth or Firebase Auth). Never store passwords ourselves.
- **Catalog:** product-data API (Channel3 free tier first: 1,000 credits/month, 1 credit per search) with a hand-curated list of 50 to 100 products as the fallback.

## App structure

- Three bottom tabs, **left to right: Home, Current Items, Catalog.**
- **Profile button at the top right of every screen.** On Current Items the top-right icons are, left to right: room layout, camera, profile.
- **Home:** cards for Current Items, Shopping, Recommended Layouts, plus a "continue where you left off" strip.
- **Current Items:** grid of items (photo, type, dimensions). Camera flow labels the item and estimates size, then a confirm screen lets the user edit it.
- **Room layout builder:** Basic (rectangle/square + size), Advanced (tap corners, enter wall lengths, see angles, "Lock angles" snaps to 30/45/60/90), and Scan. Doors, windows and outlets are fixed features.
- **Recommended Layouts:** top-down skeleton views; tap one to see what stays, moves, or is missing, and drag to adjust. Visualize makes an AI image.
- **Catalog:** budget and preferences (price, quality, materials, rating, style); recommendations fill layout gaps and are fit-checked against free space.

## Rules that must hold

- **LiDAR and non-LiDAR paths.** Check `RoomCaptureSession.isSupported` at runtime. LiDAR phones get RoomPlan; others get photo scan, AR measure, or manual entry. Both feed the same editor. The developer's phone has no LiDAR and the Simulator can't run RoomPlan, so the non-LiDAR path is the one that must always work.
- **Room scan loop.** Ask for one known measurement first (for scale). After each photo, update the draft and tell the user where to point next. Stop when the outline is closed and every wall is seen, or at **10 photos max**; then highlight uncertain walls for the user to fix. The draft is always editable.
- **Estimates are editable.** Any size from a photo is labeled "estimated" until the user confirms it.
- **No secrets in the app.** Catalog, model, and image keys live only on the backend.
- **No scraping retailer sites.** Use the product-data API or the curated list. Products without dimensions are shown but never marked as fitting.
- **Guest mode always works.** Sign-in is optional; rooms, items, and layouts stay on device in v1 (no cross-device sync yet).
- **Sign-in options:** Google OAuth, Sign in with Apple (required by Apple next to Google), and email/password with verification and reset. In-app **Delete account** is required.
- **Image generation budget.** Visualize requires sign-in, is limited to 3 images/day and 10/month per account, uses prepaid credits with auto-reload off, and has a backend kill switch once the monthly budget is spent. Label every image "AI-generated inspiration".
- **No in-app purchases in v1.** No paid credits or subscriptions.
- Affiliate links need a visible disclosure near shopping links.

## Working conventions

- Keep the UI slick and simple: one accent color, generous whitespace, large tap targets, one main action per screen.
- Keep the layout engine and room geometry on device (fast, free, offline).
- Before adding any paid service or dependency, say what it costs and how it is capped.
- Prefer small, testable units for geometry and the layout solver; add unit tests for them.
- Don't commit API keys, `.env` files, or `GoogleService-Info.plist`-style secrets.

## Open questions (don't assume an answer)

- Primary catalog source, decided in week 4 after ~20 real test searches (including whether Amazon results through Channel3 come back with dimensions).
- Which image model (test three on real room photos in week 5).
- App name, default units (metric or imperial), whether the free image limit follows the account or the device, and whether to sync rooms and items for signed-in users.
