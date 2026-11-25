# Command Center

A Control Center-style remote for your Windows PC, as a **real iPhone app** (SwiftUI), written and shipped entirely from a Windows PC.

No web wrapper. No Mac in your house. No Xcode on your machine.

**Status: the app compiles.** The macOS runner built `CommandCenter.ipa` from this source - see the Actions tab.

---

## The workaround

Xcode, `codesign` and the iOS simulator exist only on macOS, so nothing can compile an iOS app on Windows - not VS, not MAUI, not Flutter, not React Native. Every path puts a Mac *somewhere*. This repo's path:

```
edit Swift on Windows  ->  push to main  ->  GitHub Actions macOS runner
                                        ->  unsigned CommandCenter.ipa
                                        ->  download it on Windows
                                        ->  Sideloadly signs with your Apple ID
                                        ->  runs on your iPhone
```

You never maintain an `.xcodeproj`. `ios/project.yml` describes the app and **XcodeGen generates the project on the runner**, so there is no fragile project file to corrupt.

| | Free path | Paid path |
|---|---|---|
| Apple account | free Apple ID | $99/yr Developer Program |
| App lifespan before re-signing | 7 days | 1 year |
| Apps installed at once | 3 | 100 devices |
| Build minutes | free (public repo) | free (public repo) |

Start free; pay the $99 once if you use it daily.

Other routes, and why not them: **Expo/EAS** (cloud iOS builds, but React Native not SwiftUI, and device installs still need the paid account), **rented cloud Mac** (~$14/day, only worth it for interactive Xcode), **macOS VM/Hackintosh** (breaks Apple's licence).

---

## Installing on the iPhone

1. Open **Actions -> "Build iOS app" -> the latest green run**.
2. Download the artifact **`CommandCenter-ipa`**, unzip it -> `CommandCenter.ipa`.
3. Install **Sideloadly** (https://sideloadly.io) plus iTunes / Apple Mobile Device Support on Windows.
4. Plug in the iPhone, trust the computer.
5. Drag `CommandCenter.ipa` into Sideloadly, enter your Apple ID, **Start**.
6. On the iPhone: **Settings -> General -> VPN & Device Management -> trust your Apple ID**.
7. The app is now on the Home Screen.

With a free Apple ID it stops opening after 7 days - re-run Sideloadly, or use SideStore/AltStore to re-sign on-device.

## Pairing it with the PC

1. Install Node.js LTS, then double-click `pc-agent/start-agent.bat` (or `node server.js` in that folder).
2. First run creates `pc-agent/agent.config.json` and prints the **LAN address**, **port** (`8765`) and **pairing token**.
3. Allow Node.js through Windows Firewall on private networks.
4. In the app: gear icon -> address, port, token -> **Test connection**.

## What it controls

Volume (draggable dial), mute, media play/pause/skip, lock, sleep, screen off, app launchers (Steam Big Picture, Chrome, Discord, Spotify, Files, Task Manager, Settings, Terminal - all editable), and restart/shutdown with a 60-second cancellable delay.

A connected controller drives the app itself: A play/pause, B mute, X previous, Y next, D-pad up/down volume, bumpers skip.

## Playing PC games on the iPhone

Not built in, deliberately. Streaming needs hardware video encoding on the PC and a low-latency decoder on the phone - a separate product. The working free pair:

1. **Sunshine** on the PC (https://github.com/LizardByte/Sunshine).
2. **Moonlight** on the iPhone (App Store) - pair with Sunshine's PIN.
3. Xbox / DualSense / Backbone controller over Bluetooth or USB-C; iOS hands it straight to Moonlight.

The **Big Picture** button exists for this: put Steam into controller mode here, play in Moonlight.

## Security

- Plain HTTP on your LAN with a token. Anyone who sniffs your Wi-Fi and reads the token can drive the PC. Fine at home, not on cafe Wi-Fi.
- **Never port-forward** the agent - it can lock and shut down your machine.
- The token lives in `pc-agent/agent.config.json` (git-ignored). Delete it and restart to rotate.

## Verified vs assumed

Verified:

- The Swift compiles and packages on the macOS runner (Actions run 45723961808, all steps green).
- Locally: the agent serves `/status` with a valid token, returns 401 without one, and 400 for unknown actions or malformed JSON.

Not verified:

- Installing on a physical iPhone with Sideloadly, and the trust prompt.
- The volume percentage is an estimate from what the app set - Windows has no dependency-free way to read the mixer, so it can drift from the real level.
- Controller mapping on real hardware.
