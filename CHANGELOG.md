# Changelog

## Unreleased

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
