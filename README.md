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

## Paddle - streaming the PC to the iPhone

**Paddle** is the built-in stream: your own link, no Sunshine, no Moonlight, no third-party account.

1. Start the agent (`pc-agent/start-agent.bat`). It needs **ffmpeg** on the PATH for the screen capture.
2. In the app, tap **Stream now** on the amber card.
3. Tap = click, drag = drag, hold = right click. Esc / Tab / Enter / Backspace / Win are on the top bar.

How it works: `GET /paddle` (alias `/stream`) runs `ffmpeg -f gdigrab` on the PC and re-frames its MJPEG output as 4-byte big-endian length + one JPEG per frame. The app parses that directly and draws each frame; touches come back as `POST /input`, which a long-lived PowerShell helper turns into real `SetCursorPos` / `mouse_event` / `keybd_event` calls.

Measured on this PC: 15 fps at 960x540, ~54 KB per frame, ~0.8 MB/s, roughly 100 ms behind the desktop. That is comfortable for the desktop, launchers and turn-based games; it is not a competitive-shooter stream - that needs hardware H.264 and a VideoToolbox decoder, which is the next step if you want it.

## Moving files off the phone

**Open files** on the mint card. Tap the upload arrow to send photos/videos from the library to the PC, tap anything to browse folders, swipe left to move a file to the PC's `_trash`.

The agent only ever touches its shared roots. By default that is `%USERPROFILE%\CommandCenter\Files`; override with `AGENT_FILE_ROOTS="label=D:\path;label2=E:\other"`. Requests name a root label plus a relative path, `..` segments are refused, and any resolved path that leaves its root is rejected before a file is opened. Deletes are moves into `<root>/_trash/`, so nothing is destroyed. Uploads stream to a `.part` file and are renamed only when complete, capped at 512 MB.

| Endpoint | Purpose |
|---|---|
| `GET /files?root=&path=` | list a folder |
| `GET /files/raw?root=&path=` | download one file |
| `POST /files/upload?root=&path=&name=` | raw body upload |
| `POST /files/folder?root=&path=` | create a folder |
| `POST /files/trash?root=&path=` | move to `_trash` |

Run `node test-files.js` for the end-to-end check against a throwaway root.

## Security

- Plain HTTP on your LAN with a token. Anyone who sniffs your Wi-Fi and reads the token can drive the PC. Fine at home, not on cafe Wi-Fi.
- **Never port-forward** the agent - it can lock and shut down your machine.
- The token lives in `pc-agent/agent.config.json` (git-ignored). Delete it and restart to rotate.

## Verified vs assumed

Verified:

- The Swift compiles and packages on the macOS runner (Actions run 45723961808, all steps green).
- Locally: the agent serves `/status` with a valid token, returns 401 without one, and 400 for unknown actions or malformed JSON.
- Locally: `/stream` delivered 76 frames in 5.1 s (15 fps) at 960x540, 54 KB per frame, 0.83 MB/s, decoded as valid JPEG.
- Locally: `/input` moved the real Windows pointer from 1300,700 to 31,17 through the Node agent and the PowerShell helper.
- Locally: `node test-files.js` passed 17/17 - upload/download byte-identical, `..` and absolute-path escapes rejected, unknown root rejected, trash keeps the file, no `.part` left behind.

Not verified:

- Installing on a physical iPhone with Sideloadly, and the trust prompt.
- The new Swift (`PaddleClient.swift`, `PaddleView.swift`) has not been compiled yet - the macOS runner builds it.
- Streaming latency over Wi-Fi from a real iPhone, and how it behaves with the phone on a different subnet.
- The volume percentage is an estimate from what the app set - Windows has no dependency-free way to read the mixer, so it can drift from the real level.
- Controller mapping on real hardware.
