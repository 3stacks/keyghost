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
| `bindings[].nested` | Optional `{ up, right, down, left }` map of secondary actions. While the chord is held, pressing an arrow key highlights that direction's tile in a radial overlay; releasing the trigger fires it. Releasing without an arrow press falls back to the root binding |

### Nested radial example

```json
{
  "key": "F",
  "bundleId": "com.google.Chrome",
  "label": "Chrome",
  "nested": {
    "up":    { "bundleId": "com.google.Chrome", "url": "https://mail.google.com",     "label": "Gmail" },
    "right": { "bundleId": "com.google.Chrome", "url": "https://calendar.google.com", "label": "Calendar" },
    "down":  { "bundleId": "com.google.Chrome", "url": "https://github.com",          "label": "GitHub" }
  }
}
```

Caps + F by itself opens Chrome. Caps + F + ↑ opens Gmail in Chrome,
Caps + F + → opens Google Calendar, Caps + F + ↓ opens GitHub. Any
direction left out of `nested` just shows an empty slot. The Settings
UI doesn't expose `nested` editing yet — edit `bindings.json` directly.

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

Releases run locally from a machine with the signing keychain set up
(no GitHub Actions). The flow is the same as `~/ko-work/Sites/ko-nav`:
build → sign → notarize → generate appcast → upload to R2 → cut a
GitHub Release.

Existing installs poll `https://keyghost.lukeboyle.com/appcast.xml` and
self-update via Sparkle ("Check for Updates…" in the menu bar, or on the
automatic schedule).

### One-time setup

Done once per machine. All secrets live in the local Keychain or in
`wrangler`'s config — nothing in the repo, nothing in GitHub secrets.

1. **Import the Developer ID Application certificate** into your login
   Keychain (Xcode → Settings → Accounts → Manage Certificates, or
   double-click the .p12 export).

2. **Register a notarytool keychain profile** so the build script can
   submit without prompting:

   ```sh
   xcrun notarytool store-credentials notarytool-profile \
       --apple-id you@example.com \
       --team-id TEAMID \
       --password APP_SPECIFIC_PASSWORD
   ```

3. **Generate the Sparkle EdDSA signing keypair** (after running
   `swift build` at least once so the Sparkle artifacts are present):

   ```sh
   ./.build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

   The private key is stored in your Keychain — `generate_appcast` finds
   it automatically. Copy the public key it prints into
   `Bundle/Info.plist` (replace `__SU_PUBLIC_ED_KEY__` under
   `SUPublicEDKey`) and commit that one-line change.

4. **Create R2 S3 access keys and a `.env`.** Visit
   <https://dash.cloudflare.com/66bbbf59d9ee8948f770553dfc0d5721/r2/api-tokens>,
   create a token with **Object Read & Write** scoped to the `keyghost`
   bucket. Cloudflare returns an Access Key ID + Secret Access Key
   pair; paste them into a gitignored `.env` alongside your signing
   identity:

   ```sh
   brew install awscli   # one-time, if you don't already have it
   cat > .env <<'EOF'
   R2_ACCESS_KEY_ID=…
   R2_SECRET_ACCESS_KEY=…
   SIGNING_IDENTITY=Developer ID Application: Your Name (TEAMID)
   TEAM_ID=TEAMID
   EOF
   ```

   The build and upload scripts source `.env` automatically. Uploads
   use the S3-compatible API via `aws s3 cp` against
   `https://<account>.r2.cloudflarestorage.com` — no `wrangler login`,
   no Bearer token quirks.

5. **Attach the custom domain** `keyghost.lukeboyle.com` to the R2
   bucket `keyghost` in the Cloudflare dashboard (R2 → bucket →
   Settings → Custom Domains). `SUFeedURL` and the appcast download
   URLs both rely on this.

### Cutting a release

With SIGNING_IDENTITY and TEAM_ID already in `.env` from one-time setup:

```sh
VERSION=0.2.0
VERSION="$VERSION" ./scripts/build-dmg.sh   # build + sign + notarize + appcast

VERSION="$VERSION" CLOUDFLARE_ACCOUNT_ID=66bbbf59d9ee8948f770553dfc0d5721 \
    ./scripts/upload-r2.sh                  # publish DMG + appcast to R2

gh release create "v$VERSION" \
    "build/KeyGhost-$VERSION.dmg" \
    "build/appcast.xml" \
    --title "KeyGhost v$VERSION" \
    --generate-notes
```

The notarize step is what takes the most time (~3–10 minutes waiting
on Apple). Everything else is local.

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
├── package.json                    # wrangler devDep (used by upload-r2.sh)
└── Package.swift
```

## Contributing

Bug reports and PRs welcome. For non-trivial changes please open an
issue first to discuss the approach.

## License

MIT — see `LICENSE`.
