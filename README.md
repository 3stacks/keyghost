# KeyGhost

A macOS menu-bar app that turns Caps Lock (or any other trigger key)
into a launcher with a visual cheatsheet. Hold the trigger and a
translucent keyboard fades in showing the app icon bound to each key.
Press a bound letter while the trigger is held and the app launches
immediately — the chord is consumed so it never reaches your focused
window.

KeyGhost reads the trigger key directly from the HID layer, beneath any
modifier remapping (Hyperkey, Karabiner, macOS Modifier Keys), so it
works regardless of how you've configured your "hyper" key.

## Build

```sh
swift run                                 # debug build, run in-place
./scripts/build-app.sh                    # release .app at build/KeyGhost.app
./scripts/build-dmg.sh                    # also packages a DMG
./scripts/build-dmg.sh --skip-notarize    # skip the notarytool wait
```

By default the scripts ad-hoc-sign. Pass `SIGNING_IDENTITY` (and
`TEAM_ID` / `NOTARY_PROFILE`) to sign with your own Developer ID:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Org (TEAMID)" \
TEAM_ID="TEAMID" \
NOTARY_PROFILE="notarytool-profile" \
./scripts/build-dmg.sh
```

Ad-hoc signatures change on every rebuild, so the Accessibility and
Input Monitoring grants don't survive `./scripts/build-app.sh` runs. A
Developer ID identity gives a stable signature and the grants stick.

## First-run setup

1. Launch `KeyGhost.app`.
2. Menu bar → **Grant Accessibility…** → enable KeyGhost in System
   Settings → Privacy & Security → Accessibility.
3. Menu bar → **Grant Input Monitoring…** → enable KeyGhost in System
   Settings → Privacy & Security → Input Monitoring.
4. Quit and relaunch. Both monitors need the permissions at startup.
5. Menu bar → **Settings…** to add bindings via a clickable keyboard,
   or edit `~/Library/Application Support/KeyGhost/bindings.json`
   directly.

## Settings UI

Menu bar → **Settings…** (or ⌘,) opens an editor with:

- **Trigger key picker** — click-to-capture; press the physical key you
  want to use (Caps Lock, F13–F20, Right Option, etc.) and KeyGhost
  records the HID usage.
- **Hold delay slider** — how long the trigger must be held before the
  overlay fades in (0–1000 ms).
- **Keyboard grid** — click any letter or digit to add or edit a binding.
- **Per-key editor** — choose Application or URL, pick an installed
  app via `NSOpenPanel`, optionally label it, and toggle Passthrough.

## Bindings format

```json
{
  "holdDelayMs": 250,
  "triggerKey": "capsLock",
  "bindings": [
    { "key": "T", "bundleId": "com.apple.Terminal", "label": "Terminal" },
    { "key": "M", "bundleId": "com.google.Chrome", "url": "https://mail.google.com", "label": "Gmail" },
    { "key": "V", "bundleId": "org.p0deje.Maccy", "label": "Maccy", "passthrough": true }
  ]
}
```

| Field | Notes |
|---|---|
| `triggerKey` | `capsLock` (default), `f1`–`f20`, `leftShift`/`rightShift`, `leftControl`/`rightControl`, `leftOption`/`rightOption`, `leftCommand`/`rightCommand` |
| `holdDelayMs` | Delay before the overlay appears (milliseconds) |
| `bindings[].key` | Single letter or digit |
| `bindings[].bundleId` | Application bundle identifier — `osascript -e 'id of app "Terminal"'` |
| `bindings[].url` | Optional URL to open. With `bundleId`, opens in that specific app (Chrome for Gmail). Without, uses the system default |
| `bindings[].label` | Small caption beneath the icon |
| `bindings[].passthrough` | Display the icon on the overlay but let the chord through to the OS, so an already-registered hotkey owner (Maccy, KO Nav, Shortcuts.app) handles it. KeyGhost rewrites the event flags to the full `⌃⌥⇧⌘` chord before passing it through |

The file is live-watched, so saving refreshes the next overlay
invocation.

## How it works

- **`TriggerKeyMonitor`** opens an `IOHIDManager` on the keyboard usage
  page and watches for press/release of the configured key's HID usage
  code (e.g. `0x39` for Caps Lock). This is below any user-space
  remapping, so it sees the physical key regardless of what Hyperkey,
  Karabiner, or System Settings → Modifier Keys do to it.
- **`ChordMonitor`** runs a consuming `CGEventTap` on `.keyDown`
  events. When the trigger key is held (per HID state) and a bound
  letter is pressed, it dispatches to the launcher and returns `nil`
  to swallow the original event. Passthrough bindings get their flags
  rewritten to the full `⌃⌥⇧⌘` chord and pass through unchanged.
- **`Launcher`** opens the bound app via
  `NSWorkspace.openApplication(at:configuration:)`, or opens a URL via
  `NSWorkspace.open([url], withApplicationAt:configuration:)` when a
  `url` field is set.
- Icons are resolved at render time via
  `NSWorkspace.urlForApplication(withBundleIdentifier:)` →
  `NSWorkspace.icon(forFile:)`, so they always reflect the installed
  app's current icon.

## Layout

```
keyghost/
├── KeyGhost/                       # Swift sources + resources
│   ├── KeyGhostApp.swift           # @main entry point
│   ├── AppDelegate.swift           # menubar, monitor wiring, overlay
│   ├── TriggerKeyMonitor.swift     # HID-layer trigger detection
│   ├── TriggerKeyCapture.swift     # one-shot HID listener for Settings
│   ├── ChordMonitor.swift          # CGEventTap, chord dispatch
│   ├── KeyCode.swift               # ANSI virtual keycode → letter
│   ├── Launcher.swift              # NSWorkspace.openApplication / open URL
│   ├── Bindings.swift              # JSON model + load/save
│   ├── BindingsStore.swift         # @Observable wrapper
│   ├── IconResolver.swift          # bundle id → NSImage
│   ├── OverlayPanel.swift          # borderless floating NSPanel
│   ├── KeyboardOverlayView.swift   # SwiftUI keyboard grid (overlay)
│   ├── SettingsView.swift          # SwiftUI settings UI
│   └── Resources/
│       └── bindings.example.json
├── Bundle/
│   ├── Info.plist                  # template (LSUIElement, bundle id, version)
│   └── Entitlements.plist          # apple-events for NSWorkspace launches
├── scripts/
│   ├── build-app.sh                # release build → KeyGhost.app
│   └── build-dmg.sh                # signed + notarized DMG
└── Package.swift
```

## License

MIT — see `LICENSE`.
