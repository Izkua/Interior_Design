# 6-Week Build Plan: Interior Design App

Oct 21, 2026

This plan takes the app from zero to a TestFlight build by the end of week 5 and an App Store submission by day 4 or 5 of week 6, built solo in SwiftUI for all iPhones with no LiDAR required. Tabs run left to right: Home, Current Items, Catalog, with a profile button at the top right of every screen (Google and email/password sign-in, plus guest mode).

## Before day 1: start these today

Three things have waiting periods you cannot speed up, so start them before writing code. The plan assumes roughly 35 to 40 focused hours a week; if you have less, use the cut list at the end.

- [ ] Enroll in the Apple Developer Program ($99/year). Approval can take days, and you need it for TestFlight and the App Store.
- [ ] Apply for catalog access now (see Week 4). Affiliate approvals can take days to weeks, so applying late can block the shopping feature.
- [ ] Create accounts and API keys for the vision/labeling model and the image-generation model you will test in Week 5.
- [ ] Pick the app name and check that it is free on the App Store. Buy a domain or set up a simple page for the privacy policy and support URL the App Store requires.
- [ ] Install the latest Xcode, create the project (SwiftUI, iOS only, minimum iOS version set to what your phone and your target users run), and put it in Git.
- [ ] Collect test material: photos of your own room from all four directions, plus photos of 5 to 10 furniture pieces with their real measured sizes. You will test against these every week.
- [ ] Set the budget: $50 total for the whole project, outside Apple's $99. Buy prepaid credits with auto-reload off on every paid service so nothing can bill you past that.

* [ ] Choose a sign-in provider (Supabase Auth or Firebase Auth; both support Google and email/password). Create the project now.
* [ ] Create a Google Cloud project, set up the OAuth consent screen, and create an iOS OAuth client ID. Ask for basic profile and email only.
* [ ] Enable Sign in with Apple on your developer account (needed because Google sign-in is offered).

- [ ] Find a LiDAR iPhone to borrow (a Pro model) to test the RoomPlan path. The Simulator and your own phone cannot run it. If you cannot find one, ship without the LiDAR option and add it later.

## Week 1: foundation, design, basic room builder

By Friday you can open the app on your phone, move between three tabs, and draw a rectangular room to scale. Done when: a room you enter survives closing and reopening the app.

**Project and data**

- [ ] Set up the folder structure by feature (Home, Items, Rooms, Layouts, Catalog, Shared).
- [ ] Define the data models in SwiftData: Room (corner points, wall lengths, fixed features), Item (type, width/depth/height, photo, source: owned or catalog), Layout (room, placements with position and rotation, score), Preferences (budget, styles, materials, minimum rating), Product (name, price, dimensions, materials, rating, retailer link).
- [ ] Store all lengths in one unit internally (centimeters) and convert for display, with a feet/inches or metric setting. This avoids conversion bugs later.
- [ ] Add sample seed data (one room, six items) so every screen has something to show while you build.

**Design system**

- [ ] Choose 1 accent color, a neutral palette with light and dark mode, and one font family (system font is fine).
- [ ] Build reusable pieces: primary button, card, icon button, empty state, section header, chip.
- [ ] Set minimum tap target size to 44 pt and use generous spacing for the slick, simple look.

**Navigation**

- [ ] Build the bottom tab bar, left to right: Home, Current Items, Catalog. Use SF Symbols for icons.
- [ ] Home screen: three large cards (Current Items, Shopping, Recommended Layouts) that jump to the right screen or tab.
- [ ] Current Items screen shell with the room layout and camera buttons, and the profile button at the far top right (all can be placeholders this week).

* [ ] Profile button at the top right of every screen, opening a profile sheet. This week it only shows the guest state (person icon, a Sign in button that does nothing yet, and the preferences fields saved on the device).

**Basic room builder**

- [ ] Room shape picker: rectangle or square.
- [ ] Width and length entry with unit selection and validation (no zero or negative values, sensible maximums).
- [ ] Draw the room to scale in a top-down canvas, with wall length labels.
- [ ] Add doors, windows, and outlets as draggable fixed features on walls (layouts in Week 3 depend on these).
- [ ] Save, rename, and delete rooms; support more than one room.

## Week 2: advanced room builder and manual items

By Friday you can draw an irregular room from corner points with measured walls, and add furniture by hand with sizes. Done when: you can rebuild your real room accurately and add your real furniture to it.

**Advanced room builder**

- [ ] Tap to place corner points on a grid canvas; drag to move; long-press to delete.
- [ ] For each wall, let the user type the measured length. Show the angle at every corner live as points move.
- [ ] Write the geometry code first and unit-test it: wall length from two points, interior angle at a corner, polygon area, and a check that the shape is closed and does not cross itself.
- [ ] Handle measurements that do not agree (wall lengths that cannot close into a shape). Show which wall is off by how much and offer to adjust, rather than failing silently.
- [ ] Bottom-left "Lock angles" toggle: when on, snap every corner to 30, 45, 60, or 90 degrees (and the common multiples like 120, 135, 150, 180) while dragging.
- [ ] Undo and redo for point edits.
- [ ] Mark the AI scan option in the room builder as "coming soon" for now; it is built in Week 5.

**Items (manual first)**

- [ ] Current Items list or grid with photo, label, and dimensions on each card.
- [ ] Add-item sheet: pick a type from a fixed list (sofa, bed, desk, table, chair, dresser, shelf, TV stand, lamp, rug, other), enter width, depth, and height, optional photo from the library, optional notes.
- [ ] Default sizes for each type, so adding a sofa starts with a realistic size the user adjusts.
- [ ] Edit and delete items; mark whether an item is fixed in place or movable.
- [ ] Link items to a room.

**Quality**

- [ ] Install the app on your own phone and use it to model your real room. Fix whatever feels slow or awkward before moving on.

## Week 3: layout engine and Recommended Layouts

By Friday, tapping Recommended Layouts shows several skeleton floor plans of your real room with your real items placed sensibly. Done when: the top 3 layouts for your own room look like something you would actually try.

The engine is rule-based code, not an AI model. It is faster, free to run, works offline, and gives the same answer for the same input.

**Engine (build and test this before any UI)**

- [ ] Represent each item as a rectangle with position, rotation (0, 90, 180, 270 degrees), and a clearance zone (front of a dresser, door swing, space to pull out a chair).
- [ ] Hard rules, which reject a layout outright: items stay inside the room, items do not overlap, doors can open fully, windows are not blocked by tall items, and a walking path of about 76 to 91 cm (30 to 36 in) stays open between the door and the main areas.
- [ ] Placement strategies that generate candidates: large pieces against walls, a focal point (TV wall, window, or fireplace) that seating faces, beds with the headboard on a solid wall, a desk near light, and a conversation grouping for seating.
- [ ] Generate many candidates by randomizing the order and starting positions, then score each one.
- [ ] Scoring: walkability, balance, how well seating faces the focal point, outlet access for items that need power, and how little the user must move versus where items are now.
- [ ] Pick the top 3 to 5 that are meaningfully different from each other (reject near-duplicates).
- [ ] Unit-test with 5 rooms of different shapes and item sets, including a tiny room and a room too small to fit everything. When items cannot all fit, return the best partial layout and say what was left out.
- [ ] Keep generation under 1 second on your phone; run it off the main thread.

**Recommended Layouts screen**

- [ ] Skeleton top-down view of the room with each item as a labeled, softly colored shape; doors and windows drawn on the walls.
- [ ] Horizontal swipe or list of the layout options, each with a short label (for example "Seating faces window").
- [ ] Detail view for a layout: what stays, what moves, and what is missing (the gap that the Catalog will fill in Week 4).
- [ ] Manual drag-to-adjust on any layout, then save it as the user's chosen layout.
- [ ] Disabled "Visualize" button for now; it is built in Week 5.
- [ ] Empty states: no room yet, no items yet, items too big for the room.

## Week 4: backend and real catalog

By Friday you can set a budget and preferences, browse real products from real retailers, and see only the ones that fit your room. Done when: a product you tap opens at the retailer, and its listed size is checked against your free floor space.

**Pick the catalog source (day 1 of the week, using what you applied for before day 1)**

Do not scrape retailer sites. It breaks often, breaks their terms, and is a risk for App Store approval.

| Option | What it is | Main catch |
| --- | --- | --- |
| Product-data API (Channel3) | One search endpoint over many furniture brands, with images, metadata, and affiliate-ready offers | Free tier of 1,000 credits a month (1 credit per search), then $0.007 per credit, per its pricing page; check rate limits and whether commission data is available for your merchants |
| Amazon Creators API | Amazon's official catalog API, which replaced the retired PA-API | Reported to require an approved Associates account and recent qualifying sales, so a brand-new app may not qualify on day 1 |
| Affiliate networks (Impact, CJ, Awin, Rakuten) | Product feeds and links from retailers such as home-goods stores, once approved per merchant | Approval is per merchant and can be slow; feeds are daily, not live. I have not checked which furniture retailers are currently on each network |
| Furniture-data providers (Skulytics) | Manufacturer-sourced specs and variants | Built for retailers, with access governed by each manufacturer's rules |

- [ ] Test the product-data API with 20 real queries ("3 seat sofa under $800", "oak dining table 60 inch") and score the results for relevance, size data, price, and star ratings. Size data matters most: no dimensions, no fit check.
- [ ] Decide: primary source, backup source, and a small hand-curated fallback list of 50 to 100 products so the Catalog tab is never empty.

**Backend (small, and required)**

- [ ] Create a serverless proxy (Cloudflare Workers, Supabase Edge Functions, or similar). Catalog keys, image-generation keys, and model keys must live here, never inside the app.
- [ ] Endpoints: search products, get product, label item photo, scan room photos, generate visualization (the last three are used in Week 5).
- [ ] Per-device rate limits and a monthly spend cap with alerts, so a bug or abuse cannot run up your bill.
- [ ] Cache product results for a day to cut cost and speed up the app.
- [ ] Normalize every product into your Product model: name, price, width/depth/height, materials, rating, review count, image, retailer, link. Drop products with no dimensions from fit-checked results.

**Catalog tab**

- [ ] Budget input (total and per item) and preference filters: price range, minimum star rating, material, style, color.
- [ ] Product grid with image, price, rating, size, and a fit badge ("Fits your room").
- [ ] Fit check: compare product dimensions with free space in the user's chosen layout, including clearances. Show why a product does not fit.
- [ ] "Fill the gaps" mode: from a layout's missing items (for example, "needs a 60 in sofa"), search for matching products within the remaining budget and rank by your preferences.
- [ ] Product detail screen with a button that opens the retailer page in an in-app browser. Show clearly that links may earn a commission.
- [ ] Save products to a wishlist; allow adding a product to a layout as a preview.

**Profiles and sign-in**

Profiles are optional. Guests keep full use of the app, and signing in adds a saved profile, preferences, and image usage tied to the account.

- [ ] Connect the app to your sign-in provider and store the session securely in the iOS Keychain.
- [ ] Email and password: create account, email verification, sign in, sign out, and forgot-password by email. Show clear errors (wrong password, email already used, no network).
- [ ] Continue with Google: wire up Google Sign-In with the iOS OAuth client, and test on a real device and a fresh install.
- [ ] Continue with Apple: add Sign in with Apple with the same button size and prominence as Google.
- [ ] Link sign-in methods that share an email, so one person does not end up with two accounts.
- [ ] Backend: verify the sign-in token on every request that costs money (image generation, labeling, room scan) and apply the free monthly limit per account.
- [ ] Profile table in the backend: display name, email, photo, sign-in method, preferences, budget, and usage count, readable and writable only by that user.
- [ ] Finish the profile sheet from week 1: signed-in state with name and photo or initials, preferences, usage this month, Sign out, and Delete account.
- [ ] Delete account: remove the profile and usage data in the backend, sign the user out, and confirm in the app. Apple requires this inside the app.
- [ ] Guest to account: when a guest signs in, keep their on-device rooms and items, and attach their preferences to the new account.

## Week 5: camera capture, room scan, visualization

By Friday you can photograph a piece of furniture and get a labeled, sized item, scan a room from photos (or with LiDAR on a Pro iPhone), and generate an image of a layout. Done when: a TestFlight build is on your phone and you have shared it with 3 to 5 testers.

Without LiDAR, size from a single photo is an estimate. Every result below must be editable, and the app should say "estimated" until the user confirms.

**Item capture (camera button, top right of Current Items)**

- [ ] Camera permission flow with a clear reason string, and a graceful screen if the user denies access.
- [ ] Label the item by type. Test two approaches on your Week 1 test photos and keep the better one: Apple's on-device Vision image classification (free, offline, may be coarse) or a vision model through your backend (more accurate, costs per call).
- [ ] Size: check RoomCaptureSession.isSupported at launch. On LiDAR iPhones use RoomPlan for measured sizes. On the rest, use this order: (1) AR measure using ARKit plane detection, which works without LiDAR; (2) a reference object in the photo (a credit card, a sheet of paper, or a standard door) to set scale; (3) the type's default size.
- [ ] Confirm screen showing the photo, the detected type, and the estimated width, depth, and height, all editable before saving.
- [ ] Measure accuracy on your 5 to 10 real pieces and record the typical error. Show a plain-language confidence note to the user.

**AI room scan (up to 10 photos)**

- [ ] Scan loop: the user takes a first photo, then the app keeps prompting for more, with an arrow showing where to point next, until the room is understood or 10 photos are taken. Before the first photo, ask for one known measurement (for example one wall length) so the draft has a real scale; a standard door height is the fallback. Add a retake option and a progress count (for example 4 of 10).
- [ ] After each photo, send it with the earlier photos (downsized) and the current draft to your backend. Ask the model for an updated outline, door and window positions, a confidence for each wall, and what is still missing and which direction to shoot next. Stop when the outline is closed, every wall has been seen, and confidence is high, or at 10 photos; if it stops at 10, highlight the uncertain walls for the user to fix in the editor.
- [ ] Load the draft into the advanced room builder from Week 2 so the user can drag corners and fix wall lengths. The editor is what makes this feature trustworthy.
- [ ] Test on your room and two other rooms. If accuracy is poor, ship it labeled "Beta" rather than cutting it.

* [ ] LiDAR room scan (only on phones that pass `RoomCaptureSession.isSupported`): use Apple's RoomPlan to capture walls, doors, windows, and furniture with measured sizes, then convert the result into your Room and Item models so the same editors work. Hide this option on phones without LiDAR.

**Visualize (generated images of a layout)**

- [ ] Test 3 cheap image-editing models with the same input: a photo of the room plus the chosen skeleton layout and the item list. As of August 2026, candidates cost roughly $0.01 to $0.04 per image (Flux 2 klein, Reve Edit Fast, Nano Banana, Flux Kontext pro, gpt-image-2 at low quality). Compare how closely each follows the layout, then pick the cheapest one that is good enough.
- [ ] Build the flow: tap Visualize, show progress, display the result, save it, and share it. Label every image "AI-generated inspiration; furniture and placement may differ."
- [ ] Add a style picker (modern, scandinavian, warm, minimal) to steer the look.
- [ ] Limit use: Visualize requires sign-in, with 3 images a day and 10 a month per account and a clear count shown. Add a backend kill switch that pauses it for everyone once the month's budget is used. No purchases in v1, which also skips in-app purchase setup.
- [ ] Handle failures: timeouts, rejected images, no network; never charge a credit for a failed generation.

**Ship to testers**

- [ ] Archive a build, upload to App Store Connect, and distribute through TestFlight to 3 to 5 people with different iPhone models and iOS versions.

## Week 6: polish, testing, App Store submission

Submit by day 4 or 5 at the latest. Apple's review usually takes a day or two, but a rejection costs a full round trip, so the buffer matters. Done when: the app is submitted for review, or live.

**Days 1 to 2: fix what testers found**

- [ ] Triage tester feedback into must-fix (crashes, wrong math, dead ends) and later.
- [ ] Fix every crash. Run the app on the oldest iPhone and iOS version you support if you can borrow one, and on the Simulator for other screen sizes (small iPhone SE size through the largest Pro Max).
- [ ] Test the unhappy paths: no network, camera denied, backend down, very small room, very large room, 30 items, a product with missing data.

**Days 2 to 3: polish**

- [ ] First-run onboarding in 3 screens or fewer: what the app does, add your room, add your items. Then land on Home.
- [ ] Loading skeletons, empty states, and error messages written in plain words on every screen.
- [ ] Accessibility pass: Dynamic Type, VoiceOver labels on every button, enough contrast in light and dark mode, and reduced-motion support.
- [ ] Performance pass: scrolling stays smooth, layout generation stays fast, images are downsized before upload, and the app launches in about 2 seconds.
- [ ] App icon (1024 by 1024) and a launch screen that match the design system.

**Days 3 to 4: App Store requirements**

- [ ] Privacy policy page, live at a public URL, covering camera photos, what is sent to your servers and model providers, how long it is kept, and affiliate links.
- [ ] App Privacy answers in App Store Connect that match what the app really collects, including photos sent to your backend.
- [ ] Camera usage description string that says why you need the camera, in plain language.
- [ ] Support URL and a contact email.
- [ ] Accounts are in scope, so two Apple rules apply: offer Sign in with Apple next to Google (Apple requires an equivalent option when an app offers a login like Google; check the current App Review wording), and let users delete their account inside the app. Keep guest mode, and put a demo account in the review notes.
- [ ] If you sell image credits or a subscription, set up the in-app purchase products and a restore-purchases button, and test in the sandbox.
- [ ] Affiliate disclosure visible near shopping links.
- [ ] Screenshots for the required iPhone sizes (use a clean demo room and real-looking items), a short description, keywords, a category (Lifestyle or Shopping), and an age rating.
- [ ] Write review notes for Apple: how to use the app, and demo steps if anything is gated. Make sure the app works with no sign-in so the reviewer can test everything.

**Day 4 to 5: submit**

- [ ] Archive the final build, upload, select it in App Store Connect, and submit for review.
- [ ] While waiting, keep the backend spend cap and alerts on, and watch crash reports in Xcode Organizer.
- [ ] If rejected, read the exact guideline cited, fix only that, and resubmit. Reply to the reviewer in the Resolution Center if you disagree.
- [ ] After approval, choose manual release so you can do a final check before it goes live.

## If you fall behind: cut in this order

This is a big scope for one person in six weeks, and profiles with sign-in add roughly 2 to 3 days of work across weeks 1, 4, and 6 (my estimate). Check yourself at the end of each week: if the "done when" line is not true, cut from the bottom of this list instead of working nights.

1. **Image generation credits and payments.** Ship Visualize with a small free monthly limit and no purchases. Skips in-app purchase setup and review.
2. **4-photo AI room scan.** Ship it as "Beta", or drop it and keep the manual builders. This is the least accurate feature.
3. **Photo-based size estimation.** Keep photo labeling, but make size entry manual with type defaults. Drop the AR measure and reference-object steps.
4. **Doors, windows, and outlets as draggable features.** Keep doors and windows, drop outlets.
5. **Wishlist, per-item budgets, and style picker.** Keep one total budget and basic filters. Also drop avatar upload and the editable display name from the profile.
6. **Second and third catalog sources.** Ship with one source plus the hand-curated fallback list.

Do not cut: the manual room builder, the layout engine, the fit check, the privacy policy, the backend spend cap, or (if accounts ship) Sign in with Apple and account deletion. Without these, the app is either unusable or unsafe to release.

A rejected build can push the live date past week 6. The TestFlight build is already a usable app for you and your testers, so the 6-week goal of "usable" holds even if store approval takes a few extra days.

## Sources

The catalog notes in Week 4 come from search results I did not open in full, so check pricing, terms, and eligibility on each provider's own site before you commit. Everything else in this plan (iOS steps, layout rules, App Store requirements) is my own planning knowledge, not sourced from these pages.

- [Amazon: Migrating to Creators API from Product Advertising API](https://affiliate-program.amazon.com/creatorsapi/docs/en-us/migrating-to-creatorsapi-from-paapi): the older API is replaced by the Creators API, with new credentials.
- [Amazon: PA-API 5 deprecation notice](https://affiliate-program.amazon.com/creatorsapi/docs/en-us/paapiv5-deprecation): old-API calls now return an error.
- [DEV Community: PA-API v5 deprecation](https://dev.to/th3nate/amazon-pa-api-v5-is-shutting-down-april-30-2026-here-is-what-changes-at-the-auth-layer-22ek): a developer's report that Creators API access needs approved Associates status and recent qualifying sales. This is a third-party claim; confirm it with Amazon.
- [Channel3: furniture product data API example](https://trychannel3.com/product-data/brands/sei-furniture): one search endpoint with affiliate-ready offers.
- [Skulytics: furniture manufacturer data](https://skulytics.io/brands/furnitures): normalized manufacturer data for retailers, with distribution governed by manufacturer rules.
- [Apify: Wayfair scraper listing](https://apify.com/parseforge/wayfair-scraper): listed only to show that scraping tools exist; this plan recommends against scraping.
