# AETHER Portable Drive Studio for iPhone

A separate native SwiftUI app from Command Center. It creates, imports,
verifies, shares and deletes AX1VD cartridges stored in its own Documents
folder. Each cartridge holds a FAT32 volume, so a computer can open it.

## Cartridges

A cartridge is a 4096-byte AX1VD-01 header, a 64 KiB journal, then a FAT32
volume of the declared size. Formatting writes the boot sector, the two FAT
copies, the FSInfo sector and a 4 KiB root folder; the rest of the file stays
sparse on disk until files are written.

New cartridges are offered at 512 MiB, 2 GiB and 4 GiB. FAT32 needs at least
65,525 clusters, so the app refuses anything below 300 MiB instead of writing
an invalid volume.

`Documents/Cartridges` is excluded from iCloud backup, because a multi-gigabyte
cartridge does not belong in a backup.

## Delete a cartridge

Open a cartridge and tap **Delete cartridge**, or long-press its row and choose
**Delete cartridge**.
The app asks for confirmation, then removes that copy and
its `.cart.json` metadata. Importing copies a selected file into the app; the
original in Files is never deleted. Delete only works on cartridges inside the
app's own `Documents/Cartridges` folder.

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

## Filesystem check

The same workflow has a `filesystem` job. It compiles `FAT32.swift`,
`AX1VD.swift` and `Volume.swift` with `swiftc` for macOS, writes a 320 MiB test
image and an AX1VD cartridge, then runs `fsck.fat -n -v` on both copies of the
volume and `mdir`, `mcopy` and `mtype` from mtools, including a file written by
mtools and read back by this code. A green run means the image is a valid FAT32
volume.

## Scope

This build validates the header and CRC, both FAT copies, the FSInfo free count
and the cluster chains, and refuses a volume whose size disagrees with the
AX1VD header. It does not browse files yet, and it does not access
`E:\VirtualDrives`.
