# AETHER Portable Drive Studio for iPhone

A separate native SwiftUI app from Command Center. It creates, imports,
verifies, shares and deletes raw AX1VD cartridges stored in its own Documents
folder.

## Delete a cartridge

Open a cartridge and tap **Delete cartridge**, or long-press its row and choose
**Delete cartridge**. The app asks for confirmation, then removes that copy and
its `.cart.json` metadata. Importing copies a selected file into the app; the
original in Files is never deleted.

## Build and install

This Windows workspace cannot compile iOS. Push to `main` and the
`Build iPhone Portable Drive Studio` GitHub Action builds an unsigned IPA on a
macOS runner and attaches it to a `pvd-ios-<run>` release.

1. Download the `.ipa` from the latest release or the workflow artifact.
2. Connect the iPhone and open Sideloadly.
3. Drop the IPA in, sign in with the Apple ID, and start.
4. On the iPhone, trust the developer under Settings > General > VPN & Device
   Management.

A free Apple ID signature lasts 7 days and must be re-signed. A paid Apple
Developer Program membership lasts 1 year.

## Scope

This build treats `.vdrive` as a raw AX1VD enclosure. It validates the header,
CRC, journal bytes and a bounded data sample. It does not mount AXFS or browse
an internal file catalog, and it does not access `E:\VirtualDrives`.
