# Changelog

## 1.1.0

- Add Keep Awake Until with a native time picker and a Today/Tomorrow preview.
- Replace the custom minutes field with native hours/minutes inputs and steppers.
- Use matching dialog sizes and large, easy-to-read time digits.
- Reject invalid custom duration input immediately, including values exceeding the seven-day limit.
- Adjust time values with the mouse wheel or trackpad; filter inertial scrolling to avoid unintended changes.

## 1.0.4

- Remove the checkmark from the On/Off action to avoid confusing the next action with the current state.
- Add 3-hour, 4-hour, 5-hour, and 8-hour keep-awake presets alongside 15 minutes, 30 minutes, 1 hour, and 2 hours.
- Use full duration units with spaces and correct English singular/plural forms; retain indefinite and custom sessions.

## 1.0.3

- Redesign the application icon with a white background, blue-violet moon, and cyan spark using Apple Icon Composer. Include the editable layered source and a static render for the existing build pipeline.
- Keep menu bar symbols at a consistent 16-point regular size with or without a countdown.
- Show `On` for indefinite sessions and `Off` when inactive.
- Preserve icon colors and transparency during packaging, and document reproducible icon exports.

## 1.0.1

- Add preset and custom keep-awake durations, a menu bar countdown, and a 30-minute extension action.
- Reconcile timed sessions on process exit and system wake without expiry notifications.
- Rename the repository to `stay-awake` and document its focus on local AI agent workflows.

## 1.0.0

- Added native AppKit menu bar controller for the bundled `stay-awake` helper.
- Added runtime helper installation into the current user's Application Support directory.
- Added English and Simplified Chinese localizations.
- Added an image-generated `AppIcon.icns` for Finder, Launchpad, and Applications views.
- Added an SF Symbol status bar icon configured through `NSStatusBarButton`.
- Added project documentation and Makefile targets for build, install, run, verify, and clean.
- Added GitHub Actions CI and release archive packaging.
- Quit now always stops the active wake lock before exiting the menu app.
