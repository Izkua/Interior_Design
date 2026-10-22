# Interior Design App: Framework v2

Oct 21, 2026

An iPhone app that turns a room and your furniture into layout options, previews them as images, and recommends what to buy within your budget. This version supports every iPhone (no LiDAR needed), uses a real product catalog, and is scoped for one person to ship in 6 weeks.

## What changed from the first framework

Eight things changed, mostly to fit your decisions: left-to-right tabs, all iPhones, a real catalog, and a 6-week solo build.

| Area | First framework | Now |
| --- | --- | --- |
| Tab order | Home assumed on the right | Left to right: Home, Current Items, Catalog |
| Supported phones | LiDAR first, photo fallback | All iPhones; nothing depends on LiDAR |
| Item and room sizing | RoomPlan scanning (LiDAR only) | AR measure, reference object in the photo, or manual entry; the user can always edit |
| Catalog | Open question | Real product-data API plus a hand-curated fallback list |
| Backend | Not included | Small serverless proxy that holds keys, limits use, and caps spend |
| Accounts | Later | Optional profile with Google and email/password sign-in; guest mode works without an account |
| 4-photo room scan | Phase 5 extra | Built in week 5, labeled Beta, always editable |
| App Store readiness | Not covered | Privacy policy, privacy labels, affiliate disclosure, review notes |

## Navigation and screens

The app has three bottom tabs, left to right: Home, Current Items, Catalog. The look is slick and simple: one accent color, lots of whitespace, large tap targets, and one main action per screen.

**Home**

- Three large cards: Current Items, Shopping, Recommended Layouts.
- A "continue where you left off" strip for the active room.

**Current Items**

- A grid of items, each with photo, type label, and dimensions.
- Top right: the profile button, with the camera button to its left and the room layout button left of that.
- Camera flow: take a photo, the app labels the item type and gets its width, depth, and height (measured with LiDAR on iPhones that have it, estimated from the photo on the rest), then a confirm screen lets the user change the type and size. Estimates are marked "estimated" until confirmed.
- Tap any item to edit its type, size, and notes.

**Room layout builder** (opened from the room layout button)

- **Basic:** choose rectangle or square, then enter the room size.
- **Advanced:** tap to place a point at each corner, type the measured length of each wall, and see the angle at every corner so the shape stays accurate. A button at the bottom left, "Lock angles", snaps corners to 30, 45, 60, and 90 degrees.
- **AI scan (Beta):** take a photo, then keep taking more when the app asks, up to 10 in total. After each photo the AI updates the room draft and says what it still cannot see and where to point the camera next. It stops when the outline is closed and every wall has been seen, and it asks for one known measurement, such as a wall length, to set the real-world scale. The draft is always editable, and walls the AI is unsure about are highlighted.
- Doors, windows, and outlets can be added as fixed features, because layouts depend on them.

* **LiDAR scan (iPhones with LiDAR):** the app checks at launch whether the phone supports Apple's RoomPlan. If it does, the user walks around the room and the walls, doors, windows, and furniture sizes come in already measured. Phones without LiDAR never see this option and use the photo scan or the manual builders. Both paths feed the same editor.

**Recommended Layouts**

- Several skeleton top-down views of the room, with items drawn as labeled shapes.
- Tap one to see what stays, what moves, and what is missing, and to drag items to adjust.
- A Visualize button generates an AI image of the layout, labeled as inspiration.

**Catalog (shopping)**

- Set a budget and preferences: price, quality, materials, star rating, and style.
- Recommendations are tied to gaps in a layout (for example, "needs a 60 in sofa") and checked against the room's free space.
- Tapping a product opens the retailer's page.

## Profile and sign-in

A profile button sits at the top right of every screen. On Current Items it is the rightmost of three icons: room layout, camera, profile. This moves the camera one step left from where you first described it, so say so if you would rather keep the camera in the corner.

- **Guest (signed out):** the button shows a person icon. Tapping it opens a sheet with Continue with Google, Continue with Apple, and an email and password form with Sign in and Create account. Everything else keeps working as a guest, with rooms, items, and layouts stored on the device.
- **Signed in:** the button shows the user's photo or initials. The sheet shows name and email, preferences (units, default budget, styles), image generations used this month, Sign out, and Delete account.
- **Email and password:** create account, email verification, sign in, and password reset by email.
- **Google:** OAuth sign-in that asks only for basic profile and email.
- **Sign in with Apple:** added because Apple requires an equivalent option when an app offers a login like Google. Check the current App Review wording before submitting.
- **Delete account:** required inside the app whenever accounts exist.
- **What the account stores in v1:** profile details, preferences, budget, and image usage. Syncing rooms and items across devices is not in v1 (see open questions).
- **Provider:** use a managed sign-in service such as Supabase Auth or Firebase Auth, which both handle Google and email/password. Do not store passwords yourself.

## Architecture

```
iPhone app (SwiftUI)                      Your backend                 Outside services
+-----------------------------+           +------------------+         +--------------------+
| Screens, tabs, profile      |           | Holds all keys   |-------->| Product-data API   |
| Layout engine (on device)   |           | Rate limits,     |         +--------------------+
| Capture (camera, ARKit,     |---------->|   spend cap      |-------->| Labeling model     |
|   Vision, RoomPlan on LiDAR)|           | Caches products  |         +--------------------+
| Local storage (SwiftData)   |           | Checks sign-in   |-------->| Image model        |
+-----------------------------+           |   tokens         |         +--------------------+
                                          +------------------+-------->| Sign-in provider   |
                                                                        |  (Google, Apple,   |
                                                                        |   email)           |
                                                                        +--------------------+
```

Layouts, room geometry, and storage run on the phone, so they are fast, free, and work offline. Anything that needs a secret key or costs money goes through your backend. Retailer pages open directly from the app. Sign-in happens between the phone and the sign-in provider; your backend only checks the sign-in token before it spends money on a request.

## Data model

Six entities. All but Profile are stored on the device with SwiftData; Profile belongs to the sign-in account. All lengths are stored in centimeters and converted for display.

| Entity | Key fields | Notes |
| --- | --- | --- |
| Room | Name, corner points, wall lengths (cm), doors, windows, outlets | Many rooms allowed; the scan draft is a Room the user edits |
| Item | Type, width, depth, height (cm), photo, source (owned or catalog), fixed or movable, estimated or confirmed | Catalog products added to a layout become Items |
| Layout | Room, placements (item, position, rotation), score, label | The user can adjust and save a chosen layout |
| Preferences | Total budget, per-item budgets, styles, materials, minimum star rating | One set per room |
| Product | Name, price, width, depth, height (cm), materials, rating, review count, image, retailer, link | Cached from the catalog source; products without dimensions are not fit-checked |
| Profile | Name, email, photo, sign-in method (Google, Apple, or email), preferences, image usage this month | Lives with the sign-in account; guests have none and keep everything on the device |

## Catalog and money

Products come from a real product-data API, not scraped pages, and every request goes through your own backend so keys stay off the phone. A hand-curated list of 50 to 100 products is the fallback so the Catalog tab is never empty.

- **Sources to evaluate:** start with Channel3's product-data API, which has a free tier of 1,000 credits a month (a search costs 1 credit) and, per its pricing page, no approval step. Affiliate networks and Amazon's Creators API can come later. Amazon's access rules may block a brand-new app at first, so do not depend on it for launch. Check pricing and terms for each; the details are in the 6-week build plan.
- **Ranking:** filter by budget and minimum star rating, then rank by the user's material and style preferences, then by price.
- **Fit check:** compare each product's dimensions with the free space in the chosen layout, including door swing and walking paths. A product without dimensions is shown but never marked as fitting.
- **Fill the gaps:** start from what a layout is missing, search for matches within the remaining budget, and explain why each one was chosen.
- **Earning:** affiliate commission on purchases through links, shown with a clear disclosure. Image generation is the main cost, so it gets a small per-user limit; paid credits or a subscription only if the app grows.

## Running costs on a $50 budget

Apple's $99 developer fee is separate. The goal is that the app cannot spend more than $50 in total, even with a bug or a burst of users. Prices below are from the pages linked at the end of this section and will change, so recheck them when you pick services.

| Item | Plan | Budget |
| --- | --- | --- |
| Product data | Channel3 free tier: 1,000 credits a month, 1 credit per search; extra credits $0.007 each | $0 |
| Backend, sign-in, database | Free tiers of the serverless and sign-in providers you pick (check their limits) | $0 |
| Item labeling | Apple's on-device Vision framework | $0 |
| Room scan | Vision-model calls, up to 10 downsized photos per scan | $10 (my estimate) |
| Visualize images | Cheapest model that follows the layout; about $0.01 to $0.04 per image, so roughly 600 to 2,500 images | $25 |
| Buffer | Price changes and testing | $15 |

- **Prepaid only:** buy credits in a fixed amount with auto-reload off on every paid service, so a provider stops at zero instead of billing you more.
- **Limits:** Visualize requires sign-in, with 3 images a day and 10 a month per account, and a kill switch in the backend that pauses it for everyone once the month's budget is used.
- **Savings:** cache results, downsize photos before upload, and generate one image per layout instead of one per tap.

Sources: [image model prices, August 2026](https://invideo.io/blog/ai-image-model-pricing/) (Nano Banana $0.039, Flux Kontext pro $0.04, Flux 2 klein about $0.014 to $0.015, Reve Edit Fast $0.01 per edit) and [Channel3 pricing](https://docs.trychannel3.com/pricing).

## Risks and App Store requirements

The biggest risk is that a single photo cannot give accurate sizes without LiDAR, so every estimate must be editable. The rest are below.

| Risk | Why it matters | Response |
| --- | --- | --- |
| Inaccurate sizes from photos | No LiDAR on your phone or many users' phones | LiDAR iPhones measure with RoomPlan; other iPhones use AR measure, a reference object, or manual entry; label non-LiDAR results "estimated" |
| Weak room scan | Photos alone cannot give exact walls or real-world scale | Keep scanning, up to 10 photos, until the outline is understood; ask for one known measurement for scale; load the draft into the editor; ship as Beta |
| Catalog access delays | Affiliate programs and some retailer APIs need approval that can take days to weeks | Start with a product-data API that needs no approval; apply to affiliate programs in parallel; keep the hand-curated fallback |
| Image generation cost | Each image costs money | Prepaid credits only, cheapest model that follows the layout, sign-in and per-user limits, a kill switch when the budget is used |
| Generated image differs from the plan | Image models do not follow layouts exactly | Label every image "AI-generated inspiration" |
| App Store rejection | A rejection costs a review round trip | Submit by day 4 or 5 of week 6; follow the checklist below |
| Sign-in friction and Apple rules | A login wall hurts first use; Apple wants Sign in with Apple beside Google, in-app account deletion, and an app the reviewer can test | Keep guest mode, add Sign in with Apple, add Delete account, put a demo account in the review notes |

**App Store checklist**

- Apple Developer Program membership ($99 per year).
- A public privacy policy that covers photos sent to your servers and model providers, retention, and affiliate links.
- Accurate App Privacy answers and a camera usage description in plain language.
- Guest mode, so the reviewer can test every feature without signing in; because accounts exist, also add Sign in with Apple next to Google and in-app account deletion, and put a demo account in the review notes.
- Affiliate disclosure near shopping links.
- If you sell image credits or a subscription: Apple in-app purchase and a restore-purchases button.
- Screenshots, description, keywords, age rating, and review notes.

## Decisions locked and open questions

**Locked**

- Tabs run left to right: Home, Current Items, Catalog.
- Supports all iPhones; nothing requires LiDAR.
- Real catalog integration through a backend proxy.
- Solo build, 6 weeks, aimed at the App Store.

* Profile button at the top right of every screen; sign in with Google, Apple, or email and password; guest mode stays.

**Still open**

- [ ] Which catalog source is primary? Decide in week 4 after testing 20 real searches.
- [ ] How to pay for image generation: stay inside the $50 budget with per-user limits for v1, and revisit credits or a subscription only if the app grows.
- [ ] Which image-generation model? Test three on your own room photos in week 5.
- [ ] App name and whether the name is free on the App Store.
- [ ] Metric or imperial units as the default.

* [ ] Should signed-in users get their rooms and items synced across devices, or stay on-device for v1?
* [ ] Should the free image limit follow the account or the device?
