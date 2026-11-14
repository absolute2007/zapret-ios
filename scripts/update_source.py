#!/usr/bin/env python3
"""Prepends a new version to the AltStore source (altstore/source.json)."""
import argparse
import datetime as dt
import json
import os
import sys


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--source", default="altstore/source.json")
    p.add_argument("--bundle-id", default="io.github.absolute2007.zapret")
    p.add_argument("--version", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--ipa", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--notes", default="")
    p.add_argument("--notes-file")
    p.add_argument("--min-os", default="16.0")
    p.add_argument("--keep", type=int, default=15)
    a = p.parse_args()

    notes = a.notes
    if a.notes_file and os.path.exists(a.notes_file):
        with open(a.notes_file, encoding="utf-8") as f:
            notes = f.read().strip() or notes

    with open(a.source, encoding="utf-8") as f:
        source = json.load(f)

    app = next((x for x in source["apps"] if x["bundleIdentifier"] == a.bundle_id), None)
    if app is None:
        print(f"app {a.bundle_id} not found in source", file=sys.stderr)
        return 1

    now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    entry = {
        "version": a.version,
        "buildVersion": str(a.build),
        "date": now.isoformat().replace("+00:00", "Z"),
        "localizedDescription": notes or f"Версия {a.version}",
        "downloadURL": a.url,
        "size": os.path.getsize(a.ipa),
        "minOSVersion": a.min_os,
    }

    versions = [v for v in app.get("versions", []) if v.get("version") != a.version]
    app["versions"] = [entry] + versions[: a.keep - 1]

    # Legacy (AltStore 1.x) fields.
    app["version"] = entry["version"]
    app["versionDate"] = entry["date"]
    app["versionDescription"] = entry["localizedDescription"]
    app["downloadURL"] = entry["downloadURL"]
    app["size"] = entry["size"]

    news = source.setdefault("news", [])
    news_id = f"release-{a.version}"
    if not any(n.get("identifier") == news_id for n in news):
        news.insert(0, {
            "title": f"Zapret {a.version}",
            "identifier": news_id,
            "caption": (notes.splitlines()[0] if notes else "Новая версия")[:120],
            "date": entry["date"],
            "tintColor": source.get("tintColor", "#28DCAA"),
            "appID": a.bundle_id,
            "notify": True,
        })
        del news[10:]

    with open(a.source, "w", encoding="utf-8") as f:
        json.dump(source, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"source updated: {a.version} ({a.build}), {entry['size']} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
