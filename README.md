# Interior Design

An iPhone app for measuring your room, tracking what you own, and (later) planning layouts and shopping. Built with SwiftUI and SwiftData. Minimum iOS 17.

## Status: Weeks 1–6 built (simulator); backend not deployed, no AI model chosen yet

- Tabs: Home, Current Items, Catalog
- Profile button (top right) opening a guest sheet; sign-in is not wired up yet
- Room builder, Basic: rectangle or square, width/length in feet/inches or metric, a to-scale plan with wall lengths, draggable doors, windows, and outlets, rename/delete, multiple rooms
- Room builder, Advanced: any shape on a grid. Tap to add a corner, drag to move, long-press to delete; live wall lengths and angles; "Lock angles" snaps to 30/45/60/90° (and 120–180°); undo/redo; tap a wall to type its measured length, with a warning that names the wall that doesn't fit when measurements disagree
- Items: add, edit, and delete furniture by hand (type, size, photo, notes, fixed or movable, room)
- Recommended Layouts: a rule-based layout engine (on the phone, offline, same answer every time) suggests 3–5 different arrangements with labels like "Seating faces the TV"; drag or turn items to adjust (with warnings if a door or path gets blocked), see what stays, moves, or is missing, and save one as the room's layout
- Catalog: budget (total and per item), filters, "Fill the gaps" for a room, product grid with a fit check against the room's free space, product page with retailer link and commission disclosure, wishlist, and "preview in room". Uses sample placeholder products until the live catalog is deployed
- Sign-in (optional): email and password with confirmation and reset, profile with usage, sign out, delete account. Google and Apple buttons are built but off until set up
- Backend in `supabase/` (see `supabase/README.md` to deploy)
- Add furniture from a photo: on-device labeling, AR measure (supported phones), or measure against a card/paper/door in the photo; sizes stay "Estimated" until confirmed
- Room scan: RoomPlan on LiDAR iPhones (Beta); others are pointed to the drawing tools
- Visualize (AI pictures): built, off until an image model is chosen; $5/month hard cap, 3 a day and 10 a month per account
- First-run welcome, accessibility (text sizes, VoiceOver, contrast, Reduce Motion), loading placeholders
- Store drafts in `docs/`: privacy policy, App Privacy answers, listing, review notes
- Debug builds: Profile → Developer → "Demo AI features" fakes scan and image results for trying the screens for free
- Everything saves on the device with SwiftData

> Builds and passes its unit tests on the iPhone simulator (Xcode 27.1). Until you set a development team in `project.yml`, it runs in the simulator only.

## Set up

1. Install Xcode (from the App Store) and XcodeGen: `brew install xcodegen`
2. From this folder run `xcodegen` to create `InteriorDesign.xcodeproj`
3. Open the project. Under Signing & Capabilities pick your team and change the bundle identifier from `com.example.InteriorDesign`
4. Run on a simulator or your iPhone

**If XcodeGen gives you trouble:** in Xcode choose File > New > Project > iOS App (SwiftUI, SwiftData storage off), then drag the `InteriorDesign` and `InteriorDesignTests` folders in, deleting the template files.

## Try it

Debug builds load a sample living room and six items on first launch (also in the profile sheet). Open Current Items, tap the ruler button, open a room, change the size, add a door, drag it around, then force-quit and reopen. The room should still be there.

## Layout

```
InteriorDesign/
  App/        app entry and tab bar
  Home/ Items/ Rooms/ Layouts/ Catalog/   one folder per feature
  Shared/     design system, models, units, geometry, profile sheet
InteriorDesignTests/   unit tests for units, geometry, rooms
```
