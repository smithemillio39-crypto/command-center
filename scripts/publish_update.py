"""Rewrite updates/source.json so the phone sees the build that just shipped.

The file is a SideStore/AltStore source, which is what the app itself reads to
decide whether "Update" should appear.  CI runs this after packaging the IPA.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
FEED = ROOT / "updates" / "source.json"
BUNDLE_ID = "com.personal.commandcenter"
VERSION = "1.0"
MIN_OS = "17.0"
KEEP = 20

DESCRIPTION = (
    "A Control Center-style remote for your Windows PC: volume, media, power, "
    "launchers, the Paddle screen stream and the file bridge, all from the phone."
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build", required=True, help="CFBundleVersion of this build")
    parser.add_argument("--ipa", required=True, help="packaged CommandCenter.ipa")
    parser.add_argument("--tag", required=True, help="release tag holding the IPA")
    parser.add_argument("--notes", default="", help="release note shown in the app")
    args = parser.parse_args()

    repo = os.environ.get("GITHUB_REPOSITORY", "smithemillio39-crypto/command-center")
    ipa = pathlib.Path(args.ipa)
    if not ipa.exists():
        raise SystemExit(f"no IPA at {ipa}")

    previous = {}
    if FEED.exists():
        previous = json.loads(FEED.read_text(encoding="utf-8"))

    carried = []
    if previous.get("apps"):
        carried = previous["apps"][0].get("versions") or []
    versions = [v for v in carried if v.get("buildVersion") != args.build]
    versions.insert(0, {
        "version": VERSION,
        "buildVersion": args.build,
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "localizedDescription": args.notes,
        "downloadURL": f"https://github.com/{repo}/releases/download/{args.tag}/CommandCenter.ipa",
        "size": ipa.stat().st_size,
        "minOSVersion": MIN_OS,
    })

    feed = {
        "name": "Command Center builds",
        "identifier": "com.personal.commandcenter.source",
        "sourceURL": f"https://raw.githubusercontent.com/{repo}/main/updates/source.json",
        "apps": [{
            "name": "Command Center",
            "bundleIdentifier": BUNDLE_ID,
            "developerName": "smith",
            "subtitle": "Remote for your Windows PC",
            "localizedDescription": DESCRIPTION,
            "iconURL": (f"https://raw.githubusercontent.com/{repo}/main/ios/CommandCenter/"
                        "Assets.xcassets/AppIcon.appiconset/icon-1024.png"),
            "tintColor": "B993FC",
            "category": "utilities",
            "versions": versions[:KEEP],
        }],
    }

    FEED.parent.mkdir(parents=True, exist_ok=True)
    FEED.write_text(json.dumps(feed, indent=2) + "\n", encoding="utf-8")
    print(f"published build {args.build} ({ipa.stat().st_size} bytes) to {FEED}")


if __name__ == "__main__":
    main()
