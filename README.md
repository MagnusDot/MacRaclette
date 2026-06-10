# Mac Raclette

Mac Raclette is a small macOS menu bar utility that turns thermal monitoring into a raclette joke.

When the hottest readable temperature sensor goes above a configurable threshold, the app switches into **Raclette mode**: the menu bar icon changes to melted cheese, a bell can play, and the panel shows that the machine is "ready to serve".

## Features

- Native macOS menu bar app built with SwiftUI `MenuBarExtra`.
- Real sensor readings where available:
  - IOHID temperature sensors for Apple Silicon Macs.
  - AppleSMC temperature sensors as a fallback/complement on Macs that expose them.
- Dynamic raclette icons in the menu bar:
  - unavailable
  - cool
  - melting
  - ready
- Compact popover with:
  - current hottest sensor temperature
  - minimum, average, and maximum since reset
  - thermal pressure state
  - detected sensor list with source (`HID` or `SMC`)
  - configurable raclette threshold
  - bell toggle
  - refresh, reset, and quit actions

## Requirements

- macOS with SwiftUI `MenuBarExtra` support.
- Xcode to build and run the app.
- Sensor availability depends on the Mac model and macOS version. Apple Silicon machines usually expose temperature sensors through IOHID, while Intel machines may expose AppleSMC keys.

## Building

Open `MacRaclette.xcodeproj` in Xcode and run the `MacRaclette` scheme.

The app is configured as a menu bar agent using `LSUIElement`, so it appears in the menu bar instead of the Dock.

## Sensor Notes

macOS does not provide one stable public API for every temperature sensor on every Mac. Mac Raclette uses two approaches:

- `HIDTemperatureReader`: reads Apple vendor temperature sensors through IOHID.
- `SMCReader`: reads AppleSMC keys that look like temperature sensors.

If no sensors are available, the app shows a sensor unavailable state instead of inventing a fake temperature.

## Assets

The raclette logos live in `MacRaclette/Assets.xcassets`.

There are separate assets for:

- `raclette-menubar-*`: small, centered menu bar icons.
- `raclette-panel-*`: larger panel icons.

This keeps the menu bar icon crisp and correctly sized while allowing the popover to use a more detailed version.
