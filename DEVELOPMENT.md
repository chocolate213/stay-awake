# Development

## Project Layout

```text
StayAwakeMenu/
  Info.plist
  main.m
  Resources/
    Scripts/
      stay-awake
    en.lproj/
    zh-Hans.lproj/
build-menu-app.sh
Makefile
scripts/
  package-release.sh
  stay-awake-toggle
tools/
  prepare_app_icon.m
```

## Localization

User-visible strings live in:

- `StayAwakeMenu/Resources/en.lproj/Localizable.strings`
- `StayAwakeMenu/Resources/zh-Hans.lproj/Localizable.strings`

Bundle display names live in each locale’s `InfoPlist.strings`.

The app resolves the best supported localization from the current macOS language preferences when menu text is refreshed. This keeps the menu aligned with `AppleLanguages` while still using standard `.lproj` resource bundles.

## Status Bar Icon

The status bar icon uses SF Symbols via `NSImage imageWithSystemSymbolName:accessibilityDescription:`. When Stay Awake is on, the app shows `moon.stars.fill`; when it is off, the app shows `moon.zzz.fill`. Both states use full opacity so the state remains distinguishable even when macOS dims an inactive display's menu bar.

The status item uses `NSVariableStatusItemLength` with monospaced digits beside the SF Symbol during timed sessions. The app does not manually tint the icon; the symbol remains a template image so AppKit applies the menu bar's active, highlighted, light, and dark appearances.

## App Icon

`StayAwakeMenu/Assets/AppIconSource.png` is the generated source artwork for the app icon. The build script uses `tools/prepare_app_icon.m` to resize it into the standard macOS iconset sizes, remove the generated dark outer background from the connected image edges, and then uses `iconutil` to create `AppIcon.icns`.

The prepared iconset includes a 1024 by 1024 representation to match Apple's current app icon specification for iOS, iPadOS, and macOS. The generated `.icns` is copied into the bundle and referenced by `CFBundleIconFile`.

## Helper Script Installation

The app includes `StayAwakeMenu/Resources/Scripts/stay-awake` inside the bundle. At runtime it copies that helper into the current user's Application Support directory, then launches the installed copy.

When the menu app starts the helper, it passes the app process ID through `--watch-pid`. The helper forwards that to `caffeinate -w`, so the wake lock is released even if the menu app exits before `applicationWillTerminate:` can stop it.

After a toggle, the app updates the menu bar presentation from the intended action immediately, then verifies the actual `caffeinate` process shortly after. This avoids a startup race where the helper PID exists before the shell script has finished `exec`-ing into `caffeinate`.

If the machine restarts while a wake lock is active, the previous PID file is stale. The app compares the PID file modification date with the current boot time and clears stale state before presenting status or starting a new wake lock.

The app derives the Application Support location with `NSApplicationSupportDirectory` and `NSUserDomainMask`; no developer-machine absolute script path is embedded in the app.

## Timed Sessions

The menu passes seconds through the bundled helper's `--time` argument. `caffeinate -t` owns the timeout, while the app tracks an end date for presentation and wake reconciliation. A five-second timer runs in common run-loop modes, so an open menu does not freeze the countdown. A process termination handler clears the displayed running state without sending an expiry notification.

`State/session.plist` stores the PID and optional deadline alongside the existing `caffeinate.pid`. Metadata is used only when it matches the current live PID. The CLI toggle clears the metadata when starting or stopping an indefinite session. Direct helper invocations remain independent.

Changing or extending the duration starts the replacement process before terminating the previous one. If writing the new state fails, the existing session remains running. The app retains the existing bundle identifier and Application Support location across the repository rename.

## Build Checks

```bash
make verify
```

This compiles the app, runs helper and session lifecycle tests (with short real `caffeinate` processes in temporary storage), validates `Info.plist`, and checks the ad-hoc code signature. Session tests cover custom input boundaries, countdown formatting, extension, manual stop, silent expiry, wake reconciliation, CLI metadata mismatch, and failed state writes.

## Release Packaging

```bash
make release
```

The release target creates `release/Stay-Awake-<version>-macOS.zip` and a matching SHA-256 checksum. See `docs/RELEASE.md` for the release checklist.
