# Interior Design

An iPhone app for measuring your room, tracking what you own, and (later) planning layouts and shopping. Built with SwiftUI and SwiftData. Minimum iOS 17.

## Status: Week 1

- Tabs: Home, Current Items, Catalog
- Profile button (top right) opening a guest sheet; sign-in is not wired up yet
- Room builder: rectangle or square, width/length in feet/inches or metric, a to-scale plan with wall lengths, draggable doors, windows, and outlets, rename/delete, multiple rooms
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
