# KeyGhost

A macOS menu-bar app that turns Caps Lock (or any other trigger key) into
a launcher with a visual cheatsheet. Hold the trigger and a translucent
keyboard fades in showing the app icon bound to each key. Press a bound
letter while the trigger is held and the app launches immediately — the
chord is consumed so it never reaches your focused window.

KeyGhost reads the trigger key directly from the HID layer, beneath any
modifier remapping (Hyperkey, Karabiner, macOS Modifier Keys), so it
works regardless of how you've configured your "hyper" key.

<!-- TODO: replace with a real demo gif/screenshot at assets/demo.gif -->
<!-- ![KeyGhost overlay](assets/demo.gif) -->

## Install

Download the latest signed DMG from
[Releases](https://github.com/3stacks/keyghost/releases), drag
`KeyGhost.app` to `/Applications`, and launch it.

Or build from source — see [Building from source](#building-from-source).

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
| `bindings[].passthrough` | Display the icon on the overlay but let the chord through to the OS, so an already-registered hotkey owner (Maccy, Raycast, Shortcuts.app) handles it. KeyGhost rewrites the event flags to the full `⌃⌥⇧⌘` chord before passing it through |

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

## Building from source

Requires Xcode 15+ (Swift 5.9, macOS 14 SDK).

```sh
swift run                                 # debug build, run in-place
./scripts/build-app.sh                    # release .app at build/KeyGhost.app
./scripts/build-dmg.sh                    # also packages a DMG
./scripts/build-dmg.sh --skip-notarize    # skip the notarytool wait
```

By default the scripts ad-hoc-sign. Pass `SIGNING_IDENTITY` (and
`TEAM_ID` / `NOTARY_PROFILE`) to sign with your own Developer ID:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
TEAM_ID="TEAMID" \
NOTARY_PROFILE="notarytool-profile" \
./scripts/build-dmg.sh
```

Ad-hoc signatures change on every rebuild, so the Accessibility and
Input Monitoring grants don't survive `./scripts/build-app.sh` runs. A
Developer ID identity gives a stable signature and the grants stick.

## Releasing

Releases are tag-driven: push `vX.Y.Z` and `.github/workflows/release.yml`
will build, sign, notarize, generate a Sparkle appcast, publish a GitHub
Release with the DMG attached, and push the DMG + `appcast.xml` to the
Cloudflare R2 bucket served at <https://keyghost.lukeboyle.com/>.

Existing installs poll `https://keyghost.lukeboyle.com/appcast.xml` and
self-update via Sparkle ("Check for Updates…" in the menu bar, or on the
automatic schedule).

### One-time setup

Before the first release, generate the Sparkle EdDSA signing keypair and
configure the secrets and DNS.

1. **Generate the EdDSA keypair** (after running `swift build` at least
   once so the Sparkle artifacts are present):

   ```sh
   ./.build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

   Copy the public key into `Bundle/Info.plist` (replace
   `__SU_PUBLIC_ED_KEY__` under `SUPublicEDKey`). Keep the private key
   — it must go into the `SPARKLE_ED_PRIVATE_KEY` GitHub secret below
   and **never** be committed.

2. **Set the GitHub repository secrets** (Settings → Secrets and variables
   → Actions):

   | Secret | What it is |
   | --- | --- |
   | `MACOS_DEVELOPER_ID_CERT_BASE64` | `base64 < cert.p12` of the Developer ID Application export |
   | `MACOS_DEVELOPER_ID_CERT_PASSWORD` | password used when exporting the .p12 |
   | `KEYCHAIN_PASSWORD` | any string — temp keychain password for CI |
   | `SIGNING_IDENTITY` | e.g. `Developer ID Application: Luke Boyle (TEAMID)` |
   | `APPLE_ID` | Apple ID used for notarization |
   | `APPLE_ID_PASSWORD` | app-specific password from appleid.apple.com |
   | `APPLE_TEAM_ID` | 10-character Apple Developer team ID |
   | `SPARKLE_ED_PRIVATE_KEY` | EdDSA private key from step 1 |
   | `CLOUDFLARE_API_TOKEN` | R2 token with object read+write on the `keyghost` bucket |
   | `CLOUDFLARE_ACCOUNT_ID` | `66bbbf59d9ee8948f770553dfc0d5721` |

3. **Wire the custom domain**. In the Cloudflare dashboard, attach
   `keyghost.lukeboyle.com` to the R2 bucket `keyghost` (R2 → bucket →
   Settings → Custom Domains). The hostname in `SUFeedURL` and the
   `--download-url-prefix` flag both rely on this.

### Cutting a release

```sh
git tag v0.2.0
git push origin v0.2.0
```

The workflow runs on `macos-14`, takes ~10 minutes (most of which is
`notarytool` waiting), and on success the new version is live for both
fresh downloads (GitHub Release page) and existing installs (Sparkle
auto-update from R2).

For a dry run, use the workflow's manual `workflow_dispatch` trigger —
it builds + notarizes but skips the R2 upload and GitHub Release steps.

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
│   ├── build-app.sh                # release build → KeyGhost.app (embeds Sparkle.framework)
│   ├── build-dmg.sh                # signed + notarized DMG + Sparkle appcast.xml
│   └── upload-r2.sh                # publishes DMG + appcast to Cloudflare R2
├── .github/workflows/release.yml   # tag-driven build → notarize → R2 → GH Release
├── package.json                    # wrangler devDep (used by upload-r2.sh)
└── Package.swift
```

## Contributing

Bug reports and PRs welcome. For non-trivial changes please open an
issue first to discuss the approach.

## License

MIT — see `LICENSE`.
