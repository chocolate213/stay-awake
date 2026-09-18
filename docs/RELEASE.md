# Release Checklist

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `StayAwakeMenu/Info.plist`.
2. Review the source tree for local machine paths, organization-specific identifiers, generated artifacts, and stale experimental UI references.
3. Run `make verify`.
4. Run `make release`.
5. Create and push a version tag, for example `v1.0.0`, or run the Release workflow manually with an existing tag.
6. Confirm the GitHub Release contains the generated zip and checksum from `release/`.
7. On a clean macOS user account, unzip the app, launch it, and confirm the helper installs under Application Support.
8. Restart the clean account, launch the app again, and confirm the status starts as off and can be turned on from the menu bar.
9. In English and Simplified Chinese, check a preset, a custom 1-minute session, invalid input, and cancel. Confirm the menu bar countdown fits, the end time is readable, and cancel preserves the current session.
10. Extend a timed session by 30 minutes, then stop it. Confirm the countdown changes to `Off`; indefinite sessions must disable the extension action.
11. Let a 1-minute session expire with the menu open. Confirm the icon returns to off and no expiry notification appears. Check that waking after an expired deadline does not restart the session.
12. Use `scripts/stay-awake-toggle` to stop a timed session and start an indefinite one. Confirm the menu follows the process and shows `On` instead of the old countdown.

The release build is ad-hoc signed for local distribution. For notarized public distribution, sign with a Developer ID Application certificate and submit the archive to Apple's notarization service.
