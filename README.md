# Stay Awake

**Keep your Mac awake while local AI agents work.**

Stay Awake is a lightweight, native macOS menu bar app that prevents idle sleep during long-running local coding agent sessions. Use it while an agent edits code, runs tests, builds a project, or works through a task in your terminal or editor.

Choose a duration, see the time remaining in the menu bar, and extend the session when your agent needs more time. It uses macOS's built-in `caffeinate` command without changing your system sleep settings.

## Features

- Keep your Mac and display awake for **15 or 30 minutes, or 1, 2, 3, 4, 5, or 8 hours**, or indefinitely.
- Set a **custom duration** from 1 to 10,080 minutes (7 days).
- See **remaining time in the menu bar** and the expected end time in the menu.
- **Extend by 30 minutes** without resetting the remaining time, or stop at any time.
- Restore normal sleep behavior silently when the timer expires; no expiry notification.
- Native AppKit app with SF Symbols, no Dock icon, and English / Simplified Chinese UI.
- Bundled CLI helper and an optional toggle script that shares the app's running state.

## For Local Agent Workflows

1. Start your local AI coding agent, terminal automation, test suite, or build.
2. Open Stay Awake and choose **Keep Awake For → 60 minutes** (or your own duration).
3. Check the countdown at a glance. Choose **Extend by 30 Minutes** if the task is still running.
4. Stop Stay Awake when finished, or let the timer expire.

Stay Awake prevents idle sleep; it does not launch or supervise the agent, bypass its approval prompts, or remove service usage limits. Keep a MacBook's lid open. Ending a session releases this app's sleep assertions and lets macOS apply its normal rules; it does not force immediate sleep, and other apps may still keep the Mac awake.

## Requirements

- macOS 11.0 or later.

Building from source also requires Xcode Command Line Tools.

## Install

Download the latest `Stay-Awake-<version>-macOS.zip` from [GitHub Releases](https://github.com/chocolate213/stay-awake/releases), unzip it, then move `Stay Awake.app` to your Applications folder.

```text
/Applications/Stay Awake.app
```

Launch the app from Applications. It is a menu bar app, so it does not appear in the Dock; look for the moon icon in the macOS status bar.

If macOS blocks the first launch because the app is not notarized, right-click `Stay Awake.app`, choose Open, then confirm Open once. Future launches should work normally.

On first launch, the app installs its bundled helper script under the current user's Application Support directory:

```text
~/Library/Application Support/local.stay-awake.menu/
```

## Usage

Click the moon icon to open the menu:

| Action / state | Behavior |
| --- | --- |
| Turn Stay Awake On | Start an indefinite session. |
| Keep Awake For | Choose a preset or a custom number of minutes. A new duration replaces the current session, starting now. |
| Extend by 30 Minutes | Add 30 minutes to the remaining time. Available only during a timed session. |
| Turn Stay Awake Off | Stop the current session immediately. |
| Quit | Stop the current session and exit the app. |

The active moon icon indicates that Stay Awake is on; the sleeping moon means it is off. Timed sessions also show a compact countdown such as `42m`, `1h 20m`, or `<1m`. Indefinite sessions show `On` beside the icon until stopped; inactive sessions show `Off`. The countdown refreshes every few seconds, including while the menu is open.

Custom durations accept whole minutes from 1 to 10,080. Cancel leaves the current session unchanged. After sleep or wake, the app reconciles an expired deadline instead of starting the timer again.

## Install From Source

Clone the repository and enter the project directory:

```bash
git clone https://github.com/chocolate213/stay-awake.git
cd stay-awake
```

Build, install, and launch the app:

```bash
make run
```

This compiles the app and installs it to:

```text
~/Applications/Stay Awake.app
```

For a build-only workflow:

```bash
make build
```

The built app bundle is created at:

```text
dist/Stay Awake.app
```

The app is an agent app (`LSUIElement=true`), so it appears in the macOS status bar instead of the Dock.

The app does not register itself as a login item. After a restart, launch `Stay Awake.app` from Applications to show the menu bar icon again, or add it manually in System Settings > General > Login Items.

## Package A Release

```bash
make verify
make release
```

This creates a distributable zip and SHA-256 checksum in `release/`.

## Optional CLI Toggle

The menu bar app installs the helper script on launch. For terminal-only workflows after the app has launched once, this repository also includes:

```text
scripts/stay-awake-toggle
```

The toggle script stops the current session or starts an indefinite one using the same installed helper and PID file as the app, so the menu follows those changes. Launching the helper directly is a separate terminal session and does not publish a menu bar countdown.

The Application Support directory keeps its existing `local.stay-awake.menu` identifier for compatibility with earlier installations; the repository is now named `stay-awake`.

## Uninstall

Quit the app from the menu bar, delete `Stay Awake.app`, then remove the helper state directory if you want a full cleanup:

```bash
rm -rf "$HOME/Library/Application Support/local.stay-awake.menu"
```
